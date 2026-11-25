import FloppeekCore
import SwiftUI

/// One line of the listing, in the manner of AmigaDOS `List`.
public struct ListingLine: Identifiable, Equatable, Sendable {
    public enum Style: Sendable { case file, directory, note, problem, total }
    public let id: Int
    public let text: String
    public let style: Style
}

public enum Listing {
    /// The volume as AmigaDOS `List` would print it, directories expanded in place:
    /// `Startup-Sequence      47 ----rwed 29-Feb-92 12:00:00`, a comment on the
    /// line below after `: `, and the totals at the end.
    public static func lines(for volume: ADFVolume) -> [ListingLine] {
        let rows = volume.flattened()
        let nameWidth = min(32, max(16, rows.map { $0.depth * 2 + $0.entry.name.count }.max() ?? 0) + 1)
        var out: [ListingLine] = []
        func add(_ text: String, _ style: ListingLine.Style) {
            out.append(ListingLine(id: out.count, text: text, style: style))
        }
        var files = 0, directories = 0
        for (depth, entry) in rows {
            let indent = String(repeating: " ", count: depth * 2)
            let name = (indent + entry.name).padding(toLength: max(nameWidth, depth * 2 + entry.name.count + 1),
                                                     withPad: " ", startingAt: 0)
            let size: String
            switch entry.kind {
            case .directory: size = "Dir"; directories += 1
            case .softLink, .hardLink: size = "Link"; files += 1
            case .file: size = String(entry.size); files += 1
            }
            let line = name + leftPad(size, 7) + " " + entry.protection.listingString + " " + entry.date.dosString
            add(line, entry.isDirectory ? .directory : .file)
            if case .softLink(let target) = entry.kind { add(indent + "  -> " + target, .note) }
            if !entry.comment.isEmpty { add(indent + ": " + entry.comment, .note) }
        }
        if rows.isEmpty { add("(empty disk)", .note) }
        var total = "\(files) file\(files == 1 ? "" : "s") - \(directories) director\(directories == 1 ? "y" : "ies")"
        if let used = volume.usedBlocks { total += " - \(used) blocks used" }
        add("", .total)
        add(total, .total)
        for problem in volume.problems { add("! " + problem, .problem) }
        return out
    }

    /// The first 256 bytes of a boot block, 16 to a line, with their printable characters.
    public static func hexDump(_ bytes: [UInt8], count: Int = 256) -> [ListingLine] {
        stride(from: 0, to: min(count, bytes.count), by: 16).enumerated().map { index, offset in
            let row = bytes[offset..<min(offset + 16, bytes.count)]
            let hex = row.map { String(format: "%02X", $0) }.joined(separator: " ")
            let ascii = String(row.map { (0x20...0x7E).contains($0) ? Character(UnicodeScalar($0)) : "." })
            return ListingLine(id: index, text: String(format: "%04X  ", offset) + hex + "  " + ascii, style: .file)
        }
    }

    static func leftPad(_ s: String, _ width: Int) -> String {
        s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
    }
}

/// The Quick Look preview of a disk: a Workbench window on the Workbench blue screen.
public struct DiskPreviewView: View {
    public let preview: DiskPreview
    public static let fontSize: CGFloat = 16

    public init(preview: DiskPreview) { self.preview = preview }

    private var lines: [ListingLine] {
        switch preview.content {
        case .dos(let volume): return Listing.lines(for: volume)
        case .nonDOS(let boot, _): return Listing.hexDump(boot)
        }
    }

    public var body: some View {
        AmigaWindow(title: preview.label) {
            VStack(alignment: .leading, spacing: 10) {
                Text(preview.summary)
                    .foregroundStyle(Workbench.orange)
                if case .nonDOS = preview.content {
                    Text("No AmigaDOS file system: a game or demo that loads itself. Boot block:")
                        .foregroundStyle(Workbench.white)
                }
                // Vertical only: a two-axis ScrollView centres content smaller than
                // itself, which floated a short listing in the middle of the window.
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(lines) { line in
                            Text(line.text.isEmpty ? " " : line.text)
                                .foregroundStyle(color(line.style))
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.bottom, 8)
                }
                .defaultScrollAnchor(.top)
            }
            .font(Topaz.font(Self.fontSize))
            .padding(12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Workbench.blue)
    }

    private func color(_ style: ListingLine.Style) -> Color {
        switch style {
        case .file, .note: Workbench.white
        case .directory, .total: Workbench.orange
        case .problem: Workbench.orange
        }
    }
}

/// A Workbench window: orange title bar with the close gadget, the title, the
/// pinstriped drag bar and the depth gadget; a black frame and a hard shadow.
struct AmigaWindow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                CloseGadget()
                Text(title)
                    .font(Topaz.font(16))
                    .foregroundStyle(Workbench.black)
                    .lineLimit(1)
                    .layoutPriority(1)
                DragBar()
                DepthGadget()
            }
            .padding(.horizontal, 4)
            .frame(height: 24)
            .background(Workbench.orange)
            .overlay(alignment: .bottom) { Rectangle().fill(Workbench.black).frame(height: 2) }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Workbench.blue)
        .overlay(Rectangle().strokeBorder(Workbench.black, lineWidth: 2))
        .background(Rectangle().fill(Color.black.opacity(0.28)).offset(x: 6, y: 6))
    }
}

/// Pinstripes, two pixels on and two off.
private struct DragBar: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 2)),
                             with: .color(Workbench.black.opacity(0.55)))
                y += 4
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

/// A square with a dot in it.
private struct CloseGadget: View {
    var body: some View {
        ZStack {
            Rectangle().strokeBorder(Workbench.black, lineWidth: 2)
            Rectangle().fill(Workbench.black).padding(5)
        }
        .frame(width: 16, height: 16)
    }
}

/// Two squares, one in front of the other.
private struct DepthGadget: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().strokeBorder(Workbench.black, lineWidth: 2).frame(width: 11, height: 10)
            Rectangle().fill(Workbench.orange).frame(width: 11, height: 10).offset(x: 6, y: 5)
            Rectangle().strokeBorder(Workbench.black, lineWidth: 2).frame(width: 11, height: 10).offset(x: 6, y: 5)
        }
        .frame(width: 18, height: 16, alignment: .topLeading)
    }
}
