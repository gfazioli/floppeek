# Floppeek

Quick Look for Amiga files on macOS 15 and later: an `.adf` previews as a Workbench
window listing every drawer, and its Finder icon becomes a floppy with the volume name
on the label. Planned next, one slice at a time: IFF/ILBM images (loose and inside
disks), tracker modules (.mod/.xm/.s3m/.it) with their patterns and sound, then the
Commodore 64 (.sid, maybe .d64). Open source, MIT.

## Layout

- `FloppeekCore`: format readers and what a preview says, Foundation only, so the
  tests read exactly what the view draws. `ADFImage` reads OFS and FFS (DD up to 84
  cylinders, HD), boot block, hash chains, extension blocks, links and the
  allocation bitmap, and never trusts a pointer: loops, out-of-disk blocks and bad
  checksums become `ADFVolume.problems`, not crashes. `DiskPreview` decides DOS,
  non-DOS or unreadable from `ADFError` and builds the lines (`Listing`, in the
  manner of AmigaDOS `List`); `DiskPreview.label(for:)` reads the root block only,
  for thumbnails.
- `FloppeekUI`: the preview view (`DiskPreviewView`, the listing as one selectable
  text), the thumbnail drawing (`FloppyIcon`), the Workbench 1.3 palette and the
  Topaz font.
- `FloppeekPreview`, `FloppeekThumbnail`: the two extensions, each an executable
  entering at `_NSExtensionMain` (Package.swift). Their principal classes have fixed
  Objective-C names that their Info.plists name.
- `Floppeek`: the host app, which exists so macOS registers the extensions.
- `scripts/bundle.sh` wraps the three executables into `build/Floppeek.app`, signs it
  inside-out and, with `--register`, registers it. No Xcode project. A release bundle
  is checked universal, loses the rpaths the link leaves into Xcode and the Metal
  cryptex, and has each slice's SDK stamped (SwiftPM records the deployment target,
  15.0, and macOS would run the binary in 15's compatibility mode).
- `Brand/`: the app icon's masters, drawn in code by `scripts/icon.swift` and written
  by `scripts/icons.sh <concept>` (also `docs/icons/`); bundle.sh makes the `.icns`
  and compiles `Brand/AppIcon.icon` into `Assets.car` for macOS 26+.
- `scripts/release.sh`: the DMG and the release (below); `scripts/dmg/` is the DMG
  builder the other apps ship (dmgbuild, then a check that the image opens as the
  install window); `scripts/floppeek.rb` is the Homebrew cask's template.
- `docs/`: the website, gfazioli.github.io/floppeek, published by
  `.github/workflows/pages.yml` verbatim. `scripts/social.swift` draws its share card.
- `scripts/screenshots/`: `disks.sh` writes the demo disks with xdftool, `shoot.sh`
  takes `docs/screenshots/` by window id.

## Commands

```sh
swift test                                   # the reader against xdftool's own listings
scripts/bundle.sh --register                 # build/Floppeek.app, Developer ID, registered
qlmanage -p <file.adf>                       # the preview, in a qlmanage window
swift scripts/thumbnail.swift <file.adf> <out.png>   # the thumbnail, as the Finder asks for it
scripts/release.sh --dry-run                 # test, build, sign, notarize, DMG, Gatekeeper; publishes nothing
scripts/release.sh --publish                 # the same, then tag, GitHub Release, cask
XDFTOOL=<xdftool> scripts/screenshots/shoot.sh [--only finder|work|demo|app]
scripts/icons.sh [workbench|copper|pixel]    # the icon's masters and the site's icons
swift scripts/social.swift docs/social.png   # the share card, after icons and screenshots
```

Capture a preview by its window id (`screencapture -l<id>`; in the macos-workspace
checkout, `../scripts/uiverify/uiv.sh shot qlmanage <out.png>`), never a screen
rectangle, which photographs whatever is in front. `scripts/bundle.sh --release`
builds universal (arm64 and x86_64); local builds are arm64 only.

## Rules

**The reader is tested against an independent writer.** The fixtures are made by
amitools' xdftool (`scripts/make-fixtures.sh`), never by our code and never from
copyrighted disks, and each DOS fixture sits beside xdftool's own listing, which
`matchesXdftoolListing` compares line by line: names, sizes, protection, dates to the
tick, comments, nesting. A fixture change regenerates both.

**`.adf` is `public.retro.adf`**, imported, not exported: vAmiga and ADF.inder export
that identifier, so with either installed the extension type is still ours to serve.
Never invent another identifier for a format the Mac's Amiga apps already name.

**Quick Look extensions are sandboxed and offline.** They get read access to the one
file they preview and ask for nothing else.

**Nothing from Commodore's or Amiga's trademarks goes into the app icon.** "Amiga" is
used descriptively, with the non-affiliation line in NOTICE.md, the README and the
app's window.

**A DOS boot block does not mean a file system.** Kickstart boots only a boot block
that says DOS with a valid checksum, so nearly every game and demo has one and no
root block: that is `noFileSystem(dosBootBlock: true, bootable: true)`, never an
error, and only a DOS boot block counts as bootable. The root block is looked for at
880 (DD) or 1760 (HD) first: dumps with up to 84 cylinders keep their file system on
the first 80. A disk formatted over all its cylinders has it in the middle of the
image (`ffs-82cyl`), the second place looked.

**Names on a disk are any Latin-1 bytes.** Everything shown goes through
`printable` (control characters as `?`), or a line feed in a name fakes a line.

**A release is `scripts/release.sh --publish` from a clean `main`**, never by hand.
The version is `VERSION`, the notes are its `## <version>` section of `CHANGELOG.md`
(no section, no release), the DMG goes on this repository's GitHub Release and the
cask into `gfazioli/homebrew-tap` with the sha256 of the file GitHub serves. A dry run
notarizes for real: Apple's answer is the step most likely to fail. No Sparkle: the
app is opened once and never again, so an updater in it would rarely look; updates
come through `brew upgrade` and the page. After a release, the portfolio's
`refresh-site`.

**The site is hand-written static HTML** (`docs/`), no generator. Topaz is served
from `docs/fonts/` with its licence, never from Google Fonts. The Download button
links only a `.dmg` the Releases API lists, never a URL built from a version; release
notes are GitHub's own HTML (`application/vnd.github.html+json`). One `h1` per page,
descriptions of 160 characters at most, `sitemap.xml` kept honest. `404.html` is
served at any depth, so its URLs are absolute (`/floppeek/…`). The footer carries the
sponsors wall, the donate button and the publisher line with Legal and Privacy: a new
sponsor goes here as on every other wall.

**Screenshots are scripted and show demo disks only** (`scripts/screenshots/`), never
a real disk or this Mac's folders.

## Traps measured on 2026-11-25

- **`qlmanage -t` does not test the thumbnail extension**: it takes the legacy
  generator path ("missing or invalid generator for thumbnail") and hung for over two
  minutes. `scripts/thumbnail.swift` asks `QLThumbnailGenerator`, the Finder's path;
  representation type 2 means our extension drew it (runningboard logs the
  `com.gfazioli.Floppeek.Thumbnail` process).
- **Only the root block stores the hash table size** (longword 3 = 72); a user
  directory leaves it 0. Reading it per directory listed no subdirectory contents.
- **xdftool converts dates through the local time zone with daylight saving**, so a
  summer date is stored an hour off what an Amiga would write: make-fixtures.sh runs
  with `TZ=UTC`.
- **xdftool ignores `size=1760K` for an `.adf`** and writes a DD disk;
  `create type=adf_hd` makes the HD one. amitools 0.8.1 (the last for Python 3.9)
  crashes on `comment`: use 0.9.1 on Python 3.13.
- **`Bundle.module` traps inside an extension** when the resource bundle is not where
  it looks, so the font is not a SwiftPM resource: bundle.sh copies
  `Resources/Fonts` into every bundle and `Topaz.name` falls back to the system
  monospaced font.
- **A two-axis `ScrollView` centres content smaller than itself**: the listing floated
  mid-window. Vertical-only fixed that but clipped long names; the content's
  minimum frame set to the viewport (`GeometryReader`), aligned top-leading, keeps
  both axes and pins it.

- **DOS\6 and DOS\7 (long names, OS 3.2) use another header layout**: read as the
  others, every name came out blank and the date 01-Jan-78. They are `.unsupported`
  until that layout is read and tested against an xdftool `DOS7` disk.

## Traps measured on 2026-11-26

- **On macOS 27 the Finder applies neither AppleScript's icon view options nor a
  `.DS_Store` written into a local folder it has opened before**: both left 64-point
  icons in the default order, without an error. A fresh volume's `.DS_Store`, written
  by dmgbuild, is honoured (the DMGs rely on it), so `shoot.sh` photographs the demo
  disks on a throwaway disk image (`scripts/screenshots/window.py`).
- **A local folder's Finder window shows the whole path in its path bar**, the home
  folder's name included, with the toolbar hidden; a volume's root shows only the
  volume.
- **`qlmanage -p` titles its window `[DEBUG] <file>`**: the preview shots are cropped
  inside the window frame.
- **The release link leaves rpaths into Xcode's toolchain and the Metal cryptex**, and
  SwiftPM records `sdk 15.0`; bundle.sh removes the first and stamps the second.

A review on 2026-11-25 fuzzed the reader with 120,000 mutated fixtures (release
build) and constructed worst cases: no crash, hang or out-of-range read.

## Fonts and licences

Topaz a1200 by dMG (rewtnull/amigafonts), GPL with the font exception, shipped
unmodified in `Resources/Fonts` with its README; the code is MIT. See NOTICE.md.
