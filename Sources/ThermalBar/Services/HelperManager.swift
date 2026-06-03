import AppKit
import Foundation

@MainActor
struct HelperManager {
    private let launchDaemonPath = "/Library/LaunchDaemons/com.local.thermalbar.helper.plist"

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: launchDaemonPath)
    }

    func runPrivilegedScript(named scriptName: String) {
        guard let scriptPath = Bundle.main.path(forResource: scriptName, ofType: nil) else {
            presentError("Missing bundled script: \(scriptName)")
            return
        }

        let shellCommand = shellQuoted(scriptPath)
        let command = "do shell script \(appleScriptQuoted(shellCommand)) with administrator privileges"
        var errorInfo: NSDictionary?
        if let script = NSAppleScript(source: command) {
            script.executeAndReturnError(&errorInfo)
        }
        if let errorInfo {
            presentError(errorInfo.description)
        }
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "ThermalBar 辅助服务"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appleScriptQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
