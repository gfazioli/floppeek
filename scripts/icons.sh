#!/bin/bash
#
# icons.sh — render the app icon's masters into Brand/ from scripts/icon.swift.
#
#   scripts/icons.sh
#
# Two masters, one drawing:
#   Brand/app-icon-1024.png             the squircle at full bleed, transparent
#                                       corners: bundle.sh makes the .icns (macOS 15)
#   Brand/AppIcon.icon/Assets/icon.png  the same art on the whole square: macOS 26+
#                                       masks an icon to its own shape and puts a pale
#                                       plate under anything transparent, so this layer
#                                       has no corners to fill (Lancetta measured the
#                                       white frame a squircle-on-clear layer draws)
# and docs/icons/ the site's: 256 (the page, the README), 180 (touch), 32 (the tab).
#
# Compressed with ImageOptim's own oxipng, called out of the app bundle (lossless:
# the icon's gradients must not band).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILL="0.00000,0.33333,0.66667"   # Workbench blue #0055AA, the icon's ground
OPT="/Applications/ImageOptim.app/Contents/Frameworks/ImageOptimGPL.framework/Versions/A/Resources"

# Compiled once: interpreted, every call would compile it again (seconds each).
TOOL="$ROOT/.build/icon-tool"
if [ ! -x "$TOOL" ] || [ "$ROOT/scripts/icon.swift" -nt "$TOOL" ]; then
    mkdir -p "$ROOT/.build"
    swiftc -O -o "$TOOL" "$ROOT/scripts/icon.swift"
fi
icon() { "$TOOL" "$@"; }

mkdir -p "$ROOT/Brand/AppIcon.icon/Assets"
FILES=("$ROOT/Brand/app-icon-1024.png" "$ROOT/Brand/AppIcon.icon/Assets/icon.png")
icon 1024 "${FILES[0]}"
icon 1024 "${FILES[1]}" --square
cat > "$ROOT/Brand/AppIcon.icon/icon.json" <<JSON
{
  "fill" : {
    "automatic-gradient" : "extended-srgb:$FILL,1.00000"
  },
  "groups" : [
    {
      "layers" : [
        {
          "image-name" : "icon.png",
          "name" : "Floppeek"
        }
      ]
    }
  ],
  "supported-platforms" : {
    "squares" : "shared"
  }
}
JSON

mkdir -p "$ROOT/docs/icons"
for s in 256 180 32; do
    icon "$s" "$ROOT/docs/icons/icon-$s.png"
    FILES+=("$ROOT/docs/icons/icon-$s.png")
done

if [ -x "$OPT/oxipng" ]; then
    "$OPT/oxipng" -o max --strip safe -q "${FILES[@]}"
else
    echo "icons.sh: ImageOptim's oxipng not found; the icons are not compressed" >&2
fi
for f in "${FILES[@]}"; do echo "  ${f#"$ROOT/"}  $(stat -f %z "$f") bytes"; done
