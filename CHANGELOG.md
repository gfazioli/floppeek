# Changelog

Each release's notes are its section here: `scripts/release.sh` publishes the
section under the version it releases.

## 0.1.0

The first release: Amiga disk images in the Finder.

- **Quick Look for `.adf`.** Select a disk image and press Space: it opens as a
  Workbench window listing every drawer, with sizes, protection bits, dates and
  comments, the way AmigaDOS `List` prints them, and how full the disk is.
- **A floppy for every disk.** In the Finder each `.adf` becomes a 3.5" floppy with
  the volume's name on its label.
- **Game and demo disks.** Disks that boot their own loader, with no file system,
  show their boot block and whether it boots.
- **What it reads:** OFS and FFS disks, double and high density, dumps up to 84
  cylinders. Long-name disks (OS 3.2) are recognised and not read yet.
- **Offline and sandboxed.** The extensions read the one file being previewed and
  nothing else, and never touch the network.

Universal (Apple silicon and Intel), macOS 15 Sequoia or later.
