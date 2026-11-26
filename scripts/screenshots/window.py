"""The Finder window of the screenshot: dmgbuild settings for a throwaway volume.

shoot.sh puts the demo disks on a disk image built from this, mounts it and
photographs its window. On macOS 27 the Finder applies neither AppleScript's view
options nor a .DS_Store written into a local folder it has seen before, while a
fresh volume's .DS_Store, written by dmgbuild, opens as written (the DMGs prove it
every release). No toolbar, sidebar or path bar: they would show this Mac's folders.

    dmgbuild -s window.py -D disks=<folder> "Amiga Disks" <out.dmg>
"""
import os.path

_folder = defines["disks"]  # noqa: F821 (dmgbuild provides `defines`)
_names = ["Work Disk", "Music Disk", "Pixel Art", "Utilities", "Archive HD", "Starfield Demo"]

format = "UDRW"
files = [os.path.join(_folder, n + ".adf") for n in _names]
default_view = "icon-view"
window_rect = ((200, 140), (620, 470))
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
arrange_by = None
icon_size = 128
text_size = 13
show_icon_preview = True
icon_locations = {n + ".adf": (110 + 200 * (i % 3), 110 + 200 * (i // 3)) for i, n in enumerate(_names)}
