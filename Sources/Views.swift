import SwiftUI

// One accent (clay) for the main action and the current-account marker.
// Usage bars stay neutral and only turn amber/red when a limit is close.
extension Color {
    static let brand = Color(red: 0.80, green: 0.42, blue: 0.29)
    static let warn = Color(red: 0.85, green: 0.58, blue: 0.16)
    static let bad = Color(red: 0.82, green: 0.30, blue: 0.26)

    /// Three deliberate text levels.
    static let text1 = Color.primary.opacity(0.88)
    static let text2 = Color.primary.opacity(0.62)
    static let text3 = Color.primary.opacity(0.45)

    static func usage(_ fraction: Double) -> Color {
        fraction >= 0.9 ? .bad : fraction >= 0.7 ? .warn : Color.primary.opacity(0.42)
    }
}

/// Warm off-white window, deep warm grey in dark mode.
struct WindowBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        scheme == .dark ? Color(red: 0.155, green: 0.148, blue: 0.140) : Color(red: 0.985, green: 0.978, blue: 0.968)
    }
}

/// The app icon, used in the popover header.
let appLogo: NSImage = Bundle.main.image(forResource: "AppIcon") ?? NSApp?.applicationIconImage ?? NSImage()

// MARK: - Popover

struct PopoverView: View {
    @ObservedObject var model: AppModel
    var onSettings: () -> Void = {}
    var onQuit: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(model.mismatchedProfiles, id: \.id) { p in
                MismatchNotice(model: model, profile: p)
            }
            if let hero = model.hero {
                CurrentAccount(model: model, account: hero).padding(.horizontal, 8)
            } else {
                emptyState
            }
            if let pick = model.smartPick {
                Divider().padding(.horizontal, 16).padding(.top, 8)
                Recommendation(model: model, account: pick.account, remaining: pick.remaining)
            }
            if !model.others.isEmpty {
                Text("Other accounts")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 4)
                VStack(spacing: 0) {
                    ForEach(Array(model.others.enumerated()), id: \.element.id) { i, a in
                        if i > 0 { Divider().padding(.leading, 54).padding(.trailing, 16) }
                        AccountRow(model: model, account: a, shortcut: i + 2)
                    }
                }
            }
            Divider().padding(.top, 8)
            footer
        }
        .frame(width: 360)
        .background(WindowBackground())
        .overlay { if model.busy { BusyOverlay() } }
        .background(shortcuts)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: appLogo).resizable().frame(width: 22, height: 22)
            Text("Claude Switcher").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.text1)
            Spacer()
            Text(updatedText).font(.system(size: 11)).foregroundStyle(Color.text3)
            IconButton(symbol: "arrow.clockwise", help: "Refresh usage", spinning: model.isLoadingUsage) {
                model.refresh(); model.refreshUsage()
            }
            IconButton(symbol: "gearshape", help: "Settings", action: onSettings)
        }
        .padding(.leading, 16).padding(.trailing, 10)
        .padding(.vertical, 12)
    }

    private var updatedText: String {
        if model.lastUsageFetch == .distantPast { return "" }
        let s = Date().timeIntervalSince(model.lastUsageFetch)
        return s < 60 ? "Updated now" : "Updated \(Int(s / 60))m ago"
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("No accounts yet").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.text1)
            Text("Sign in to Claude Code and it shows up here.")
                .font(.system(size: 12)).foregroundStyle(Color.text2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            QuietButton(title: "Add account", symbol: "plus", action: model.addAccount)
            Spacer()
            if !model.others.isEmpty {
                Text("⌘1–\(min(model.others.count + 1, 9)) to switch")
                    .font(.system(size: 11)).foregroundStyle(Color.text2)
            }
            QuietButton(title: "Quit", action: onQuit).keyboardShortcut("q")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Invisible buttons that give ⌘1…⌘9 to the accounts in display order.
    private var shortcuts: some View {
        let ordered = (model.hero.map { [$0] } ?? []) + model.others
        return ZStack {
            ForEach(Array(ordered.prefix(9).enumerated()), id: \.element.id) { i, a in
                Button("") { model.switchTo(a) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
    }
}

// MARK: - Current account

struct CurrentAccount: View {
    @ObservedObject var model: AppModel
    let account: Account

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Avatar(name: model.name(account), seed: account.accountUuid ?? account.id, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.name(account)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.text1)
                        HStack(spacing: 4) {
                            Circle().fill(Color.brand).frame(width: 6, height: 6)
                            Text("Current").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.brand)
                        }
                    }
                    Text(detailLine).font(.system(size: 11.5)).foregroundStyle(Color.text2).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            usage
            activeIn
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.brand.opacity(0.06)))
    }

    private var detailLine: String {
        let plan = account.code.flatMap { model.plans[$0.id] }
        return [model.subtitle(account), plan].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder private var usage: some View {
        if let c = account.code {
            switch model.usage[c.id] {
            case .ok(let windows, _) where !windows.isEmpty:
                VStack(spacing: 10) { ForEach(windows, id: \.label) { UsageLine(window: $0, large: true) } }
            case .ok:
                Note(text: "No usage limits reported for this plan")
            case .failed(let msg):
                Note(text: msg, warning: true)
            case .loading, nil:
                Note(text: "Loading usage…")
            }
        } else {
            Note(text: "Add a Claude Code login for this account to see usage.")
        }
    }

    private var activeIn: some View {
        let cli = model.isCLIActive(account), desktop = model.isDesktopActive(account)
        let places = [cli ? "Claude Code" : nil, desktop ? "Desktop" : nil].compactMap { $0 }
        return HStack(spacing: 6) {
            Text(places.isEmpty ? "Not active anywhere" : "Active in " + places.joined(separator: " and "))
                .font(.system(size: 11.5)).foregroundStyle(Color.text2)
            Spacer(minLength: 0)
            if model.desktopInstalled && !desktop && account.code != nil {
                Button("Use in Desktop too") { model.switchTo(account) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.brand)
            }
        }
    }
}

// MARK: - Mismatch warning

/// A Desktop profile ended up signed in to a different account than it was set up for.
struct MismatchNotice: View {
    @ObservedObject var model: AppModel
    let profile: DesktopProfile

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Color.warn)
            VStack(alignment: .leading, spacing: 6) {
                Text("Desktop profile “\(profile.name)” is signed in to \(model.label(forAccount: profile.accountUuid)), not \(model.label(forAccount: profile.linkedAccountUuid)).")
                    .font(.system(size: 11.5)).foregroundStyle(Color.text1)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Button("Keep it as \(model.label(forAccount: profile.accountUuid))") { model.relink(profile) }
                    Button("Rename…") { model.renameProfile(profile) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.brand)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
        .help("Sessions and settings in this profile now belong to the account it's signed in to.")
    }
}

// MARK: - Recommendation

struct Recommendation: View {
    @ObservedObject var model: AppModel
    let account: Account
    let remaining: Double

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.name(account)) · \(Int(remaining.rounded()))% remaining")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.text1)
                Text("Most room before its next limit")
                    .font(.system(size: 11.5)).foregroundStyle(Color.text2)
            }
            Spacer(minLength: 8)
            PrimaryButton(title: "Switch to \(model.name(account))") { model.switchTo(account) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .help("Based on whichever of its session and weekly limits is closer to running out")
    }
}

// MARK: - Other accounts

struct AccountRow: View {
    @ObservedObject var model: AppModel
    let account: Account
    let shortcut: Int
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(name: model.name(account), seed: account.accountUuid ?? account.id, size: 28)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.name(account)).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.text1)
                    if let plan = account.code.flatMap({ model.plans[$0.id] }) {
                        Text(plan).font(.system(size: 11)).foregroundStyle(Color.text2)
                    }
                    Spacer(minLength: 4)
                    Text(hover ? (shortcut <= 9 ? "Switch  ⌘\(shortcut)" : "Switch") : "")
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.brand)
                }
                usage
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.primary.opacity(hover ? 0.04 : 0))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { model.switchTo(account) }
        .contextMenu {
            Button("Switch to \(model.name(account))") { model.switchTo(account) }
            Button("Rename…") { model.rename(account) }
            Divider()
            Button("Remove…") { model.remove(account) }.disabled(!model.canRemove(account))
        }
    }

    @ViewBuilder private var usage: some View {
        if let c = account.code {
            switch model.usage[c.id] {
            case .ok(let windows, _) where !windows.isEmpty:
                VStack(spacing: 6) { ForEach(windows, id: \.label) { UsageLine(window: $0, large: false) } }
            case .ok:
                Note(text: "No usage limits reported")
            case .failed(let msg):
                Note(text: msg, warning: true)
            case .loading, nil:
                Note(text: "Loading usage…")
            }
        } else {
            Note(text: model.subtitle(account))
        }
    }
}

// MARK: - Usage

/// One limit: label, bar, percentage, reset time. Pace lives in the tooltip.
struct UsageLine: View {
    let window: ClaudeAPI.Window
    let large: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: large ? 12 : 11.5)).foregroundStyle(Color.text2)
                .frame(width: 52, alignment: .leading)
            Meter(value: window.utilization / 100, height: large ? 6 : 4)
            Text("\(Int(window.utilization.rounded()))%")
                .font(.system(size: large ? 13 : 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.text1)
                .frame(width: 38, alignment: .trailing)
            Text(shortReset)
                .font(.system(size: 11).monospacedDigit()).foregroundStyle(Color.text2)
                .lineLimit(1).fixedSize()
                .frame(width: 56, alignment: .trailing)
        }
        .help(tooltip)
    }

    private var label: String {
        switch window.label {
        case "Session": return "Session"
        case "Week": return "Weekly"
        default: return window.label.replacingOccurrences(of: "Week · ", with: "")
        }
    }

    private var shortReset: String {
        guard let d = window.resetsAt else { return "" }
        let s = max(0, d.timeIntervalSinceNow)
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86400 { return "\(Int(s / 3600))h \(Int(s.truncatingRemainder(dividingBy: 3600) / 60))m" }
        let f = DateFormatter(); f.dateFormat = "EEE ha"
        return f.string(from: d)
    }

    private var tooltip: String {
        var parts = [resetText(window.resetsAt)]
        if let e = window.elapsed {
            let diff = window.utilization - e * 100
            parts.append(abs(diff) < 5 ? "On pace"
                         : diff < 0 ? "\(Int(-diff))% under pace" : "\(Int(diff))% over pace")
            parts.append("\(Int(e * 100))% of this window has passed")
        }
        return parts.joined(separator: " · ")
    }
}

func resetText(_ d: Date?) -> String {
    guard let d else { return "" }
    let s = max(0, d.timeIntervalSinceNow)
    if s < 3600 { return "Resets in \(Int(s / 60))m" }
    if s < 86400 { return "Resets in \(Int(s / 3600))h \(Int(s.truncatingRemainder(dividingBy: 3600) / 60))m" }
    let f = DateFormatter(); f.dateFormat = "EEE h a"
    return "Resets " + f.string(from: d)
}

struct Meter: View {
    let value: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { g in
            let v = min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(Color.usage(v)).frame(width: max(height, g.size.width * v))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Small components

struct Note: View {
    let text: String
    var warning = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if warning { Image(systemName: "exclamationmark.triangle").foregroundStyle(Color.warn) }
            Text(text).foregroundStyle(Color.text2).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11.5))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Flat initials on a quiet tinted circle.
struct Avatar: View {
    let name: String
    let seed: String
    let size: CGFloat
    @Environment(\.colorScheme) private var scheme

    private static let hues: [Color] = [
        Color(red: 0.70, green: 0.40, blue: 0.29), // clay
        Color(red: 0.33, green: 0.42, blue: 0.58), // slate
        Color(red: 0.31, green: 0.50, blue: 0.42), // sage
        Color(red: 0.52, green: 0.38, blue: 0.56), // plum
        Color(red: 0.60, green: 0.48, blue: 0.26), // sand
    ]

    var body: some View {
        let hue = Self.hues[abs(seed.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % Self.hues.count]
        Text(initials)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(hue)
            .brightness(scheme == .dark ? 0.28 : 0)
            .frame(width: size, height: size)
            .background(Circle().fill(hue.opacity(scheme == .dark ? 0.28 : 0.16)))
    }

    private var initials: String {
        let base = name.split(separator: "@").first.map(String.init) ?? name
        let words = base.split(whereSeparator: { " ._-".contains($0) })
        let letters = words.count > 1 ? words.prefix(2).compactMap(\.first) : Array(base.prefix(1))
        return String(letters).uppercased()
    }
}

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.brand.opacity(hover ? 0.9 : 1)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct QuietButton: View {
    let title: String
    var symbol: String? = nil
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
                Text(title)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(hover ? Color.text1 : Color.text2)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var spinning = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.text2)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(spinning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: spinning)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hover ? 0.07 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

struct BusyOverlay: View {
    var body: some View {
        ZStack {
            WindowBackground().opacity(0.85)
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Switching…").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.text2)
            }
        }
    }
}
