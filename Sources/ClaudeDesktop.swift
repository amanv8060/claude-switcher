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
    static func sync(_ state: inout AppState) {
        guard isInstalled else { return }
        if state.activeDesktopID == nil, fm.fileExists(atPath: desktopLiveDir.path) {
            let p = DesktopProfile(id: UUID().uuidString, name: "Desktop")
            state.desktop.append(p)
            state.activeDesktopID = p.id
        }
        for i in state.desktop.indices {
            if let uuid = accountUuid(in: folder(for: state.desktop[i], state: state)) {
                state.desktop[i].accountUuid = uuid
                // First sign-in links the profile; later changes count as a mismatch.
                if state.desktop[i].linkedAccountUuid == nil { state.desktop[i].linkedAccountUuid = uuid }
            }
        }
    }

    static func folder(for p: DesktopProfile, state: AppState) -> URL {
        p.id == state.activeDesktopID ? desktopLiveDir : dir(for: p.id)
    }

    // MARK: Shared session history

    /// Desktop keeps Code and agent sessions in per-account folders
    /// (<folder>/<accountUuid>/<orgUuid>/…), so every profile can hold all of
    /// them without collisions. Keeping one shared copy means history never gets
    /// stranded in a profile that isn't live.
    static let sessionFolders = ["claude-code-sessions", "local-agent-mode-sessions"]

    /// Copies a profile's sessions into the shared store. Only reads `profileDir`.
    static func collectSessions(from profileDir: URL) {
        for name in sessionFolders {
            merge(profileDir.appendingPathComponent(name), into: sharedSessionsDir.appendingPathComponent(name))
        }
    }

    /// Copies the shared sessions into a profile. Only call while Claude is quit.
    static func distributeSessions(into profileDir: URL) {
        for name in sessionFolders {
            merge(sharedSessionsDir.appendingPathComponent(name), into: profileDir.appendingPathComponent(name))
        }
    }

    /// Gathers every profile's sessions into the shared store (reads only).
    static func collectAllSessions(_ state: AppState) {
        for p in state.desktop { collectSessions(from: folder(for: p, state: state)) }
    }

    /// Copies files from `src` into `dst`, keeping whichever copy is newer. Never deletes.
    static func merge(_ src: URL, into dst: URL) {
        let src = src.resolvingSymlinksInPath()
        guard let files = fm.enumerator(at: src, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        for case let file as URL in files {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let rel = file.resolvingSymlinksInPath().pathComponents.dropFirst(src.pathComponents.count)
            let target = rel.reduce(dst) { $0.appendingPathComponent($1) }
            if let have = modified(target), let new = modified(file), have >= new { continue }
            do {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try fm.copyItem(at: file, to: target)
            } catch {
                NSLog("Claude Switcher: couldn't copy session file \(rel.joined(separator: "/")): \(error)")
            }
        }
    }

    private static func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
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

    static func switchTo(_ target: DesktopProfile, state: inout AppState) throws {
        guard let active = state.activeDesktopID else { throw SwitcherError("Save the current Desktop login first.") }
        let src = dir(for: target.id)
        guard fm.fileExists(atPath: src.path) else { throw SwitcherError("Stored data for \(target.name) is missing.") }
        try quit()
        collectSessions(from: desktopLiveDir)
        try stashLive(as: active)
        do {
            try fm.moveItem(at: src, to: desktopLiveDir)
        } catch {
            try? fm.moveItem(at: dir(for: active), to: desktopLiveDir) // roll back
            throw error
        }
        state.activeDesktopID = target.id
        distributeSessions(into: desktopLiveDir)
        launch()
    }

    /// Starts a fresh, signed-out profile. `account` is who it's meant for, if known.
    static func addNew(named name: String, for account: String?, state: inout AppState) throws {
        guard let active = state.activeDesktopID else { throw SwitcherError("Save the current Desktop login first.") }
        try quit()
        collectSessions(from: desktopLiveDir)
        try stashLive(as: active)
        let p = DesktopProfile(id: UUID().uuidString, name: name, linkedAccountUuid: account)
        state.desktop.append(p)
        state.activeDesktopID = p.id
        launch() // starts with an empty folder → login screen
    }

    static func remove(_ p: DesktopProfile, state: inout AppState) {
        let d = dir(for: p.id)
        collectSessions(from: d) // keep its history before it goes to the Trash
        if fm.fileExists(atPath: d.path) { try? fm.trashItem(at: d, resultingItemURL: nil) }
        state.desktop.removeAll { $0.id == p.id }
    }
}
