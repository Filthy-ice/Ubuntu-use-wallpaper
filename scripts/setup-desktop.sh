#!/bin/bash
# Desktop icons via Nemo with a transparent background (DING is incompatible:
# it self-lowers on every restack and fights any desktop-layer wallpaper).
set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "disabling DING (its self-lowering conflicts with the wallpaper window)"
gnome-extensions disable ding@rastersoft.com 2>/dev/null || true

echo "installing nemo-desktop autostart (3s delay, transparent background)"
mkdir -p "$HOME/.config/autostart"
cat > "$HOME/.config/autostart/nemo-desktop.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=Nemo Desktop
Comment=Desktop icons provided by Nemo (transparent background)
Exec=/usr/bin/nemo-desktop
Terminal=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=3
DESK

echo "transparent background for Cinnamon/Nemo desktop"
mkdir -p "$KIT/assets"
[ -f "$KIT/assets/transparent.png" ] || python3 - "$KIT/assets/transparent.png" <<'PY'
import sys
from PIL import Image
Image.new('RGBA', (8, 8), (0, 0, 0, 0)).save(sys.argv[1])
PY
gsettings set org.cinnamon.desktop.background picture-uri "file://$KIT/assets/transparent.png" 2>/dev/null || true
gsettings set org.cinnamon.desktop.background picture-options 'stretch' 2>/dev/null || true

echo "installing nemo actions (copy path / remove symlink)"
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/nemo/actions"
cat > "$HOME/.local/bin/nemo-copy-path.sh" <<'SH'
#!/bin/bash
printf '%s\n' "$@" | sed '/^$/d' | xclip -selection clipboard
SH
cat > "$HOME/.local/bin/nemo-remove-links.sh" <<'SH'
#!/bin/bash
for f in "$@"; do
  [ -n "$f" ] || continue
  if [ -L "$f" ]; then gio trash "$f" 2>/dev/null || rm -- "$f"; fi
done
SH
chmod +x "$HOME/.local/bin/nemo-copy-path.sh" "$HOME/.local/bin/nemo-remove-links.sh"
cat > "$HOME/.local/share/nemo/actions/copy-path.nemo_action" <<ACT
[Nemo Action]
Active=true
Name=复制路径
Comment=复制所选文件的绝对路径
Exec=$HOME/.local/bin/nemo-copy-path.sh %F
Icon-Name=edit-copy-symbolic
Selection=m
Extensions=any;
ACT
cat > "$HOME/.local/share/nemo/actions/remove-symlink.nemo_action" <<ACT
[Nemo Action]
Active=true
Name=删除软链接（只删链接）
Comment=把选中的软链接移到回收站，不影响目标
Exec=$HOME/.local/bin/nemo-remove-links.sh %F
Icon-Name=edit-delete-symbolic
Selection=m
Mimetypes=inode/symlink;
ACT

pkill -x nemo-desktop 2>/dev/null || true
sleep 1
setsid nemo-desktop >/dev/null 2>&1 || true
echo "done: DING off, Nemo desktop on (log out/in for a clean start)"
