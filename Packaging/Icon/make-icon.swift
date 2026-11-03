// Draws the RemoteKeepAliver app icon at 1024 x 1024 and writes a PNG.
// Usage: swift Packaging/Icon/make-icon.swift <output.png>
// The Makefile turns the PNG into AppIcon.icns with sips and iconutil.
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// Apple's icon grid: 824 pt artwork centered in 1024 pt with a 185 pt radius.
let inset: CGFloat = 100
let tile = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

// Soft drop shadow under the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 40, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor(calibratedRed: 0.10, green: 0.22, blue: 0.55, alpha: 1).setFill()
tilePath.fill()
ctx.restoreGState()

// Background gradient: deep blue to sky.
tilePath.addClip()
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.07, green: 0.16, blue: 0.48, alpha: 1),
    NSColor(calibratedRed: 0.11, green: 0.45, blue: 0.92, alpha: 1),
    NSColor(calibratedRed: 0.35, green: 0.78, blue: 0.98, alpha: 1),
])!
gradient.draw(in: tile, angle: 90)

// Remote desktop window: a light card with a title bar.
let win = CGRect(x: tile.minX + 120, y: tile.minY + 150, width: tile.width - 240, height: tile.height - 300)
let winPath = NSBezierPath(roundedRect: win, xRadius: 48, yRadius: 48)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: NSColor.black.withAlphaComponent(0.30).cgColor)
NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
winPath.fill()
ctx.restoreGState()

// Title bar.
ctx.saveGState()
winPath.addClip()
let bar = CGRect(x: win.minX, y: win.maxY - 96, width: win.width, height: 96)
NSColor(calibratedWhite: 0.86, alpha: 1).setFill()
bar.fill()
ctx.restoreGState()
// Traffic lights.
let lights: [NSColor] = [
    NSColor(calibratedRed: 1.00, green: 0.38, blue: 0.35, alpha: 1),
    NSColor(calibratedRed: 1.00, green: 0.74, blue: 0.18, alpha: 1),
    NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.35, alpha: 1),
]
for (i, c) in lights.enumerated() {
    c.setFill()
    NSBezierPath(ovalIn: CGRect(x: win.minX + 44 + CGFloat(i) * 56, y: bar.midY - 18, width: 36, height: 36)).fill()
}

// Faint "desktop" content lines so the card reads as a remote screen.
NSColor(calibratedWhite: 0.80, alpha: 1).setFill()
for i in 0..<3 {
    let w: CGFloat = [0.55, 0.40, 0.30][i] * win.width
    NSBezierPath(roundedRect: CGRect(x: win.minX + 72, y: win.maxY - 180 - CGFloat(i) * 64, width: w, height: 26), xRadius: 13, yRadius: 13).fill()
}

// Motion arcs to the right of the cursor, in the accent blue.
let accent = NSColor(calibratedRed: 0.10, green: 0.42, blue: 0.95, alpha: 1)
let cursorTip = CGPoint(x: win.minX + 200, y: win.minY + 330)
ctx.saveGState()
ctx.setLineCap(.round)
for (i, r) in [100.0, 160.0, 220.0].enumerated() {
    let arc = NSBezierPath()
    arc.lineWidth = 34 - CGFloat(i) * 4
    arc.lineCapStyle = .round
    arc.appendArc(withCenter: CGPoint(x: cursorTip.x + 100, y: cursorTip.y - 40), radius: CGFloat(r), startAngle: -38, endAngle: 38)
    accent.withAlphaComponent(1.0 - CGFloat(i) * 0.25).setStroke()
    arc.stroke()
}
ctx.restoreGState()

// Classic arrow cursor: black fill with a white outline. Coordinates are in a
// 0..1 unit box with the tip at the top left (flipped below because AppKit's
// origin is bottom-left).
let unit: [CGPoint] = [
    CGPoint(x: 0.00, y: 0.00), CGPoint(x: 0.00, y: 1.00), CGPoint(x: 0.27, y: 0.77),
    CGPoint(x: 0.44, y: 1.10), CGPoint(x: 0.60, y: 1.03), CGPoint(x: 0.44, y: 0.72),
    CGPoint(x: 0.78, y: 0.72),
]
let scale: CGFloat = 300
let cursor = NSBezierPath()
for (i, p) in unit.enumerated() {
    let pt = CGPoint(x: cursorTip.x + p.x * scale, y: cursorTip.y + (1.10 - p.y) * scale - 1.10 * scale)
    i == 0 ? cursor.move(to: pt) : cursor.line(to: pt)
}
cursor.close()
cursor.lineJoinStyle = .round
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.white.setStroke()
cursor.lineWidth = 30
cursor.stroke()
ctx.restoreGState()
NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
cursor.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(2) }
do { try png.write(to: URL(fileURLWithPath: out)) } catch { fputs("write failed: \(error)\n", stderr); exit(3) }
print("wrote \(out) \(Int(rep.pixelsWide))x\(Int(rep.pixelsHigh))")
