// thumbnail.swift — ask for an .adf's thumbnail the way the Finder does.
//
//   swift scripts/thumbnail.swift <file.adf> <out.png>
//
// Prints the representation type: 2 (.thumbnail) means the Floppeek extension drew it;
// 0 is the generic icon. `qlmanage -t` is no test of the extension: it takes the legacy
// generator path and hung for minutes on 2026-11-25.
import AppKit
import QuickLookThumbnailing
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let out = URL(fileURLWithPath: CommandLine.arguments[2])
let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 256, height: 256), scale: 2, representationTypes: .thumbnail)
let done = DispatchSemaphore(value: 0)
QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, error in
    if let rep {
        let image = rep.nsImage
        if let tiff = image.tiffRepresentation, let bmp = NSBitmapImageRep(data: tiff), let png = bmp.representation(using: .png, properties: [:]) {
            try? png.write(to: out)
        }
        print("type", rep.type.rawValue, "size", image.size)
    } else {
        print("error", error.map { String(describing: $0) } ?? "nil")
    }
    done.signal()
}
_ = done.wait(timeout: .now() + 50)
