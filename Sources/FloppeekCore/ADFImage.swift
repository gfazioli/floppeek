import Foundation

/// Why an ADF could not be read.
public enum ADFError: Error, Equatable, Sendable {
    /// Not the size of an Amiga floppy image.
    case unexpectedSize(Int)
    /// The boot block does not start with `DOS`: a game or demo disk with its own
    /// track loader, or not an Amiga disk at all.
    case notDOS
    /// A block the file system points at is not what it should be.
    case badBlock(UInt32, String)
    /// A file system variant Floppeek does not read yet.
    case unsupported(String)
}

/// One file, directory or link on a disk.
public struct ADFEntry: Identifiable, Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case file
        case directory
        case softLink(target: String)
        /// A hard link, with the header block of what it points at.
        case hardLink(to: UInt32)
    }

    /// The entry's header block: unique on the disk.
    public let id: UInt32
    public let name: String
    public let kind: Kind
    /// Bytes, for files and hard links to files; 0 otherwise.
    public let size: UInt32
    public let protection: Protection
    public let date: AmigaDate
    public let comment: String
    /// Directories only, sorted by name ignoring case, as `List` sorts them.
    public let children: [ADFEntry]

    public var isDirectory: Bool { kind == .directory }
}

/// A DOS disk's file system, read from its root block.
public struct ADFVolume: Sendable {
    public let name: String
    public let dosType: DOSType
    public let density: Density
    public let totalBlocks: Int
    /// From the allocation bitmap; nil when the bitmap is flagged invalid
    /// (the disk was not validated after its last write).
    public let usedBlocks: Int?
    /// Last change to the root directory.
    public let modified: AmigaDate
    /// The root directory, sorted.
    public let entries: [ADFEntry]
    /// What was skipped while reading: bad checksums, broken chains. Empty on a sound disk.
    public let problems: [String]

    /// Every entry, depth first, with its depth (0 for the root's children).
    public func flattened() -> [(depth: Int, entry: ADFEntry)] {
        var out: [(Int, ADFEntry)] = []
        func walk(_ list: [ADFEntry], _ depth: Int) {
            for e in list {
                out.append((depth, e))
                walk(e.children, depth + 1)
            }
        }
        walk(entries, 0)
        return out
    }
}

/// An Amiga floppy image (`.adf`): 512-byte blocks, two boot blocks, the root
/// block in the middle of the disk.
public struct ADFImage: Sendable {
    public static let blockSize = 512
    /// Hash slots in every directory block, and data pointers in every file header
    /// or extension block: BSIZE/4 - 56.
    static let slots = blockSize / 4 - 56
    /// 80 cylinders × 2 heads × 11 sectors.
    static let ddBlocks = 1760
    /// The longest DD layout seen in the wild: 84 cylinders.
    static let ddMaxBlocks = 84 * 22
    static let hdBlocks = 3520

    /// The image as read, mapped when the file system allows: never copied, so a
    /// thumbnail that needs the root block reads one block, not the disk.
    let data: Data
    public let blockCount: Int
    public let density: Density
    /// The blocks a file system is formatted on, most likely first: 1760 on DD, 3520
    /// on HD. A standard disk dumped with extra cylinders (up to 84) keeps its root
    /// block at 880 and its bitmap over 1760; a disk formatted over all of them
    /// (xdftool chs=82,2,11) has its root in the middle of the image.
    var formatCandidates: [Int] {
        density == .highDensity ? [Self.hdBlocks] : (blockCount == Self.ddBlocks ? [blockCount] : [Self.ddBlocks, blockCount])
    }

    public init(data: Data) throws {
        guard data.count % Self.blockSize == 0 else { throw ADFError.unexpectedSize(data.count) }
        let blocks = data.count / Self.blockSize
        if blocks == Self.hdBlocks {
            density = .highDensity
        } else if blocks >= Self.ddBlocks, blocks <= Self.ddMaxBlocks, blocks % 22 == 0 {
            density = .doubleDensity
        } else {
            throw ADFError.unexpectedSize(data.count)
        }
        // Offsets below count from zero; a slice of a larger Data would not.
        self.data = data.startIndex == 0 ? data : Data(data)
        blockCount = blocks
    }

    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    // MARK: Boot block

    /// The file system named by the boot block, or nil for a non-DOS disk.
    public var dosType: DOSType? {
        guard data[0] == 0x44, data[1] == 0x4F, data[2] == 0x53 else { return nil } // "DOS"
        return DOSType(flags: data[3])
    }

    /// The boot block checksum is right: Kickstart would run its code.
    public var isBootable: Bool {
        var sum: UInt32 = 0
        for offset in stride(from: 0, to: 1024, by: 4) {
            let (s, overflow) = sum.addingReportingOverflow(long(at: offset))
            sum = overflow ? s &+ 1 : s
        }
        return ~sum == 0
    }

    /// The two boot blocks, raw: what a non-DOS disk can show of itself.
    public var bootBlock: [UInt8] { [UInt8](data.prefix(1024)) }

    // MARK: Volume

    /// The volume name from the root block alone, without reading the directories:
    /// all a thumbnail needs. Nil for a non-DOS disk or an unreadable root block.
    /// The long-name file systems keep the root block's name where the others do.
    public var volumeName: String? {
        guard dosType != nil, let (root, _) = try? rootBlock() else { return nil }
        return root.bcplString(at: Offset.name, max: 30)
    }

    /// Reads the whole directory tree. Throws `.notDOS` for a disk whose boot block
    /// does not say DOS, `.badBlock` when there is no root block (most game disks:
    /// a DOS boot block, which Kickstart needs to boot them, and a loader of their
    /// own), and `.unsupported` for the long-name file systems.
    public func volume() throws -> ADFVolume {
        guard let dosType else { throw ADFError.notDOS }
        // No root block first: a game disk with a DOS\7 boot block is still a game disk.
        let (root, formatted) = try rootBlock()
        // DOS\6 and DOS\7 (OS 3.2) keep name and comment together and move the
        // date: read with this layout they list blank names.
        guard !dosType.hasLongNames else { throw ADFError.unsupported("long file names (\(dosType.name))") }
        var walk = TreeWalk(image: self, visited: [root.number])
        if !root.checksumIsValid { walk.problems.append("Root block \(root.number): bad checksum") }
        let entries = walk.directory(root, depth: 0)
        let used = usedBlocks(root: root, formatted: formatted, problems: &walk.problems)
        return ADFVolume(
            name: root.bcplString(at: Offset.name, max: 30),
            dosType: dosType,
            density: density,
            totalBlocks: formatted,
            usedBlocks: used,
            modified: root.date(at: Offset.date),
            entries: entries,
            problems: walk.problems)
    }

    /// The bytes of a file (or of the file a hard link points at).
    public func contents(of entry: ADFEntry) throws -> Data {
        switch entry.kind {
        case .file: return try fileContents(header: entry.id)
        case .hardLink(let target): return try fileContents(header: target)
        case .directory, .softLink: return Data()
        }
    }

    /// The root block and the number of blocks its file system was formatted on.
    private func rootBlock() throws -> (Block, formatted: Int) {
        for formatted in formatCandidates {
            let root = try block(UInt32(formatted / 2))
            if root.long(at: Offset.type) == BlockType.header,
               root.signedLong(at: Offset.secondaryType) == SecondaryType.root {
                return (root, formatted)
            }
        }
        throw ADFError.badBlock(UInt32(formatCandidates[0] / 2), "the root block is not a root block")
    }

    // MARK: Directories

    /// One pass over the tree: the blocks already seen (a loop in a corrupt chain
    /// stops at the second visit) and what was skipped on the way.
    private struct TreeWalk {
        let image: ADFImage
        var visited: Set<UInt32>
        var problems: [String] = []

        mutating func directory(_ dir: Block, depth: Int) -> [ADFEntry] {
            // Deeper than any real disk; a loop that slipped past `visited` stops here.
            guard depth < 64 else {
                problems.append("Block \(dir.number): directories nested too deep")
                return []
            }
            var entries: [ADFEntry] = []
            for slot in 0..<ADFImage.slots {
                var next = dir.long(at: Offset.table + slot * 4)
                while next != 0 {
                    guard visited.insert(next).inserted else {
                        problems.append("Block \(next): listed twice (a loop in the hash chain)")
                        break
                    }
                    let header: Block
                    do {
                        header = try image.block(next)
                    } catch {
                        problems.append("Block \(next): outside the disk")
                        break
                    }
                    guard header.long(at: Offset.type) == BlockType.header else {
                        problems.append("Block \(next): not a header block")
                        break
                    }
                    if !header.checksumIsValid { problems.append("Block \(next): bad checksum") }
                    if let entry = entry(header, depth: depth) { entries.append(entry) }
                    next = header.long(at: Offset.hashChain)
                }
            }
            return entries.sorted { $0.name.caseInsensitiveCompare($1.name) == .orderedAscending }
        }

        mutating func entry(_ header: Block, depth: Int) -> ADFEntry? {
            let secondary = header.signedLong(at: Offset.secondaryType)
            let kind: ADFEntry.Kind
            var size: UInt32 = 0
            var children: [ADFEntry] = []
            switch secondary {
            case SecondaryType.file:
                kind = .file
                size = header.long(at: Offset.byteSize)
            case SecondaryType.userDirectory:
                kind = .directory
                children = directory(header, depth: depth + 1)
            case SecondaryType.softLink:
                // The target path: a C string at 0x18, up to BSIZE - 224 = 288 bytes.
                kind = .softLink(target: header.cString(at: Offset.table, max: ADFImage.blockSize - 224))
            case SecondaryType.hardLinkFile, SecondaryType.hardLinkDirectory:
                let target = header.long(at: Offset.realEntry)
                kind = .hardLink(to: target)
                if secondary == SecondaryType.hardLinkFile, let real = try? image.block(target) {
                    size = real.long(at: Offset.byteSize)
                }
            default:
                problems.append("Block \(header.number): unknown entry type \(secondary)")
                return nil
            }
            return ADFEntry(
                id: header.number,
                name: header.bcplString(at: Offset.name, max: 30),
                kind: kind,
                size: size,
                protection: Protection(rawValue: header.long(at: Offset.protection)),
                date: header.date(at: Offset.date),
                comment: header.bcplString(at: Offset.comment, max: 79),
                children: children)
        }
    }

    // MARK: Files

    private func fileContents(header number: UInt32) throws -> Data {
        let header = try block(number)
        guard header.long(at: Offset.type) == BlockType.header,
              header.signedLong(at: Offset.secondaryType) == SecondaryType.file else {
            throw ADFError.badBlock(number, "not a file header")
        }
        let size = Int(header.long(at: Offset.byteSize))
        guard size <= blockCount * Self.blockSize else { throw ADFError.badBlock(number, "file size \(size)") }

        // Data block pointers: up to 72 in the header, the rest in a chain of
        // extension blocks, each table filled from its last slot backwards.
        var pointers: [UInt32] = []
        var table = header
        var seen: Set<UInt32> = [number]
        while true {
            let count = Int(table.long(at: Offset.highSeq))
            guard count <= Self.slots else { throw ADFError.badBlock(table.number, "\(count) data pointers") }
            for i in 0..<count {
                pointers.append(table.long(at: Offset.table + (Self.slots - 1 - i) * 4))
            }
            let next = table.long(at: Offset.extension)
            if next == 0 { break }
            guard seen.insert(next).inserted else { throw ADFError.badBlock(next, "extension chain loops") }
            table = try block(next)
            guard table.long(at: Offset.type) == BlockType.list else {
                throw ADFError.badBlock(next, "not an extension block")
            }
        }

        var out = Data(capacity: size)
        let ofs = !(dosType?.isFFS ?? false)
        for pointer in pointers where out.count < size {
            let data = try block(pointer)
            if ofs {
                // OFS data blocks: a 24-byte header, then up to 488 bytes.
                guard data.long(at: Offset.type) == BlockType.data else {
                    throw ADFError.badBlock(pointer, "not a data block")
                }
                let used = Int(data.long(at: Offset.dataSize))
                guard used <= Self.blockSize - 24 else { throw ADFError.badBlock(pointer, "\(used) bytes in a data block") }
                out.append(data.bytes(24, used))
            } else {
                out.append(data.bytes(0, min(Self.blockSize, size - out.count)))
            }
        }
        guard out.count == size else {
            throw ADFError.badBlock(number, "read \(out.count) of \(size) bytes")
        }
        return out
    }

    // MARK: Bitmap

    private func usedBlocks(root: Block, formatted: Int, problems: inout [String]) -> Int? {
        guard root.long(at: Offset.bitmapFlag) == 0xFFFF_FFFF else { return nil }
        let bitsPerBlock = (Self.blockSize / 4 - 1) * 32 // longword 0 is the checksum
        let needed = formatted - 2 // the boot blocks are not in the map
        var free = 0
        var counted = 0
        for page in 0..<25 where counted < needed {
            let pointer = root.long(at: Offset.bitmapPages + page * 4)
            guard pointer != 0, let map = try? block(pointer) else { break }
            if !map.checksumIsValid { problems.append("Bitmap block \(pointer): bad checksum") }
            let bits = min(bitsPerBlock, needed - counted)
            for bit in 0..<bits where map.long(at: 4 + bit / 32 * 4) & (1 << UInt32(bit % 32)) != 0 {
                free += 1
            }
            counted += bits
        }
        guard counted == needed else {
            problems.append("Bitmap covers \(counted) of \(needed) blocks")
            return nil
        }
        return formatted - free
    }

    // MARK: Blocks

    func long(at offset: Int) -> UInt32 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).bigEndian }
    }

    func block(_ number: UInt32) throws -> Block {
        guard number >= 2, Int(number) < blockCount else {
            throw ADFError.badBlock(number, "outside the disk")
        }
        return Block(number: number, image: self)
    }

    struct Block {
        let number: UInt32
        let image: ADFImage
        var base: Int { Int(number) * ADFImage.blockSize }

        /// The longword at a byte offset in the block (an `Offset`).
        func long(at offset: Int) -> UInt32 { image.long(at: base + offset) }
        func signedLong(at offset: Int) -> Int32 { Int32(bitPattern: long(at: offset)) }

        func bytes(_ offset: Int, _ count: Int) -> Data {
            image.data[(base + offset)..<(base + offset + count)]
        }

        /// A BCPL string: a length byte, then ISO Latin-1 characters.
        func bcplString(at offset: Int, max: Int) -> String {
            let length = min(Int(image.data[base + offset]), max)
            return String(bytes: bytes(offset + 1, length), encoding: .isoLatin1) ?? ""
        }

        func cString(at offset: Int, max: Int) -> String {
            let raw = bytes(offset, max).prefix { $0 != 0 }
            return String(bytes: raw, encoding: .isoLatin1) ?? ""
        }

        func date(at offset: Int) -> AmigaDate {
            AmigaDate(days: long(at: offset), minutes: long(at: offset + 4), ticks: long(at: offset + 8))
        }

        /// All 128 longwords add up to zero.
        var checksumIsValid: Bool {
            var sum: UInt32 = 0
            for offset in stride(from: 0, to: ADFImage.blockSize, by: 4) { sum = sum &+ long(at: offset) }
            return sum == 0
        }
    }
}

// MARK: Layout

/// Primary block types (longword 0).
enum BlockType {
    static let header: UInt32 = 2
    static let data: UInt32 = 8
    static let list: UInt32 = 16
}

/// Secondary types (the last longword of a header block).
enum SecondaryType {
    static let root: Int32 = 1
    static let userDirectory: Int32 = 2
    static let softLink: Int32 = 3
    static let hardLinkDirectory: Int32 = 4
    static let file: Int32 = -3
    static let hardLinkFile: Int32 = -4
}

/// Byte offsets inside a 512-byte block (ADF FAQ, Laurent Clévy).
enum Offset {
    static let type = 0x00
    /// File header and extension blocks: how many data pointers this table holds.
    static let highSeq = 0x08
    /// OFS data blocks: bytes of data in this block.
    static let dataSize = 0x0C
    /// The hash table of a directory, or the data pointers of a file header.
    static let table = 0x18
    static let bitmapFlag = 0x138
    static let bitmapPages = 0x13C
    static let protection = 0x140
    static let byteSize = 0x144
    static let comment = 0x148
    static let date = 0x1A4
    static let name = 0x1B0
    static let realEntry = 0x1D4
    static let hashChain = 0x1F0
    static let `extension` = 0x1F8
    static let secondaryType = 0x1FC
}
