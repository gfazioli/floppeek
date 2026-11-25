import Foundation

/// One line of a preview's text; highlighted lines are drawn in the accent colour.
public struct ListingLine: Identifiable, Equatable, Sendable {
    public let id: Int
    public let text: String
    public let highlighted: Bool
}

/// What a preview of one `.adf` shows, worked out once: the volume's listing in
/// the manner of AmigaDOS `List`, or the boot block of a disk with no readable
/// file system. Foundation only, so the tests read exactly what the view draws.
public struct DiskPreview: Sendable {
    public enum Content: Sendable {
        case dos(ADFVolume)
        /// A game or demo disk: no file system, only what its boot block says.
        case nonDOS(bootable: Bool)
        /// The boot block says DOS but the file system cannot be read: why.
        case unreadable(reason: String)
    }

    public let fileName: String
    public let density: Density
    public let content: Content
    /// One line in the manner of AmigaDOS `Info`: "880K · OFS · DD · 125 of 1760 blocks used (7%)".
    public let summary: String
    /// A sentence under the summary when the listing needs explaining.
    public let note: String?
    public let lines: [ListingLine]

    /// Throws only when the file is not an Amiga floppy image at all.
    public init(url: URL) throws {
        let image = try ADFImage(contentsOf: url)
        fileName = url.lastPathComponent
        density = image.density
        do {
            content = .dos(try image.volume())
        } catch ADFError.notDOS {
            content = .nonDOS(bootable: image.isBootable)
        } catch {
            content = .unreadable(reason: Self.describe(error))
        }

        let size = density == .highDensity ? "1.76M" : "880K"
        switch content {
        case .dos(let volume):
            var parts = [size, volume.dosType.name, density.rawValue]
            if let used = volume.usedBlocks {
                let percent = Int((Double(used) / Double(volume.totalBlocks) * 100).rounded())
                parts.append("\(used) of \(volume.totalBlocks) blocks used (\(percent)%)")
            }
            summary = parts.joined(separator: " · ")
            note = nil
            lines = Listing.lines(for: volume)
        case .nonDOS(let bootable):
            summary = [size, density.rawValue, "not a DOS disk", bootable ? "bootable" : "not bootable"]
                .joined(separator: " · ")
            note = "No AmigaDOS file system: a game or demo that loads itself. Boot block:"
            lines = Listing.hexDump(image.bootBlock)
        case .unreadable(let reason):
            summary = [size, density.rawValue, image.dosType?.name ?? "DOS", "unreadable"].joined(separator: " · ")
            note = "The boot block says DOS, but the file system cannot be read (\(reason)). Boot block:"
            lines = Listing.hexDump(image.bootBlock)
        }
    }

    /// The name on the floppy's label: the volume name, or the file name without its extension.
    public var label: String {
        if case .dos(let volume) = content, !volume.name.isEmpty { return volume.name }
        return (fileName as NSString).deletingPathExtension
    }

    /// The same label without reading the directories: the root block's name only.
    /// What the thumbnail asks for, once per file in a Finder window.
    public static func label(for url: URL) throws -> String {
        let name = try ADFImage(contentsOf: url).volumeName ?? ""
        return name.isEmpty ? (url.lastPathComponent as NSString).deletingPathExtension : name
    }

    static func describe(_ error: any Error) -> String {
        switch error {
        case ADFError.badBlock(let block, let why): "block \(block): \(why)"
        case ADFError.unexpectedSize(let size): "\(size) bytes"
        default: String(describing: error)
        }
    }
}

public enum Listing {
    /// The volume as AmigaDOS `List` would print it, directories expanded in place:
    /// `Startup-Sequence      47 ----rwed 29-Feb-92 12:00:00`, a comment on the
    /// line below after `: `, and the totals at the end.
    public static func lines(for volume: ADFVolume) -> [ListingLine] {
        let rows = volume.flattened()
        let nameWidth = min(32, max(16, rows.map { $0.depth * 2 + $0.entry.name.count }.max() ?? 0) + 1)
        var out: [ListingLine] = []
        func add(_ text: String, highlighted: Bool = false) {
            out.append(ListingLine(id: out.count, text: text, highlighted: highlighted))
        }
        var files = 0, directories = 0
        for (depth, entry) in rows {
            let indent = String(repeating: " ", count: depth * 2)
            let name = indent + entry.name
            let size: String
            switch entry.kind {
            case .directory: size = "Dir"; directories += 1
            case .softLink, .hardLink: size = "Link"; files += 1
            case .file: size = String(entry.size); files += 1
            }
            add(name.padding(toLength: max(nameWidth, name.count + 1), withPad: " ", startingAt: 0)
                + String(repeating: " ", count: max(0, 7 - size.count)) + size
                + " " + entry.protection.listingString + " " + entry.date.dosString,
                highlighted: entry.isDirectory)
            if case .softLink(let target) = entry.kind { add(indent + "  -> " + target) }
            if !entry.comment.isEmpty { add(indent + ": " + entry.comment) }
        }
        if rows.isEmpty { add("(empty disk)") }
        var total = "\(files) file\(files == 1 ? "" : "s") - \(directories) director\(directories == 1 ? "y" : "ies")"
        if let used = volume.usedBlocks { total += " - \(used) blocks used" }
        add("")
        add(total, highlighted: true)
        for problem in volume.problems { add("! " + problem, highlighted: true) }
        return out
    }

    /// The first 256 bytes of a boot block, 16 to a line, with their printable characters.
    public static func hexDump(_ bytes: [UInt8], count: Int = 256) -> [ListingLine] {
        stride(from: 0, to: min(count, bytes.count), by: 16).enumerated().map { index, offset in
            let row = bytes[offset..<min(offset + 16, bytes.count)]
            let hex = row.map { String(format: "%02X", $0) }.joined(separator: " ")
            let ascii = String(row.map { (0x20...0x7E).contains($0) ? Character(UnicodeScalar($0)) : "." })
            return ListingLine(id: index, text: String(format: "%04X  ", offset) + hex + "  " + ascii, highlighted: false)
        }
    }
}
