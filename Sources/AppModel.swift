import AppKit
import ServiceManagement

/// One row per account: its CLI login and/or its Claude Desktop profile.
struct Account: Identifiable {
    var code: CodeProfile?
    var desktop: DesktopProfile?
    var id: String { code.map { "code:" + $0.id } ?? "desktop:" + (desktop?.id ?? "") }
    var accountUuid: String? { code.map { String($0.key.split(separator: "|")[0]) } ?? desktop?.accountUuid }
}

/// All app state and actions. The popover and the status item observe it.
@MainActor
final class AppModel: ObservableObject {
    @Published var state: AppState
    @Published var usage: [String: UsageState] = [:] // CLI profile id → usage
    @Published var plans: [String: String] = [:]      // CLI profile id → "Max 20x"
    @Published var activeKey: String?
    @Published var lastUsageFetch = Date.distantPast
    @Published var busy = false
    let desktopInstalled: Bool
    let isPreview: Bool

    /// Called before showing a dialog, so the popover gets out of the way.
    var dismissPopover: () -> Void = {}
    private var timer: Timer?

    init() {
        state = AppState.load()
        desktopInstalled = ClaudeDesktop.isInstalled
        isPreview = false
        refresh()
        refreshUsage()
        // Gather every profile's Code sessions into the shared store (reads profiles only).
        let snapshot = state
        DispatchQueue.global(qos: .utility).async { ClaudeDesktop.collectAllSessions(snapshot) }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshUsage() }
        }
    }

    /// Sample data for `--render-preview`; touches nothing on disk.
    init(preview: Void) {
        isPreview = true
        desktopInstalled = true
        var s = AppState()
        func code(_ name: String, _ email: String, _ org: String, _ uuid: String) -> CodeProfile {
            CodeProfile(id: uuid, name: name, email: email, org: org, key: "\(uuid)|org", oauthAccountJSON: "{}")
        }
        s.code = [code("Personal", "aman@example.com", "", "u1"),
                  code("Work", "aman@acme.example", "Acme Inc", "u2")]
        s.desktop = [DesktopProfile(id: "d1", name: "Desktop", accountUuid: "u1"),
                     DesktopProfile(id: "d3", name: "Side project", accountUuid: "u3")]
        s.activeDesktopID = "d1"
        state = s
        activeKey = "u1|org"
        lastUsageFetch = Date().addingTimeInterval(-90)
        let now = Date()
        func w(_ l: String, _ u: Double, _ h: Double) -> ClaudeAPI.Window {
            .init(label: l, utilization: u, resetsAt: now.addingTimeInterval(h * 3600))
        }
        plans = ["u1": "Max 20x", "u2": "Pro"]
        usage = ["u1": .ok([w("Session", 34, 2.2), w("Week", 61, 70)], now),
                 "u2": .ok([w("Session", 18, 4.1), w("Week", 27, 120), w("Week · Opus", 12, 120)], now)]
    }

    // MARK: Derived

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

    var activeDesktopUuid: String? { state.desktop.first { $0.id == state.activeDesktopID }?.accountUuid }
    var activeCode: CodeProfile? { state.code.first { $0.key == activeKey } }

    func isCLIActive(_ a: Account) -> Bool { a.code != nil && a.code?.key == activeKey }
    /// Only the profile that's actually live counts, even if another profile is
    /// signed in to the same account.
    func isDesktopActive(_ a: Account) -> Bool {
        desktopInstalled && a.desktop != nil && a.desktop?.id == state.activeDesktopID
    }

    /// Desktop profiles signed in to a different account than the one they belong to.
    var mismatchedProfiles: [DesktopProfile] { state.desktop.filter(\.isMismatched) }

    /// "aman@example.com" for a known account ID, else a generic label.
    func label(forAccount uuid: String?) -> String {
        state.code.first { $0.key.hasPrefix((uuid ?? "-") + "|") }?.email ?? "another account"
    }

    /// Accept the account Desktop is now signed in to as this profile's account.
    func relink(_ p: DesktopProfile) {
        guard let i = state.desktop.firstIndex(where: { $0.id == p.id }) else { return }
        state.desktop[i].linkedAccountUuid = state.desktop[i].accountUuid
        state.save()
    }

    func renameProfile(_ p: DesktopProfile) {
        guard let i = state.desktop.firstIndex(where: { $0.id == p.id }),
              let n = ask("Rename Desktop profile", "", default: p.name) else { return }
        state.desktop[i].name = n
        state.save()
    }

    func name(_ a: Account) -> String { a.code?.name ?? a.desktop?.name ?? "Account" }

    func subtitle(_ a: Account) -> String {
        if let c = a.code {
            let org = c.org.isEmpty || c.org.contains(c.email) ? "" : " · \(c.org)"
            return c.name == c.email ? (org.isEmpty ? "Claude Code" : String(org.dropFirst(3))) : c.email + org
        }
        return a.desktop?.accountUuid == nil ? "Claude Desktop · signed out" : "Claude Desktop only"
    }

    /// The account shown large at the top: the CLI's, else the Desktop app's.
    var hero: Account? { accounts.first(where: isCLIActive) ?? accounts.first(where: isDesktopActive) }
    var others: [Account] { accounts.filter { $0.id != hero?.id } }
    var isLoadingUsage: Bool { usage.values.contains { if case .loading = $0 { return true } else { return false } } }

    /// Headroom left on an account: the tighter of its session and weekly limits (0–100).
    func remaining(_ a: Account) -> Double? {
        guard let id = a.code?.id, case .ok(let w, _) = usage[id] else { return nil }
        let used = w.filter { $0.label == "Session" || $0.label == "Week" }.map(\.utilization)
        return used.isEmpty ? nil : 100 - (used.max() ?? 0)
    }

    /// The account with the most headroom, if it beats the current one by a useful margin.
    var smartPick: (account: Account, remaining: Double)? {
        let scored = accounts.compactMap { a in remaining(a).map { (account: a, remaining: $0) } }
        guard let best = scored.max(by: { $0.remaining < $1.remaining }), best.account.id != hero?.id else { return nil }
        let current = hero.flatMap(remaining) ?? 0
        return best.remaining - current >= 10 ? best : nil
    }

    func sessionPercent(_ id: String) -> Double? {
        if case .ok(let w, _) = usage[id] { return w.first { $0.label == "Session" }?.utilization }
        return nil
    }

    // MARK: Refresh

    func refresh() {
        guard !isPreview else { return }
        _ = try? ClaudeCode.snapshot(into: &state)
        ClaudeDesktop.sync(&state)
        activeKey = ClaudeCode.current()?.key
        state.save()
        if Date().timeIntervalSince(lastUsageFetch) > 60 { refreshUsage() }
    }

    func refreshUsage() {
        guard !isPreview else { return }
        lastUsageFetch = Date()
        for p in state.code {
            if case .ok = usage[p.id] {} else { usage[p.id] = .loading }
            let active = p.key == activeKey
            Task { await self.fetchUsage(p, active: active) }
        }
    }

    private func fetchUsage(_ p: CodeProfile, active: Bool) async {
        do {
            guard var oauth = ClaudeCode.oauth(for: p, active: active) else { throw SwitcherError("No saved login") }
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
            plans[p.id] = ClaudeAPI.planName(oauth)
        } catch {
            usage[p.id] = .failed(error.localizedDescription)
        }
    }

    // MARK: Switching

    /// Switches the CLI immediately, then brings Claude Desktop (and its Code tab) to the same account.
    func switchTo(_ a: Account) {
        guard !isPreview else { return }
        perform {
            if let c = a.code, c.key != ClaudeCode.current()?.key {
                try ClaudeCode.switchTo(c, state: &state)
                activeKey = ClaudeCode.current()?.key
                refreshUsage()
            }
            try switchDesktop(to: a)
        }
    }

    private func switchDesktop(to a: Account) throws {
        guard desktopInstalled, state.activeDesktopID != nil else { return }
        if let target = a.desktop {
            guard target.id != state.activeDesktopID else { return }
            guard confirmDesktop("Switch Claude Desktop to \(name(a))?",
                                 "Claude will quit and reopen. Chats and Code sessions running in it will stop.") else { return }
            try ClaudeDesktop.switchTo(target, state: &state)
        } else if let uuid = a.accountUuid, uuid != activeDesktopUuid, let c = a.code {
            guard confirm("\(c.email) isn't signed in to Claude Desktop yet",
                          "Claude will quit and reopen signed out. Sign in as \(c.email) and it'll be linked to this account automatically. Your current Desktop login is kept.",
                          "Set Up Desktop") else { return }
            try ClaudeDesktop.addNew(named: c.name, for: uuid, state: &state)
        }
    }

    private func confirmDesktop(_ title: String, _ text: String) -> Bool {
        guard state.confirmDesktopSwitch else { return true }
        let a = makeAlert(title, text)
        a.addButton(withTitle: "Switch"); a.addButton(withTitle: "Cancel")
        a.showsSuppressionButton = true
        a.suppressionButton?.title = "Don't ask again"
        let ok = a.runModal() == .alertFirstButtonReturn
        if ok && a.suppressionButton?.state == .on { state.confirmDesktopSwitch = false }
        return ok
    }

    // MARK: Account management

    func addAccount() {
        guard confirm("Add a Claude account",
                      "Your current login is saved. Terminal will run `claude auth login`. Sign in with the other account and it appears here. Clicking it the first time offers to sign Claude Desktop in too.\n\nDon't use “logout” to change accounts: it can revoke the saved login.",
                      "Open Terminal") else { return }
        perform {
            try ClaudeCode.snapshot(into: &state)
            let script = "tell application \"Terminal\"\n activate\n do script \"claude auth login\"\nend tell"
            var err: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&err)
            if let err { throw SwitcherError("Couldn't open Terminal: \(err)") }
        }
    }

    func addDesktopLogin() {
        guard let n = ask("Add a Claude Desktop login",
                          "Claude will quit and reopen signed out so you can sign in. Your current login is kept.",
                          default: "Work") else { return }
        perform { try ClaudeDesktop.addNew(named: n, for: nil, state: &state) }
    }

    func rename(_ a: Account) {
        guard let n = ask("Rename account", a.code?.email ?? "", default: name(a)) else { return }
        if let c = a.code, let i = state.code.firstIndex(where: { $0.id == c.id }) { state.code[i].name = n }
        if let d = a.desktop, let i = state.desktop.firstIndex(where: { $0.id == d.id }) { state.desktop[i].name = n }
        state.save()
    }

    func canRemove(_ a: Account) -> Bool { !isCLIActive(a) && !isDesktopActive(a) }

    func remove(_ a: Account) {
        guard canRemove(a), confirm("Remove \(name(a))?",
                                    "Its saved logins (and stored Claude Desktop data, moved to the Trash) are removed from Claude Switcher. The account itself isn't affected.",
                                    "Remove") else { return }
        if let c = a.code { ClaudeCode.remove(c, state: &state) }
        if let d = a.desktop { ClaudeDesktop.remove(d, state: &state) }
        state.save()
    }

    // MARK: Settings

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func toggleLaunchAtLogin() {
        perform {
            if launchAtLogin { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        }
        objectWillChange.send()
    }

    func revealDataFolder() {
        try? fm.createDirectory(at: storeDir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([storeDir])
    }

    // MARK: Dialogs

    func perform(_ body: () throws -> Void) {
        busy = true
        do { try body() } catch { alert("Something went wrong", error.localizedDescription) }
        busy = false
        state.save()
    }

    private func makeAlert(_ title: String, _ text: String) -> NSAlert {
        dismissPopover()
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = title; a.informativeText = text
        return a
    }

    func alert(_ title: String, _ text: String) { makeAlert(title, text).runModal() }

    func confirm(_ title: String, _ text: String, _ button: String) -> Bool {
        let a = makeAlert(title, text)
        a.addButton(withTitle: button); a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn
    }

    func ask(_ title: String, _ text: String, default value: String) -> String? {
        let a = makeAlert(title, text)
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
