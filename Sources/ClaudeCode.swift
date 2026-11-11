import AppKit

enum ClaudeCode {
    struct Current {
        var key: String
        var email: String
        var org: String
        var oauthAccount: [String: Any]
        var claudeAiOauth: Any
    }

    static func readClaudeJSON() throws -> [String: Any] {
        let d = try Data(contentsOf: claudeJSON)
        guard let obj = try JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            throw SwitcherError("~/.claude.json is not a JSON object")
        }
        return obj
    }

    static func current() -> Current? {
        guard let cfg = try? readClaudeJSON(),
              let acct = cfg["oauthAccount"] as? [String: Any],
              let blobStr = Keychain.read(service: codeKeychainService),
              let blob = parseJSONObject(blobStr),
              let oauth = blob["claudeAiOauth"] else { return nil }
        let uuid = acct["accountUuid"] as? String ?? "?"
        let orgUuid = acct["organizationUuid"] as? String ?? "?"
        return Current(key: "\(uuid)|\(orgUuid)",
                       email: acct["emailAddress"] as? String ?? "unknown",
                       org: acct["organizationName"] as? String ?? "",
                       oauthAccount: acct,
                       claudeAiOauth: oauth)
    }

    /// Saves the live login into its profile (creating one if new). Claude Code
    /// rotates refresh tokens, so this runs before every switch and menu open.
    @discardableResult
    static func snapshot(into state: inout AppState) throws -> String? {
        guard let cur = current() else { return nil }
        let id = try profileID(for: cur, in: &state)
        // Never replace a saved login that can be renewed with one that can't.
        let live = cur.claudeAiOauth as? [String: Any]
        let saved = Keychain.read(service: switcherKeychainService, account: "code-" + id).flatMap(parseJSONObject)
        if live?["refreshToken"] == nil, saved?["refreshToken"] != nil { return id }
        try Keychain.write(service: switcherKeychainService, account: "code-" + id, value: try jsonString(cur.claudeAiOauth))
        return id
    }

    /// A token filed under the wrong account (for example, written by a session
    /// that was still running on another account) is moved to its real owner,
    /// creating that account if needed. Returns the owner's profile id.
    @discardableResult
    static func refile(_ oauth: [String: Any], from wrong: CodeProfile, to owner: ClaudeAPI.Owner,
                       live: Bool, state: inout AppState) throws -> String {
        let key = "\(owner.accountUuid)|\(owner.orgUuid)"
        let id: String
        if let p = state.code.first(where: { $0.key == key }) {
            id = p.id
        } else {
            let acct: [String: Any] = ["accountUuid": owner.accountUuid, "emailAddress": owner.email,
                                       "organizationUuid": owner.orgUuid, "displayName": owner.displayName ?? "",
                                       "organizationName": owner.orgName ?? ""]
            let p = CodeProfile(id: UUID().uuidString, name: owner.email, email: owner.email,
                                org: owner.orgName ?? "", key: key, oauthAccountJSON: try jsonString(acct))
            state.code.append(p)
            id = p.id
        }
        try Keychain.write(service: switcherKeychainService, account: "code-" + id, value: try jsonString(oauth))
        // Drop the misfiled copy from the wrong account, but only if it's this same token.
        let misfiled = Keychain.read(service: switcherKeychainService, account: "code-" + wrong.id).flatMap(parseJSONObject)
        if misfiled?["accessToken"] as? String == oauth["accessToken"] as? String {
            Keychain.delete(service: switcherKeychainService, account: "code-" + wrong.id)
        }
        // The CLI is really signed in as the owner: make ~/.claude.json agree.
        if live, let p = state.code.first(where: { $0.id == id }), let acct = parseJSONObject(p.oauthAccountJSON) {
            var cfg = try readClaudeJSON()
            cfg["oauthAccount"] = acct
            try Data(try jsonString(cfg, pretty: true).utf8).write(to: claudeJSON, options: .atomic)
        }
        return id
    }

    /// `claude` sessions running in a terminal. They keep their account in memory
    /// and write refreshed tokens back to the shared keychain item, so switching
    /// under them can overwrite the new account's login.
    static func runningTerminalSessions() -> Int {
        let r = run("/bin/ps", ["-axo", "tty=,args="])
        return r.out.split(separator: "\n").filter { line in
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2, parts[0] != "??" else { return false }
            let exe = parts[1].split(separator: " ").first.map(String.init) ?? ""
            return exe == "claude" || exe.hasSuffix("/claude") || exe.contains("/.local/share/claude/versions/")
        }.count
    }

    /// Opens Terminal on `claude auth login`, pre-filled with the account's email.
    static func signIn(email: String?) throws {
        guard let cli = cliPath() else { throw SwitcherError("Claude Code isn't installed. Install it with: \(installCommand)") }
        var command = "'\(cli.replacingOccurrences(of: "'", with: "'\\''"))' auth login"
        if let email, !email.isEmpty { command += " --email '\(email.replacingOccurrences(of: "'", with: "'\\''"))'" }
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var err: NSDictionary?
        NSAppleScript(source: "tell application \"Terminal\"\n activate\n do script \"\(escaped)\"\nend tell")?
            .executeAndReturnError(&err)
        if let err { throw SwitcherError("Couldn't open Terminal: \(err)") }
    }

    private static func profileID(for cur: Current, in state: inout AppState) throws -> String {
        let acctJSON = try jsonString(cur.oauthAccount)
        if let i = state.code.firstIndex(where: { $0.key == cur.key }) {
            state.code[i].oauthAccountJSON = acctJSON
            state.code[i].email = cur.email
            state.code[i].org = cur.org
            return state.code[i].id
        }
        let p = CodeProfile(id: UUID().uuidString, name: cur.email, email: cur.email,
                            org: cur.org, key: cur.key, oauthAccountJSON: acctJSON)
        state.code.append(p)
        return p.id
    }

    static func switchTo(_ target: CodeProfile, state: inout AppState) throws {
        try snapshot(into: &state)

        guard let tokenStr = Keychain.read(service: switcherKeychainService, account: "code-" + target.id),
              let token = try? JSONSerialization.jsonObject(with: Data(tokenStr.utf8)) else {
            throw SwitcherError("No saved login for \(target.name). Log in to it again with “Add account…”.")
        }
        guard let acct = parseJSONObject(target.oauthAccountJSON) else {
            throw SwitcherError("Saved account info for \(target.name) is unreadable.")
        }

        // 1. Keychain: replace only claudeAiOauth, keep mcpOAuth etc.
        var blob = Keychain.read(service: codeKeychainService).flatMap(parseJSONObject) ?? [:]
        blob["claudeAiOauth"] = token
        try Keychain.write(service: codeKeychainService, account: NSUserName(), value: try jsonString(blob))

        // 2. ~/.claude.json: replace only oauthAccount (backup first).
        var cfg = try readClaudeJSON()
        let backup = home.appendingPathComponent(".claude.json.switcher-backup")
        try? fm.removeItem(at: backup)
        try? fm.copyItem(at: claudeJSON, to: backup)
        cfg["oauthAccount"] = acct
        try Data(try jsonString(cfg, pretty: true).utf8).write(to: claudeJSON, options: .atomic)
    }

    /// Where the `claude` command lives: the common install locations, then the
    /// user's login shell PATH. Nil when Claude Code isn't installed.
    static func cliPath() -> String? {
        let candidates = [home.appendingPathComponent(".local/bin/claude").path,
                          "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        if let p = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) { return p }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let r = run(shell, ["-lc", "command -v claude"])
        let p = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.status == 0 && fm.isExecutableFile(atPath: p) ? p : nil
    }

    static let installCommand = "curl -fsSL https://claude.ai/install.sh | bash"

    static func remove(_ p: CodeProfile, state: inout AppState) {
        Keychain.delete(service: switcherKeychainService, account: "code-" + p.id)
        state.code.removeAll { $0.id == p.id }
    }
}
