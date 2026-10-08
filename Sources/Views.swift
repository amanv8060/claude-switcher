import SwiftUI

extension Color {
    static let brand = Color(red: 0.851, green: 0.467, blue: 0.341)
    // Clay (brand) marks identity: the active account, badges, primary actions.
    // Green / amber / red mark usage health only.
    static let good = Color(red: 0.24, green: 0.62, blue: 0.49)
    static let warn = Color(red: 0.89, green: 0.64, blue: 0.23)
    static let bad = Color(red: 0.85, green: 0.33, blue: 0.29)

    /// Green until 70%, then amber, then red from 90%.
    static func usage(_ fraction: Double) -> Color {
        fraction >= 0.9 ? .bad : fraction >= 0.7 ? .warn : .good
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
            if let hero = model.hero {
                HeroCard(model: model, account: hero)
                    .padding(.horizontal, 12)
            } else {
                emptyState
            }
            if let pick = model.smartPick {
                SmartSwitch(model: model, account: pick.account, remaining: pick.remaining)
                    .padding(.horizontal, 12).padding(.top, 10)
            }
            if !model.others.isEmpty {
                SectionLabel("Other accounts").padding(.top, 14).padding(.bottom, 6)
                VStack(spacing: 8) {
                    ForEach(Array(model.others.enumerated()), id: \.element.id) { i, a in
                        AccountCard(model: model, account: a, shortcut: i + 2)
                    }
                }
                .padding(.horizontal, 12)
            }
            footer.padding(.top, 14)
        }
        .frame(width: 360)
        .overlay { if model.busy { BusyOverlay() } }
        .background(shortcuts)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: appLogo).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Claude Switcher").font(.system(size: 13, weight: .semibold))
                Text(updatedText).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            IconButton(symbol: "arrow.clockwise", help: "Refresh usage", spinning: model.isLoadingUsage) {
                model.refresh(); model.refreshUsage()
            }
            IconButton(symbol: "gearshape", help: "Settings", action: onSettings)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var updatedText: String {
        if model.lastUsageFetch == .distantPast { return "Usage not loaded yet" }
        let s = Date().timeIntervalSince(model.lastUsageFetch)
        return s < 60 ? "Updated just now" : "Updated \(Int(s / 60)) min ago"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 34, weight: .light)).foregroundStyle(Color.brand)
            Text("No accounts yet").font(.system(size: 14, weight: .semibold))
            Text("Sign in to Claude Code and your account\nwill show up here.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var footer: some View {
        HStack {
            Button(action: model.addAccount) {
                Label("Add account", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.brand.opacity(0.12)))
                    .foregroundStyle(Color.brand)
            }
            .buttonStyle(.plain)
            Spacer()
            if model.others.count > 0 {
                Text("⌘2–\(min(model.others.count + 1, 9)) to switch")
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                Spacer()
            }
            Button(action: onQuit) {
                Text("Quit").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
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

// MARK: - Active account

struct HeroCard: View {
    @ObservedObject var model: AppModel
    let account: Account

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Avatar(name: model.name(account), seed: account.accountUuid ?? account.id, size: 42, ring: true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.name(account)).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        if let plan = account.code.flatMap({ model.plans[$0.id] }) { PlanPill(text: plan) }
                    }
                    Text(model.subtitle(account))
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            usage
            activeIn
        }
        .padding(14)
        .background(shape.fill(LinearGradient(colors: [Color.brand.opacity(0.13), Color.brand.opacity(0.05)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(shape.strokeBorder(Color.brand.opacity(0.28), lineWidth: 1))
    }

    @ViewBuilder private var usage: some View {
        if let c = account.code {
            switch model.usage[c.id] {
            case .ok(let windows, _) where !windows.isEmpty:
                let main = windows.filter { $0.label == "Session" || $0.label == "Week" }
                let extra = windows.filter { $0.label != "Session" && $0.label != "Week" }
                HStack(spacing: 0) {
                    ForEach(main, id: \.label) { Gauge(window: $0).frame(maxWidth: .infinity) }
                }
                if !extra.isEmpty {
                    VStack(spacing: 6) { ForEach(extra, id: \.label) { BarRow(window: $0) } }
                }
            case .ok:
                Note(text: "No usage limits reported for this plan", symbol: "infinity")
            case .failed(let msg):
                Note(text: msg, symbol: "exclamationmark.triangle.fill", tint: .warn)
            case .loading, nil:
                HStack(spacing: 0) {
                    Gauge.placeholder("Session").frame(maxWidth: .infinity)
                    Gauge.placeholder("Weekly").frame(maxWidth: .infinity)
                }
            }
        } else {
            Note(text: "Add a Claude Code login for this account to see usage", symbol: "chart.bar.xaxis")
        }
    }

    private var activeIn: some View {
        let cli = model.isCLIActive(account), desktop = model.isDesktopActive(account)
        return HStack(spacing: 6) {
            Text("Active in").font(.system(size: 10.5)).foregroundStyle(.secondary)
            if account.code != nil { StatusChip(text: "Claude Code", symbol: "terminal", on: cli) }
            if model.desktopInstalled { StatusChip(text: "Desktop", symbol: "macwindow", on: desktop) }
            Spacer(minLength: 0)
            if model.desktopInstalled && !desktop && account.code != nil {
                Button { model.switchTo(account) } label: {
                    Label("Sync Desktop", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Color.brand)
                }
                .buttonStyle(.plain)
                .help("Switch Claude Desktop to this account too")
            }
        }
    }
}

/// A ring gauge with the percentage in the middle, reset time and pace below.
struct Gauge: View {
    let window: ClaudeAPI.Window

    var body: some View {
        let f = window.utilization / 100
        VStack(spacing: 6) {
            ZStack {
                Ring(value: f, pace: window.elapsed, size: 76, lineWidth: 8)
                VStack(spacing: -1) {
                    Text("\(Int(window.utilization.rounded()))%")
                        .font(.system(size: 19, weight: .bold, design: .rounded).monospacedDigit())
                    Text(window.label == "Session" ? "Session" : "Weekly")
                        .font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 1) {
                Text(resetText(window.resetsAt))
                    .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.secondary)
                PaceText(window: window)
            }
        }
    }

    static func placeholder(_ label: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Ring(value: 0, pace: nil, size: 76, lineWidth: 8)
                Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
            }
            Text("Loading…").font(.system(size: 10.5)).foregroundStyle(.tertiary)
        }
    }
}

struct Ring: View {
    let value: Double
    let pace: Double?
    let size: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        let v = min(max(value, 0), 1)
        let tint = Color.usage(v)
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: v)
                .stroke(AngularGradient(colors: [tint.opacity(0.55), tint], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * max(v, 0.01))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let pace {
                // Where usage would be if spread evenly over the window.
                Capsule()
                    .fill(Color.primary.opacity(0.7))
                    .frame(width: 2, height: lineWidth + 5)
                    .offset(y: -size / 2)
                    .rotationEffect(.degrees(360 * pace))
            }
        }
        .frame(width: size, height: size)
    }
}

struct PaceText: View {
    let window: ClaudeAPI.Window

    var body: some View {
        if let elapsed = window.elapsed {
            let diff = window.utilization - elapsed * 100
            let (text, color): (String, Color) =
                abs(diff) < 5 ? ("On pace", .secondary)
                : diff < 0 ? ("\(Int(-diff))% under pace", .good)
                : ("\(Int(diff))% over pace", .warn)
            Text(text).font(.system(size: 10, weight: .medium)).foregroundStyle(color)
                .help("The tick on the ring marks how much of this window has passed.")
        }
    }
}

// MARK: - Smart switch

struct SmartSwitch: View {
    @ObservedObject var model: AppModel
    let account: Account
    let remaining: Double
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button { model.switchTo(account) } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.good)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.good.opacity(0.15)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(model.name(account)) has the most room")
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text("\(Int(remaining.rounded()))% left before its next limit")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text("Smart switch")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.good.opacity(hover ? 1 : 0.9)))
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(shape.fill(Color.good.opacity(hover ? 0.13 : 0.09)))
            .overlay(shape.strokeBorder(Color.good.opacity(0.3), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Switch to the account with the most usage left (the tighter of its session and weekly limits)")
    }
}

// MARK: - Other accounts

struct AccountCard: View {
    @ObservedObject var model: AppModel
    let account: Account
    let shortcut: Int
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(alignment: .top, spacing: 11) {
            Avatar(name: model.name(account), seed: account.accountUuid ?? account.id, size: 34, ring: false)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(model.name(account)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            if let plan = account.code.flatMap({ model.plans[$0.id] }) { PlanPill(text: plan, subtle: true) }
                        }
                        Text(model.subtitle(account))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 4)
                    if hover {
                        Text(shortcut <= 9 ? "Switch ⌘\(shortcut)" : "Switch")
                            .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.brand))
                    } else {
                        HStack(spacing: 4) {
                            if account.code != nil { Badge(text: "CLI", on: model.isCLIActive(account)) }
                            if model.desktopInstalled && account.desktop != nil {
                                Badge(text: "Desktop", on: model.isDesktopActive(account))
                            }
                        }
                    }
                }
                usage
            }
        }
        .padding(11)
        .background(shape.fill(Color.primary.opacity(hover ? 0.075 : 0.04)))
        .overlay(shape.strokeBorder(Color.primary.opacity(hover ? 0.12 : 0.07), lineWidth: 1))
        .contentShape(shape)
        .onHover { hover = $0 }
        .onTapGesture { model.switchTo(account) }
        .animation(.easeOut(duration: 0.12), value: hover)
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
                VStack(spacing: 6) { ForEach(windows, id: \.label) { UsageLine(window: $0) } }
            case .ok:
                Note(text: "No usage limits reported", symbol: "infinity")
            case .failed(let msg):
                Note(text: msg, symbol: "exclamationmark.triangle.fill", tint: .warn)
            case .loading, nil:
                Note(text: "Loading usage…", symbol: "hourglass")
            }
        } else {
            Note(text: "Add a Claude Code login to see usage", symbol: "chart.bar.xaxis")
        }
    }
}

/// One limit as a labelled bar with percentage and reset time.
struct UsageLine: View {
    let window: ClaudeAPI.Window

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)
            Meter(value: window.utilization / 100, pace: window.elapsed, height: 6)
            Text("\(Int(window.utilization.rounded()))%")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .frame(width: 34, alignment: .trailing)
            Text(shortReset)
                .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.tertiary)
                .lineLimit(1).fixedSize()
                .frame(width: 58, alignment: .trailing)
        }
        .help(resetText(window.resetsAt))
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
}

struct Badge: View {
    let text: String
    let on: Bool

    var body: some View {
        HStack(spacing: 3) {
            if on { Circle().fill(Color.white).frame(width: 4, height: 4) }
            Text(text)
        }
        .font(.system(size: 9.5, weight: .semibold))
        .padding(.horizontal, 6).padding(.vertical, 2.5)
        .foregroundStyle(on ? Color.white : Color.secondary)
        .background(Capsule().fill(on ? Color.brand : Color.primary.opacity(0.08)))
        .help(on ? "\(text) is using this account" : "\(text) is on another account")
    }
}

/// Full-width bar for extra limits (Opus, Sonnet).
struct BarRow: View {
    let window: ClaudeAPI.Window

    var body: some View {
        HStack(spacing: 8) {
            Text(window.label.replacingOccurrences(of: "Week · ", with: "") + " weekly")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            Meter(value: window.utilization / 100, pace: window.elapsed, height: 6)
            Text("\(Int(window.utilization.rounded()))%")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .frame(width: 34, alignment: .trailing)
        }
    }
}

// MARK: - Small components

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
    var pace: Double? = nil
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { g in
            let v = min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.09))
                Capsule()
                    .fill(LinearGradient(colors: [Color.usage(v).opacity(0.7), Color.usage(v)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, g.size.width * v))
                if let pace {
                    Capsule().fill(Color.primary.opacity(0.55))
                        .frame(width: 1.5, height: height + 4)
                        .offset(x: g.size.width * pace - 0.75)
                }
            }
        }
        .frame(height: height)
    }
}

struct PlanPill: View {
    let text: String
    var subtle = false

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .foregroundStyle(subtle ? Color.secondary : Color.brand)
            .background(Capsule().fill(subtle ? Color.primary.opacity(0.07) : Color.brand.opacity(0.15)))
    }
}

struct StatusChip: View {
    let text: String
    let symbol: String
    let on: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle.dashed")
            Text(text)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .foregroundStyle(on ? Color.brand : Color.secondary)
        .background(Capsule().fill(on ? Color.brand.opacity(0.14) : Color.primary.opacity(0.06)))
        .help(on ? "\(text) is using this account" : "\(text) is on another account")
    }
}

struct Note: View {
    let text: String
    let symbol: String
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11.5))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SectionLabel: View {
    let text: String
    init(_ t: String) { text = t }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold)).tracking(0.6)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
    }
}

struct Avatar: View {
    let name: String
    let seed: String
    let size: CGFloat
    let ring: Bool

    // Muted, warm-leaning tones so avatars sit quietly next to the clay accent.
    private static let palettes: [(Color, Color)] = [
        (Color(red: 0.82, green: 0.58, blue: 0.47), Color(red: 0.66, green: 0.40, blue: 0.31)), // clay
        (Color(red: 0.55, green: 0.62, blue: 0.75), Color(red: 0.38, green: 0.45, blue: 0.60)), // slate
        (Color(red: 0.52, green: 0.68, blue: 0.60), Color(red: 0.34, green: 0.51, blue: 0.44)), // sage
        (Color(red: 0.70, green: 0.58, blue: 0.72), Color(red: 0.52, green: 0.40, blue: 0.56)), // plum
        (Color(red: 0.80, green: 0.69, blue: 0.48), Color(red: 0.62, green: 0.51, blue: 0.31)), // sand
    ]

    var body: some View {
        let p = Self.palettes[abs(seed.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % Self.palettes.count]
        Text(initials)
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(LinearGradient(colors: [p.0, p.1], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            .padding(ring ? 2.5 : 0)
            .overlay(Circle().strokeBorder(ring ? Color.brand : .clear, lineWidth: 1.5))
    }

    private var initials: String {
        let base = name.split(separator: "@").first.map(String.init) ?? name
        let words = base.split(whereSeparator: { " ._-".contains($0) })
        let letters = words.count > 1 ? words.prefix(2).compactMap(\.first) : Array(base.prefix(1))
        return String(letters).uppercased()
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
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(spinning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: spinning)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(hover ? 0.08 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

struct BusyOverlay: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Switching…").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
        }
    }
}
