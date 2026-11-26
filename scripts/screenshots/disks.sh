#!/bin/bash
#
# disks.sh — the demo disks the screenshots show, written by amitools' xdftool.
#
#   XDFTOOL=<xdftool> scripts/screenshots/disks.sh <out-dir>
#
# Made here, never copied from a real disk: everything on them is invented (names,
# sizes, comments) or a byte pattern, so a published screenshot shows no one's
# software. xdftool as in scripts/make-fixtures.sh (amitools 0.9.1, Python 3.13).

set -euo pipefail
export TZ=UTC   # AmigaDOS dates are wall-clock; see make-fixtures.sh

OUT="${1:?usage: disks.sh <out-dir>}"
XDFTOOL="${XDFTOOL:-xdftool}"
command -v "$XDFTOOL" >/dev/null || { echo "disks.sh: no xdftool (set XDFTOOL)" >&2; exit 1; }
mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'trash "$WORK" 2>/dev/null || true' EXIT

# A file of <size> bytes: byte i is (i * 7 + seed) mod 256.
blob() { python3 -c 'import sys; n=int(sys.argv[2]); s=int(sys.argv[3]); open(sys.argv[1],"wb").write(bytes((i*7+s)%256 for i in range(n)))' "$WORK/$1" "$2" "$3"; }
fresh() { [ ! -e "$1" ] || trash "$1"; }

printf 'Echo "Welcome to the Work Disk"\nAssign T: RAM:\nLoadWB\nEndCLI >NIL:\n' > "$WORK/startup"
printf 'Floppeek demo disk.\nEverything here is made up for the screenshots.\n' > "$WORK/readme"
blob dir 1260 1; blob list 2084 2; blob copy 1932 3; blob ed 19312 4; blob calc 8840 5
blob mod1 98450 6; blob mod2 121304 7; blob mod3 64128 8; blob inst 23110 9
blob pic1 41022 10; blob pic2 55380 11; blob pic3 38916 12; blob brush 6404 13
blob font 3340 14; blob lib 21740 15; blob arc 412300 16; blob tool 15020 17

D="$OUT/Work Disk.adf"; fresh "$D"
"$XDFTOOL" "$D" create size=880K + format "Work Disk" ffs \
    + makedir C + makedir S + makedir Libs + makedir Tools + makedir Docs \
    + write "$WORK/dir" C/Dir + write "$WORK/list" C/List + write "$WORK/copy" C/Copy \
    + write "$WORK/startup" S/Startup-Sequence + write "$WORK/lib" Libs/disk.library \
    + write "$WORK/ed" Tools/Notepad + write "$WORK/calc" Tools/Calculator \
    + write "$WORK/readme" Docs/ReadMe + write "$WORK/readme" ReadMe \
    + comment Tools/Notepad "Small text editor" + comment ReadMe "Read me first" \
    + protect ReadMe rw + protect Docs/ReadMe rw \
    + time C/Dir "12.03.1991 10:15:00" + time C/List "12.03.1991 10:15:02" \
    + time C/Copy "12.03.1991 10:15:04" + time S/Startup-Sequence "04.11.1992 21:40:12" \
    + time Libs/disk.library "12.03.1991 10:16:30" + time Tools/Notepad "18.07.1993 16:02:44" \
    + time Tools/Calculator "02.02.1993 09:30:10" + time Docs/ReadMe "24.12.1993 18:00:00" \
    + time ReadMe "24.12.1993 18:00:00" + time C "12.03.1991 10:14:00" + time S "04.11.1992 21:39:00" \
    + time Libs "12.03.1991 10:16:00" + time Tools "18.07.1993 16:00:00" + time Docs "24.12.1993 17:58:00"

D="$OUT/Music Disk.adf"; fresh "$D"
"$XDFTOOL" "$D" create size=880K + format "Music Disk" ffs + makedir Modules + makedir Samples \
    + write "$WORK/mod1" Modules/mod.sunset-drive + write "$WORK/mod2" Modules/mod.copper-dreams \
    + write "$WORK/mod3" Modules/mod.blitter-blues + write "$WORK/inst" Samples/bass.raw \
    + write "$WORK/readme" ReadMe \
    + comment Modules/mod.sunset-drive "4 channels, 125 BPM" \
    + comment Modules/mod.copper-dreams "Slow one, for the end part" \
    + time Modules/mod.sunset-drive "03.06.1990 23:12:00" + time Modules/mod.copper-dreams "19.08.1990 02:44:10" \
    + time Modules/mod.blitter-blues "01.10.1990 14:05:33" + time Samples/bass.raw "15.05.1990 11:11:11" \
    + time Modules "03.06.1990 23:10:00" + time Samples "15.05.1990 11:10:00"

D="$OUT/Pixel Art.adf"; fresh "$D"
"$XDFTOOL" "$D" create size=880K + format "Pixel Art" ofs + makedir Pics + makedir Brushes \
    + write "$WORK/pic1" Pics/Harbour.iff + write "$WORK/pic2" Pics/Sunset.iff \
    + write "$WORK/pic3" Pics/Robot.iff + write "$WORK/brush" Brushes/Palm.brush \
    + comment Pics/Sunset.iff "32 colours, 320x256" \
    + time Pics/Harbour.iff "07.02.1992 19:20:00" + time Pics/Sunset.iff "21.06.1992 21:30:00" \
    + time Pics/Robot.iff "30.09.1992 17:45:12" + time Brushes/Palm.brush "21.06.1992 20:58:41" \
    + time Pics "07.02.1992 19:18:00" + time Brushes "21.06.1992 20:57:00"

D="$OUT/Utilities.adf"; fresh "$D"
"$XDFTOOL" "$D" create size=880K + format "Utilities" ffs + makedir Fonts \
    + write "$WORK/font" Fonts/pixel.font + write "$WORK/tool" DiskCheck + write "$WORK/calc" Clock \
    + time DiskCheck "11.11.1991 11:11:11" + time Clock "05.05.1991 05:05:05" + time Fonts/pixel.font "29.04.1991 15:00:00" + time Fonts "29.04.1991 14:59:00"

D="$OUT/Archive HD.adf"; fresh "$D"
"$XDFTOOL" "$D" create type=adf_hd + format "Archive HD" ffs + makedir Backups \
    + write "$WORK/arc" Backups/Projects.lha + write "$WORK/readme" ReadMe \
    + time Backups/Projects.lha "01.03.1995 08:00:00" + time ReadMe "01.03.1995 08:00:05" + time Backups "01.03.1995 07:59:00"

# A demo with its own loader: a DOS boot block (Kickstart boots nothing else), a
# message in it, a valid checksum, no root block. The label shows the file's name.
D="$OUT/Starfield Demo.adf"; fresh "$D"
python3 - "$D" <<'PY'
import struct, sys
disk = bytearray(901120)
boot = bytearray(1024)
boot[0:4] = b"DOS\0"
boot[8:12] = struct.pack(">I", 880)
# A few 68000 instructions' worth of bytes, then the text a demo would print.
boot[12:28] = bytes.fromhex("43FA003E4EAEFFA04A80670A20402068")
text = b"STARFIELD DEMO  - a Floppeek demo disk, made up for the screenshots.  Press fire.  "
boot[64:64 + len(text)] = text
total = 0
for i in range(0, 1024, 4):
    total += struct.unpack(">I", boot[i:i + 4])[0]
    if total > 0xFFFFFFFF:
        total = (total & 0xFFFFFFFF) + 1
boot[4:8] = struct.pack(">I", (~total) & 0xFFFFFFFF)
disk[0:1024] = boot
open(sys.argv[1], "wb").write(disk)
PY

ls -l "$OUT"
