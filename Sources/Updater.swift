import AppKit

/// Checks GitHub for a newer release and upgrades through Homebrew when the app
/// was installed with it.
enum Updater {
    static let repo = "amanv8060/claude-switcher"
    static let caskName = "claude-switcher"

    struct Release { let version: String; let url: URL }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// github.com/<repo>/releases/latest redirects to the newest release's page
    /// (…/releases/tag/vX.Y.Z). Unlike the REST API, it isn't rate-limited per IP,
    /// which matters on shared VPN or relay addresses.
    static func latestRelease() async throws -> Release {
        var req = URLRequest(url: URL(string: "https://github.com/\(repo)/releases/latest")!)
        req.httpMethod = "HEAD"
        req.setValue("ClaudeSwitcher/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200, let page = http.url,
              page.pathComponents.dropLast().last == "tag" else {
            throw SwitcherError("Couldn't check for updates")
        }
        let tag = page.lastPathComponent
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, url: page)
    }

    /// Compares dotted versions numerically ("1.10.0" > "1.9.2").
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    static var brewPath: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { fm.isExecutableFile(atPath: $0) }
    }

    /// True when this copy came from the Homebrew cask.
    static var installedWithHomebrew: Bool {
        ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"].contains {
            fm.fileExists(atPath: "\($0)/\(caskName)")
        } && brewPath != nil
    }

    /// Runs the Homebrew upgrade in Terminal, where its progress is visible.
    /// Homebrew quits this app during the upgrade and reopens it afterwards.
    static func upgradeWithHomebrew() throws {
        guard let brew = brewPath else { throw SwitcherError("Homebrew isn't installed") }
        let command = "\(brew) update && \(brew) upgrade --cask \(caskName)"
        let script = "tell application \"Terminal\"\n activate\n do script \"\(command)\"\nend tell"
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        if let err { throw SwitcherError("Couldn't open Terminal: \(err)") }
    }
}
