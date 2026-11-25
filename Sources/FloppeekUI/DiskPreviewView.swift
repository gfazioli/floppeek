import FloppeekCore
import SwiftUI

/// The Quick Look preview of a disk: a Workbench window on the Workbench blue screen.
public struct DiskPreviewView: View {
    public static let fontSize: CGFloat = 16

    private let preview: DiskPreview
    /// The whole listing as one text, built once: a drag selects across lines,
    /// and SwiftUI lays out one view instead of one per line.
    private let listing: AttributedString

    public init(preview: DiskPreview) {
        self.preview = preview
        var text = AttributedString()
        for (index, line) in preview.lines.enumerated() {
            var run = AttributedString((index > 0 ? "\n" : "") + line.text)
            run.foregroundColor = line.highlighted ? Workbench.orange : Workbench.white
            text += run
        }
        listing = text
    }

    public var body: some View {
        AmigaWindow(title: preview.label) {
            VStack(alignment: .leading, spacing: 10) {
                Text(preview.summary)
                    .foregroundStyle(Workbench.orange)
                if let note = preview.note {
                    Text(note).foregroundStyle(Workbench.white)
                }
                // Both axes, so a long name scrolls instead of being clipped; the
                // minimum frame pins short content to the top left, where a
                // ScrollView would otherwise centre it.
                GeometryReader { space in
                    ScrollView([.vertical, .horizontal]) {
                        Text(listing)
                            .lineSpacing(2)
                            .fixedSize()
                            .textSelection(.enabled)
                            .frame(minWidth: space.size.width, minHeight: space.size.height, alignment: .topLeading)
                    }
                }
            }
            .font(Topaz.font(Self.fontSize))
            .padding(12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Workbench.blue)
    }
}

/// A Workbench window: orange title bar with the close gadget, the title, the
/// pinstriped drag bar and the depth gadget; a black frame and a hard shadow.
struct AmigaWindow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                CloseGadget()
                Text(title)
                    .font(Topaz.font(DiskPreviewView.fontSize))
                    .foregroundStyle(Workbench.black)
                    .lineLimit(1)
                    .layoutPriority(1)
                DragBar()
                DepthGadget()
            }
            .padding(.horizontal, 4)
            .frame(height: 24)
            .background(Workbench.orange)
            .overlay(alignment: .bottom) { Rectangle().fill(Workbench.black).frame(height: 2) }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Workbench.blue)
        .overlay(Rectangle().strokeBorder(Workbench.black, lineWidth: 2))
        .background(Rectangle().fill(Color.black.opacity(0.28)).offset(x: 6, y: 6))
    }
}

/// Pinstripes, two pixels on and two off.
private struct DragBar: View {
    var body: some View {
        Canvas { context, size in
            for y in stride(from: 0, to: size.height, by: 4) {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 2)),
                             with: .color(Workbench.black.opacity(0.55)))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

/// A square with a dot in it.
private struct CloseGadget: View {
    var body: some View {
        ZStack {
            Rectangle().strokeBorder(Workbench.black, lineWidth: 2)
            Rectangle().fill(Workbench.black).padding(5)
        }
        .frame(width: 16, height: 16)
    }
}

/// Two squares, one in front of the other.
private struct DepthGadget: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().strokeBorder(Workbench.black, lineWidth: 2).frame(width: 11, height: 10)
            Rectangle().fill(Workbench.orange).frame(width: 11, height: 10).offset(x: 6, y: 5)
            Rectangle().strokeBorder(Workbench.black, lineWidth: 2).frame(width: 11, height: 10).offset(x: 6, y: 5)
        }
        .frame(width: 18, height: 16, alignment: .topLeading)
    }
}
