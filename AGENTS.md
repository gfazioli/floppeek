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
  inside-out and, with `--register`, registers it. No Xcode project.

## Commands

```sh
swift test                                   # the reader against xdftool's own listings
scripts/bundle.sh --register                 # build/Floppeek.app, Developer ID, registered
qlmanage -p <file.adf>                       # the preview, in a qlmanage window
swift scripts/thumbnail.swift <file.adf> <out.png>   # the thumbnail, as the Finder asks for it
```

Capture a preview with `../scripts/uiverify/uiv.sh shot qlmanage <out.png>`, never a
screen rectangle.

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

## Fonts and licences

Topaz a1200 by dMG (rewtnull/amigafonts), GPL with the font exception, shipped
unmodified in `Resources/Fonts` with its README; the code is MIT. See NOTICE.md.
