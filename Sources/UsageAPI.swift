import Foundation

/// Same endpoints Claude Code uses for `/usage` and token refresh.
enum ClaudeAPI {
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let userAgent = "claude-cli/2.0.0 (external, cli)" // default UAs get blocked by Cloudflare

    struct Window { let label: String; let utilization: Double; let resetsAt: Date? }

    static func isExpired(_ oauth: [String: Any]) -> Bool {
        guard let ms = (oauth["expiresAt"] as? NSNumber)?.doubleValue else { return true }
        return ms / 1000 < Date().timeIntervalSince1970 + 60
    }

    /// Returns `oauth` with a new access token (and rotated refresh token).
    static func refresh(_ oauth: [String: Any]) async throws -> [String: Any] {
        guard let rt = oauth["refreshToken"] as? String else { throw SwitcherError("No refresh token") }
        let scopes = oauth["scopes"] as? [String] ?? ["user:inference", "user:profile"]
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token", "refresh_token": rt,
            "client_id": clientID, "scope": scopes.joined(separator: " "),
        ])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 400 || status == 401 { throw SwitcherError("Login expired — log in to this account again") }
        guard status == 200,
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = obj["access_token"] as? String,
              let expiresIn = (obj["expires_in"] as? NSNumber)?.doubleValue else {
            throw SwitcherError("Token refresh failed (HTTP \(status))")
        }
        var out = oauth
        out["accessToken"] = access
        out["refreshToken"] = obj["refresh_token"] as? String ?? rt
        out["expiresAt"] = Int64((Date().timeIntervalSince1970 + expiresIn) * 1000)
        return out
    }

    static func usage(token: String) async throws -> [Window] {
        var req = URLRequest(url: usageURL)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw SwitcherError("unauthorized") }
        guard status == 200, let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SwitcherError("Usage unavailable (HTTP \(status))")
        }
        let keys = [("five_hour", "Session"), ("seven_day", "Week"),
                    ("seven_day_opus", "Week · Opus"), ("seven_day_sonnet", "Week · Sonnet")]
        return keys.compactMap { key, label in
            guard let w = obj[key] as? [String: Any],
                  let u = (w["utilization"] as? NSNumber)?.doubleValue else { return nil }
            return Window(label: label, utilization: u, resetsAt: (w["resets_at"] as? String).flatMap(parseDate))
        }
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

extension ClaudeCode {
    /// The OAuth token for a profile: the live keychain item if it's the active
    /// account, otherwise the copy saved by the switcher.
    static func oauth(for p: CodeProfile, active: Bool) -> [String: Any]? {
        if active {
            return Keychain.read(service: codeKeychainService).flatMap(parseJSONObject)?["claudeAiOauth"] as? [String: Any]
        }
        return Keychain.read(service: switcherKeychainService, account: "code-" + p.id).flatMap(parseJSONObject)
    }

    /// Persists a refreshed token everywhere it lives, so the rotated refresh token isn't lost.
    static func saveOAuth(_ oauth: [String: Any], for p: CodeProfile, active: Bool) throws {
        let s = try jsonString(oauth)
        try Keychain.write(service: switcherKeychainService, account: "code-" + p.id, value: s)
        if active, var blob = Keychain.read(service: codeKeychainService).flatMap(parseJSONObject) {
            blob["claudeAiOauth"] = oauth
            try Keychain.write(service: codeKeychainService, account: NSUserName(), value: try jsonString(blob))
        }
    }
}

enum UsageState {
    case loading
    case ok([ClaudeAPI.Window], Date)
    case failed(String)
}
