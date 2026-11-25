# Floppeek

Quick Look for Amiga disk images on macOS.

Select an `.adf` in the Finder and press Space: the disk opens as a Workbench window,
every drawer listed with sizes, protection bits, dates and comments, the way AmigaDOS
`List` prints them. Its icon becomes a floppy with the volume name on the label. Disks
without a file system (games and demos with their own loaders) show their boot block.

**Status:** early development, not released yet. Reads OFS and FFS disks, DD and HD.

Coming next: IFF/ILBM pictures, tracker modules (.mod, .xm, .s3m, .it) with their
patterns and sound, then Commodore 64 files.

## Build

```sh
swift test
scripts/bundle.sh --register   # needs a Developer ID Application identity
```

## Credits and licence

Floppeek is MIT-licensed. The Topaz a1200 font is by dMG of Trueschool and Divine
Stylers ([rewtnull/amigafonts](https://github.com/rewtnull/amigafonts)), GPL with the
font exception. Test disks are made with [amitools](https://github.com/cnvogelg/amitools).

Amiga is a trademark of its owner. Floppeek is not affiliated with or endorsed by it.
