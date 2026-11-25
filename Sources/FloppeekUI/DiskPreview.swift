import Foundation
import FloppeekCore

/// What a preview of one `.adf` shows: a DOS disk's tree, or a non-DOS disk's boot block.
public struct DiskPreview: Sendable {
    public enum Content: Sendable {
        case dos(ADFVolume)
        /// A game or demo disk: no file system, only what its boot block says.
        case nonDOS(bootBlock: [UInt8], bootable: Bool)
    }

    public let fileName: String
    public let density: Density
    public let content: Content

    /// Throws only when the file is not an Amiga floppy image at all.
    public init(url: URL) throws {
        let image = try ADFImage(contentsOf: url)
        fileName = url.lastPathComponent
        density = image.density
        if image.dosType != nil, let volume = try? image.volume() {
            content = .dos(volume)
        } else {
            content = .nonDOS(bootBlock: image.bootBlock, bootable: image.isBootable)
        }
    }

    /// The name on the floppy's label: the volume name, or the file name without its extension.
    public var label: String {
        if case .dos(let volume) = content, !volume.name.isEmpty { return volume.name }
        return (fileName as NSString).deletingPathExtension
    }

    /// One line in the manner of AmigaDOS `Info`: "880K · OFS · 125 blocks used (7%)".
    public var summary: String {
        let kilobytes = density == .highDensity ? "1.76M" : "880K"
        switch content {
        case .dos(let volume):
            var parts = [kilobytes, volume.dosType.name, density.rawValue]
            if let used = volume.usedBlocks {
                let percent = Int((Double(used) / Double(volume.totalBlocks) * 100).rounded())
                parts.append("\(used) of \(volume.totalBlocks) blocks used (\(percent)%)")
            }
            return parts.joined(separator: " · ")
        case .nonDOS(_, let bootable):
            return [kilobytes, density.rawValue, "not a DOS disk", bootable ? "bootable" : "not bootable"]
                .joined(separator: " · ")
        }
    }
}
