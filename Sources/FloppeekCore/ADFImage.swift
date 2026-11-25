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
    /// When the disk was formatted.
    public let created: AmigaDate
    /// The root directory, sorted.
    public let entries: [ADFEntry]
    /// What was skipped while reading: bad checksums, broken chains. Empty on a sound disk.
    public let problems: [String]

    public var usedBytes: Int? { usedBlocks.map { $0 * ADFImage.blockSize } }
    public var totalBytes: Int { totalBlocks * ADFImage.blockSize }

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
    /// 80 cylinders × 2 heads × 11 sectors.
    static let ddBlocks = 1760
    /// The longest DD layout seen in the wild: 84 cylinders.
    static let ddMaxBlocks = 84 * 22
    static let hdBlocks = 3520

    let bytes: [UInt8]
    public let blockCount: Int
    public let density: Density

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
        bytes = [UInt8](data)
        blockCount = blocks
    }

    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    // MARK: Boot block

    /// The file system named by the boot block, or nil for a non-DOS disk.
    public var dosType: DOSType? {
        guard bytes[0] == 0x44, bytes[1] == 0x4F, bytes[2] == 0x53 else { return nil } // "DOS"
        return DOSType(flags: bytes[3])
    }

    /// The boot block checksum is right: Kickstart would run its code.
    public var isBootable: Bool {
        var sum: UInt32 = 0
        for i in stride(from: 0, to: 1024, by: 4) {
            let (s, overflow) = sum.addingReportingOverflow(long(at: i))
            sum = overflow ? s &+ 1 : s
        }
        return ~sum == 0
    }

    /// Bytes 12…1023 hold anything but zeros: a boot program (or a virus) is there.
    public var hasBootCode: Bool {
        bytes[12..<1024].contains { $0 != 0 }
    }

    /// The two boot blocks, raw: what a non-DOS disk can show of itself.
    public var bootBlock: [UInt8] { Array(bytes[0..<1024]) }

    // MARK: Volume

    /// Reads the whole directory tree. Throws `.notDOS` for a disk without a file system.
    public func volume() throws -> ADFVolume {
        guard let dosType else { throw ADFError.notDOS }
        var problems: [String] = []
        let rootBlock = UInt32(blockCount / 2)
        let root = try block(rootBlock)
        guard root.word(0) == BlockType.header, root.signedLong(Offset.secondaryType) == SecondaryType.root else {
            throw ADFError.badBlock(rootBlock, "the root block is not a root block")
        }
        if !root.checksumIsValid { problems.append("Root block \(rootBlock): bad checksum") }

        var visited: Set<UInt32> = [rootBlock]
        let entries = readDirectory(root, visited: &visited, problems: &problems, depth: 0)
        return ADFVolume(
            name: root.bcplString(at: Offset.name, max: 30),
            dosType: dosType,
            density: density,
            totalBlocks: blockCount,
            usedBlocks: usedBlocks(root: root, problems: &problems),
            modified: root.date(at: Offset.date),
            created: root.date(at: Offset.rootCreated),
            entries: entries,
            problems: problems)
    }

    /// The bytes of a file (or of the file a hard link points at).
    public func contents(of entry: ADFEntry) throws -> Data {
        switch entry.kind {
        case .file: return try fileContents(header: entry.id)
        case .hardLink(let target): return try fileContents(header: target)
        case .directory, .softLink: return Data()
        }
    }

    // MARK: Directories

    private func readDirectory(_ dir: Block, visited: inout Set<UInt32>, problems: inout [String], depth: Int) -> [ADFEntry] {
        // Deeper than any real disk; a loop that slipped past `visited` stops here.
        guard depth < 64 else {
            problems.append("Block \(dir.number): directories nested too deep")
            return []
        }
        // BSIZE/4 - 56 = 72 slots in every directory. Only the root block stores the
        // number (ht_size, longword 3); a user directory leaves that longword 0.
        let tableSize = Self.blockSize / 4 - 56
        var entries: [ADFEntry] = []
        for slot in 0..<tableSize {
            var next = dir.long(at: Offset.hashTable + slot * 4)
            while next != 0 {
                guard !visited.contains(next) else {
                    problems.append("Block \(next): listed twice (a loop in the hash chain)")
                    break
                }
                visited.insert(next)
                guard let header = try? block(next), header.word(0) == BlockType.header else {
                    problems.append("Block \(next): not a header block")
                    break
                }
                if !header.checksumIsValid { problems.append("Block \(next): bad checksum") }
                if let entry = readEntry(header, visited: &visited, problems: &problems, depth: depth) {
                    entries.append(entry)
                }
                next = header.long(Offset.hashChain)
            }
        }
        return entries.sorted { $0.name.caseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func readEntry(_ header: Block, visited: inout Set<UInt32>, problems: inout [String], depth: Int) -> ADFEntry? {
        let secondary = header.signedLong(Offset.secondaryType)
        let kind: ADFEntry.Kind
        var size: UInt32 = 0
        var children: [ADFEntry] = []
        switch secondary {
        case SecondaryType.file:
            kind = .file
            size = header.long(Offset.byteSize)
        case SecondaryType.userDirectory:
            kind = .directory
            children = readDirectory(header, visited: &visited, problems: &problems, depth: depth + 1)
        case SecondaryType.softLink:
            // The target path: a C string at 0x18, up to BSIZE - 224 = 288 bytes.
            kind = .softLink(target: header.cString(at: Offset.hashTable, max: Self.blockSize - 224))
        case SecondaryType.hardLinkFile, SecondaryType.hardLinkDirectory:
            let target = header.long(Offset.realEntry)
            kind = .hardLink(to: target)
            if secondary == SecondaryType.hardLinkFile, let real = try? block(target) {
                size = real.long(Offset.byteSize)
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
            protection: Protection(rawValue: header.long(Offset.protection)),
            date: header.date(at: Offset.date),
            comment: header.bcplString(at: Offset.comment, max: 79),
            children: children)
    }

    // MARK: Files

    private func fileContents(header number: UInt32) throws -> Data {
        let header = try block(number)
        guard header.word(0) == BlockType.header, header.signedLong(Offset.secondaryType) == SecondaryType.file else {
            throw ADFError.badBlock(number, "not a file header")
        }
        let size = Int(header.long(Offset.byteSize))
        guard size <= blockCount * Self.blockSize else { throw ADFError.badBlock(number, "file size \(size)") }

        // Data block pointers: up to 72 in the header, the rest in a chain of
        // extension blocks, each table filled from its last slot backwards.
        var pointers: [UInt32] = []
        var table = header
        var seen: Set<UInt32> = [number]
        while true {
            let count = Int(table.word(2)) // high_seq
            guard count <= 72 else { throw ADFError.badBlock(table.number, "\(count) data pointers") }
            for i in 0..<count {
                pointers.append(table.long(at: Offset.hashTable + (71 - i) * 4))
            }
            let next = table.long(Offset.extension)
            if next == 0 { break }
            guard seen.insert(next).inserted else { throw ADFError.badBlock(next, "extension chain loops") }
            table = try block(next)
            guard table.word(0) == BlockType.list else { throw ADFError.badBlock(next, "not an extension block") }
        }

        var out = Data(capacity: size)
        let ofs = !(dosType?.isFFS ?? false)
        for pointer in pointers where out.count < size {
            let data = try block(pointer)
            if ofs {
                // OFS data blocks: a 24-byte header, then up to 488 bytes.
                guard data.word(0) == BlockType.data else { throw ADFError.badBlock(pointer, "not a data block") }
                let used = Int(data.word(3))
                guard used <= Self.blockSize - 24 else { throw ADFError.badBlock(pointer, "\(used) bytes in a data block") }
                out.append(contentsOf: data.bytes(24, used))
            } else {
                out.append(contentsOf: data.bytes(0, min(Self.blockSize, size - out.count)))
            }
        }
        guard out.count == size else {
            throw ADFError.badBlock(number, "read \(out.count) of \(size) bytes")
        }
        return out
    }

    // MARK: Bitmap

    private func usedBlocks(root: Block, problems: inout [String]) -> Int? {
        guard root.long(Offset.bitmapFlag) == 0xFFFF_FFFF else { return nil }
        let bitsPerBlock = (Self.blockSize / 4 - 1) * 32
        let needed = blockCount - 2 // the boot blocks are not in the map
        var free = 0
        var counted = 0
        for page in 0..<25 where counted < needed {
            let pointer = root.long(at: Offset.bitmapPages + page * 4)
            guard pointer != 0, let map = try? block(pointer) else { break }
            if !map.checksumIsValid { problems.append("Bitmap block \(pointer): bad checksum") }
            for bit in 0..<min(bitsPerBlock, needed - counted) {
                let word = map.word(1 + bit / 32) // longword 0 is the checksum
                if word & (1 << UInt32(bit % 32)) != 0 { free += 1 }
            }
            counted += min(bitsPerBlock, needed - counted)
        }
        guard counted == needed else {
            problems.append("Bitmap covers \(counted) of \(needed) blocks")
            return nil
        }
        return blockCount - free
    }

    // MARK: Blocks

    func long(at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
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

        /// Longword number `index` (0…127).
        func word(_ index: Int) -> UInt32 { image.long(at: base + index * 4) }
        /// The longword at a byte offset.
        func long(at byteOffset: Int) -> UInt32 { image.long(at: base + byteOffset) }
        /// The longword at a named field.
        func long(_ offset: Offset.Value) -> UInt32 { image.long(at: base + offset.rawValue) }
        func signedLong(_ offset: Offset.Value) -> Int32 { Int32(bitPattern: long(offset)) }

        func bytes(_ offset: Int, _ count: Int) -> ArraySlice<UInt8> {
            image.bytes[(base + offset)..<(base + offset + count)]
        }

        /// A BCPL string: a length byte, then ISO Latin-1 characters.
        func bcplString(at offset: Offset.Value, max: Int) -> String {
            let length = min(Int(image.bytes[base + offset.rawValue]), max)
            let raw = bytes(offset.rawValue + 1, length)
            return String(bytes: raw, encoding: .isoLatin1) ?? ""
        }

        func cString(at byteOffset: Int, max: Int) -> String {
            let raw = bytes(byteOffset, max).prefix { $0 != 0 }
            return String(bytes: raw, encoding: .isoLatin1) ?? ""
        }

        func date(at offset: Offset.Value) -> AmigaDate {
            AmigaDate(days: long(offset),
                      minutes: image.long(at: base + offset.rawValue + 4),
                      ticks: image.long(at: base + offset.rawValue + 8))
        }

        /// All 128 longwords add up to zero.
        var checksumIsValid: Bool {
            var sum: UInt32 = 0
            for i in 0..<(ADFImage.blockSize / 4) { sum = sum &+ word(i) }
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

/// Byte offsets inside a 512-byte header block (ADF FAQ, Laurent Clévy).
enum Offset {
    struct Value { let rawValue: Int }
    static let hashTable = 0x18
    static let bitmapFlag = Value(rawValue: 0x138)
    static let bitmapPages = 0x13C
    static let protection = Value(rawValue: 0x140)
    static let byteSize = Value(rawValue: 0x144)
    static let comment = Value(rawValue: 0x148)
    static let date = Value(rawValue: 0x1A4)
    static let name = Value(rawValue: 0x1B0)
    static let realEntry = Value(rawValue: 0x1D4)
    static let rootCreated = Value(rawValue: 0x1E4)
    static let hashChain = Value(rawValue: 0x1F0)
    static let parent = Value(rawValue: 0x1F4)
    static let `extension` = Value(rawValue: 0x1F8)
    static let secondaryType = Value(rawValue: 0x1FC)
}

