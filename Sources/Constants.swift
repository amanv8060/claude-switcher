import AppKit

let fm = FileManager.default
let home = fm.homeDirectoryForCurrentUser
let appSupport = home.appendingPathComponent("Library/Application Support")
let storeDir = appSupport.appendingPathComponent("ClaudeSwitcher")
let stateFile = storeDir.appendingPathComponent("state.json")
let desktopStore = storeDir.appendingPathComponent("desktop")
let sharedSessionsDir = storeDir.appendingPathComponent("shared")
let desktopLiveDir = appSupport.appendingPathComponent("Claude")
let claudeJSON = home.appendingPathComponent(".claude.json")

let codeKeychainService = "Claude Code-credentials"
let switcherKeychainService = "ClaudeSwitcher"
let desktopBundleID = "com.anthropic.claudefordesktop"
