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
EXECUTABLES=("$APP/Contents/MacOS/Floppeek")
for part in "${PARTS[@]}"; do EXECUTABLES+=("$APP/Contents/PlugIns/Floppeek$part.appex/Contents/MacOS/Floppeek$part"); done

# The icon, from the masters scripts/icons.sh renders into Brand/: an .icns for
# macOS 15, and Assets.car compiled from Brand/AppIcon.icon for 26 and later, which
# insets a legacy .icns on a pale plate of its own (Lancetta measured it). On 26+
# Assets.car wins; below 26 the .icns is all there is.
ICONSET="$ROOT/.build/AppIcon.iconset"
mkdir -p "$ICONSET" "$APP/Contents/Resources"
for s in 16 32 128 256 512; do
    sips -z $s $s "$ROOT/Brand/app-icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2)); sips -z $d $d "$ROOT/Brand/app-icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
if ACTOOL=$(xcrun --find actool 2>/dev/null); then
    ICON_OUT="$ROOT/.build/appicon"
    mkdir -p "$ICON_OUT"
    "$ACTOOL" "$ROOT/Brand/AppIcon.icon" --compile "$ICON_OUT" --platform macosx \
        --minimum-deployment-target 15.0 --app-icon AppIcon \
        --output-partial-info-plist "$ICON_OUT/partial.plist" --errors >/dev/null
    cp -f "$ICON_OUT/Assets.car" "$APP/Contents/Resources/Assets.car"
elif [ "$CONFIG" = release ]; then
    echo "bundle.sh: no actool (Xcode missing?): a release would ship macOS 26+ the plated icon" >&2
    exit 1
fi

if [ "$CONFIG" = release ]; then
    # Universal or nothing, checked on what is in the bundle: an arm64-only download
    # does not open on the Intel Macs macOS 15 still runs on, and nothing else says so.
    # And the rpaths the release link leaves pointing into this Mac (Xcode's toolchain,
    # the Metal cryptex): nothing resolves through them (every dylib is in /usr/lib or
    # a system framework), so a developer's paths are not shipped to strangers.
    # `sort -u`: otool lists every slice's commands, install_name_tool removes a path
    # from all slices at once, and a second removal fails.
    for exe in "${EXECUTABLES[@]}"; do
        archs=" $(lipo -archs "$exe") "
        for arch in arm64 x86_64; do
            case "$archs" in *" $arch "*) ;;
                *) echo "bundle.sh: $(basename "$exe") has no $arch slice (got:$archs)" >&2; exit 1 ;;
            esac
        done
        otool -l "$exe" | awk '/LC_RPATH/{f=1} f&&/ path /{print $2; f=0}' | sort -u | while read -r rp; do
            case "$rp" in
                /Applications/Xcode*|/var/run/com.apple.security.cryptexd/*|/Library/Developer/*)
                    install_name_tool -delete_rpath "$rp" "$exe" ;;
            esac
        done
    done
fi

# The SDK each binary says it was linked against. SwiftPM's link records the deployment
# target there (sdk 15.0), and macOS runs a binary linked on 15 in that release's
# compatibility mode (Lancetta measured old controls and missing behaviour until the
# number said 27). The build ran a moment ago in this script with the selected Xcode,
# so the selected SDK is the one linked. Rewritten before signing (vtool breaks a
# signature), each slice keeping its own deployment target and the linker's tool entry,
# then read back.
SDK=$(xcrun --sdk macosx --show-sdk-version)
for exe in "${EXECUTABLES[@]}"; do
    for arch in $(lipo -archs "$exe"); do
        minos=$(otool -arch "$arch" -l "$exe" | awk '/LC_BUILD_VERSION/{f=1} f&&/ minos /{if (!n++) print $2; f=0}')
        tools=()
        for entry in $(otool -arch "$arch" -l "$exe" \
                       | awk '/cmd LC_BUILD_VERSION/{f=1; next} /^Load command/{f=0}
                              f&&$1=="tool"{t=$2} f&&$1=="version"&&t!=""{print t ":" $2; t=""}'); do
            tools+=(-tool "${entry%%:*}" "${entry#*:}")
        done
        xcrun vtool -arch "$arch" -set-build-version macos "$minos" "$SDK" ${tools[@]+"${tools[@]}"} \
            -replace -output "$exe" "$exe" 2>/dev/null
        recorded=$(otool -arch "$arch" -l "$exe" | awk '/LC_BUILD_VERSION/{f=1} f&&/ sdk /{print $2; f=0}')
        [ "$recorded" = "$SDK" ] || { echo "bundle.sh: $(basename "$exe") $arch records sdk $recorded, not $SDK" >&2; exit 1; }
    done
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
