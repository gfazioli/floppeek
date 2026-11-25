import AppKit
import FloppeekUI
import SwiftUI

/// The host app. macOS registers a Quick Look extension through the app that
/// contains it, so this exists to be installed and opened once; its window says
/// how the previews are used.
@main
struct FloppeekApp: App {
    var body: some Scene {
        Window("Floppeek", id: "main") {
            WelcomeView()
                .frame(width: 560, height: 360)
        }
        .windowResizability(.contentSize)
    }
}

struct WelcomeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                // NSImage's drawing handler sets the AppKit context FloppyIcon draws into.
                Image(nsImage: NSImage(size: NSSize(width: 96, height: 96), flipped: false) { rect in
                    FloppyIcon.draw(in: rect, label: "Floppeek")
                    return true
                })
                VStack(alignment: .leading, spacing: 6) {
                    Text("Floppeek")
                        .font(Topaz.font(32))
                    Text("Quick Look for Amiga disk images")
                        .font(Topaz.font(16))
                        .foregroundStyle(Workbench.orange)
                }
            }
            Text("Select an .adf file in the Finder and press the Space bar: the disk opens as a Workbench window, every drawer listed. Its icon becomes a floppy with the disk's name on the label.")
                .font(.body)
            Text("If nothing changes, turn Floppeek on in System Settings > General > Login Items & Extensions > Quick Look.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            HStack {
                Button("Open Extension Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Spacer()
                Text("Amiga is a trademark of its owner. Floppeek is not affiliated with it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }
}
