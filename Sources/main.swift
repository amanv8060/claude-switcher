// Claude Switcher — a menu bar app for switching between Claude accounts.
//
// Claude Code (CLI):  the OAuth token lives in the login keychain item
//   "Claude Code-credentials" (key `claudeAiOauth`) and the account metadata
//   lives in ~/.claude.json (key `oauthAccount`). A switch swaps just those two
//   things; MCP tokens and every other setting stay untouched.
//
// Claude Desktop:     each account is a whole copy of
//   ~/Library/Application Support/Claude. A switch quits Claude, swaps the
//   folder with a stored one (a rename, so it's instant) and relaunches.

import AppKit
import ServiceManagement

// `--selftest` prints what the app detects without changing anything in Claude.
if CommandLine.arguments.contains("--selftest") {
    if let c = ClaudeCode.current() {
        print("Claude Code account: \(c.email) [\(c.org)]")
        print("Token keys: \((c.claudeAiOauth as? [String: Any])?.keys.sorted() ?? [])")
    } else {
        print("Claude Code: no login detected")
    }
    if CommandLine.arguments.contains("--usage") {
        // Note: refreshes and saves the token if it has expired, as the app does.
        let sem = DispatchSemaphore(value: 0)
        Task {
            do {
                var oauth = Keychain.read(service: codeKeychainService).flatMap(parseJSONObject)?["claudeAiOauth"] as? [String: Any] ?? [:]
                if ClaudeAPI.isExpired(oauth) {
                    print("Token expired, refreshing…")
                    oauth = try await ClaudeAPI.refresh(oauth)
                    var blob = Keychain.read(service: codeKeychainService).flatMap(parseJSONObject) ?? [:]
                    blob["claudeAiOauth"] = oauth
                    try Keychain.write(service: codeKeychainService, account: NSUserName(), value: try jsonString(blob))
                }
                for w in try await ClaudeAPI.usage(token: oauth["accessToken"] as? String ?? "") {
                    print("  \(w.label): \(w.utilization)% resets \(w.resetsAt.map { "\($0)" } ?? "-")")
                }
            } catch { print("Usage error: \(error.localizedDescription)") }
            sem.signal()
        }
        sem.wait()
    }
    print("Claude Desktop installed: \(ClaudeDesktop.isInstalled), data folder exists: \(fm.fileExists(atPath: desktopLiveDir.path))")
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--render-preview") {
    let dir = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "docs"
    MainActor.assumeIsolated { PreviewRenderer.run(into: URL(fileURLWithPath: dir)) }
    exit(0)
}

// `--login-item on|off` registers this copy of the app to start at login.
if let i = CommandLine.arguments.firstIndex(of: "--login-item") {
    let on = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] != "off" : true
    do {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        print("Launch at login: \(SMAppService.mainApp.status == .enabled ? "on" : "off")")
    } catch { print("Launch at login failed: \(error.localizedDescription)"); exit(1) }
    exit(0)
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
