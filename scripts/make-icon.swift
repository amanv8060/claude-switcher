// Renders the app icon at every size macOS needs.
// Usage: swift scripts/make-icon.swift <output.iconset> [preview.png]
import AppKit

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

/// Draws the icon on a 1024×1024 canvas (y-up).
func drawIcon(_ ctx: CGContext) {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!

    // Squircle tile on Apple's icon grid (824pt tile, 100pt margin).
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: color(0x000000, 0.28))
    ctx.addPath(tilePath); ctx.setFillColor(color(0xC8603E)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    let bg = CGGradient(colorsSpace: cs, colors: [color(0xF2A27C), color(0xD9714C), color(0xB24A2B)] as CFArray,
                        locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 300, y: 924), end: CGPoint(x: 724, y: 100), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // Soft top glow.
    let glow = CGGradient(colorsSpace: cs, colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 360, y: 860), startRadius: 0,
                           endCenter: CGPoint(x: 360, y: 860), endRadius: 560, options: [])
    ctx.restoreGState()

    let cream = color(0xFFF4EA)
    let center = CGPoint(x: 512, y: 512)

    // Two switch arrows forming a ring.
    let r: CGFloat = 270, w: CGFloat = 46
    func arrow(from a0: CGFloat, to a1: CGFloat) {
        let arc = CGMutablePath()
        arc.addArc(center: center, radius: r, startAngle: a0, endAngle: a1, clockwise: false)
        let body = arc.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 10)
        // Arrowhead built pointing along +x, then rotated onto the arc's tangent (CCW travel).
        let tip = CGPoint(x: center.x + r * cos(a1), y: center.y + r * sin(a1))
        var t = CGAffineTransform(translationX: tip.x, y: tip.y).rotated(by: a1 + .pi / 2)
        let head = CGMutablePath()
        head.move(to: CGPoint(x: 78, y: 0))
        head.addLine(to: CGPoint(x: -22, y: 64))
        head.addLine(to: CGPoint(x: -22, y: -64))
        head.closeSubpath()
        let rounded = head.copy(strokingWithWidth: 18, lineCap: .round, lineJoin: .round, miterLimit: 10)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: color(0x6B2410, 0.35))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setFillColor(cream)
        ctx.addPath(body); ctx.fillPath()
        ctx.addPath(head.copy(using: &t)!); ctx.fillPath()
        ctx.addPath(rounded.copy(using: &t)!); ctx.fillPath()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
    arrow(from: .pi * 0.60, to: .pi * 1.22)
    arrow(from: .pi * 1.60, to: .pi * 2.22)

    // Two overlapping account avatars in the middle.
    func avatar(_ c: CGPoint, _ radius: CGFloat, fill: CGColor, figure: CGColor) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: color(0x6B2410, 0.35))
        ctx.addEllipse(in: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
        ctx.setFillColor(fill); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
        ctx.clip()
        ctx.setFillColor(figure)
        let hr = radius * 0.36
        ctx.fillEllipse(in: CGRect(x: c.x - hr, y: c.y + radius * 0.02, width: hr * 2, height: hr * 2))
        let bw = radius * 1.30
        ctx.fillEllipse(in: CGRect(x: c.x - bw / 2, y: c.y - radius * 1.12, width: bw, height: radius * 1.0))
        ctx.restoreGState()
    }
    avatar(CGPoint(x: 448, y: 470), 112, fill: color(0xF7C8AE), figure: color(0xC25A37))
    avatar(CGPoint(x: 572, y: 548), 124, fill: cream, figure: color(0xD46A44))
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    ctx.interpolationQuality = .high
    drawIcon(ctx)
    return rep.representation(using: .png, properties: [:])!
}

let args = CommandLine.arguments
let iconset = URL(fileURLWithPath: args.count > 1 ? args[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
if args.count > 2 { try! render(1024).write(to: URL(fileURLWithPath: args[2])) }
