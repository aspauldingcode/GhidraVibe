import AppKit
import Foundation
import SwiftUI

enum UserAgreement {
    static let defaultsKey = "ghidra.vibe.userAgreementAccepted"
    static let ghidraPrefKey = "USER_AGREEMENT"

    static let title = "Ghidra User Agreement"

    /// Plain-text body matching stock `docs/UserAgreement.html` (Apache + NSA SRE notice).
    static let body = """
    Licensed under the Apache License, Version 2.0 (the "License"); Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.

    As a software reverse engineering (SRE) framework, Ghidra is designed solely to facilitate lawful SRE activities. You should always ensure that any SRE activities in which you engage are permissible as computer software may be protected under governing law (e.g., copyright) or under an applicable licensing agreement. In making Ghidra available for public use, the National Security Agency does not condone or encourage any improper usage of Ghidra. Consistent with the Apache 2.0 license under which Ghidra has been made available, you are solely responsible for determining the appropriateness of using or redistributing Ghidra.
    """

    /// Native shell first-run gate (independent of Swing prefs).
    static var needsPrompt: Bool {
        !UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static var isAccepted: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static func accept() {
        UserDefaults.standard.set(true, forKey: defaultsKey)
        seedGhidraPreferencesAccepted()
    }

    /// Write USER_AGREEMENT=ACCEPT so headless / accidental Swing never show the Java dialog.
    static func seedGhidraPreferencesAccepted() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        // In-process engine settings (application.settingsdir) — avoid stock Extensions collision.
        writePref(home.appendingPathComponent("Library/ghidra-vibe/settings/preferences"))
        let ghidraHome = home.appendingPathComponent("Library/ghidra", isDirectory: true)
        guard let dirs = try? fm.contentsOfDirectory(
            at: ghidraHome, includingPropertiesForKeys: nil
        ) else {
            writePref(ghidraHome.appendingPathComponent("ghidra_12.1.2_NIX/preferences"))
            return
        }
        for dir in dirs where dir.hasDirectoryPath {
            writePref(dir.appendingPathComponent("preferences"))
        }
    }

    private static func ghidraPreferencesAlreadyAccepted() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/ghidra", isDirectory: true)
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: home, includingPropertiesForKeys: nil
        ) else { return false }
        for dir in dirs {
            let pref = dir.appendingPathComponent("preferences")
            if let text = try? String(contentsOf: pref, encoding: .utf8),
               text.contains("USER_AGREEMENT=ACCEPT")
            {
                return true
            }
        }
        return false
    }

    private static func writePref(_ url: URL) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var lines: [String] = []
        if let existing = try? String(contentsOf: url, encoding: .utf8) {
            lines = existing.split(whereSeparator: \.isNewline).map(String.init)
                .filter { !$0.hasPrefix("USER_AGREEMENT=") }
        }
        lines.append("USER_AGREEMENT=ACCEPT")
        try? lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Native first-run agreement. Uses SwiftUI `.alert` (not Swing `UserAgreementDialog`).
struct UserAgreementModifier: ViewModifier {
    @Binding var isPresented: Bool
    var onDecline: () -> Void
    var onAccept: () -> Void = {}

    func body(content: Content) -> some View {
        content
            .alert(UserAgreement.title, isPresented: $isPresented) {
                Button("I Agree") {
                    UserAgreement.accept()
                    isPresented = false
                    onAccept()
                }
                .a11yCatalog("ghidra.vibe.agreement.agree")
                // role: .cancel so AppKit does not inject a third "Cancel" button.
                // Decline is the only dismiss path (stock: Agree / Don't Agree only).
                Button("I Don't Agree", role: .cancel) {
                    isPresented = false
                    onDecline()
                }
                .a11yCatalog("ghidra.vibe.agreement.decline")
            } message: {
                Text(UserAgreement.body)
                    .accessibilityIdentifier("ghidra.vibe.agreement.body")
            }
    }
}

extension View {
    func ghidraUserAgreement(
        isPresented: Binding<Bool>,
        onDecline: @escaping () -> Void,
        onAccept: @escaping () -> Void = {}
    ) -> some View {
        modifier(UserAgreementModifier(isPresented: isPresented, onDecline: onDecline, onAccept: onAccept))
    }
}
