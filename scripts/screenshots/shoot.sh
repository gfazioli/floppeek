#!/bin/bash
#
# shoot.sh — the screenshots the README and the page show, taken by window id.
#
#   XDFTOOL=<xdftool> scripts/screenshots/shoot.sh [--only finder|work|demo|app]
#
# Writes docs/screenshots/{finder,preview-work-disk,preview-demo,app}.png from the
# demo disks disks.sh makes (never a real disk), with the extensions macOS has
# registered: the script prints which copy that is, so an image of an old build is
# caught before it is published. Captures go through macos-workspace's uiverify
# (`uiv.sh shot`, the window's own buffer, never a screen rectangle).
#
# What it touches, and gives back: a Finder window on the demo disks (opened, shot,
# closed), a qlmanage window per preview, the Floppeek app (launched, shot, quit).
# The Finder window hides its toolbar and sidebar, which would show this Mac's own
# folders.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UIV="${UIV:-$ROOT/../scripts/uiverify/uiv.sh}"
[ -x "$UIV" ] || UIV="$HOME/Lavoro/GitHub/MacOS/scripts/uiverify/uiv.sh"
[ -x "$UIV" ] || { echo "shoot.sh: uiverify not found (set UIV)" >&2; exit 1; }
OUT="$ROOT/docs/screenshots"
DISKS="$ROOT/build/screenshots/Amiga Disks"
ONLY="${2:-}"; [ "${1:-}" = --only ] || ONLY=""
want() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }
mkdir -p "$OUT"

# Which build answers: the one pluginkit names is the one the captures show.
APP=""
for part in Preview Thumbnail; do
    line=$(pluginkit -m -v -i "com.gfazioli.Floppeek.$part" | head -1)
    # pluginkit answers " (no matches)", and exits 0, for an extension it does not know.
    case "$line" in *.appex) ;; *) echo "shoot.sh: Floppeek $part is not registered (scripts/bundle.sh --register)" >&2; exit 1 ;; esac
    echo "  $part: ${line##*$'\t'}"
    APP="${APP:-$(echo "$line" | sed -E 's|.*\t(/.*\.app)/Contents/PlugIns/.*|\1|')}"
done

# Captures until two in a row are the same picture, so a shot never catches a window
# still filling in (generic icons before the thumbnails, an empty preview), and never
# waits longer than it has to. <app> <out.png> [window title]
settle() {
    local previous=""
    local now
    local i
    for i in $(seq 1 30); do
        sleep 0.7
        "$UIV" shot "$@" >/dev/null || continue
        now=$(shasum -a 256 "$2" | cut -d' ' -f1)
        # Not before the third: the Finder can show its generic icons for over a second.
        if [ "$i" -ge 3 ] && [ "$now" = "$previous" ]; then echo "  settled after $i captures: ${2#"$ROOT/"}"; return 0; fi
        previous=$now
    done
    echo "shoot.sh: $1's window never settled" >&2
    return 1
}

"$ROOT/scripts/screenshots/disks.sh" "$DISKS" >/dev/null

if want finder; then
    # The window is a throwaway volume's, laid out by dmgbuild (why: window.py's header),
    # with the DMG builder's own environment.
    DMGBUILD=$(ls -d "$HOME"/Library/Caches/com.gfazioli.Floppeek.release-tools/dmgbuild-*/bin/dmgbuild 2>/dev/null | tail -1 || true)
    [ -n "$DMGBUILD" ] || { echo "shoot.sh: no dmgbuild; run scripts/release.sh --dry-run once" >&2; exit 1; }
    VOLUME="/Volumes/Amiga Disks"
    [ ! -e "$VOLUME" ] || { echo "shoot.sh: $VOLUME is already mounted; eject it first" >&2; exit 1; }
    IMAGE="$ROOT/build/screenshots/amiga-disks.dmg"
    [ ! -e "$IMAGE" ] || trash "$IMAGE"
    "$DMGBUILD" -s "$ROOT/scripts/screenshots/window.py" -D disks="$DISKS" "Amiga Disks" "$IMAGE" >/dev/null
    hdiutil attach -noverify -noautoopen "$IMAGE" >/dev/null
    trap 'hdiutil detach "$VOLUME" -quiet 2>/dev/null || true' EXIT
    # Thumbnails are cached per file; new files get fresh ones, drawn by this build.
    qlmanage -r cache >/dev/null 2>&1 || true
    WID=$(osascript -e 'tell application "Finder" to open disk "Amiga Disks"' \
                    -e 'tell application "Finder" to return id of front window')
    settle Finder "$OUT/finder.png" "Amiga Disks"   # the thumbnails arrive one by one
    osascript -e "tell application \"Finder\" to close window id $WID"
    hdiutil detach "$VOLUME" -quiet
    trap - EXIT
fi

# qlmanage titles its window "[DEBUG] <file>": the capture is cropped to the preview
# itself, inside the title bar and the rounded frame. The insets are measured on a
# Retina capture of the 760 x 560 preview (PreviewViewController), whose window shot
# is 1540 x 1206 pixels; any other size means other insets, so it stops there.
CROP="$(dirname "$UIV")/crop"
preview() { # <disk> <out>
    qlmanage -p "$DISKS/$1" >/dev/null 2>&1 &
    local pid=$!
    local raw="$ROOT/build/screenshots/raw-$2"
    local size
    settle qlmanage "$raw"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    size=$(sips -g pixelWidth -g pixelHeight "$raw" | awk '/pixel/{printf "%s ", $2}')
    [ "$size" = "1540 1206 " ] || { echo "shoot.sh: the preview window is ${size}px, not 1540 x 1206: measure the crop again" >&2; exit 1; }
    [ ! -e "$OUT/$2" ] || trash "$OUT/$2"
    "$CROP" "$raw" "$OUT/$2" 20 92 1500 1094
}
want work && preview "Work Disk.adf" preview-work-disk.png
want demo && preview "Starfield Demo.adf" preview-demo.png

if want app; then
    open -n "$APP"
    settle Floppeek "$OUT/app.png"
    osascript -e 'tell application id "com.gfazioli.Floppeek" to quit'
fi

for f in "$OUT"/*.png; do echo "  ${f#"$ROOT/"}  $(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/{printf "%s ", $2}')"; done
echo "shoot.sh: optimise with ImageOptim before committing (claude-global scripts/imageoptim-batch)"
