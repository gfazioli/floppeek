import AppKit

/// A 3.5" floppy drawn in the Workbench palette, its label carrying the volume
/// name: the Finder thumbnail of an `.adf`. Draws into the current AppKit
/// graphics context, unflipped (origin at the bottom left), as
/// `QLThumbnailReply(contextSize:currentContextDrawing:)` provides it.
public enum FloppyIcon {
    public static func draw(in rect: CGRect, label: String) {
        // Inset by the outline's width, or half of the stroke falls outside and the
        // cut corner is clipped. A real disk is 90 × 94 mm: fit that, centred.
        let bounds = rect.insetBy(dx: max(1, rect.width * 0.015), dy: max(1, rect.height * 0.015))
        let height = min(bounds.height, bounds.width * 94 / 90)
        let width = height * 90 / 94
        let disk = CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
        let mm = width / 90
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: disk.minX + x * mm, y: disk.minY + y * mm, width: w * mm, height: h * mm)
        }
        func fill(_ r: CGRect, _ colour: NSColor) {
            colour.setFill()
            NSBezierPath.fill(r)
        }

        // Body, with the corner cut at the top right.
        let body = NSBezierPath()
        let cut = 5 * mm, radius = 2.5 * mm
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
        body.lineWidth = max(1, 1.2 * mm)
        body.stroke()

        // Metal shutter at the top, with its window onto the disk.
        let shutter = NSBezierPath(rect: box(20, 61, 48, 33))
        NSColor(srgbRed: 0.80, green: 0.82, blue: 0.85, alpha: 1).setFill()
        shutter.fill()
        shutter.lineWidth = max(1, 0.8 * mm)
        shutter.stroke()
        fill(box(50, 68, 10, 22), Workbench.nsBlack)
        // Write-protect hole, bottom left.
        fill(box(4, 4, 6, 6), Workbench.nsBlack)

        // The label: white, an orange band at its top, the name in Topaz.
        let labelRect = box(8, 14, 74, 40)
        fill(labelRect, .white)
        fill(box(8, 48, 74, 6), Workbench.nsOrange)

        guard width >= 48 else { return } // too small for words to read
        let space = box(11, 17, 68, 28) // under the band, inside a margin
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        // The largest of a few sizes at which the name fits; the last one wins regardless.
        for size in [9, 7.5, 6, 5, 4, 3].map({ CGFloat($0) * mm }) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: Topaz.nsFont(size), .foregroundColor: Workbench.nsBlack, .paragraphStyle: paragraph,
            ]
            let measured = (label as NSString).boundingRect(
                with: CGSize(width: space.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin], attributes: attributes)
            if measured.height <= space.height || size <= 3 * mm {
                let textRect = CGRect(x: space.minX, y: space.minY + (space.height - measured.height) / 2,
                                      width: space.width, height: measured.height)
                (label as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin], attributes: attributes)
                return
            }
        }
    }
}
