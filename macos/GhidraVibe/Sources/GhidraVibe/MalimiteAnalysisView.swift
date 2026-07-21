import SwiftUI

/// First-class App Bundle analysis (Malimite-parity pipeline under the hood).
struct MalimiteAnalysisView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .bundle

    enum Tab: String, CaseIterable, Identifiable {
        case bundle = "Bundle"
        case classes = "Classes"
        case resources = "Resources"
        case strings = "Strings"
        case entrypoints = "Entrypoints"
        case references = "References"
        case libraries = "Libraries"
        case translate = "LLM Translate"
        var id: String { rawValue }
    }

    var body: some View {
        @Bindable var model = model
        ProviderChrome(kind: .appleBundle, title: "App Bundle") {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(6)
                .accessibilityIdentifier("ghidra.vibe.provider.apple_bundle.tabs")

                Group {
                    switch tab {
                    case .bundle: bundlePane
                    case .classes: classesPane
                    case .resources: resourcesPane
                    case .strings: stringsPane
                    case .entrypoints: entrypointsPane
                    case .references: referencesPane
                    case .libraries: librariesPane
                    case .translate: translatePane
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var bundlePane: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 8) {
            Text(model.appleBundlePath.isEmpty ? "(no bundle)" : model.appleBundlePath)
                .font(.caption.monospaced())
                .a11yCatalog("ghidra.vibe.provider.apple_bundle.path")
            Text(model.malimiteInfoSummary)
                .font(.caption2)
                .foregroundStyle(Color.vibeSecondary)
            LiquidGlass.Bar(spacing: 8) {
                HStack(spacing: 8) {
                    Button("Open IPA / App…") { model.openAppBundlePicker() }
                        .buttonStyle(.bordered)
                        .tint(Color.vibeAccent)
                        .a11yCatalog("ghidra.vibe.provider.apple_bundle.open")
                        .help("Open a whole .app / IPA / framework bundle")
                    Button("Analyze Bundle") { model.runMalimiteAnalyze(binOnly: false) }
                        .buttonStyle(.borderedProminent)
                    .tint(Color.vibeAccent)
                        .a11yCatalog("ghidra.vibe.provider.apple_bundle.import")
                        .disabled(model.appleBundlePath.isEmpty)
                        .help("Full app-bundle analysis: resources, class dump, refs")
                    Button("List resources") { model.listAppleResources() }
                        .buttonStyle(.bordered)
                        .tint(Color.vibeAccent)
                        .a11yCatalog("ghidra.vibe.provider.apple_bundle.resources")
                    Button("Refresh DB") { model.refreshMalimiteDB() }
                        .buttonStyle(.bordered)
                        .tint(Color.vibeAccent)
                        .a11yCatalog("ghidra.vibe.provider.apple_bundle.refresh_db")
                }
            }
            Text("DB: \(model.malimiteDBPath.isEmpty ? "(none)" : model.malimiteDBPath)")
                .font(.caption2.monospaced())
            Text(model.malimiteStatsText)
                .font(.caption2)
                .foregroundStyle(Color.vibeSecondary)
            Spacer()
        }
        .padding(8)
    }

    private var classesPane: some View {
        @Bindable var model = model
        return HSplitView {
            List(model.malimiteClassRows, id: \.self, selection: $model.selectedMalimiteClass) { row in
                Text(row).font(.caption.monospaced())
            }
            .a11yCatalog("ghidra.vibe.provider.swift_classes.list")
                .vibeThemedList()
            .frame(minWidth: 160)
            .onChange(of: model.selectedMalimiteClass) { _, row in
                if let row { model.loadMalimiteClassFunctions(row) }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(model.selectedMalimiteClass ?? "Select a class")
                    .font(.caption.weight(.semibold))
                    .padding(6)
                List(model.malimiteFunctionRows, id: \.self, selection: $model.selectedMalimiteFunction) { fn in
                    Text(fn).font(.caption.monospaced())
                }
                .onChange(of: model.selectedMalimiteFunction) { _, name in
                    if let name { model.loadMalimiteFunctionCode(name) }
                }
                SyntaxHighlightedCodeView(
                    text: model.malimiteFunctionCode.isEmpty ? "// decompile from DB" : model.malimiteFunctionCode,
                    fontSize: 11
                )
                localsStrip(for: model.malimiteFunctionCode)
            }
        }
        .onAppear { model.refreshMalimiteClasses() }
    }

    @ViewBuilder
    private func localsStrip(for code: String) -> some View {
        let syms = DecompileSyntax.extractSymbols(code)
        if !syms.locals.isEmpty {
            Text("Locals (SyntaxParser parity): \(syms.locals.prefix(8).joined(separator: ", "))")
                .font(.caption2)
                .foregroundStyle(Color.vibeSecondary)
                .padding(.horizontal, 6)
                .lineLimit(2)
        }
    }

    private var resourcesPane: some View {
        List(model.appleResourceRows, id: \.self) { row in
            Text(row).font(.caption.monospaced())
        }
        .a11yCatalog("ghidra.vibe.provider.apple_bundle.list")
                .vibeThemedList()
    }

    private var stringsPane: some View {
        List(model.malimiteStringRows, id: \.self) { row in
            Text(row).font(.caption.monospaced())
        }
        .onAppear { model.refreshMalimiteStrings() }
    }

    private var entrypointsPane: some View {
        List(model.malimiteEntrypointRows, id: \.self) { row in
            Button(row) {
                model.goToDraft = row
                model.performGoTo()
            }
            .buttonStyle(.plain)
            .font(.caption.monospaced())
            .a11yCatalog("ghidra.vibe.provider.apple_bundle.entrypoint.go")
                .vibeThemedList()
            .help("Go to entrypoint \(row)")
        }
        .onAppear { model.refreshMalimiteEntrypoints() }
    }

    private var referencesPane: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            TextField("Function name", text: $model.malimiteRefQuery)
                .textFieldStyle(.roundedBorder)
                .padding(6)
                .onSubmit { model.refreshMalimiteRefs() }
            List(model.malimiteRefRows, id: \.self) { Text($0).font(.caption.monospaced()) }
        }
        .onAppear { model.refreshMalimiteRefs() }
    }

    private var librariesPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Skip decompiling these library namespaces (stock library skip-list).")
                .font(.caption)
                .foregroundStyle(Color.vibeSecondary)
            LiquidGlass.Bar(spacing: 8) {
                HStack {
                    Button("Reload") { model.refreshMalimiteLibraries() }
                        .buttonStyle(.bordered)
                        .tint(Color.vibeAccent)
                        .a11yCatalog("ghidra.vibe.provider.apple_bundle.libraries.reload")
                    Button("Reset defaults") { model.resetMalimiteLibraries() }
                        .buttonStyle(.bordered)
                        .tint(Color.vibeAccent)
                        .a11yCatalog("ghidra.vibe.provider.apple_bundle.libraries.reset")
                }
            }
            .padding(.horizontal, 6)
            List(model.malimiteLibraryRows, id: \.self) { Text($0).font(.caption) }
        }
        .onAppear { model.refreshMalimiteLibraries() }
    }

    private var translatePane: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 8) {
            Text("LLM actions: Auto Fix → Swift/ObjC, Summarize, Find Vulnerabilities.")
                .font(.caption)
                .foregroundStyle(Color.vibeSecondary)
            Picker("Action", selection: $model.malimiteTranslateAction) {
                Text("Auto Fix").tag("auto_fix")
                Text("Summarize").tag("summarize")
                Text("Find Vulnerabilities").tag("find_vulnerabilities")
            }
            .pickerStyle(.segmented)
            Picker("Language", selection: $model.malimiteTranslateLanguage) {
                Text("Swift").tag("Swift")
                Text("Objective-C").tag("Objective-C")
            }
            .pickerStyle(.segmented)
            LiquidGlass.Bar(spacing: 8) {
                HStack {
                    Button("Load current decompile") {
                        model.malimiteTranslateInput = model.decompiledText
                    }
                    .buttonStyle(.bordered)
                        .tint(Color.vibeAccent)
                    .a11yCatalog("ghidra.vibe.provider.apple_bundle.translate.load_decompile")
                    Button("Load DB function") {
                        model.malimiteTranslateInput = model.malimiteFunctionCode
                    }
                    .buttonStyle(.bordered)
                        .tint(Color.vibeAccent)
                    .a11yCatalog("ghidra.vibe.provider.apple_bundle.translate.load_db")
                    Button("Run Translate") { model.runMalimiteTranslate() }
                        .buttonStyle(.borderedProminent)
                    .tint(Color.vibeAccent)
                        .a11yCatalog("ghidra.vibe.provider.apple_bundle.translate.run")
                    Button("Send to Agent") {
                        model.agentDraft = model.malimiteTranslateOutput
                        model.showProvider(.agent)
                    }
                    .buttonStyle(.bordered)
                        .tint(Color.vibeAccent)
                    .a11yCatalog("ghidra.vibe.provider.apple_bundle.translate.to_agent")
                }
            }
            HSplitView {
                SyntaxCodeEditor(text: $model.malimiteTranslateInput)
                SyntaxCodeEditor(text: $model.malimiteTranslateOutput)
            }
        }
        .padding(8)
    }
}
