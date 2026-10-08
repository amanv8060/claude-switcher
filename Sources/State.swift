import Foundation

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
