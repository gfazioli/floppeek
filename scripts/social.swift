// social.swift — the page's share card (Open Graph, 1200 x 630), from the app icon,
// a real preview screenshot and the Topaz font.
//
//   swift scripts/social.swift docs/social.png     (from the repository root)
//
// Run scripts/icons.sh and scripts/screenshots/shoot.sh first: it reads their output.

import AppKit
import CoreText

let out = CommandLine.arguments.count == 2 ? CommandLine.arguments[1] : "docs/social.png"
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func image(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(root.appendingPathComponent(path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fputs("social.swift: cannot read \(path)\n", stderr); exit(1)
    }
    return image
}
let fontURL = root.appendingPathComponent("Resources/Fonts/Topaz_a1200_v1.0.ttf") as CFURL
CTFontManagerRegisterFontsForURL(fontURL, .process, nil)
let topaz = (CTFontManagerCreateFontDescriptorsFromURL(fontURL) as? [CTFontDescriptor])?.first
    .flatMap { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String } ?? "Menlo"

let W = 1200, H = 630
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func text(_ s: String, _ size: CGFloat, _ colour: CGColor, x: CGFloat, baseline: CGFloat) {
    let attributed = NSAttributedString(string: s, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(topaz as CFString, size, nil),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): colour,
    ])
    ctx.textPosition = CGPoint(x: x, y: baseline)
    CTLineDraw(CTLineCreateWithAttributedString(attributed), ctx)
}

// The Workbench screen, copper bars along the top and the bottom.
ctx.setFillColor(rgb(0x0055AA)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
func bar(_ y: CGFloat, _ bright: UInt32, _ dark: UInt32) {
    let g = CGGradient(colorsSpace: srgb, colors: [rgb(dark), rgb(bright), rgb(0xFFFFFF), rgb(bright), rgb(dark)] as CFArray,
                       locations: [0, 0.35, 0.5, 0.65, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: y + 7), end: CGPoint(x: 0, y: y - 7), options: [])
}
ctx.setFillColor(rgb(0x000022)); ctx.fill(CGRect(x: 0, y: H - 44, width: W, height: 44)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: 44))
bar(CGFloat(H) - 12, 0xFF9F43, 0x5C1A00); bar(CGFloat(H) - 32, 0x6EE7FF, 0x05265E)
bar(32, 0xFF6EC7, 0x4A0A55); bar(12, 0x9BFF7A, 0x0B4A16)

// Left: the icon, the name, what it does.
ctx.draw(image("Brand/app-icon-1024.png"), in: CGRect(x: 64, y: 340, width: 200, height: 200))
text("Floppeek", 92, rgb(0xFFFFFF), x: 60, baseline: 238)
text("Quick Look for", 36, rgb(0xFF8800), x: 64, baseline: 176)
text("Amiga disk images", 36, rgb(0xFF8800), x: 64, baseline: 134)
text("macOS · free and open source", 24, rgb(0xFFFFFF, 0.85), x: 64, baseline: 82)

// Right: a real preview (its Workbench window is in the picture), framed in black
// with a hard shadow, centred between the copper bars.
let shot = image("docs/screenshots/preview-work-disk.png")
let shotHeight = 600 * CGFloat(shot.height) / CGFloat(shot.width)
let frame = CGRect(x: 548, y: (CGFloat(H) - shotHeight) / 2, width: 600, height: shotHeight)
ctx.setFillColor(rgb(0x000022)); ctx.fill(frame.offsetBy(dx: 12, dy: -12))
ctx.fill(frame.insetBy(dx: -4, dy: -4))
ctx.draw(shot, in: frame)

let dest = CGImageDestinationCreateWithURL(root.appendingPathComponent(out) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(dest) else { fputs("social.swift: cannot write \(out)\n", stderr); exit(1) }
print("social.swift: \(out)")
