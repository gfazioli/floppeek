"""The disk image's window, once, for the builder and for the check.

The window, the icon size and both positions are drawn into the background
picture (macos-workspace scripts/dmg-background/README.md): change them
together with it, here and nowhere else.

Read two ways:
- by dmgbuild, as its settings file (`dmgbuild -s layout.py -D app=… -D background=…`),
  which is why the names below are dmgbuild's;
- by `check.py`, which imports the constants to say what a finished image
  must hold.
"""
import os.path

WINDOW_ORIGIN = (200, 120)
WINDOW_SIZE = (600, 400)
ICON_SIZE = 100
TEXT_SIZE = 16
APP_POSITION = (175, 200)
APPLICATIONS_POSITION = (425, 200)

# dmgbuild runs this file with `defines` in scope; an import does not have it.
_defines = globals().get("defines", {})
if _defines:
    app = _defines["app"]
    _app_name = os.path.basename(app)

    format = "UDZO"
    files = [app]
    symlinks = {"Applications": "/Applications"}
    # No `hide_extensions` (plural: dmgbuild ignores a name it does not know,
    # which is how the singular sat here doing nothing). dmgbuild hides an
    # extension by writing a com.apple.FinderInfo attribute on the bundle, and
    # with it `codesign --verify --deep --strict` on the app in the image says
    # "resource fork, Finder information, or similar detritus not allowed"
    # (measured on the notarized 0.62.1 build; Gatekeeper still accepted it).
    # Finder hides `.app` on its own unless the person asked to see every
    # extension, and then it shows it whatever this flag says.
    background = _defines["background"]

    default_view = "icon-view"
    window_rect = (WINDOW_ORIGIN, WINDOW_SIZE)
    show_status_bar = False
    show_tab_view = False
    show_toolbar = False
    show_pathbar = False
    show_sidebar = False

    arrange_by = None
    icon_size = ICON_SIZE
    text_size = TEXT_SIZE
    icon_locations = {
        _app_name: APP_POSITION,
        "Applications": APPLICATIONS_POSITION,
    }
