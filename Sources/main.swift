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

// MARK: - Paths & constants

let fm = FileManager.default
let home = fm.homeDirectoryForCurrentUser
let appSupport = home.appendingPathComponent("Library/Application Support")
let storeDir = appSupport.appendingPathComponent("ClaudeSwitcher")
let stateFile = storeDir.appendingPathComponent("state.json")
let desktopStore = storeDir.appendingPathComponent("desktop")
let desktopLiveDir = appSupport.appendingPathComponent("Claude")
let claudeJSON = home.appendingPathComponent(".claude.json")

let codeKeychainService = "Claude Code-credentials"
let switcherKeychainService = "ClaudeSwitcher"
let desktopBundleID = "com.anthropic.claudefordesktop"

// MARK: - Shell / keychain helpers

@discardableResult
func run(_ path: String, _ args: [String]) -> (status: Int32, out: String, err: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let out = Pipe(), err = Pipe()
    p.standardOutput = out
    p.standardError = err
    do { try p.run() } catch { return (-1, "", error.localizedDescription) }
    let o = out.fileHandleForReading.readDataToEndOfFile()
    let e = err.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
}

struct SwitcherError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

/// Uses /usr/bin/security rather than SecItem APIs: Claude Code creates its item
/// with that tool, so it is already on the item's ACL and no access prompts appear.
enum Keychain {
    static func read(service: String, account: String? = nil) -> String? {
        var args = ["find-generic-password", "-s", service]
        if let account { args += ["-a", account] }
        args.append("-w")
        let r = run("/usr/bin/security", args)
        guard r.status == 0 else { return nil }
        let s = r.out.trimmingCharacters(in: .newlines)
        // `security -w` prints hex when the data isn't plain text.
        if !s.hasPrefix("{"), s.count % 2 == 0, s.allSatisfy(\.isHexDigit),
           let d = Data(hex: s), let text = String(data: d, encoding: .utf8) {
            return text
        }
        return s
    }

    static func write(service: String, account: String, value: String) throws {
        let hex = Data(value.utf8).map { String(format: "%02x", $0) }.joined()
        let r = run("/usr/bin/security",
                    ["add-generic-password", "-U", "-a", account, "-s", service, "-X", hex])
        if r.status != 0 { throw SwitcherError("Keychain write failed: \(r.err)") }
    }

    static func delete(service: String, account: String) {
        run("/usr/bin/security", ["delete-generic-password", "-a", account, "-s", service])
    }
}

extension Data {
    init?(hex: String) {
        var d = Data(capacity: hex.count / 2)
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            guard let b = UInt8(hex[i..<j], radix: 16) else { return nil }
            d.append(b)
            i = j
        }
        self = d
    }
}

func parseJSONObject(_ s: String) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any]
}

func jsonString(_ obj: Any, pretty: Bool = false) throws -> String {
    var opts: JSONSerialization.WritingOptions = [.withoutEscapingSlashes]
    if pretty { opts.insert(.prettyPrinted) }
    return String(decoding: try JSONSerialization.data(withJSONObject: obj, options: opts), as: UTF8.self)
}

// MARK: - State

struct CodeProfile: Codable {
    var id: String
    var name: String
    var email: String
    var org: String
    var key: String              // accountUuid|organizationUuid
    var oauthAccountJSON: String // copy of ~/.claude.json → oauthAccount
}

struct DesktopProfile: Codable {
    var id: String
    var name: String
    var accountUuid: String? // from the profile's config.json → lastKnownAccountUuid
}

struct State: Codable {
    var code: [CodeProfile] = []
    var desktop: [DesktopProfile] = []
    var activeDesktopID: String?
    var showNameInMenuBar = true
    var showUsageInMenuBar = true
    var confirmDesktopSwitch = true

    init() {}

    // Tolerate missing keys so adding a setting never wipes saved profiles.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decodeIfPresent([CodeProfile].self, forKey: .code) ?? []
        desktop = try c.decodeIfPresent([DesktopProfile].self, forKey: .desktop) ?? []
        activeDesktopID = try c.decodeIfPresent(String.self, forKey: .activeDesktopID)
        showNameInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showNameInMenuBar) ?? true
        showUsageInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showUsageInMenuBar) ?? true
        confirmDesktopSwitch = try c.decodeIfPresent(Bool.self, forKey: .confirmDesktopSwitch) ?? true
    }

    static func load() -> State {
        guard let d = try? Data(contentsOf: stateFile),
              let s = try? JSONDecoder().decode(State.self, from: d) else { return State() }
        return s
    }

    func save() {
        try? fm.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(self).write(to: stateFile, options: .atomic)
    }
}

// MARK: - Claude Code accounts

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
    static func snapshot(into state: inout State) throws -> String? {
        guard let cur = current() else { return nil }
        try Keychain.write(service: switcherKeychainService, account: "code-" + profileID(for: cur, in: &state),
                           value: try jsonString(cur.claudeAiOauth))
        return state.code.first { $0.key == cur.key }?.id
    }

    private static func profileID(for cur: Current, in state: inout State) throws -> String {
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

    static func switchTo(_ target: CodeProfile, state: inout State) throws {
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

    static func remove(_ p: CodeProfile, state: inout State) {
        Keychain.delete(service: switcherKeychainService, account: "code-" + p.id)
        state.code.removeAll { $0.id == p.id }
    }
}

// MARK: - Claude Desktop accounts

enum ClaudeDesktop {
    static func dir(for id: String) -> URL { desktopStore.appendingPathComponent(id) }

    /// The account a Desktop data folder is signed in to (matches oauthAccount.accountUuid).
    static func accountUuid(in folder: URL) -> String? {
        guard let d = try? Data(contentsOf: folder.appendingPathComponent("config.json")),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }
        return obj["lastKnownAccountUuid"] as? String
    }

    /// Registers the live folder as a profile on first run and keeps every
    /// profile's account id current (the user may sign in/out inside Claude).
    static func sync(_ state: inout State) {
        guard isInstalled else { return }
        if state.activeDesktopID == nil, fm.fileExists(atPath: desktopLiveDir.path) {
            let p = DesktopProfile(id: UUID().uuidString, name: "Desktop")
            state.desktop.append(p)
            state.activeDesktopID = p.id
        }
        for i in state.desktop.indices {
            let folder = state.desktop[i].id == state.activeDesktopID ? desktopLiveDir : dir(for: state.desktop[i].id)
            if let uuid = accountUuid(in: folder) { state.desktop[i].accountUuid = uuid }
        }
    }

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: desktopBundleID) != nil
    }

    static func quit() throws {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: desktopBundleID)
        apps.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(20)
        while apps.contains(where: { !$0.isTerminated }) {
            if Date() > deadline { throw SwitcherError("Claude didn't quit. Quit it yourself, then try again.") }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        // Let helper processes release their files.
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
    }

    static func launch() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: desktopBundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    /// Moves the live folder into the store under `activeID`.
    static func stashLive(as activeID: String) throws {
        try fm.createDirectory(at: desktopStore, withIntermediateDirectories: true)
        let dest = dir(for: activeID)
        if fm.fileExists(atPath: dest.path) {
            throw SwitcherError("A stored folder already exists for the active profile — refusing to overwrite it.")
        }
        if fm.fileExists(atPath: desktopLiveDir.path) {
            try fm.moveItem(at: desktopLiveDir, to: dest)
        }
    }

    static func switchTo(_ target: DesktopProfile, state: inout State) throws {
        guard let active = state.activeDesktopID else { throw SwitcherError("Save the current Desktop login first.") }
        let src = dir(for: target.id)
        guard fm.fileExists(atPath: src.path) else { throw SwitcherError("Stored data for \(target.name) is missing.") }
        try quit()
        try stashLive(as: active)
        do {
            try fm.moveItem(at: src, to: desktopLiveDir)
        } catch {
            try? fm.moveItem(at: dir(for: active), to: desktopLiveDir) // roll back
            throw error
        }
        state.activeDesktopID = target.id
        launch()
    }

    static func addNew(named name: String, state: inout State) throws {
        guard let active = state.activeDesktopID else { throw SwitcherError("Save the current Desktop login first.") }
        try quit()
        try stashLive(as: active)
        let p = DesktopProfile(id: UUID().uuidString, name: name)
        state.desktop.append(p)
        state.activeDesktopID = p.id
        launch() // starts with an empty folder → login screen
    }

    static func remove(_ p: DesktopProfile, state: inout State) {
        let d = dir(for: p.id)
        if fm.fileExists(atPath: d.path) { try? fm.trashItem(at: d, resultingItemURL: nil) }
        state.desktop.removeAll { $0.id == p.id }
    }
}

// MARK: - Usage limits

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

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var state = State.load()
    var usage: [String: UsageState] = [:]      // profile id → usage
    var usageItems: [String: NSMenuItem] = [:] // live rows in the open menu
    var lastUsageFetch = Date.distantPast
    var timer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "person.2.circle", accessibilityDescription: "Claude accounts")
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshCodeSnapshot()
        updateButton()
        refreshUsage()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshUsage() }
        }
    }

    // MARK: Usage

    func refreshUsage() {
        lastUsageFetch = Date()
        let activeKey = ClaudeCode.current()?.key
        for p in state.code {
            if case .ok = usage[p.id] {} else { usage[p.id] = .loading }
            Task { await self.fetchUsage(p, active: p.key == activeKey) }
        }
        renderUsageItems()
    }

    func fetchUsage(_ p: CodeProfile, active: Bool) async {
        do {
            guard var oauth = ClaudeCode.oauth(for: p, active: active) else {
                throw SwitcherError("No saved login")
            }
            if ClaudeAPI.isExpired(oauth) {
                oauth = try await ClaudeAPI.refresh(oauth)
                try ClaudeCode.saveOAuth(oauth, for: p, active: active)
            }
            var windows: [ClaudeAPI.Window]
            do {
                windows = try await ClaudeAPI.usage(token: oauth["accessToken"] as? String ?? "")
            } catch let e as SwitcherError where e.message == "unauthorized" {
                oauth = try await ClaudeAPI.refresh(oauth)
                try ClaudeCode.saveOAuth(oauth, for: p, active: active)
                windows = try await ClaudeAPI.usage(token: oauth["accessToken"] as? String ?? "")
            }
            usage[p.id] = .ok(windows, Date())
        } catch {
            usage[p.id] = .failed(error.localizedDescription)
        }
        renderUsageItems()
        updateButton()
    }

    func renderUsageItems() {
        for (id, item) in usageItems { item.attributedTitle = usageText(id) }
    }

    func usageText(_ id: String) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let text: String
        switch usage[id] {
        case .ok(let windows, _) where !windows.isEmpty:
            text = windows.map { w in
                let label = w.label.padding(toLength: 13, withPad: " ", startingAt: 0)
                let pct = String(format: "%3.0f%%", w.utilization)
                let reset = w.resetsAt.map { "  resets " + relative($0) } ?? ""
                return "\(label) \(bar(w.utilization)) \(pct)\(reset)"
            }.joined(separator: "\n")
        case .ok: text = "No usage limits reported"
        case .failed(let msg): text = "⚠︎ " + msg
        case .loading, nil: text = "Loading usage…"
        }
        return NSAttributedString(string: text, attributes: attrs)
    }

    func bar(_ pct: Double) -> String {
        let filled = Int((min(max(pct, 0), 100) / 10).rounded())
        return String(repeating: "▰", count: filled) + String(repeating: "▱", count: 10 - filled)
    }

    func relative(_ d: Date) -> String {
        let s = max(0, d.timeIntervalSinceNow)
        if s < 3600 { return "in \(Int(s / 60))m" }
        if s < 86400 { return "in \(Int(s / 3600))h \(Int(s.truncatingRemainder(dividingBy: 3600) / 60))m" }
        let f = DateFormatter(); f.dateFormat = "EEE h:mm a"
        return f.string(from: d)
    }

    func sessionPercent(_ id: String) -> Double? {
        if case .ok(let w, _) = usage[id] { return w.first { $0.label == "Session" }?.utilization }
        return nil
    }

    func refreshCodeSnapshot() {
        _ = try? ClaudeCode.snapshot(into: &state)
        ClaudeDesktop.sync(&state)
        state.save()
    }

    /// One row per account: its CLI login and/or its Claude Desktop profile.
    struct Account {
        var code: CodeProfile?
        var desktop: DesktopProfile?
        var id: String { code.map { "code:" + $0.id } ?? "desktop:" + (desktop?.id ?? "") }
        var accountUuid: String? { code.map { String($0.key.split(separator: "|")[0]) } ?? desktop?.accountUuid }
    }

    var accounts: [Account] {
        var rows = state.code.map { c -> Account in
            let uuid = String(c.key.split(separator: "|")[0])
            let matches = state.desktop.filter { $0.accountUuid == uuid }
            return Account(code: c, desktop: matches.first { $0.id == state.activeDesktopID } ?? matches.first)
        }
        for d in state.desktop where !rows.contains(where: { $0.desktop?.id == d.id }) {
            rows.append(Account(code: nil, desktop: d))
        }
        return rows
    }

    func displayName(_ a: Account) -> String {
        if let p = a.code {
            return p.org.isEmpty || p.org.contains(p.email) || p.name.contains(p.org) ? p.name : "\(p.name)  —  \(p.org)"
        }
        let d = a.desktop!
        return d.accountUuid == nil ? "\(d.name) (signed out)" : "\(d.name) (Desktop only)"
    }

    var activeDesktopUuid: String? { state.desktop.first { $0.id == state.activeDesktopID }?.accountUuid }

    var activeCodeProfile: CodeProfile? {
        guard let cur = ClaudeCode.current() else { return nil }
        return state.code.first { $0.key == cur.key }
    }

    func updateButton() {
        let active = activeCodeProfile
        var parts: [String] = []
        if state.showNameInMenuBar, let a = active { parts.append(short(a.name)) }
        if state.showUsageInMenuBar, let id = active?.id, let pct = sessionPercent(id) {
            parts.append(String(format: "%.0f%%", pct))
        }
        statusItem.button?.title = parts.isEmpty ? "" : " " + parts.joined(separator: " · ")
        statusItem.button?.toolTip = "Claude Code: \(activeCodeProfile?.email ?? "not logged in")"
    }

    func short(_ s: String) -> String {
        let base = s.split(separator: "@").first.map(String.init) ?? s
        return base.count > 14 ? String(base.prefix(13)) + "…" : base
    }

    // Rebuild every time it opens so it reflects logins made elsewhere.
    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshCodeSnapshot()
        updateButton()
        if Date().timeIntervalSince(lastUsageFetch) > 60 { refreshUsage() }
        menu.removeAllItems()
        menu.autoenablesItems = false
        usageItems = [:]

        menu.addItem(header("Accounts"))
        let activeKey = ClaudeCode.current()?.key
        let desktopInstalled = ClaudeDesktop.isInstalled
        for a in accounts {
            let cliActive = a.code != nil && a.code?.key == activeKey
            let desktopActive = desktopInstalled && a.accountUuid != nil && a.accountUuid == activeDesktopUuid
            var title = displayName(a)
            // Only call out where it's active when CLI and Desktop disagree.
            if cliActive != desktopActive && desktopInstalled {
                title += cliActive ? "   · CLI" : "   · Desktop"
            }
            let it = item(title, #selector(switchAccount(_:)), a.id)
            it.state = cliActive || desktopActive ? .on : .off
            it.toolTip = a.code?.email
            menu.addItem(it)
            let u = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            u.indentationLevel = 1
            if let c = a.code {
                u.attributedTitle = usageText(c.id)
                usageItems[c.id] = u
            } else {
                u.attributedTitle = NSAttributedString(string: "Usage needs a Claude Code login — use “Add account…”", attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor])
            }
            menu.addItem(u)
        }
        if state.code.isEmpty && state.desktop.isEmpty {
            menu.addItem(disabled("No accounts yet — use “Add account…”"))
        }
        menu.addItem(item("Add account…", #selector(addCode)))

        // Manage
        menu.addItem(.separator())
        let manage = NSMenu()
        let rename = NSMenu(), remove = NSMenu()
        remove.autoenablesItems = false
        for p in state.code {
            rename.addItem(item("Code: \(p.name)", #selector(renameCode(_:)), p.id))
            let r = item("Code: \(p.name)", #selector(removeCode(_:)), p.id)
            if p.key == activeKey { r.isEnabled = false; r.toolTip = "Can't remove the active account" }
            remove.addItem(r)
        }
        for p in state.desktop {
            rename.addItem(item("Desktop: \(p.name)", #selector(renameDesktop(_:)), p.id))
            let r = item("Desktop: \(p.name)", #selector(removeDesktop(_:)), p.id)
            if p.id == state.activeDesktopID { r.isEnabled = false }
            remove.addItem(r)
        }
        manage.addItem(submenu("Rename", rename))
        manage.addItem(submenu("Remove", remove))
        if ClaudeDesktop.isInstalled {
            manage.addItem(item("Add Claude Desktop login…", #selector(addDesktop)))
        }
        manage.addItem(.separator())
        let confirmItem = item("Confirm before restarting Claude Desktop", #selector(toggleConfirmDesktop))
        confirmItem.state = state.confirmDesktopSwitch ? .on : .off
        manage.addItem(confirmItem)
        let showName = item("Show account name in menu bar", #selector(toggleName))
        showName.state = state.showNameInMenuBar ? .on : .off
        manage.addItem(showName)
        let showUsage = item("Show session usage in menu bar", #selector(toggleUsage))
        showUsage.state = state.showUsageInMenuBar ? .on : .off
        manage.addItem(showUsage)
        manage.addItem(item("Refresh usage now", #selector(refreshUsageAction)))
        let login = item("Launch at login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        manage.addItem(login)
        manage.addItem(item("Show data folder", #selector(revealStore)))
        menu.addItem(submenu("Manage", manage))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Claude Switcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    // MARK: Menu builders

    func header(_ t: String) -> NSMenuItem {
        if #available(macOS 14.0, *) { return NSMenuItem.sectionHeader(title: t) }
        return disabled(t)
    }
    func disabled(_ t: String) -> NSMenuItem {
        let i = NSMenuItem(title: t, action: nil, keyEquivalent: ""); i.isEnabled = false; return i
    }
    func item(_ t: String, _ a: Selector, _ rep: String? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: t, action: a, keyEquivalent: "")
        i.target = self
        i.representedObject = rep
        return i
    }
    func submenu(_ t: String, _ m: NSMenu) -> NSMenuItem {
        let i = NSMenuItem(title: t, action: nil, keyEquivalent: ""); i.submenu = m; return i
    }

    // MARK: Claude Code actions

    /// Switches the CLI immediately, then brings Claude Desktop (and its Code tab) to the same account.
    @objc func switchAccount(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let a = accounts.first(where: { $0.id == id }) else { return }
        perform {
            if let c = a.code, c.key != ClaudeCode.current()?.key {
                try ClaudeCode.switchTo(c, state: &state)
                refreshUsage()
            }
            try switchDesktop(to: a)
        }
    }

    func switchDesktop(to a: Account) throws {
        guard ClaudeDesktop.isInstalled, state.activeDesktopID != nil else { return }
        if let target = a.desktop {
            guard target.id != state.activeDesktopID else { return }
            guard confirmDesktop("Switch Claude Desktop to \(displayName(a))?",
                                 "Claude will quit and reopen. Chats and Code sessions running in it will stop.") else { return }
            try ClaudeDesktop.switchTo(target, state: &state)
        } else if let uuid = a.accountUuid, uuid != activeDesktopUuid, let c = a.code {
            guard confirm("\(c.email) isn't signed in to Claude Desktop yet",
                          "Claude will quit and reopen signed out. Sign in as \(c.email) and it'll be linked to this account automatically. Your current Desktop login is kept.",
                          "Set Up Desktop") else { return }
            try ClaudeDesktop.addNew(named: c.name, state: &state)
        }
    }

    func confirmDesktop(_ title: String, _ text: String) -> Bool {
        guard state.confirmDesktopSwitch else { return true }
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = title; a.informativeText = text
        a.addButton(withTitle: "Switch"); a.addButton(withTitle: "Cancel")
        a.showsSuppressionButton = true
        a.suppressionButton?.title = "Don't ask again"
        let ok = a.runModal() == .alertFirstButtonReturn
        if ok && a.suppressionButton?.state == .on { state.confirmDesktopSwitch = false }
        return ok
    }

    @objc func addCode() {
        let ok = confirm("Add a Claude Code account",
                         "Your current login is saved. A Terminal window will run `claude auth login` — sign in with the other account, then open this menu again and it'll be listed. Clicking it the first time offers to sign Claude Desktop in too.\n\nDon't use “logout”: it can revoke the saved login.",
                         "Open Terminal")
        guard ok else { return }
        perform {
            try ClaudeCode.snapshot(into: &state)
            let script = "tell application \"Terminal\"\n activate\n do script \"claude auth login\"\nend tell"
            var err: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&err)
            if let err { throw SwitcherError("Couldn't open Terminal: \(err)") }
        }
    }

    @objc func renameCode(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let i = state.code.firstIndex(where: { $0.id == id }),
              let name = ask("Rename account", state.code[i].email, default: state.code[i].name) else { return }
        state.code[i].name = name
        state.save(); updateButton()
    }

    @objc func removeCode(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let p = state.code.first(where: { $0.id == id }),
              confirm("Remove \(p.name)?", "The saved login is deleted from Claude Switcher. The account itself isn't affected.", "Remove") else { return }
        ClaudeCode.remove(p, state: &state)
        state.save()
    }

    // MARK: Claude Desktop actions

    @objc func addDesktop() {
        guard let name = ask("Add a Claude Desktop account",
                             "Claude will quit and reopen signed out so you can log in. Your current login is kept.",
                             default: "Work") else { return }
        perform { try ClaudeDesktop.addNew(named: name, state: &state) }
    }

    @objc func renameDesktop(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let i = state.desktop.firstIndex(where: { $0.id == id }),
              let name = ask("Rename profile", "", default: state.desktop[i].name) else { return }
        state.desktop[i].name = name
        state.save()
    }

    @objc func removeDesktop(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let p = state.desktop.first(where: { $0.id == id }),
              confirm("Remove \(p.name)?", "Its stored Claude Desktop data is moved to the Trash.", "Remove") else { return }
        ClaudeDesktop.remove(p, state: &state)
        state.save()
    }

    // MARK: Misc actions

    @objc func toggleName() {
        state.showNameInMenuBar.toggle(); state.save(); updateButton()
    }

    @objc func toggleConfirmDesktop() {
        state.confirmDesktopSwitch.toggle(); state.save()
    }

    @objc func toggleUsage() {
        state.showUsageInMenuBar.toggle(); state.save(); updateButton()
    }

    @objc func refreshUsageAction() { refreshUsage() }

    @objc func toggleLogin() {
        perform {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        }
    }

    @objc func revealStore() {
        try? fm.createDirectory(at: storeDir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([storeDir])
    }

    // MARK: Dialog helpers

    func perform(_ body: () throws -> Void) {
        do { try body() } catch { alert("Something went wrong", error.localizedDescription) }
        state.save()
        updateButton()
    }

    func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal()
    }

    func notify(_ title: String, _ text: String) { alert(title, text) }

    func confirm(_ title: String, _ text: String, _ button: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = title; a.informativeText = text
        a.addButton(withTitle: button); a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn
    }

    func ask(_ title: String, _ text: String, default value: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = title; a.informativeText = text
        a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = value
        a.accessoryView = field
        a.window.initialFirstResponder = field
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        let s = field.stringValue.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? nil : s
    }
}

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

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
