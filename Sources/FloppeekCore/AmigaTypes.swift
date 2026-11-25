import Foundation

/// An AmigaDOS date: days since 1 January 1978, minutes since midnight and ticks
/// (1/50 s) into the minute. It is wall-clock time with no zone, so it is read and
/// formatted in UTC: what the Amiga's clock said is what is shown.
public struct AmigaDate: Equatable, Hashable, Sendable {
    public let days: UInt32
    public let minutes: UInt32
    public let ticks: UInt32

    public init(days: UInt32, minutes: UInt32, ticks: UInt32) {
        self.days = days
        self.minutes = minutes
        self.ticks = ticks
    }

    /// 1978-01-01T00:00:00Z as seconds since 1970.
    static let epoch: TimeInterval = 252_460_800

    /// The wall-clock moment as a `Date` in UTC; format it with a UTC calendar.
    public var date: Date {
        Date(timeIntervalSince1970: Self.epoch
             + TimeInterval(days) * 86_400
             + TimeInterval(minutes) * 60
             + TimeInterval(ticks / 50))
    }

    /// `dd.MM.yyyy HH:mm:ss.tt`, the ticks left over the second after the dot:
    /// the form amitools' xdftool lists, which the tests compare against.
    public var listingString: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%02d.%02d.%04d %02d:%02d:%02d.%02d",
                      c.day ?? 0, c.month ?? 0, c.year ?? 0,
                      c.hour ?? 0, c.minute ?? 0, c.second ?? 0, Int(ticks % 50))
    }

    /// `29-Feb-92 12:00:00`, as the AmigaDOS `List` command prints it.
    public var dosString: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let month = months[max(0, min(11, (c.month ?? 1) - 1))]
        return String(format: "%02d-%@-%02d %02d:%02d:%02d",
                      c.day ?? 0, month, (c.year ?? 0) % 100, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
}

/// The protection bits of a file or directory. The low four (delete, execute,
/// write, read) are stored inverted: set means *not* allowed. The next four
/// (archived, pure, script, hold) mean what they say.
public struct Protection: Equatable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public var canRead: Bool { rawValue & 0b1000 == 0 }
    public var canWrite: Bool { rawValue & 0b0100 == 0 }
    public var canExecute: Bool { rawValue & 0b0010 == 0 }
    public var canDelete: Bool { rawValue & 0b0001 == 0 }
    public var isArchived: Bool { rawValue & 0x10 != 0 }
    public var isPure: Bool { rawValue & 0x20 != 0 }
    public var isScript: Bool { rawValue & 0x40 != 0 }
    public var isHold: Bool { rawValue & 0x80 != 0 }

    /// `hsparwed`, a dash for each flag that is off, as `List` and xdftool print it.
    public var listingString: String {
        let letters: [(Bool, Character)] = [
            (isHold, "h"), (isScript, "s"), (isPure, "p"), (isArchived, "a"),
            (canRead, "r"), (canWrite, "w"), (canExecute, "e"), (canDelete, "d"),
        ]
        return String(letters.map { $0.0 ? $0.1 : "-" })
    }
}

/// The file system a disk was formatted with: the fourth byte of `DOS\x`.
public struct DOSType: Equatable, Hashable, Sendable {
    public let flags: UInt8

    public init(flags: UInt8) { self.flags = flags }

    /// Fast File System; otherwise the original (OFS), whose data blocks carry headers.
    public var isFFS: Bool { flags & 1 != 0 }
    /// International mode: case-folds accented Latin-1 letters when hashing names.
    /// The directory-cache modes imply it.
    public var isInternational: Bool { flags >= 2 }
    /// Directory caching (DOS\4, DOS\5): extra cache blocks, same headers.
    public var hasDirectoryCache: Bool { flags == 4 || flags == 5 }
    /// Long file names (DOS\6, DOS\7, OS 3.2): names past 30 characters.
    public var hasLongNames: Bool { flags == 6 || flags == 7 }

    /// "OFS", "FFS", "FFS INTL", "FFS DC", "FFS LNFS"…
    public var name: String {
        let base = isFFS ? "FFS" : "OFS"
        switch flags {
        case 0, 1: return base
        case 2, 3: return base + " INTL"
        case 4, 5: return base + " DC"
        case 6, 7: return base + " LNFS"
        default: return "DOS\\\(flags)"
        }
    }

    /// `DOS0`…`DOS7`, as AmigaDOS writes it.
    public var tag: String { "DOS\(flags)" }
}

/// Floppy density, from the image size.
public enum Density: String, Sendable {
    case doubleDensity = "DD"
    case highDensity = "HD"
}
