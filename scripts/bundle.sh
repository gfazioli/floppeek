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

# The extensions, each a SwiftPM product Floppeek<part>, a template
# scripts/bundle/<part>-Info.plist and the bundle id com.gfazioli.Floppeek.<part>.
PARTS=(Preview Thumbnail)

# A release runs on Intel Macs too: both slices. Local builds stay arm64, faster.
ARCHS=()
[ "$CONFIG" = release ] && ARCHS=(--arch arm64 --arch x86_64)
# ${ARCHS[@]+…}: macOS's bash 3.2 calls an empty array unbound under set -u.
swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --package-path "$ROOT"
PRODUCTS="$(swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --package-path "$ROOT" --show-bin-path)" # prints, builds nothing

APP="$ROOT/build/Floppeek.app"
pkill -f "$APP/Contents/PlugIns/" 2>/dev/null || true

# assemble <product> <bundle> <Info.plist template>: executable, stamped Info.plist, fonts.
assemble() {
    mkdir -p "$2/Contents/MacOS" "$2/Contents/Resources/Fonts"
    cp -f "$PRODUCTS/$1" "$2/Contents/MacOS/$1"
    sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" "$3" > "$2/Contents/Info.plist"
    plutil -lint -s "$2/Contents/Info.plist"
    cp -f "$ROOT/Resources/Fonts/"* "$2/Contents/Resources/Fonts/"
}

assemble Floppeek "$APP" "$ROOT/scripts/bundle/App-Info.plist"
for part in "${PARTS[@]}"; do
    assemble "Floppeek$part" "$APP/Contents/PlugIns/Floppeek$part.appex" "$ROOT/scripts/bundle/$part-Info.plist"
done

# Inside-out: each extension with its sandbox, then the app around them.
for part in "${PARTS[@]}"; do
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
    for part in "${PARTS[@]}"; do pluginkit -m -v -i "com.gfazioli.Floppeek.$part" || true; done
fi
