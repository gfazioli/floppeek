#!/bin/bash
#
# bundle.sh — build build/Floppeek.app: the host app with its two Quick Look
# extensions in Contents/PlugIns, signed inside-out, optionally registered.
#
#   scripts/bundle.sh [--release] [--identity "<codesign identity>"] [--register]
#
# SwiftPM builds three executables; this wraps them. An extension is an executable
# entering at _NSExtensionMain (Package.swift), an Info.plist naming its principal
# class and the content types it serves, and the sandbox entitlement.
#
# Signing defaults to the first "Developer ID Application" identity in the
# keychain: LaunchServices registers a Developer ID bundle's extensions (Lancetta
# measured that pkd refuses an extension registered on its own). Local builds get
# no secure timestamp; --release asks Apple's timestamp server for one, which
# notarization requires.
#
# The bundle is updated in place, never trashed and rebuilt: a trashed copy stays
# registered with LaunchServices and Spotlight shows two apps (Lancetta, 10-24).
# Running extension processes are stopped first, so none is killed by a binary
# rewritten under it.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG=debug
IDENTITY=""
REGISTER=0
TIMESTAMP="--timestamp=none"
while [ $# -gt 0 ]; do
    case "$1" in
        --release) CONFIG=release; TIMESTAMP="--timestamp" ;;
        --identity) IDENTITY="${2:?--identity needs a codesign identity}"; shift ;;
        --register) REGISTER=1 ;;
        *) echo "bundle.sh: unknown option $1" >&2; exit 2 ;;
    esac
    shift
done

if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
    [ -n "$IDENTITY" ] || { echo "bundle.sh: no Developer ID Application identity; pass --identity" >&2; exit 1; }
fi

VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
BUILD="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 0)"

swift build -c "$CONFIG" --package-path "$ROOT"
PRODUCTS="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"

APP="$ROOT/build/Floppeek.app"
pkill -f "$APP/Contents/PlugIns/" 2>/dev/null || true

stamp() { # <template> <destination>
    sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" "$1" > "$2"
    plutil -lint -s "$2"
}

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts" "$APP/Contents/PlugIns"
cp -f "$PRODUCTS/Floppeek" "$APP/Contents/MacOS/Floppeek"
stamp "$ROOT/scripts/bundle/App-Info.plist" "$APP/Contents/Info.plist"
cp -f "$ROOT/Resources/Fonts/"* "$APP/Contents/Resources/Fonts/"

for part in Preview Thumbnail; do
    EXT="$APP/Contents/PlugIns/Floppeek$part.appex"
    mkdir -p "$EXT/Contents/MacOS" "$EXT/Contents/Resources/Fonts"
    cp -f "$PRODUCTS/Floppeek$part" "$EXT/Contents/MacOS/Floppeek$part"
    stamp "$ROOT/scripts/bundle/$part-Info.plist" "$EXT/Contents/Info.plist"
    cp -f "$ROOT/Resources/Fonts/"* "$EXT/Contents/Resources/Fonts/"
done

# Inside-out: each extension with its sandbox, then the app around them.
for part in Preview Thumbnail; do
    codesign --force --options=runtime "$TIMESTAMP" \
        --entitlements "$ROOT/scripts/bundle/Extension.entitlements" \
        --sign "$IDENTITY" "$APP/Contents/PlugIns/Floppeek$part.appex"
done
codesign --force --options=runtime "$TIMESTAMP" --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

echo "bundle.sh: $APP ($VERSION, build $BUILD, $CONFIG), signed by $IDENTITY"

if [ "$REGISTER" = 1 ]; then
    LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    "$LSREGISTER" -f -R -trusted "$APP"
    qlmanage -r >/dev/null 2>&1 || true
    qlmanage -r cache >/dev/null 2>&1 || true
    pluginkit -m -v -i com.gfazioli.Floppeek.Preview || true
    pluginkit -m -v -i com.gfazioli.Floppeek.Thumbnail || true
fi
