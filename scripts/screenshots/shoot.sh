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
for part in Preview Thumbnail; do
    line=$(pluginkit -m -v -i "com.gfazioli.Floppeek.$part" | head -1)
    [ -n "$line" ] || { echo "shoot.sh: Floppeek $part is not registered (scripts/bundle.sh --register)" >&2; exit 1; }
    echo "  $part: ${line##*$'\t'}"
done
APP="$(pluginkit -m -v -i com.gfazioli.Floppeek.Preview | head -1 | sed -E 's|.*\t(/.*\.app)/Contents/PlugIns/.*|\1|')"

"$ROOT/scripts/screenshots/disks.sh" "$DISKS" >/dev/null

if want finder; then
    # The window is written into the folder's .DS_Store, as dmgbuild writes a DMG's:
    # on macOS 27 the Finder answers AppleScript's icon size and arrangement without an
    # error and applies neither (measured here, and by create-dmg on the DMGs). No
    # toolbar, sidebar or path bar: they show this Mac's folders and its home's name.
    # The tools are the DMG builder's environment (scripts/dmg/build.sh installs it).
    # So the window is a volume's, built by dmgbuild from scripts/screenshots/window.py
    # (why: that file's header), in the DMG builder's environment.
    DMGBUILD=$(ls -d "$HOME"/Library/Caches/com.gfazioli.Floppeek.release-tools/dmgbuild-*/bin/dmgbuild 2>/dev/null | tail -1)
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
    sleep 6   # the Finder asks the thumbnail extension for each disk
    "$UIV" shot Finder "$OUT/finder.png" "Amiga Disks"
    osascript -e "tell application \"Finder\" to close window id $WID"
    hdiutil detach "$VOLUME" -quiet
    trap - EXIT
fi

# qlmanage titles its window "[DEBUG] <file>": the capture is cropped to the preview
# itself, inside the window's title bar and rounded frame (2x pixels).
CROP="$(dirname "$UIV")/crop"
preview() { # <disk> <out>
    qlmanage -p "$DISKS/$1" >/dev/null 2>&1 &
    local pid=$!
    sleep 4
    local raw="$ROOT/build/screenshots/raw-$2"
    "$UIV" shot qlmanage "$raw"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    local w h
    w=$(sips -g pixelWidth "$raw" | awk '/pixelWidth/{print $2}')
    h=$(sips -g pixelHeight "$raw" | awk '/pixelHeight/{print $2}')
    [ ! -e "$OUT/$2" ] || trash "$OUT/$2"
    "$CROP" "$raw" "$OUT/$2" 20 92 $((w - 40)) $((h - 112))
}
want work && preview "Work Disk.adf" preview-work-disk.png
want demo && preview "Starfield Demo.adf" preview-demo.png

if want app; then
    open -n "$APP"
    sleep 3
    "$UIV" shot Floppeek "$OUT/app.png"
    osascript -e 'tell application id "com.gfazioli.Floppeek" to quit'
fi

for f in "$OUT"/*.png; do echo "  ${f#"$ROOT/"}  $(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/{printf "%s ", $2}')"; done
echo "shoot.sh: optimise with ImageOptim before committing (claude-global scripts/imageoptim-batch)"
