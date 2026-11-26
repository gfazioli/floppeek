#!/usr/bin/env bash
#
# build.sh — package an app as the disk image people download, and prove the
# image opens as the install window.
#
#   scripts/dmg/build.sh "<volume name>" <App>.app <background.tiff> <out.dmg>
#   scripts/dmg/build.sh --check <some.dmg> <App>.app      # the proof alone
#
# WHY NOT create-dmg
#
# create-dmg lays the window out by scripting Finder: it opens the mounted
# image, sets the background, the icon size and the positions through
# AppleScript, and trusts Finder to write them to the volume's .DS_Store. On
# the Mac Studio (macOS 27.2.1, Finder 27.2) Finder answers every one of those
# commands without an error and applies none of them to the window: measured
# 2026-11-12, the script read back "icon size 100" over a window drawn at the
# default size, the background reached the .DS_Store for a few seconds and was
# overwritten with the default window the moment the window closed. Mounted
# visibly or hidden, closed or left open, with a pause or without: the same.
# create-dmg's own wait is only for the file to exist. FinderGit 0.62.0 was
# built there and shipped as two bare icons on a dark window; 0.61.0, built on
# the MacBook Pro the day before with the same script, was right.
#
# dmgbuild writes the .DS_Store itself, so the window does not depend on which
# Finder is running, on a window server, or on timing. The window is described
# once, in layout.py.
#
# THE PROOF
#
# Whatever builds it, the image is mounted again and its .DS_Store is read
# (check.py): a picture is named as the background, the icons are the size and
# at the positions layout.py says. A release whose window is wrong stops here.
# `--check` runs the same on any image; it fails FinderGit-0.62.0.dmg and
# Lancetta-0.64.2.dmg, the last Lancetta image without the picture.
#
# The same builder ships FinderGit, Netfox and Lancetta, where it was measured;
# this copy is theirs unchanged but for the cache directory below.
#
# The tools are three pure-Python packages pinned by hash (requirements.txt),
# installed once into an environment of their own under ~/Library/Caches and
# again whenever the pins change. DMG_TOOLS_DIR moves that environment.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="${DMG_PYTHON:-/usr/bin/python3}"
TOOLS_ROOT="${DMG_TOOLS_DIR:-$HOME/Library/Caches/com.gfazioli.Floppeek.release-tools}"

usage() {
    sed -n '3,7p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
}

# The environment is named after the pins, so moving one makes a new one and
# an interrupted install is never mistaken for a finished one.
tools() {
    local pins venv
    pins="$(shasum -a 256 "$HERE/requirements.txt" | cut -c1-16)"
    venv="$TOOLS_ROOT/dmgbuild-$pins"
    if [[ ! -x "$venv/bin/dmgbuild" || ! -f "$venv/.complete" ]]; then
        echo "  installing the disk image tools into $venv" >&2
        rm -rf "$venv"
        mkdir -p "$TOOLS_ROOT"
        # Each step returns on failure: tools runs in a command substitution, where
        # bash 3.2 turns errexit off, so a failed pip went on to write .complete.
        "$PYTHON" -m venv "$venv" || return 1
        "$venv/bin/pip" install --quiet --disable-pip-version-check --no-deps \
            --require-hashes -r "$HERE/requirements.txt" >&2 || return 1
        touch "$venv/.complete"
    fi
    echo "$venv"
}

# Mounts the image where nothing else looks, reads its window, unmounts it.
check() {
    local dmg="$1" app_name="$2" venv="$3" mount rc=0
    mount="$(mktemp -d "${TMPDIR:-/tmp}/dmg-check.XXXXXX")"
    if ! hdiutil attach -nobrowse -readonly -noverify -noautoopen -mountpoint "$mount" "$dmg" >/dev/null; then
        echo "Error: could not mount $dmg to read its window" >&2
        rmdir "$mount" 2>/dev/null || true
        return 2
    fi
    PYTHONPATH="$HERE" "$venv/bin/python" "$HERE/check.py" "$mount" "$app_name" || rc=$?
    # The app as it sits in the image, which is the copy people drag out.
    # Packaging can add to a signed bundle: an attribute that hides the
    # extension made this fail while Gatekeeper went on accepting the image.
    if ! codesign --verify --deep --strict "$mount/$app_name" 2>/dev/null; then
        echo "  ✗ $app_name in the image fails codesign --verify --deep --strict:" >&2
        codesign --verify --deep --strict "$mount/$app_name" 2>&1 | sed 's/^/      /' >&2 || true
        rc=1
    fi
    hdiutil detach "$mount" >/dev/null 2>&1 || hdiutil detach -force "$mount" >/dev/null 2>&1 || true
    rmdir "$mount" 2>/dev/null || true
    return "$rc"
}

if [[ "${1:-}" == "--check" ]]; then
    [[ $# -eq 3 ]] || usage
    [[ -f "$2" ]] || { echo "Error: no disk image at $2" >&2; exit 2; }
    VENV="$(tools)" || { echo "Error: could not install the disk image tools" >&2; exit 2; }
    if check "$2" "$3" "$VENV"; then
        echo "  ✓ $(basename "$2") opens as the install window"
    else
        echo "Error: $(basename "$2") does not open as the install window" >&2
        exit 1
    fi
    exit 0
fi

[[ $# -eq 4 ]] || usage
VOLUME_NAME="$1"; APP="$2"; BACKGROUND="$3"; OUT="$4"
[[ -d "$APP" ]] || { echo "Error: no app at $APP" >&2; exit 2; }
[[ -f "$BACKGROUND" ]] || { echo "Error: no background at $BACKGROUND" >&2; exit 2; }

VENV="$(tools)" || { echo "Error: could not install the disk image tools" >&2; exit 2; }
# Built and checked beside, then moved over $OUT: an image already there stays until
# its replacement has passed the check.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/dmg-build.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
BUILT="$WORK/$(basename "$OUT")"
"$VENV/bin/dmgbuild" -s "$HERE/layout.py" \
    -D app="$APP" -D background="$BACKGROUND" \
    "$VOLUME_NAME" "$BUILT"

if ! check "$BUILT" "$(basename "$APP")" "$VENV"; then
    mv -f "$BUILT" "${OUT%.dmg}.rejected.dmg"
    echo "Error: ${OUT%.dmg}.rejected.dmg was built, and does not open as the install window — not releasing it" >&2
    exit 1
fi
mv -f "$BUILT" "$OUT"
echo "  ✓ $(basename "$OUT") opens as the install window"
