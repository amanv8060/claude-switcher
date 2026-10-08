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
        try Keychain.write(service: switcherKeychainService, account: "code-" + profileID(for: cur, in: &state),
                           value: try jsonString(cur.claudeAiOauth))
        return state.code.first { $0.key == cur.key }?.id
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

    static func remove(_ p: CodeProfile, state: inout AppState) {
        Keychain.delete(service: switcherKeychainService, account: "code-" + p.id)
        state.code.removeAll { $0.id == p.id }
    }
}
