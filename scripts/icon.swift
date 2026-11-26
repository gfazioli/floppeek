// icon.swift — Floppeek's app icon, drawn in code.
//
//   swift scripts/icon.swift <concept> <size> <out.png> [--square]
//   swift scripts/icon.swift sheet <out.png>
//
// Concepts: workbench, copper, pixel. Run from the repository root (the Topaz font is
// read from Resources/Fonts). Without --square the tile is clipped to the squircle at
// full bleed, the shape the family's icons ship (Netfox, FinderGit and Lancetta touch
// all four edges); --square keeps the corners, for the macOS 26+ .icon layer, which
// the system masks to its own shape.
//
// The palette is Workbench 1.3's four colours. Nothing from Commodore's or Amiga's
// marks: a floppy, and an eye for BASIC's PEEK.

import AppKit
import CoreText

struct RGB {
    let r, g, b, a: CGFloat
    init(_ hex: UInt32, _ a: CGFloat = 1) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
        self.a = a
    }
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

let blue = RGB(0x0055AA), black = RGB(0x000022), orange = RGB(0xFF8800), white = RGB(0xFFFFFF)
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

let topaz: String = {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Resources/Fonts/Topaz_a1200_v1.0.ttf")
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
       let name = descriptors.first.flatMap({ CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String }) {
        return name
    }
    fputs("icon.swift: Topaz not found, run from the repository root\n", stderr)
    return "Menlo"
}()

// MARK: - Shapes

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

func linear(_ ctx: CGContext, _ colours: [RGB], _ locations: [CGFloat], from: CGPoint, to: CGPoint) {
    let gradient = CGGradient(colorsSpace: sRGB, colors: colours.map(\.cg) as CFArray, locations: locations)!
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radial(_ ctx: CGContext, _ colours: [RGB], center: CGPoint, radius: CGFloat) {
    let gradient = CGGradient(colorsSpace: sRGB, colors: colours.map(\.cg) as CFArray, locations: nil)!
    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
                           options: [.drawsAfterEndLocation])
}

func text(_ ctx: CGContext, _ string: String, size: CGFloat, colour: RGB, centre: CGPoint) {
    let font = CTFontCreateWithName(topaz as CFString, size, nil)
    let attributed = NSAttributedString(string: string, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): colour.cg,
    ])
    let line = CTLineCreateWithAttributedString(attributed)
    let bounds = CTLineGetBoundsWithOptions(line, [])
    ctx.textPosition = CGPoint(x: centre.x - bounds.width / 2 - bounds.minX, y: centre.y - bounds.height / 2 - bounds.minY)
    CTLineDraw(line, ctx)
}

/// An almond eye with a blue iris looking out: PEEK.
func eye(_ ctx: CGContext, in r: CGRect, stroke: CGFloat) {
    let almond = CGMutablePath()
    almond.move(to: CGPoint(x: r.minX, y: r.midY))
    almond.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY), control: CGPoint(x: r.midX, y: r.maxY + r.height * 0.5))
    almond.addQuadCurve(to: CGPoint(x: r.minX, y: r.midY), control: CGPoint(x: r.midX, y: r.minY - r.height * 0.5))
    almond.closeSubpath()
    ctx.saveGState()
    ctx.addPath(almond); ctx.clip()
    let irisR = r.height * 0.46
    let iris = CGPoint(x: r.midX + r.width * 0.06, y: r.midY)
    ctx.setFillColor(blue.cg); ctx.fillEllipse(in: CGRect(x: iris.x - irisR, y: iris.y - irisR, width: irisR * 2, height: irisR * 2))
    let pupilR = irisR * 0.48
    ctx.setFillColor(black.cg); ctx.fillEllipse(in: CGRect(x: iris.x - pupilR, y: iris.y - pupilR, width: pupilR * 2, height: pupilR * 2))
    let glint = irisR * 0.22
    ctx.setFillColor(white.cg)
    ctx.fillEllipse(in: CGRect(x: iris.x - irisR * 0.42 - glint, y: iris.y + irisR * 0.30 - glint, width: glint * 2, height: glint * 2))
    ctx.restoreGState()
    ctx.addPath(almond)
    ctx.setStrokeColor(black.cg); ctx.setLineWidth(stroke); ctx.setLineJoin(.round)
    ctx.strokePath()
}

/// A 3.5" floppy, 90 x 94 mm, centred on `centre`, `width` wide, rotated by `angle`.
/// `label` draws on the label, in the floppy's own coordinates.
func floppy(_ ctx: CGContext, centre: CGPoint, width: CGFloat, angle: CGFloat, body: RGB, highlight: CGFloat,
            label: (CGContext, CGRect, CGFloat) -> Void) {
    ctx.saveGState()
    ctx.translateBy(x: centre.x, y: centre.y)
    ctx.rotate(by: angle)
    let mm = width / 90, height = 94 * mm
    let disk = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
    func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: disk.minX + x * mm, y: disk.minY + y * mm, width: w * mm, height: h * mm)
    }
    let cut = 6 * mm, radius = 3.5 * mm
    let outline = CGMutablePath()
    outline.move(to: CGPoint(x: disk.midX, y: disk.minY))
    outline.addArc(tangent1End: CGPoint(x: disk.maxX, y: disk.minY), tangent2End: CGPoint(x: disk.maxX, y: disk.maxY), radius: radius)
    outline.addLine(to: CGPoint(x: disk.maxX, y: disk.maxY - cut))
    outline.addLine(to: CGPoint(x: disk.maxX - cut, y: disk.maxY))
    outline.addArc(tangent1End: CGPoint(x: disk.minX, y: disk.maxY), tangent2End: CGPoint(x: disk.minX, y: disk.minY), radius: radius)
    outline.addArc(tangent1End: CGPoint(x: disk.minX, y: disk.minY), tangent2End: CGPoint(x: disk.maxX, y: disk.minY), radius: radius)
    outline.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -0.045 * width), blur: 0.09 * width, color: CGColor(gray: 0, alpha: 0.55))
    ctx.addPath(outline); ctx.setFillColor(body.cg); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(outline); ctx.clip()
    linear(ctx, [RGB(0xFFFFFF, highlight), RGB(0xFFFFFF, 0), RGB(0x000000, 0.18)], [0, 0.45, 1],
           from: CGPoint(x: disk.minX, y: disk.maxY), to: CGPoint(x: disk.maxX, y: disk.minY))
    // The recess the shutter slides in.
    ctx.setFillColor(RGB(0x000000, 0.22).cg); ctx.fill(box(16, 58, 62, 36))
    // The metal shutter, open to the top edge, with its window.
    let shutter = box(20, 60, 50, 34)
    ctx.saveGState(); ctx.clip(to: shutter)
    linear(ctx, [RGB(0xF2F4F7), RGB(0xC3CAD3), RGB(0x9AA3AF)], [0, 0.55, 1],
           from: CGPoint(x: shutter.minX, y: shutter.maxY), to: CGPoint(x: shutter.maxX, y: shutter.minY))
    ctx.restoreGState()
    ctx.setFillColor(RGB(0x000000, 0.25).cg); ctx.fill(CGRect(x: shutter.minX, y: shutter.minY, width: shutter.width, height: 0.8 * mm))
    let window = box(52, 66, 11, 22)
    ctx.addPath(CGPath(roundedRect: window, cornerWidth: 1.2 * mm, cornerHeight: 1.2 * mm, transform: nil))
    ctx.setFillColor(RGB(0x0B0B14).cg); ctx.fillPath()
    // The magnetic disk glimpsed through the window.
    ctx.setFillColor(RGB(0x3A2A1A).cg); ctx.fill(box(53.5, 68, 8, 18))
    // Write-protect hole.
    ctx.addPath(CGPath(roundedRect: box(4, 4, 6, 6), cornerWidth: 0.8 * mm, cornerHeight: 0.8 * mm, transform: nil))
    ctx.setFillColor(RGB(0x000000, 0.7).cg); ctx.fillPath()
    // The label, its orange band, and whatever it carries.
    let paper = box(12, 4, 70, 50)
    ctx.addPath(CGPath(roundedRect: paper, cornerWidth: 1.6 * mm, cornerHeight: 1.6 * mm, transform: nil))
    ctx.setFillColor(white.cg); ctx.fillPath()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: paper, cornerWidth: 1.6 * mm, cornerHeight: 1.6 * mm, transform: nil)); ctx.clip()
    ctx.setFillColor(orange.cg); ctx.fill(box(12, 46, 70, 8))
    ctx.restoreGState()
    label(ctx, box(14, 6, 66, 38), mm)
    ctx.restoreGState()
    ctx.restoreGState()
}

// MARK: - Concepts

/// Workbench blue, a black disk at a tilt, the eye on its label.
func workbench(_ ctx: CGContext, _ s: CGFloat) {
    radial(ctx, [RGB(0x2A7FD4), RGB(0x0055AA), RGB(0x00396F)], center: CGPoint(x: s * 0.5, y: s * 0.62), radius: s * 0.78)
    floppy(ctx, centre: CGPoint(x: s * 0.5, y: s * 0.49), width: s * 0.60, angle: -0.12, body: RGB(0x16161F), highlight: 0.16) { ctx, r, mm in
        eye(ctx, in: r.insetBy(dx: r.width * 0.12, dy: r.height * 0.22), stroke: 2.6 * mm)
    }
}

/// Demo-scene copper bars behind the blue disk the Finder shows, its name in Topaz.
func copper(_ ctx: CGContext, _ s: CGFloat) {
    ctx.setFillColor(black.cg); ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    let bars: [(CGFloat, UInt32, UInt32)] = [
        (0.90, 0xFFE066, 0x8A3B00), (0.70, 0xFF6EC7, 0x4A0A55), (0.50, 0x6EE7FF, 0x05265E),
        (0.30, 0x9BFF7A, 0x0B4A16), (0.10, 0xFF9F43, 0x5C1A00),
    ]
    let barHeight = s * 0.12
    for (y, bright, dark) in bars {
        let mid = s * y
        linear(ctx, [RGB(dark, 0), RGB(dark), RGB(bright), RGB(0xFFFFFF), RGB(bright), RGB(dark), RGB(dark, 0)],
               [0, 0.12, 0.38, 0.5, 0.62, 0.88, 1],
               from: CGPoint(x: 0, y: mid + barHeight / 2), to: CGPoint(x: 0, y: mid - barHeight / 2))
        // The gradient extends past both ends in its end colours, which are clear.
    }
    // Scanlines, faint.
    ctx.setFillColor(RGB(0x000000, 0.18).cg)
    var y: CGFloat = 0
    while y < s { ctx.fill(CGRect(x: 0, y: y, width: s, height: s / 256)); y += s / 128 }
    floppy(ctx, centre: CGPoint(x: s * 0.5, y: s * 0.49), width: s * 0.62, angle: 0, body: blue, highlight: 0.22) { ctx, r, mm in
        text(ctx, "Floppeek", size: 11 * mm, colour: black, centre: CGPoint(x: r.midX, y: r.midY + 1 * mm))
    }
}

/// Pixel art in the four Workbench colours, a hard shadow as the Workbench drew them.
func pixel(_ ctx: CGContext, _ s: CGFloat) {
    ctx.setFillColor(blue.cg); ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    var rows = [
        "KKKKKKKKKKKKKKKKKK..",
        "KKKKWWWWWWWWWWWKKKK.",
        "KKKKWWWWWWWKKWWKKKKK",
        "KKKKWWWWWWWKKWWKKKKK",
        "KKKKWWWWWWWKKWWKKKKK",
        "KKKKWWWWWWWKKWWKKKKK",
        "KKKKWWWWWWWWWWWKKKKK",
        "KKKKKKKKKKKKKKKKKKKK",
        "KKOOOOOOOOOOOOOOOOKK",
    ]
    rows += Array(repeating: "KKWWWWWWWWWWWWWWWWKK", count: 9)
    rows += ["KKKKKKKKKKKKKKKKKKKK", "K.KKKKKKKKKKKKKKKKKK"]
    let eyeRows = [
        "....KKKKKK....",
        "..KK.BBBB.KK..",
        ".K..BBWKBB..K.",
        "K...BBKKBB...K",
        ".K..BBBBBB..K.",
        "..KK.BBBB.KK..",
        "....KKKKKK....",
    ]
    for (i, eyeRow) in eyeRows.enumerated() {
        var chars = Array(rows[10 + i])
        for (j, c) in eyeRow.enumerated() where c != "." { chars[3 + j] = c }
        rows[10 + i] = String(chars)
    }
    let cell = (s * 0.70 / 20).rounded()
    let origin = CGPoint(x: ((s - cell * 20) / 2).rounded(), y: ((s - cell * 20) / 2).rounded())
    // One path per colour, filled once: cells filled one by one leave hairline seams
    // where their antialiased edges meet at sizes that are not a multiple of the grid.
    func plot(_ dx: CGFloat, _ dy: CGFloat, colour: (Character) -> RGB?) {
        var paths: [Character: (RGB, CGMutablePath)] = [:]
        for (r, row) in rows.enumerated() {
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
    plot(cell, -cell) { $0 == "." ? nil : RGB(0x002A5C) }
    plot(0, 0) {
        switch $0 {
        case "K": black
        case "W": white
        case "O": orange
        case "B": blue
        default: nil
        }
    }
}

// MARK: - Rendering

func render(_ size: Int, square: Bool, _ draw: (CGContext, CGFloat) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let scale = CGFloat(size) / 1024
    ctx.scaleBy(x: scale, y: scale)
    if !square { ctx.addPath(squircle(CGRect(x: 0, y: 0, width: 1024, height: 1024))); ctx.clip() }
    draw(ctx, 1024)
    return ctx.makeImage()!
}

func write(_ image: CGImage, _ path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fputs("icon.swift: cannot write \(path)\n", stderr); exit(1) }
}

let concepts: [(String, (CGContext, CGFloat) -> Void)] = [("workbench", workbench), ("copper", copper), ("pixel", pixel)]

let args = Array(CommandLine.arguments.dropFirst())
if args.first == "sheet", args.count == 2 {
    // Each concept at 512 and at the sizes the Finder and the Dock really use, on
    // a light and a dark ground, each rendered at its own size (not scaled down).
    let width = 1500, rowHeight = 600
    let ctx = CGContext(data: nil, width: width, height: rowHeight * concepts.count, bitsPerComponent: 8, bytesPerRow: 0,
                        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for (index, (name, draw)) in concepts.enumerated() {
        let top = CGFloat(rowHeight * (concepts.count - index))
        ctx.setFillColor(RGB(0xECECEC).cg); ctx.fill(CGRect(x: 0, y: top - CGFloat(rowHeight), width: 1000, height: CGFloat(rowHeight)))
        ctx.setFillColor(RGB(0x1E1E1E).cg); ctx.fill(CGRect(x: 1000, y: top - CGFloat(rowHeight), width: 500, height: CGFloat(rowHeight)))
        ctx.draw(render(512, square: false, draw), in: CGRect(x: 24, y: top - 556, width: 512, height: 512))
        text(ctx, "\(index + 1). \(name)", size: 28, colour: black, centre: CGPoint(x: 280, y: top - 24))
        for (ground, x0) in [(0, 560), (1, 1024)] {
            _ = ground
            var x = CGFloat(x0), y = top - 330
            for size in [256, 128, 64, 32, 16] {
                if size == 256 { ctx.draw(render(size, square: false, draw), in: CGRect(x: x, y: top - 300, width: 256, height: 256)); y = top - 520; x = CGFloat(x0); continue }
                ctx.draw(render(size, square: false, draw), in: CGRect(x: x, y: y + CGFloat(128 - size) / 2, width: CGFloat(size), height: CGFloat(size)))
                x += CGFloat(size) + 24
            }
        }
    }
    write(ctx.makeImage()!, args[1])
} else if args.count >= 3, let draw = concepts.first(where: { $0.0 == args[0] })?.1, let size = Int(args[1]) {
    write(render(size, square: args.contains("--square"), draw), args[2])
} else {
    fputs("usage: icon.swift <workbench|copper|pixel> <size> <out.png> [--square] | icon.swift sheet <out.png>\n", stderr)
    exit(2)
}
