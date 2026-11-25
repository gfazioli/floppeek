import AppKit

/// A 3.5" floppy drawn in the Workbench palette, its label carrying the volume
/// name: the Finder thumbnail of an `.adf`. Draws into the current AppKit
/// graphics context, unflipped (origin at the bottom left), as
/// `QLThumbnailReply(contextSize:currentContextDrawing:)` provides it.
public enum FloppyIcon {
    public static func draw(in rect: CGRect, label: String) {
        // Inset by the outline's width, or half of the stroke falls outside and the
        // cut corner is clipped.
        let bounds = rect.insetBy(dx: max(1, rect.width * 0.015), dy: max(1, rect.height * 0.015))
        // A real disk is 90 × 94 mm: fit that, centred.
        let height = min(bounds.height, bounds.width * 94 / 90)
        let width = height * 90 / 94
        let disk = CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
        let unit = width / 90 // one millimetre

        // Body, with the corner cut at the top right.
        let body = NSBezierPath()
        let cut = 5 * unit, radius = 2.5 * unit
        body.move(to: CGPoint(x: disk.minX + radius, y: disk.minY))
        body.line(to: CGPoint(x: disk.maxX - radius, y: disk.minY))
        body.appendArc(from: CGPoint(x: disk.maxX, y: disk.minY), to: CGPoint(x: disk.maxX, y: disk.minY + radius), radius: radius)
        body.line(to: CGPoint(x: disk.maxX, y: disk.maxY - cut))
        body.line(to: CGPoint(x: disk.maxX - cut, y: disk.maxY))
        body.line(to: CGPoint(x: disk.minX + radius, y: disk.maxY))
        body.appendArc(from: CGPoint(x: disk.minX, y: disk.maxY), to: CGPoint(x: disk.minX, y: disk.maxY - radius), radius: radius)
        body.line(to: CGPoint(x: disk.minX, y: disk.minY + radius))
        body.appendArc(from: CGPoint(x: disk.minX, y: disk.minY), to: CGPoint(x: disk.minX + radius, y: disk.minY), radius: radius)
        body.close()
        Workbench.nsBlue.setFill()
        body.fill()
        Workbench.nsBlack.setStroke()
        body.lineWidth = max(1, 1.2 * unit)
        body.stroke()

        // Metal shutter at the top, with its window onto the disk.
        let shutter = CGRect(x: disk.minX + 20 * unit, y: disk.maxY - 33 * unit, width: 48 * unit, height: 33 * unit)
        NSColor(srgbRed: 0.80, green: 0.82, blue: 0.85, alpha: 1).setFill()
        NSBezierPath(rect: shutter).fill()
        Workbench.nsBlack.setStroke()
        let shutterPath = NSBezierPath(rect: shutter)
        shutterPath.lineWidth = max(1, 0.8 * unit)
        shutterPath.stroke()
        let window = CGRect(x: shutter.minX + 30 * unit, y: shutter.minY + 7 * unit, width: 10 * unit, height: 22 * unit)
        Workbench.nsBlack.setFill()
        NSBezierPath(rect: window).fill()

        // Write-protect hole, bottom left.
        Workbench.nsBlack.setFill()
        NSBezierPath(rect: CGRect(x: disk.minX + 4 * unit, y: disk.minY + 4 * unit, width: 6 * unit, height: 6 * unit)).fill()

        // The label: white, an orange band at its top, the name in Topaz.
        let labelRect = CGRect(x: disk.minX + 8 * unit, y: disk.minY + 14 * unit, width: 74 * unit, height: 40 * unit)
        NSColor.white.setFill()
        NSBezierPath(rect: labelRect).fill()
        Workbench.nsOrange.setFill()
        NSBezierPath(rect: CGRect(x: labelRect.minX, y: labelRect.maxY - 6 * unit, width: labelRect.width, height: 6 * unit)).fill()

        guard width >= 48 else { return } // too small for words to read
        let text = label.isEmpty ? "NDOS" : label
        var size = 9 * unit
        let inset = labelRect.insetBy(dx: 3 * unit, dy: 3 * unit)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        var attributes: [NSAttributedString.Key: Any] = [:]
        var measured = CGRect.zero
        // Shrink until the name fits in two lines.
        repeat {
            attributes = [.font: Topaz.nsFont(size), .foregroundColor: Workbench.nsBlack, .paragraphStyle: paragraph]
            measured = (text as NSString).boundingRect(with: CGSize(width: inset.width, height: .greatestFiniteMagnitude),
                                                       options: [.usesLineFragmentOrigin], attributes: attributes)
            size *= 0.9
        } while measured.height > inset.height - 6 * unit && size > 3 * unit
        let textRect = CGRect(x: inset.minX, y: inset.minY + (inset.height - 6 * unit - measured.height) / 2,
                              width: inset.width, height: measured.height)
        (text as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin], attributes: attributes)
    }
}
