import Foundation
import Testing
@testable import FloppeekCore

/// The fixtures are written by amitools' xdftool (scripts/make-fixtures.sh), an
/// implementation independent of ours; each DOS disk sits beside xdftool's own
/// listing of it, which these tests hold the reader to, line by line.
struct ADFImageTests {
    static func fixture(_ name: String, _ ext: String = "adf") throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    }

    static func image(_ name: String) throws -> ADFImage {
        try ADFImage(contentsOf: fixture(name))
    }

    /// Byte i of a pattern file is (i * 7 + seed) mod 256, as make-fixtures.sh writes it.
    static func pattern(_ count: Int, seed: Int) -> Data {
        Data((0..<count).map { UInt8(($0 * 7 + seed) % 256) })
    }

    // MARK: xdftool's listing

    struct ListedEntry: Equatable, CustomStringConvertible {
        let depth: Int
        let name: String
        let size: String // "DIR" or bytes
        let protection: String
        let date: String
        let comment: String
        var description: String { "\(String(repeating: "  ", count: depth))\(name) \(size) \(protection) \(date) \(comment)" }
    }

    /// Parses `xdftool <disk> list`: the volume line, one line per entry indented two
    /// spaces per level, then the `sum:`/`data:`/`fs:` totals.
    static func listing(_ name: String) throws -> (volume: String, volumeDate: String, entries: [ListedEntry]) {
        let text = try String(contentsOf: fixture(name, "list.txt"), encoding: .utf8)
        let line = #/^( *)(.*\S) +(DIR|VOLUME|\d+) +([-a-z]{8}) +(\d\d\.\d\d\.\d{4} \d\d:\d\d:\d\d\.\d\d)(?:  (.*?))? *$/#
        var volume = "", volumeDate = ""
        var entries: [ListedEntry] = []
        for raw in text.split(separator: "\n") {
            guard let m = String(raw).wholeMatch(of: line) else { continue }
            if m.3 == "VOLUME" {
                volume = String(m.2)
                volumeDate = String(m.5)
                continue
            }
            entries.append(ListedEntry(depth: m.1.count / 2 - 1, name: String(m.2), size: String(m.3),
                                       protection: String(m.4), date: String(m.5),
                                       comment: String(m.6 ?? "")))
        }
        return (volume, volumeDate, entries)
    }

    static func ours(_ volume: ADFVolume) -> [ListedEntry] {
        volume.flattened().map { depth, e in
            ListedEntry(depth: depth, name: e.name, size: e.isDirectory ? "DIR" : String(e.size),
                        protection: e.protection.listingString, date: e.date.listingString,
                        comment: e.comment)
        }
    }

    @Test(arguments: ["ofs", "ffs", "ffs-hd"])
    func matchesXdftoolListing(disk: String) throws {
        let volume = try Self.image(disk).volume()
        let expected = try Self.listing(disk)
        #expect(!expected.entries.isEmpty, "the listing parsed to nothing")
        #expect(volume.name == expected.volume)
        #expect(volume.modified.listingString == expected.volumeDate)
        #expect(Self.ours(volume) == expected.entries)
        #expect(volume.problems.isEmpty)
    }

    // MARK: Volumes

    @Test func ofsVolume() throws {
        let image = try Self.image("ofs")
        let volume = try image.volume()
        #expect(image.dosType == DOSType(flags: 0))
        #expect(volume.dosType.name == "OFS")
        #expect(volume.density == .doubleDensity)
        #expect(volume.totalBlocks == 1760)
        #expect(volume.usedBlocks == 125) // xdftool info: used 125, free 1635
        #expect(!image.hasBootCode)
    }

    @Test func ffsVolumeHasHashChains() throws {
        let volume = try Self.image("ffs").volume()
        #expect(volume.dosType.name == "FFS")
        // 80 files and 2 directories in 72 hash slots: chains are certain.
        #expect(volume.entries.count == 82)
        #expect(volume.entries.filter(\.isDirectory).map(\.name) == ["Music", "Pictures"])
    }

    @Test func highDensity() throws {
        let image = try Self.image("ffs-hd")
        #expect(image.density == .highDensity)
        #expect(image.blockCount == 3520)
        let volume = try image.volume()
        #expect(volume.name == "Floppeek HD")
        #expect(volume.entries.map(\.name) == ["ReadMe"])
    }

    // MARK: Contents

    @Test func ofsContentsCrossExtensionBlocks() throws {
        let image = try Self.image("ofs")
        let entries = try image.volume().flattened().map(\.entry)
        func file(_ name: String) throws -> ADFEntry { try #require(entries.first { $0.name == name }) }
        // 50 000 bytes in 488-byte OFS blocks: 103 blocks, 31 of them through an extension block.
        #expect(try image.contents(of: file("Big.bin")) == Self.pattern(50_000, seed: 3))
        #expect(try image.contents(of: file("Dir")) == Self.pattern(1_200, seed: 1))
        #expect(try image.contents(of: file("Empty")).isEmpty)
        let startup = try String(decoding: image.contents(of: file("Startup-Sequence")), as: UTF8.self)
        #expect(startup.hasPrefix("Echo \"Hello from Floppeek\""))
    }

    @Test func ffsContentsCrossExtensionBlocks() throws {
        let image = try Self.image("ffs")
        let entries = try image.volume().flattened().map(\.entry)
        let long = try #require(entries.first { $0.name == "Long.mod" })
        // 100 000 bytes in 512-byte blocks: 196 blocks, two extension blocks.
        #expect(try image.contents(of: long) == Self.pattern(100_000, seed: 4))
        #expect(long.comment == "Not really a module")
        let file42 = try #require(entries.first { $0.name == "file42" })
        #expect(try image.contents(of: file42) == Self.pattern(500, seed: 2))
    }

    // MARK: Not a DOS disk, not an ADF

    @Test func nonDOSDisk() throws {
        let image = try Self.image("ndos")
        #expect(image.dosType == nil)
        #expect(throws: ADFError.notDOS) { try image.volume() }
    }

    @Test(arguments: [0, 512, 901_120 - 512, 901_120 + 1, 3_000_000])
    func rejectsOtherSizes(size: Int) {
        #expect(throws: ADFError.unexpectedSize(size)) { try ADFImage(data: Data(count: size)) }
    }

    // MARK: Formats

    @Test func protectionString() {
        #expect(Protection(rawValue: 0).listingString == "----rwed")
        #expect(Protection(rawValue: 0b0011).listingString == "----rw--")
        #expect(Protection(rawValue: 0xF0).listingString == "hsparwed")
        #expect(Protection(rawValue: 0x0F).listingString == "--------")
    }

    @Test func dateString() {
        #expect(AmigaDate(days: 0, minutes: 0, ticks: 0).listingString == "01.01.1978 00:00:00.00")
        // 29 February 1992 at noon, plus 75 ticks: one second and 25 ticks.
        let leap = AmigaDate(days: 5172, minutes: 720, ticks: 75)
        #expect(leap.listingString == "29.02.1992 12:00:01.25")
        #expect(leap.dosString == "29-Feb-92 12:00:01")
    }
}
