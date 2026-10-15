// Renders assets/vocume.svg to PNGs. Usage: swift scripts/render-icon.swift <svg> <out.png> <pixels> [--mac-icon]
// --mac-icon draws it on the macOS app-icon grid: artwork 824/1024 of the canvas, centred, with a
// soft drop shadow, so it sits in the Dock like other Mac apps. Corners stay transparent.
import AppKit

let args = CommandLine.arguments
let svg = URL(fileURLWithPath: args[1])
let out = URL(fileURLWithPath: args[2])
let size = Int(args[3])!
let macIcon = args.contains("--mac-icon")
guard let image = NSImage(contentsOf: svg) else { fatalError("can't read \(svg.path)") }

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
let canvas = CGFloat(size)
var frame = NSRect(x: 0, y: 0, width: canvas, height: canvas)
if macIcon {
    let side = canvas * 824 / 1024
    frame = NSRect(x: (canvas - side) / 2, y: (canvas - side) / 2 + canvas * 0.008, width: side, height: side)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = canvas * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -canvas * 0.01)
    shadow.set()
}
image.draw(in: frame)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
