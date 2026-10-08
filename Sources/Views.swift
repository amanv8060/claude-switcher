import SwiftUI

extension Color {
    static let brand = Color(red: 0.851, green: 0.467, blue: 0.341)
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
            VStack(spacing: 8) {
                ForEach(model.accounts) { AccountCard(model: model, account: $0) }
                if model.accounts.isEmpty { emptyState }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 12)
            Divider().opacity(0.6)
            footer
        }
        .frame(width: 344)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: appLogo).resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("Claude Switcher").font(.system(size: 13, weight: .semibold))
                Text(updatedText).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            IconButton(symbol: "arrow.clockwise", help: "Refresh usage") {
                model.refresh(); model.refreshUsage()
            }
            IconButton(symbol: "gearshape", help: "Settings", action: onSettings)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var updatedText: String {
        if model.lastUsageFetch == .distantPast { return "Usage not loaded yet" }
        let s = Date().timeIntervalSince(model.lastUsageFetch)
        return s < 60 ? "Usage updated just now" : "Usage updated \(Int(s / 60)) min ago"
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 28)).foregroundStyle(Color.brand)
            Text("No accounts yet").font(.system(size: 13, weight: .semibold))
            Text("Add your first Claude account to get started.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private var footer: some View {
        HStack {
            Button(action: model.addAccount) {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add account")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.brand)
            }
            .buttonStyle(.plain)
            Spacer()
            Button(action: onQuit) {
                Text("Quit").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Account card

struct AccountCard: View {
    @ObservedObject var model: AppModel
    let account: Account
    @State private var hover = false

    var body: some View {
        let cli = model.isCLIActive(account)
        let desktop = model.isDesktopActive(account)
        let active = cli || desktop
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        HStack(alignment: .top, spacing: 11) {
            Avatar(name: model.name(account), seed: account.accountUuid ?? account.id, active: active)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.name(account))
                            .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(model.subtitle(account))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        if account.code != nil { Badge(text: "CLI", on: cli) }
                        if model.desktopInstalled && account.desktop != nil { Badge(text: "Desktop", on: desktop) }
                    }
                }
                usage
            }
        }
        .padding(11)
        .background(shape.fill(active ? Color.brand.opacity(0.11) : Color.primary.opacity(hover ? 0.075 : 0.04)))
        .overlay(shape.strokeBorder(active ? Color.brand.opacity(0.5) : Color.primary.opacity(0.07), lineWidth: 1))
        .contentShape(shape)
        .onHover { hover = $0 }
        .onTapGesture { model.switchTo(account) }
        .help(active && cli == desktop ? "Active account" : "Switch to \(model.name(account))")
        .contextMenu {
            Button("Switch to \(model.name(account))") { model.switchTo(account) }
            Button("Rename…") { model.rename(account) }
            Divider()
            Button("Remove…") { model.remove(account) }.disabled(!model.canRemove(account))
        }
        .animation(.easeOut(duration: 0.12), value: hover)
    }

    @ViewBuilder private var usage: some View {
        if let c = account.code {
            switch model.usage[c.id] {
            case .ok(let windows, _) where !windows.isEmpty:
                VStack(spacing: 6) {
                    ForEach(windows, id: \.label) { UsageRow(window: $0) }
                }
            case .ok:
                note("No usage limits reported", symbol: "infinity")
            case .failed(let msg):
                note(msg, symbol: "exclamationmark.triangle.fill", tint: .orange)
            case .loading, nil:
                note("Loading usage…", symbol: "hourglass")
            }
        } else {
            note("Add a Claude Code login to see usage", symbol: "chart.bar")
        }
    }

    private func note(_ text: String, symbol: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).foregroundStyle(.secondary).lineLimit(2)
        }
        .font(.system(size: 11))
    }
}

struct UsageRow: View {
    let window: ClaudeAPI.Window

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
            Meter(value: window.utilization / 100)
            Text("\(Int(window.utilization.rounded()))%")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .frame(width: 34, alignment: .trailing)
            Text(reset)
                .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.tertiary)
                .frame(width: 52, alignment: .trailing)
        }
        .help(window.resetsAt.map { "Resets \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")
    }

    private var label: String {
        switch window.label {
        case "Session": return "Session"
        case "Week": return "Weekly"
        default: return window.label.replacingOccurrences(of: "Week · ", with: "")
        }
    }

    private var reset: String {
        guard let d = window.resetsAt else { return "" }
        let s = max(0, d.timeIntervalSinceNow)
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86400 { return "\(Int(s / 3600))h \(Int(s.truncatingRemainder(dividingBy: 3600) / 60))m" }
        let f = DateFormatter(); f.dateFormat = "EEE ha"
        return f.string(from: d)
    }
}

// MARK: - Small components

struct Meter: View {
    let value: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.09))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, g.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 6)
    }

    private var tint: Color {
        value >= 0.9 ? Color(red: 0.89, green: 0.27, blue: 0.24)
            : value >= 0.7 ? Color(red: 0.95, green: 0.62, blue: 0.20) : .brand
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
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .foregroundStyle(on ? Color.white : Color.secondary)
        .background(Capsule().fill(on ? Color.brand : Color.primary.opacity(0.08)))
        .help(on ? "\(text) is using this account" : "\(text) is on another account")
    }
}

struct Avatar: View {
    let name: String
    let seed: String
    let active: Bool

    private static let palettes: [(Color, Color)] = [
        (Color(red: 0.95, green: 0.60, blue: 0.45), Color(red: 0.80, green: 0.36, blue: 0.24)),
        (Color(red: 0.49, green: 0.56, blue: 0.95), Color(red: 0.33, green: 0.36, blue: 0.80)),
        (Color(red: 0.36, green: 0.78, blue: 0.70), Color(red: 0.16, green: 0.55, blue: 0.52)),
        (Color(red: 0.82, green: 0.52, blue: 0.86), Color(red: 0.58, green: 0.30, blue: 0.68)),
        (Color(red: 0.93, green: 0.74, blue: 0.36), Color(red: 0.78, green: 0.52, blue: 0.16)),
    ]

    var body: some View {
        let p = Self.palettes[abs(seed.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % Self.palettes.count]
        Text(initials)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(Circle().fill(LinearGradient(colors: [p.0, p.1], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            .padding(2)
            .overlay(Circle().strokeBorder(active ? Color.brand : .clear, lineWidth: 1.5))
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
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(hover ? 0.08 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}
