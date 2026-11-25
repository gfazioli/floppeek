import Foundation

/// An AmigaDOS date: days since 1 January 1978, minutes since midnight and ticks
/// (1/50 s) into the minute. It is wall-clock time with no zone, so it is turned
/// into a calendar date by arithmetic alone: what the Amiga's clock said is what
/// is shown, whatever zone the Mac is in.
public struct AmigaDate: Equatable, Hashable, Sendable {
    public let days: UInt32
    public let minutes: UInt32
    public let ticks: UInt32

    public init(days: UInt32, minutes: UInt32, ticks: UInt32) {
        self.days = days
        self.minutes = minutes
        self.ticks = ticks
    }

    /// The Gregorian date and time the three numbers stand for.
    public struct Civil: Equatable, Sendable {
        public let year, month, day, hour, minute, second: Int
    }

    public var civil: Civil {
        let seconds = Int(minutes) * 60 + Int(ticks) / 50
        let extraDays = seconds / 86_400 // a corrupt disk can store more minutes than a day has
        let inDay = seconds % 86_400
        // Days since 1970-01-01 (1978 is 2922 days later), then Howard Hinnant's
        // civil_from_days.
        let z = Int(days) + 2922 + extraDays + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        let year = yoe + era * 400 + (month <= 2 ? 1 : 0)
        return Civil(year: year, month: month, day: day,
                     hour: inDay / 3600, minute: inDay / 60 % 60, second: inDay % 60)
    }

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// `29-Feb-92 12:00:00`, as the AmigaDOS `List` command prints it.
    public var dosString: String {
        let c = civil
        return String(format: "%02d-%@-%02d %02d:%02d:%02d",
                      c.day, Self.months[c.month - 1], c.year % 100, c.hour, c.minute, c.second)
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

    /// `hsparwed`, a dash for each flag that is off, as `List` prints it.
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

    /// "OFS", "FFS", "FFS INTL" (international case folding), "FFS DC" (directory
    /// cache), "FFS LNFS" (long names, OS 3.2).
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
}

/// Floppy density, from the image size.
public enum Density: String, Sendable {
    case doubleDensity = "DD"
    case highDensity = "HD"
}
