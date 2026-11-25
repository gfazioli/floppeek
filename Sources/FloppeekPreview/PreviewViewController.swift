import AppKit
import FloppeekUI
import Quartz
import SwiftUI

/// The Quick Look preview of an `.adf`. Its Objective-C name is what the
/// extension's Info.plist names as NSExtensionPrincipalClass.
@objc(FloppeekPreviewController)
final class PreviewViewController: NSViewController, QLPreviewingController {
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 560))
    }

    func preparePreviewOfFile(at url: URL) async throws {
        // Not an Amiga floppy image: throwing hands the file back to Quick Look's
        // generic preview.
        let preview = try DiskPreview(url: url)
        let host = NSHostingView(rootView: DiskPreviewView(preview: preview))
        host.frame = view.bounds
        host.autoresizingMask = [.width, .height]
        view.subviews.forEach { $0.removeFromSuperview() }
        view.addSubview(host)
        preferredContentSize = NSSize(width: 760, height: 560)
    }
}
