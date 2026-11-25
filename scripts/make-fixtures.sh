#!/bin/bash
#
# make-fixtures.sh — build the ADF test disks with amitools' xdftool.
#
# The reader is tested against disks written by an independent implementation,
# never against images made by our own code (a writer and a reader that share a
# misunderstanding of the format agree with each other) and never against
# copyrighted disks.
#
# Needs xdftool from amitools 0.9.1 (0.8.1 on Python 3.9 crashes on `comment`):
#   python3.13 -m venv .venv && .venv/bin/pip install amitools==0.9.1
#   XDFTOOL=.venv/bin/xdftool scripts/make-fixtures.sh
#
# Writes Tests/FloppeekCoreTests/Fixtures/{ofs,ffs,ffs-hd,ndos}.adf and, beside
# each DOS disk, xdftool's own listing (<name>.list.txt) for a human to compare.

set -euo pipefail

# AmigaDOS dates are wall-clock days/minutes/ticks with no time zone. xdftool
# converts through the local zone with daylight saving, so a summer date typed
# here would be stored an hour off what an Amiga would store; in UTC there is
# no shift, and its listing matches the naive values the reader returns.
export TZ=UTC

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/Tests/FloppeekCoreTests/Fixtures"
XDFTOOL="${XDFTOOL:-xdftool}"
command -v "$XDFTOOL" >/dev/null || { echo "make-fixtures.sh: no xdftool (set XDFTOOL)" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'trash "$WORK" 2>/dev/null || true' EXIT
mkdir -p "$OUT"

# Deterministic file contents: byte i of a pattern file is (i * 7 + seed) mod 256,
# the same formula the tests use to check what the reader returns.
pattern() { # <path> <size> <seed>
    python3 -c 'import sys; n=int(sys.argv[2]); s=int(sys.argv[3]); open(sys.argv[1],"wb").write(bytes((i*7+s)%256 for i in range(n)))' "$1" "$2" "$3"
}
printf 'Echo "Hello from Floppeek"\nLoadWB\nEndCLI >NIL:\n' > "$WORK/startup"
printf 'Floppeek test disk.\nMade with amitools xdftool for the reader tests.\n' > "$WORK/readme"
: > "$WORK/empty"
pattern "$WORK/small" 1200 1
pattern "$WORK/keymap" 500 2
pattern "$WORK/big50k" 50000 3
pattern "$WORK/big100k" 100000 4

fresh() { [ ! -e "$1" ] || trash "$1"; }

# OFS: nested directories, a file past the 72 data-block pointers of its header
# (OFS blocks carry 488 bytes, so 50 000 bytes need an extension block), an empty
# file, a comment, protection bits and fixed dates.
D="$OUT/ofs.adf"; fresh "$D"
"$XDFTOOL" "$D" create size=880K + format "Floppeek OFS" ofs \
    + makedir c + makedir s + makedir Devs + makedir Devs/Keymaps \
    + write "$WORK/small" c/Dir \
    + write "$WORK/startup" s/Startup-Sequence \
    + write "$WORK/keymap" Devs/Keymaps/i \
    + write "$WORK/readme" ReadMe \
    + write "$WORK/big50k" Big.bin \
    + write "$WORK/empty" Empty \
    + comment ReadMe "Read me first" \
    + protect ReadMe rw \
    + protect c/Dir rwed \
    + time ReadMe "02.01.1990 03:04:05" \
    + time Big.bin "31.12.1999 23:59:59" \
    + time s/Startup-Sequence "29.02.1992 12:00:00"
"$XDFTOOL" "$D" list > "${D%.adf}.list.txt"

# FFS: 80 files in the root, more than the 72 hash slots, so hash chains are
# certain; a 100 000-byte file (FFS blocks carry 512, 72 pointers = 36 864).
D="$OUT/ffs.adf"; fresh "$D"
cmds=(create size=880K + format "Floppeek FFS" ffs + makedir Pictures + makedir Music)
for i in $(seq -w 0 79); do cmds+=(+ write "$WORK/keymap" "file$i"); done
cmds+=(+ write "$WORK/big100k" Music/Long.mod + write "$WORK/readme" Pictures/About.txt
       + comment Music/Long.mod "Not really a module" + time Music/Long.mod "15.06.1987 08:30:00")
"$XDFTOOL" "$D" "${cmds[@]}"
"$XDFTOOL" "$D" list > "${D%.adf}.list.txt"

# FFS on an HD disk: 1760K, 3520 blocks, the root at 1760. xdftool ignores
# size=1760K for an .adf and writes a DD disk; the type option is what works.
D="$OUT/ffs-hd.adf"; fresh "$D"
"$XDFTOOL" "$D" create type=adf_hd + format "Floppeek HD" ffs + write "$WORK/readme" ReadMe
"$XDFTOOL" "$D" list > "${D%.adf}.list.txt"

# Not a DOS disk: a boot block without "DOS", as game disks have.
D="$OUT/ndos.adf"; fresh "$D"
python3 -c 'import sys; b=bytearray(901120); b[0:4]=b"\x00\x00\x00\x00"; b[12:28]=b"Not a DOS disk!!"; open(sys.argv[1],"wb").write(bytes(b))' "$D"

ls -l "$OUT"
