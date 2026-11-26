#!/bin/bash
#
# release.sh — package Floppeek as the DMG a stranger downloads, and publish it.
#
#   scripts/release.sh --dry-run     test, build, sign, notarize, staple, DMG, Gatekeeper:
#                                    everything a release does, publishing nothing
#   scripts/release.sh --publish     the same, then the tag, the GitHub Release on this
#                                    repository and the cask in gfazioli/homebrew-tap
#
# Options: --profile <notarytool keychain profile>, --identity "<codesign identity>".
#
# The version is VERSION's; the notes are its section of CHANGELOG.md (`## 0.1.0`),
# and a publish without one stops before anything leaves this Mac. Writes
# build/dist/Floppeek-<version>.dmg and prints its size and sha256.
#
# There is no Sparkle: the app is opened once and then never again (the extensions
# are what runs), so an updater inside it would rarely get the chance to look.
# Updates reach people through Homebrew (`brew upgrade`) and the page's download.
#
# A dry run notarizes for real: Apple's answer is the part of a release most likely to
# fail, and a submission publishes nothing. notarytool reads its profiles from the
# data-protection keychain, which a locked screen closes: on "No Keychain password
# item found" for every profile, unlock the Mac, wait a minute, run it again.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/build/dist"
APP="$ROOT/build/Floppeek.app"
REPO="gfazioli/floppeek"
TAP="gfazioli/homebrew-tap"

MODE=""
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
IDENTITY="${SIGN_IDENTITY:-}"
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) MODE=dry ;;
        --publish) MODE=publish ;;
        --profile) NOTARY_PROFILE="${2:?--profile needs a name}"; shift ;;
        --identity) IDENTITY="${2:?--identity needs a codesign identity}"; shift ;;
        *) echo "release.sh: unknown argument '$1'" >&2; exit 2 ;;
    esac
    shift
done
[ -n "$MODE" ] || { sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

say() { printf '\n\033[1m→ %s\033[0m\n' "$1"; }
die() { printf '\033[31mrelease.sh: %s\033[0m\n' "$1" >&2; exit 1; }

VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
TAG="v$VERSION"
DMG="$DIST/Floppeek-$VERSION.dmg"
NOTES="$DIST/notes-$VERSION.md"

# ── Pre-flight ───────────────────────────────────────────────────────────────
say "Pre-flight: Floppeek $VERSION ($MODE)"

mkdir -p "$DIST"
# The section of CHANGELOG.md under "## <version>", up to the next "## ".
# GitHub keeps every newline of a release body as a line break, so the changelog's
# wrapped lines are joined: a bullet or a paragraph becomes one line. (No code blocks,
# tables or nested bullets in the notes: they would be joined too.) Versions compare as strings: as
# numbers, 1.10 would find "## 1.1".
awk -v v="$VERSION" '$0 ~ "^## " { if (f) exit; if ($2 "" == v "") { f = 1; next } } f' "$ROOT/CHANGELOG.md" \
    | awk '/^[[:space:]]*$/ { if (line != "") print line; line = ""; print ""; next }
           /^(- |\* |[0-9]+\. |#)/ { if (line != "") print line; line = $0; next }
           { sub(/^[[:space:]]+/, ""); line = (line == "" ? $0 : line " " $0) }
           END { if (line != "") print line }' \
    | sed -e '/./,$!d' > "$NOTES"
[ -s "$NOTES" ] || die "CHANGELOG.md has no section '## $VERSION'"
echo "  notes:    CHANGELOG.md, $(wc -l < "$NOTES" | tr -d ' ') lines"

if [ "$MODE" = publish ]; then
    [ "$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)" = main ] || die "publish from main"
    [ -z "$(git -C "$ROOT" status --porcelain)" ] || die "the working tree is not clean"
    git -C "$ROOT" fetch -q origin
    [ "$(git -C "$ROOT" rev-parse HEAD)" = "$(git -C "$ROOT" rev-parse origin/main)" ] \
        || die "main is not origin/main: pull or push first"
    ! git -C "$ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null || die "the tag $TAG exists already"
    # gh must be able to do what publish asks of it, before ten minutes of notarizing
    # and a public tag: a lapsed token would otherwise also read as "no Release yet".
    gh auth status >/dev/null 2>&1 || die "gh is not signed in (gh auth login)"
    [ "$(gh api "repos/$TAP" --jq .permissions.push 2>/dev/null)" = true ] || die "no push access to $TAP"
    ! gh release view "$TAG" -R "$REPO" >/dev/null 2>&1 || die "the GitHub Release $TAG exists already"
fi

if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
fi
[ -n "$IDENTITY" ] || die "no Developer ID Application identity in the keychain"
echo "  identity: $IDENTITY"

if [ -z "$NOTARY_PROFILE" ]; then
    for p in Floppeek-Notary Netfox-Notary Lancetta-Notary FinderGit-Notary; do
        if xcrun notarytool history --keychain-profile "$p" --output-format plist >/dev/null 2>&1; then
            NOTARY_PROFILE="$p"; break
        fi
    done
fi
[ -n "$NOTARY_PROFILE" ] || die "no working notarytool profile (a locked screen hides them all: unlock, wait a minute, retry)"
# A profile carries no bundle id, so a sibling app's works; the line says which.
echo "  notary:   $NOTARY_PROFILE"

# The site serves its own copy of the font and its licence (docs/ is published as
# it is, so it cannot point outside itself): the copies must be the app's.
for f in Topaz_a1200_v1.0.ttf COPYING-GPL-3.0.txt; do
    cmp -s "$ROOT/Resources/Fonts/$f" "$ROOT/docs/fonts/$f" || die "docs/fonts/$f differs from Resources/Fonts/$f"
done

DMG_BACKGROUND="$ROOT/scripts/dmg-background.tiff"
[ -f "$DMG_BACKGROUND" ] || die "no $DMG_BACKGROUND (macos-workspace scripts/dmg-background/render.sh Floppeek <repo>)"

# ── Test, build, sign ────────────────────────────────────────────────────────
say "Tests"
if ! swift test --package-path "$ROOT" > "$DIST/test.log" 2>&1; then
    tail -20 "$DIST/test.log" >&2
    die "the tests fail (build/dist/test.log)"
fi
{ grep -E 'Test run with [0-9]+ tests' "$DIST/test.log" || true; } | tail -1 | sed 's/^/  /'

say "Building, bundling, signing (universal, secure timestamp)"
"$ROOT/scripts/bundle.sh" --release --identity "$IDENTITY"

BUILT_VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
[ "$BUILT_VERSION" = "$VERSION" ] || die "the app says $BUILT_VERSION, VERSION says $VERSION"
MIN_MACOS=$(plutil -extract LSMinimumSystemVersion raw "$APP/Contents/Info.plist")

say "Checking what the signed bundle declares"
# Read off the signed artifacts: get-task-allow lets any process of the user attach a
# debugger, and an extension without its sandbox is not loaded by Quick Look at all.
ENT=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null) || die "cannot read the app's entitlements"
case "$ENT" in *get-task-allow*|*disable-library-validation*) die "the app carries a debug entitlement" ;; esac
for appex in "$APP"/Contents/PlugIns/*.appex; do
    E=$(codesign -d --entitlements - --xml "$appex" 2>/dev/null) || die "cannot read $(basename "$appex")'s entitlements"
    case "$E" in *get-task-allow*|*disable-library-validation*) die "$(basename "$appex") carries a debug entitlement" ;; esac
    case "$E" in *com.apple.security.app-sandbox*) ;; *) die "$(basename "$appex") is not sandboxed" ;; esac
    case "$E" in *com.apple.security.network*) die "$(basename "$appex") asks for the network" ;; esac
    echo "  $(basename "$appex"): sandboxed, offline"
done
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E 'Authority=Developer ID Application|TeamIdentifier|flags' | sed 's/^/  /'

# ── Notarize the app, then the DMG ──────────────────────────────────────────
# The verdict is read from the submission's own answer, not the exit code (`--wait`
# can end well on a submission Apple found Invalid), and its log is this submission's,
# not the profile's latest, which on a shared profile may be another app's.
notarize() {
    local answer
    local status
    local id
    answer=$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json) || true
    status=$(echo "$answer" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' 2>/dev/null || true)
    id=$(echo "$answer" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' 2>/dev/null || true)
    echo "  $(basename "$1"): ${status:-no answer}${id:+ ($id)}"
    if [ "$status" != Accepted ]; then
        [ -z "$id" ] || xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
        die "notarization did not accept $(basename "$1"): ${answer:-no answer from notarytool}"
    fi
}

say "Notarizing the app (a few minutes)"
ZIP="$DIST/Floppeek-app.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
notarize "$ZIP"
trash "$ZIP" 2>/dev/null || true
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

say "Creating the DMG"
[ ! -e "$DMG" ] || trash "$DMG"
# dmgbuild writes the window itself and build.sh mounts the result and refuses an
# image that does not open as the install window (scripts/dmg/build.sh).
"$ROOT/scripts/dmg/build.sh" "Floppeek $VERSION" "$APP" "$DMG_BACKGROUND" "$DMG"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

say "Notarizing the DMG (a few minutes)"
notarize "$DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

say "Gatekeeper, as a stranger's Mac sees the download"
if ! verdict=$(spctl --assess --verbose=4 --type install "$DMG" 2>&1); then
    echo "$verdict" >&2
    die "Gatekeeper rejects the DMG"
fi
echo "$verdict" | sed 's/^/  /'

SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
SIZE=$(stat -f%z "$DMG")

if [ "$MODE" = dry ]; then
    cat <<SUMMARY

  Dry run done: $DMG
  $SIZE bytes, sha256 $SHA, notarized and stapled, macOS $MIN_MACOS or later.
  Nothing was tagged, released or pushed. The notes the release would carry: $NOTES
SUMMARY
    exit 0
fi

# ── Publish ──────────────────────────────────────────────────────────────────
# Three public steps in order: the tag, the Release, the cask. The pre-flight refuses
# an existing tag or Release, so a run that stops between them cannot simply be run
# again: on the way out it says what is published and what is left to do by hand.
STEP=""
recover() {
    local status=$?
    [ "$status" -ne 0 ] || return 0
    case "$STEP" in
        tag) echo "release.sh: the tag $TAG is pushed and there is no Release. Retry with:" >&2
             echo "  gh release create $TAG '$DMG' -R $REPO --verify-tag --title 'Floppeek $VERSION' --notes-file '$NOTES'" >&2
             echo "or take the tag back: git push origin :refs/tags/$TAG && git tag -d $TAG" >&2 ;;
        release) echo "release.sh: the Release $TAG is out and the cask is not. Check the DMG it serves" >&2
                 echo "(sha256 $SHA expected), then write Casks/floppeek.rb in $TAP from scripts/floppeek.rb." >&2 ;;
    esac
}
trap recover EXIT

say "Tagging $TAG"
git -C "$ROOT" tag -a "$TAG" -m "Floppeek $VERSION"
git -C "$ROOT" push -q origin "$TAG" || { git -C "$ROOT" tag -d "$TAG" >/dev/null; die "could not push $TAG"; }
STEP=tag

say "GitHub Release on $REPO"
gh release create "$TAG" "$DMG" -R "$REPO" --verify-tag --title "Floppeek $VERSION" --notes-file "$NOTES"
STEP=release
# The asset as GitHub serves it, byte for byte: what the cask's sha256 is checked against.
CHECK="$(mktemp -d)"
gh release download "$TAG" -R "$REPO" -p "Floppeek-$VERSION.dmg" -D "$CHECK"
REMOTE=$(shasum -a 256 "$CHECK/Floppeek-$VERSION.dmg" | cut -d' ' -f1)
trash "$CHECK" || true
[ "$REMOTE" = "$SHA" ] || die "the DMG GitHub serves hashes to $REMOTE, not $SHA: no cask written"
echo "  $(gh release view "$TAG" -R "$REPO" --json url --jq .url)"

say "Cask in $TAP"
TAPDIR="$(mktemp -d)"
gh repo clone "$TAP" "$TAPDIR" -- -q
mkdir -p "$TAPDIR/Casks"
sed -e "s/__VERSION__/$VERSION/" -e "s/__SHA256__/$SHA/" "$ROOT/scripts/floppeek.rb" > "$TAPDIR/Casks/floppeek.rb"
git -C "$TAPDIR" add Casks/floppeek.rb
git -C "$TAPDIR" commit -q -m "floppeek $VERSION"
git -C "$TAPDIR" push -q origin HEAD
STEP=done
echo "  $(git -C "$TAPDIR" log --oneline -1)"
trash "$TAPDIR" || true

cat <<SUMMARY

  Floppeek $VERSION is out:
    https://github.com/$REPO/releases/tag/$TAG
    brew install --cask gfazioli/tap/floppeek
SUMMARY
