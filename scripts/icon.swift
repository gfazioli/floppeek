// icon.swift — Floppeek's app icon, drawn in code: a 3.5" floppy in pixel art, in
// Workbench 1.3's four colours, with an eye on its label for BASIC's PEEK. Nothing
// from Commodore's or Amiga's marks. Chosen on 2026-11-26 from three concepts (a
// tilted vector floppy, a floppy over copper bars, this one).
//
//   swift scripts/icon.swift <size> <out.png> [--square]
//
// scripts/icons.sh runs it for every icon the app and the site ship. Without --square
// the tile is clipped to the squircle at full bleed, the shape the family's icons ship
// (Netfox, FinderGit and Lancetta touch all four edges); --square keeps the corners,
// for the macOS 26+ .icon layer, which the system masks to its own shape.

import AppKit

struct RGB {
    let r, g, b: CGFloat
    init(_ hex: UInt32) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
    }
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
}

let blue = RGB(0x0055AA)
let shadow = RGB(0x002A5C)
let palette: [Character: RGB] = ["K": RGB(0x000022), "W": RGB(0xFFFFFF), "O": RGB(0xFF8800), "B": blue]

// 20 x 20, top row first; "." is the tile showing through (the cut corner, the
// write-protect hole). The shutter with its window, the orange band, the eye.
let floppy = [
    "KKKKKKKKKKKKKKKKKK..",
    "KKKKWWWWWWWWWWWKKKK.",
    "KKKKWWWWWWWKKWWKKKKK",
    "KKKKWWWWWWWKKWWKKKKK",
    "KKKKWWWWWWWKKWWKKKKK",
    "KKKKWWWWWWWKKWWKKKKK",
    "KKKKWWWWWWWWWWWKKKKK",
    "KKKKKKKKKKKKKKKKKKKK",
    "KKOOOOOOOOOOOOOOOOKK",
    "KKWWWWWWWWWWWWWWWWKK",
    "KKWWWWWKKKKKKWWWWWKK",
    "KKWWWKKWBBBBWKKWWWKK",
    "KKWWKWWBBWKBBWWKWWKK",
    "KKWKWWWBBKKBBWWWKWKK",
    "KKWWKWWBBBBBBWWKWWKK",
    "KKWWWKKWBBBBWKKWWWKK",
    "KKWWWWWKKKKKKWWWWWKK",
    "KKWWWWWWWWWWWWWWWWKK",
    "KKKKKKKKKKKKKKKKKKKK",
    "K.KKKKKKKKKKKKKKKKKK",
]

/// The tile: a superellipse (n = 5), close to the macOS icon shape, at full bleed.
func squircle(_ r: CGRect, n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let steps = 1440
    for i in 0..<steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = pow(abs(c), 2 / n) * (c < 0 ? -1 : 1)
        let y = pow(abs(s), 2 / n) * (s < 0 ? -1 : 1)
        let point = CGPoint(x: r.midX + x * r.width / 2, y: r.midY + y * r.height / 2)
        i == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

/// The floppy on Workbench blue, with a hard shadow one cell down and right, as the
/// Workbench drew them. Drawn on a 1024-point canvas.
func draw(_ ctx: CGContext) {
    let s: CGFloat = 1024
    ctx.setFillColor(blue.cg); ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    let cell = (s * 0.70 / 20).rounded()
    let origin = CGPoint(x: ((s - cell * 20) / 2).rounded(), y: ((s - cell * 20) / 2).rounded())
    // One path per colour, filled once: cells filled one by one leave hairline seams
    // where their antialiased edges meet at sizes that are not a multiple of the grid.
    func plot(_ dx: CGFloat, _ dy: CGFloat, _ colour: (Character) -> RGB?) {
        var paths: [Character: (RGB, CGMutablePath)] = [:]
        for (r, row) in floppy.enumerated() {
            for (c, ch) in row.enumerated() {
                guard let fill = colour(ch) else { continue }
                if paths[ch] == nil { paths[ch] = (fill, CGMutablePath()) }
                paths[ch]!.1.addRect(CGRect(x: origin.x + CGFloat(c) * cell + dx, y: origin.y + CGFloat(19 - r) * cell + dy,
                                            width: cell, height: cell))
            }
        }
        for (fill, path) in paths.values {
            ctx.addPath(path); ctx.setFillColor(fill.cg); ctx.fillPath()
        }
    }
    plot(cell, -cell) { $0 == "." ? nil : shadow }
    plot(0, 0) { palette[$0] }
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2, let size = Int(args[0]) else {
    fputs("usage: icon.swift <size> <out.png> [--square]\n", stderr)
    exit(2)
}
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high
ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
if !args.contains("--square") { ctx.addPath(squircle(CGRect(x: 0, y: 0, width: 1024, height: 1024))); ctx.clip() }
draw(ctx)
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(dest) else { fputs("icon.swift: cannot write \(args[1])\n", stderr); exit(1) }
