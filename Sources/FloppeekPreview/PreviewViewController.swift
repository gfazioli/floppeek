import AppKit
import FloppeekCore
import FloppeekUI
import Quartz
import SwiftUI

/// The Quick Look preview of an `.adf`. Its Objective-C name is what the
/// extension's Info.plist names as NSExtensionPrincipalClass.
@objc(FloppeekPreviewController)
final class PreviewViewController: NSViewController, QLPreviewingController {
    static let size = NSSize(width: 760, height: 560)

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: Self.size))
    }

    func preparePreviewOfFile(at url: URL) async throws {
        // Read and lay out the disk off the main actor. Not an Amiga floppy image:
        // throwing hands the file back to Quick Look's generic preview.
        let preview = try await Task.detached { try DiskPreview(url: url) }.value
        let host = NSHostingView(rootView: DiskPreviewView(preview: preview))
        host.frame = view.bounds
        host.autoresizingMask = [.width, .height]
        view.subviews.forEach { $0.removeFromSuperview() }
        view.addSubview(host)
        preferredContentSize = Self.size
    }
}
