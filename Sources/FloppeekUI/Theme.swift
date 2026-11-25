import AppKit
import CoreText
import SwiftUI

/// The Workbench 1.3 palette: four colours, as the Amiga drew its desktop.
public enum Workbench {
    public static let blue = Color(red: 0x00 / 255, green: 0x55 / 255, blue: 0xAA / 255)
    public static let white = Color.white
    public static let black = Color(red: 0x00 / 255, green: 0x00 / 255, blue: 0x22 / 255)
    public static let orange = Color(red: 0xFF / 255, green: 0x88 / 255, blue: 0x00 / 255)

    public static let nsBlue = NSColor(srgbRed: 0x00 / 255, green: 0x55 / 255, blue: 0xAA / 255, alpha: 1)
    public static let nsBlack = NSColor(srgbRed: 0x00 / 255, green: 0x00 / 255, blue: 0x22 / 255, alpha: 1)
    public static let nsOrange = NSColor(srgbRed: 0xFF / 255, green: 0x88 / 255, blue: 0x00 / 255, alpha: 1)
}

/// Topaz, the Amiga's system font (the a1200 TrueType by dMG, GPL with the font
/// exception: Resources/Fonts/README.txt). bundle.sh copies it into
/// Contents/Resources/Fonts of the app and of each extension.
public enum Topaz {
    /// The font's PostScript name once registered, or nil when the file is missing:
    /// the views then fall back to the system monospaced font.
    public static let name: String? = {
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("Fonts/Topaz_a1200_v1.0.ttf"))
        }
        // Renders outside a bundle (tests, scripts) point here.
        if let dir = ProcessInfo.processInfo.environment["FLOPPEEK_FONTS"] {
            candidates.append(URL(fileURLWithPath: dir).appendingPathComponent("Topaz_a1200_v1.0.ttf"))
        }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                  let first = descriptors.first,
                  let name = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String
            else { continue }
            // A second registration of the same file fails harmlessly.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            return name
        }
        return nil
    }()

    /// Topaz at `size` points; it is drawn from an 8-pixel grid, so multiples of 8 stay crisp.
    public static func font(_ size: CGFloat) -> Font {
        if let name { return .custom(name, fixedSize: size) }
        return .system(size: size * 0.8, design: .monospaced)
    }

    public static func nsFont(_ size: CGFloat) -> NSFont {
        if let name, let font = NSFont(name: name, size: size) { return font }
        return .monospacedSystemFont(ofSize: size * 0.8, weight: .regular)
    }
}
