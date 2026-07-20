import Foundation
import Network

/// Localhost HTTP/JSON control plane for agents (default 127.0.0.1:8091).
/// Bind failure must never freeze the UI — try a small port range and keep going.
@MainActor
final class GuiControlServer {
    private var listener: NWListener?
    private weak var model: AppModel?
    private let preferredPort: UInt16
    private let queue = DispatchQueue(label: "dev.ghidravibe.gui-control")
    private var portOffset: UInt16 = 0

    private(set) var boundPort: UInt16?

    init(port: UInt16 = 8091) {
        self.preferredPort = port
    }

    func start(model: AppModel) {
        self.model = model
        portOffset = 0
        attemptBind()
    }

    private func attemptBind() {
        guard portOffset <= 8 else {
            model?.statusMessage =
                "GUI control offline — ports \(preferredPort)–\(preferredPort + 8) busy (UI still works)"
            return
        }
        let port = preferredPort &+ portOffset
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.includePeerToPeer = false
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.boundPort = port
                        let note = port == self.preferredPort
                            ? "GUI control http://127.0.0.1:\(port)"
                            : "GUI control http://127.0.0.1:\(port) (\(self.preferredPort) busy)"
                        self.model?.statusMessage = note
                    case .failed(let err):
                        NSLog("GuiControlServer failed on \(port): \(err)")
                        listener.cancel()
                        if self.listener === listener {
                            self.listener = nil
                        }
                        self.portOffset += 1
                        self.attemptBind()
                    case .cancelled:
                        break
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in
                    self?.handle(connection: conn)
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            NSLog("GuiControlServer bind \(port): \(error)")
            portOffset += 1
            attemptBind()
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        boundPort = nil
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let data, let req = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            Task { @MainActor in
                guard let self else {
                    connection.cancel()
                    return
                }
                let response = self.route(httpRequest: req)
                let payload = response.data(using: .utf8) ?? Data()
                connection.send(
                    content: payload,
                    completion: .contentProcessed { _ in connection.cancel() }
                )
            }
        }
    }

    private func route(httpRequest: String) -> String {
        let lines = httpRequest.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let requestLine = lines.first else { return httpJSON(400, ["ok": false, "error": "bad request"]) }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return httpJSON(400, ["ok": false, "error": "bad request"]) }
        let method = String(parts[0])
        let pathQuery = String(parts[1])
        let path = pathQuery.split(separator: "?").first.map(String.init) ?? pathQuery
        let body = httpRequest.components(separatedBy: "\r\n\r\n").dropFirst().joined(separator: "\r\n\r\n")
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]

        guard let model else { return httpJSON(503, ["ok": false, "error": "no model"]) }

        switch (method, path) {
        case ("GET", "/health"):
            return httpJSON(200, ["ok": true, "service": "ghidra-vibe-gui"])
        case ("GET", "/state"):
            return httpJSON(200, model.controlState())
        case ("POST", "/navigate"):
            if let pane = json["pane"] as? String { model.navigate(pane: pane) }
            return httpJSON(200, ["ok": true, "state": model.controlState()])
        case ("POST", "/select_function"):
            model.selectFunction(name: json["name"] as? String, address: json["address"] as? String, id: json["id"] as? String)
            return httpJSON(200, ["ok": true, "state": model.controlState()])
        case ("POST", "/search"):
            model.searchQuery = (json["query"] as? String) ?? ""
            return httpJSON(200, ["ok": true, "state": model.controlState()])
        case ("POST", "/action"):
            model.runAction(id: (json["id"] as? String) ?? "")
            return httpJSON(200, ["ok": true, "state": model.controlState()])
        case ("GET", "/dyld/caches"):
            return httpJSON(200, ["ok": true, "caches": model.dyldCachePaths()])
        case ("POST", "/dyld/list"):
            let q = (json["query"] as? String) ?? ""
            return httpJSON(200, ["ok": true, "images": model.listDyldImages(query: q)])
        case ("POST", "/dyld/open"):
            let image = (json["image"] as? String) ?? ""
            if let analyze = json["analyze"] as? Bool {
                model.dyldRunAnalysisOnImport = analyze
            } else if let analyzeNum = json["analyze"] as? NSNumber {
                model.dyldRunAnalysisOnImport = analyzeNum.boolValue
            }
            // Optional project pin for GUI smokes (dir or .gpr).
            if let project = json["project"] as? String, !project.isEmpty {
                var gpr = project
                if !gpr.hasSuffix(".gpr") {
                    let name = (json["project_name"] as? String)?.isEmpty == false
                        ? (json["project_name"] as? String)!
                        : "VibeDSC"
                    gpr = (project as NSString).appendingPathComponent("\(name).gpr")
                }
                model.rememberProject(gpr)
            } else if let gpr = json["project_gpr"] as? String, !gpr.isEmpty {
                model.rememberProject(gpr)
            }
            model.importDyldImage(image)
            return httpJSON(200, ["ok": true, "state": model.controlState()])
        case ("POST", "/refresh_classes"):
            model.refreshObjcClassesFromFunctions()
            model.refreshSwiftClasses()
            return httpJSON(200, ["ok": true, "state": model.controlState()])
        case ("POST", "/refresh_function_graph"):
            model.showProvider(.functionGraph)
            model.refreshFunctionGraph()
            return httpJSON(200, ["ok": true, "state": model.controlState()])
        case ("GET", "/rag/stats"), ("GET", "/jspace/stats"):
            return httpJSON(200, ["ok": true, "status": model.jspaceStatus])
        case ("POST", "/rag/index"), ("POST", "/jspace/index"):
            model.indexJSpace()
            return httpJSON(200, ["ok": true, "status": model.jspaceStatus])
        case ("POST", "/rag/discover"), ("POST", "/jspace/discover"):
            let q = (json["query"] as? String) ?? ""
            let pack = model.jspaceDiscover(q)
            return httpJSON(200, ["ok": true, "discovery": pack, "status": model.jspaceStatus])
        case ("POST", "/agent/send"):
            let text = (json["text"] as? String) ?? (json["message"] as? String) ?? ""
            guard !text.isEmpty else {
                return httpJSON(400, ["ok": false, "error": "text required"])
            }
            model.agentDraft = text
            model.sendAgentMessage()
            return httpJSON(200, ["ok": true, "queued": true, "state": model.controlState()])
        case ("GET", "/agent/status"):
            return httpJSON(200, [
                "ok": true,
                "agentEnabled": model.agentEnabled,
                "agentSidebarVisible": model.dockLayout.agentSidebarVisible,
                "agentBusy": model.agentBusy,
                "agentBackend": model.agentBackend,
                "agentModel": model.agentModel,
                "agentBaseURL": model.agentBaseURL,
                "pendingEdits": model.agentPendingEdits.count,
                "messageCount": model.agentMessages.count,
                "lastMessage": String(model.agentMessages.last?.text.prefix(500) ?? ""),
                "jspaceStatus": model.jspaceStatus,
                "state": model.controlState(),
            ])
        case ("POST", "/agent/playbook"):
            let budget = (json["budget"] as? Int) ?? (json["budget"] as? NSNumber)?.intValue ?? 8
            let apply: Bool
            if let b = json["apply"] as? Bool {
                apply = b
            } else if let n = json["apply"] as? NSNumber {
                apply = n.boolValue
            } else {
                apply = true
            }
            model.runAutonomousREPlaybook(budget: budget, apply: apply)
            return httpJSON(200, ["ok": true, "started": true, "budget": budget, "state": model.controlState()])
        case ("POST", "/agent/rename"):
            let result = model.renameFunction(
                address: (json["address"] as? String) ?? "",
                oldName: (json["name"] as? String) ?? "",
                newName: (json["new_name"] as? String) ?? (json["newName"] as? String) ?? "",
                apply: true
            )
            return httpBody(200, result, contentType: "application/json")
        case ("POST", "/agent/comment"):
            let result = model.setFunctionComment(
                address: (json["address"] as? String) ?? "",
                comment: (json["comment"] as? String) ?? "",
                kind: (json["kind"] as? String) ?? "plate",
                apply: true
            )
            return httpBody(200, result, contentType: "application/json")
        case ("POST", "/agent/improve_decompile"):
            model.queueImproveDecompile(
                name: json["name"] as? String,
                address: json["address"] as? String,
                apply: (json["apply"] as? Bool) ?? (json["apply"] as? NSNumber)?.boolValue ?? false
            )
            return httpJSON(200, ["ok": true, "started": true, "state": model.controlState()])
        case ("GET", "/a11y/catalog"):
            if let text = A11yCatalog.catalogJSONString() {
                return httpBody(200, text, contentType: "application/json")
            }
            return httpJSON(500, ["ok": false, "error": "catalog missing"])
        default:
            return httpJSON(404, ["ok": false, "error": "not found", "path": path])
        }
    }

    private func httpJSON(_ code: Int, _ obj: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data("{}".utf8)
        let body = String(data: data, encoding: .utf8) ?? "{}"
        return httpBody(code, body, contentType: "application/json")
    }

    private func httpBody(_ code: Int, _ body: String, contentType: String) -> String {
        let reason = code == 200 ? "OK" : "ERR"
        return "HTTP/1.1 \(code) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
    }
}
