// swift-tools-version: 6.0
//
// Floppeek: Quick Look previews for Amiga files. No Xcode project: SwiftPM builds
// the app and both extensions, and scripts/bundle.sh wraps them into Floppeek.app
// with the extensions in Contents/PlugIns (the Lancetta widgets recipe).

import PackageDescription

// A Quick Look extension is an executable entering at `_NSExtensionMain`, built for
// extensions, exactly as Xcode links one; from its own `main` it would never be
// handed a preview request.
let extensionSwift: [SwiftSetting] = [.unsafeFlags(["-application-extension"])]
let extensionLinker: [LinkerSetting] = [.unsafeFlags(["-Xlinker", "-application_extension",
                                                      "-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]

let package = Package(
    name: "Floppeek",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Floppeek", targets: ["Floppeek"]),
        .executable(name: "FloppeekPreview", targets: ["FloppeekPreview"]),
        .executable(name: "FloppeekThumbnail", targets: ["FloppeekThumbnail"]),
    ],
    targets: [
        // Format readers. Foundation only, no UI: the tests and both extensions link it.
        .target(name: "FloppeekCore"),
        // The views the preview shows and the thumbnail draws. The Topaz font is not a
        // SwiftPM resource: `Bundle.module` traps inside an extension when its bundle is
        // missing, so bundle.sh copies Resources/Fonts into each bundle and the views
        // look for it there, falling back to the system monospaced font.
        .target(name: "FloppeekUI", dependencies: ["FloppeekCore"],
                swiftSettings: extensionSwift),
        .executableTarget(name: "FloppeekPreview", dependencies: ["FloppeekCore", "FloppeekUI"],
                          swiftSettings: extensionSwift, linkerSettings: extensionLinker),
        .executableTarget(name: "FloppeekThumbnail", dependencies: ["FloppeekCore", "FloppeekUI"],
                          swiftSettings: extensionSwift, linkerSettings: extensionLinker),
        // The host app: it exists so macOS registers the extensions, and says how to use them.
        .executableTarget(name: "Floppeek", dependencies: ["FloppeekCore", "FloppeekUI"]),
        .testTarget(name: "FloppeekCoreTests", dependencies: ["FloppeekCore"],
                    resources: [.copy("Fixtures")]),
    ]
)
