import AppKit

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
