import AppKit
import CoreText
import SwiftUI

/// The Workbench 1.3 palette: four colours, as the Amiga drew its desktop. Defined
/// once for AppKit (the thumbnail draws with it) and derived for SwiftUI.
public enum Workbench {
    public static let nsBlue = NSColor(srgbRed: 0x00 / 255, green: 0x55 / 255, blue: 0xAA / 255, alpha: 1)
    public static let nsBlack = NSColor(srgbRed: 0x00 / 255, green: 0x00 / 255, blue: 0x22 / 255, alpha: 1)
    public static let nsOrange = NSColor(srgbRed: 0xFF / 255, green: 0x88 / 255, blue: 0x00 / 255, alpha: 1)

    public static let blue = Color(nsColor: nsBlue)
    public static let black = Color(nsColor: nsBlack)
    public static let orange = Color(nsColor: nsOrange)
    public static let white = Color.white
}

/// Topaz, the Amiga's system font (the a1200 TrueType by dMG, GPL with the font
/// exception: Resources/Fonts/README.txt). bundle.sh copies it into
/// Contents/Resources/Fonts of the app and of each extension; outside a bundle
/// the system monospaced font stands in.
public enum Topaz {
    /// The font's PostScript name once registered from the running bundle, or nil.
    public static let name: String? = {
        guard let url = Bundle.main.url(forResource: "Topaz_a1200_v1.0", withExtension: "ttf", subdirectory: "Fonts"),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let name = descriptors.first.flatMap({ CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String })
        else { return nil }
        // A second registration of the same file fails harmlessly.
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return name
    }()

    /// Topaz at `size` points; it is drawn on an 8-pixel grid, so multiples of 8 stay crisp.
    public static func nsFont(_ size: CGFloat) -> NSFont {
        if let name, let font = NSFont(name: name, size: size) { return font }
        return .monospacedSystemFont(ofSize: size * 0.8, weight: .regular)
    }

    public static func font(_ size: CGFloat) -> Font { Font(nsFont(size) as CTFont) }
}
