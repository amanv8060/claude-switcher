import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var model: AppModel!
    private var observer: AnyCancellable?

    func applicationDidFinishLaunching(_ n: Notification) {
        model = AppModel()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = StatusIcon.image
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover)
        }

        let host = NSHostingController(rootView: PopoverView(
            model: model,
            onSettings: { [weak self] in self?.showSettings() },
            onQuit: { NSApp.terminate(nil) }))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        model.dismissPopover = { [weak self] in self?.popover.performClose(nil) }

        observer = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateButton() }
        }
        updateButton()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateButton() {
        var parts: [String] = []
        let active = model.activeCode
        if model.state.showNameInMenuBar, let a = active { parts.append(short(a.name)) }
        if model.state.showUsageInMenuBar, let a = active, let pct = model.sessionPercent(a.id) {
            parts.append(String(format: "%.0f%%", pct))
        }
        statusItem.button?.title = parts.isEmpty ? "" : " " + parts.joined(separator: " · ")
        statusItem.button?.toolTip = "Claude Switcher — \(active?.email ?? "no Claude Code login")"
    }

    private func short(_ s: String) -> String {
        let base = s.split(separator: "@").first.map(String.init) ?? s
        return base.count > 14 ? String(base.prefix(13)) + "…" : base
    }

    // MARK: Settings menu

    private func showSettings() {
        let menu = NSMenu()
        func add(_ title: String, _ on: Bool? = nil, _ action: @escaping () -> Void) {
            let item = ClosureMenuItem(title: title, action: action)
            if let on { item.state = on ? .on : .off }
            menu.addItem(item)
        }
        let s = model.state
        add("Show account name in menu bar", s.showNameInMenuBar) { [model] in model!.state.showNameInMenuBar.toggle(); model!.state.save() }
        add("Show session usage in menu bar", s.showUsageInMenuBar) { [model] in model!.state.showUsageInMenuBar.toggle(); model!.state.save() }
        if model.desktopInstalled {
            add("Confirm before restarting Claude Desktop", s.confirmDesktopSwitch) { [model] in model!.state.confirmDesktopSwitch.toggle(); model!.state.save() }
        }
        add("Launch at login", model.launchAtLogin) { [model] in model!.toggleLaunchAtLogin() }
        menu.addItem(.separator())
        if model.desktopInstalled {
            add("Add Claude Desktop login…") { [model] in model!.addDesktopLogin() }
        }
        add("Show data folder") { [model] in model!.revealDataFolder() }
        menu.addItem(.separator())
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        add("Claude Switcher \(version) · Releases…") {
            NSWorkspace.shared.open(URL(string: "https://github.com/amanv8060/claude-switcher/releases")!)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}

// MARK: - Menu bar icon

/// A template version of the logo: two switch arrows around an account.
enum StatusIcon {
    static let image: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            draw(scale: 1)
            return true
        }
        img.isTemplate = true
        return img
    }()

    static func draw(scale k: CGFloat) {
        let c = CGPoint(x: 9 * k, y: 9 * k), r = 7.0 * k
        NSColor.black.set()
        for (a0, a1) in [(CGFloat.pi * 0.60, CGFloat.pi * 1.20), (CGFloat.pi * 1.60, CGFloat.pi * 2.20)] {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: c, radius: r, startAngle: a0 * 180 / .pi, endAngle: a1 * 180 / .pi)
            arc.lineWidth = 1.6 * k
            arc.lineCapStyle = .round
            arc.stroke()
            let tip = CGPoint(x: c.x + r * cos(a1), y: c.y + r * sin(a1))
            let t = AffineTransform(translationByX: tip.x, byY: tip.y)
            var rot = AffineTransform(rotationByRadians: a1 + .pi / 2)
            rot.append(t)
            let head = NSBezierPath()
            head.move(to: CGPoint(x: 2.6 * k, y: 0))
            head.line(to: CGPoint(x: -1.0 * k, y: 2.4 * k))
            head.line(to: CGPoint(x: -1.0 * k, y: -2.4 * k))
            head.close()
            head.transform(using: rot)
            head.fill()
        }
        // Person in the middle.
        NSBezierPath(ovalIn: CGRect(x: c.x - 1.75 * k, y: c.y + 0.1 * k, width: 3.5 * k, height: 3.5 * k)).fill()
        let body = NSBezierPath()
        body.move(to: CGPoint(x: c.x - 3.3 * k, y: c.y - 3.2 * k))
        body.curve(to: CGPoint(x: c.x + 3.3 * k, y: c.y - 3.2 * k),
                   controlPoint1: CGPoint(x: c.x - 3.0 * k, y: c.y + 0.2 * k),
                   controlPoint2: CGPoint(x: c.x + 3.0 * k, y: c.y + 0.2 * k))
        body.close()
        body.fill()
    }
}

// MARK: - README screenshots

/// `--render-preview <dir>` writes screenshots of the UI with sample data.
@MainActor
enum PreviewRenderer {
    static func run(into dir: URL) {
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = AppModel(preview: ())
        for (scheme, name) in [(ColorScheme.light, "light"), (.dark, "dark")] {
            let view = PreviewScene(model: model).environment(\.colorScheme, scheme)
            let r = ImageRenderer(content: view)
            r.scale = 2
            guard let cg = r.cgImage else { continue }
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: dir.appendingPathComponent("screenshot-\(name).png"))
        }
    }
}

/// A mock menu bar plus the popover, on a soft backdrop.
struct PreviewScene: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 14) {
                Spacer()
                HStack(spacing: 4) {
                    Image(nsImage: StatusIcon.image).renderingMode(.template)
                    Text("Personal · 34%").font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.14)))
                Image(systemName: "wifi").font(.system(size: 13, weight: .medium))
                Image(systemName: "battery.75percent").font(.system(size: 15))
                Text("Thu 9:41 AM").font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 14)
            .frame(height: 26)
            .background(dark ? Color.black.opacity(0.35) : Color.white.opacity(0.45))

            PopoverView(model: model)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(dark ? 0.14 : 0.07)))
                .compositingGroup()
                .shadow(color: .black.opacity(dark ? 0.45 : 0.14), radius: 18, y: 8)
                .padding(.trailing, 74)
                .padding(.bottom, 40)
        }
        .frame(width: 640)
        .background(LinearGradient(
            colors: dark ? [Color(red: 0.16, green: 0.12, blue: 0.20), Color(red: 0.33, green: 0.17, blue: 0.13)]
                         : [Color(red: 0.99, green: 0.86, blue: 0.78), Color(red: 0.86, green: 0.82, blue: 0.95)],
            startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
