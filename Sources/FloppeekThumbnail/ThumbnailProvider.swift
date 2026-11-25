import AppKit
import FloppeekCore
import FloppeekUI
import QuickLookThumbnailing

/// The Finder icon of an `.adf`: a floppy whose label carries the volume name.
/// Its Objective-C name is the extension's NSExtensionPrincipalClass.
@objc(FloppeekThumbnailProvider)
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, (any Error)?) -> Void) {
        // The root block's name only: the Finder asks once per file in a window,
        // and the directories are not needed for a label.
        let label: String
        do {
            label = try DiskPreview.label(for: request.fileURL)
        } catch {
            // Not a floppy image: let Quick Look draw its generic icon.
            handler(nil, error)
            return
        }
        let size = request.maximumSize
        handler(QLThumbnailReply(contextSize: size, currentContextDrawing: { () -> Bool in
            FloppyIcon.draw(in: CGRect(origin: .zero, size: size), label: label)
            return true
        }), nil)
    }
}
