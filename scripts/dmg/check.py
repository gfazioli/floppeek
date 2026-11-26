"""Does a mounted disk image open as the install window, or as two bare icons?

    check.py <mounted volume> <App>.app

Reads the volume's .DS_Store, the file Finder draws the window from, and says
what is wrong with it. Exit 0 when the window is the one `layout.py` describes,
1 when it is not, 2 when the file cannot be read at all.

Why it exists: FinderGit 0.62.0 went out with a .DS_Store that named no
background picture and left both icons where Finder puts them. The step that
writes it had reported success, the image was signed and notarized, and every
check of the release passed, because none of them opened the window.
"""
import os
import re
import sys

import ds_store.store
from ds_store import DSStore

import layout

# Reading one record of a file decodes every record beside it, and a store
# written by Finder carries a bookmark (pBBk) newer than the library can parse:
# "Not a bookmark file (truncated)" on FinderGit-0.61.0.dmg, the image this
# check exists to call right. Nothing here reads the bookmark, so it stays
# the bytes it is.
ds_store.store.codecs.pop(b"pBBk", None)


def problems(volume, app_name):
    store_path = os.path.join(volume, ".DS_Store")
    if not os.path.isfile(store_path):
        return ["no .DS_Store: Finder will show the default window"]
    found = []
    with DSStore.open(store_path, "r") as store:
        def record(name, code):
            try:
                return store[name][code]
            except KeyError:
                return None

        view = record(".", "icvp")
        if view is None:
            found.append("no icon view settings (icvp)")
        else:
            if view.get("backgroundType") != 2:
                found.append(f"the background is not a picture (backgroundType {view.get('backgroundType')!r})")
            if not view.get("backgroundImageAlias"):
                found.append("no background picture is named (backgroundImageAlias)")
            if round(view.get("iconSize", 0)) != layout.ICON_SIZE:
                found.append(f"icon size {view.get('iconSize')!r}, not {layout.ICON_SIZE}")
            # A window kept arranged puts its icons in a sorted grid and
            # ignores the positions below. FinderGit 0.62.0's store held both
            # positions right and arrangeBy "dateModified": the two icons came
            # up in a row at the top left, newest first. dmgbuild writes "none".
            if view.get("arrangeBy", "none") != "none":
                found.append(f"the window is arranged by {view.get('arrangeBy')!r}, so the icons ignore their positions")

        # The picture is drawn for one window size: in a smaller window the
        # Applications folder is outside it. Only the size is compared; the
        # origin is where the window stood on the screen that saved it, and
        # Finder writes it from the bottom of that screen.
        window = record(".", "bwsp")
        if window is None:
            found.append("no window settings (bwsp)")
        else:
            size = re.search(r"\},\s*\{\s*(\d+)\s*,\s*(\d+)\s*\}\s*\}\s*$", str(window.get("WindowBounds", "")))
            if size is None:
                found.append(f"the window has no size ({window.get('WindowBounds')!r})")
            elif (int(size.group(1)), int(size.group(2))) != layout.WINDOW_SIZE:
                found.append(f"the window is {size.group(1)}x{size.group(2)}, not {layout.WINDOW_SIZE[0]}x{layout.WINDOW_SIZE[1]}")

        # A view style is not always written (Finder leaves it out of a store
        # that has icon view settings), but one that is must be icon view: a
        # list has no background.
        for code in ("icvl", "vstl"):
            style = record(".", code)
            # A record with no codec of its own comes back as (type, value).
            if isinstance(style, (tuple, list)):
                style = style[-1]
            if style is not None and style != b"icnv":
                found.append(f"the window opens as {style!r}, not in icon view")

        for name, wanted in ((app_name, layout.APP_POSITION), ("Applications", layout.APPLICATIONS_POSITION)):
            if not os.path.lexists(os.path.join(volume, name)):
                found.append(f"{name} is not in the image")
                continue
            position = record(name, "Iloc")
            if position is None:
                found.append(f"{name} has no position")
            elif tuple(position[:2]) != wanted:
                found.append(f"{name} is at {tuple(position[:2])}, not {wanted}")
    return found


def main(argv):
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    volume, app_name = argv[1], argv[2]
    try:
        found = problems(volume, app_name)
    except Exception as error:  # a .DS_Store that is not one, an unreadable volume
        print(f"check.py: cannot read the window of {volume}: {error}", file=sys.stderr)
        return 2
    for line in found:
        print(f"  ✗ {line}", file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
