"""Finder layout for the drag-to-Applications installer; no GUI automation."""
from pathlib import Path

root = Path(defines["root"]).resolve()
application = str(Path(defines["app"]).resolve())  # supplied by dmgbuild
files = [application]
symlinks = {"Applications": "/Applications"}
format = "UDZO"
filesystem = "HFS+"
volume_name = "Codex Widget"
icon = str(root / "Resources/AppIcon.icns")
background = str(root / "Resources/DMGBackground.png")
window_rect = ((200, 160), (660, 420))
icon_locations = {"Codex Widget.app": (180, 220), "Applications": (480, 220)}
icon_size = 112
text_size = 14
label_pos = "bottom"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
include_list_view_settings = False
default_view = "icon-view"
arrange_by = None
# Do not set FinderInfo on the app: it would invalidate strict code-signature checks.
