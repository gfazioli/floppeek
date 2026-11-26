#!/bin/bash
#
# icons.sh — render the app icon's masters into Brand/ from scripts/icon.swift.
#
#   scripts/icons.sh [concept]      # workbench (default), copper, pixel
#
# Two masters, one drawing:
#   Brand/app-icon-1024.png             the squircle at full bleed, transparent
#                                       corners: bundle.sh makes the .icns (macOS 15)
#   Brand/AppIcon.icon/Assets/icon.png  the same art on the whole square: macOS 26+
#                                       masks an icon to its own shape and puts a pale
#                                       plate under anything transparent, so this layer
#                                       has no corners to fill (Lancetta measured the
#                                       white frame a squircle-on-clear layer draws)
# and docs/ gets the site's icons when there is a docs/ (the page, the favicon).
#
# Compressed with ImageOptim's own oxipng, called out of the app bundle (lossless:
# the icon's gradients must not band).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONCEPT="${1:-workbench}"
case "$CONCEPT" in
    workbench|pixel) FILL="0.00000,0.33333,0.66667" ;;  # Workbench blue #0055AA
    copper) FILL="0.00000,0.00000,0.13333" ;;           # Workbench black #000022
    *) echo "icons.sh: unknown concept '$CONCEPT' (workbench, copper, pixel)" >&2; exit 2 ;;
esac
OPT="/Applications/ImageOptim.app/Contents/Frameworks/ImageOptimGPL.framework/Versions/A/Resources"

# icon.swift reads the Topaz font relative to the working directory.
icon() { ( cd "$ROOT" && swift scripts/icon.swift "$@" ); }

mkdir -p "$ROOT/Brand/AppIcon.icon/Assets"
FILES=("$ROOT/Brand/app-icon-1024.png" "$ROOT/Brand/AppIcon.icon/Assets/icon.png")
icon "$CONCEPT" 1024 "${FILES[0]}"
icon "$CONCEPT" 1024 "${FILES[1]}" --square
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

if [ -d "$ROOT/docs" ]; then
    mkdir -p "$ROOT/docs/icons"
    for s in 512 180 32; do
        icon "$CONCEPT" "$s" "$ROOT/docs/icons/icon-$s.png"
        FILES+=("$ROOT/docs/icons/icon-$s.png")
    done
fi

if [ -x "$OPT/oxipng" ]; then
    "$OPT/oxipng" -o max --strip safe -q "${FILES[@]}"
else
    echo "icons.sh: ImageOptim's oxipng not found; the icons are not compressed" >&2
fi
for f in "${FILES[@]}"; do echo "  ${f#"$ROOT/"}  $(stat -f %z "$f") bytes"; done
echo "icons.sh: $CONCEPT"
