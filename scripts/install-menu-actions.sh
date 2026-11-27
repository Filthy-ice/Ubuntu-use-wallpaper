#!/bin/bash
# Install the rich right-click menu for BOTH Nemo desktop and Nautilus (Files).
set -euo pipefail
BIN="$HOME/.local/bin"; ACT="$HOME/.local/share/nemo/actions"; NAUT="$HOME/.local/share/nautilus-python/extensions"
mkdir -p "$BIN" "$ACT" "$NAUT"

# ---------- scripts ----------
cat > "$BIN/nemo-copy-path.sh" <<'S1'
#!/bin/bash
printf '%s\n' "$@" | sed '/^$/d' | xclip -selection clipboard
S1
cat > "$BIN/nemo-copy-name.sh" <<'S2'
#!/bin/bash
for f in "$@"; do [ -n "$f" ] && basename -- "$f"; done | xclip -selection clipboard
S2
cat > "$BIN/nemo-copy-uri.sh" <<'S3'
#!/bin/bash
for f in "$@"; do [ -n "$f" ] && printf 'file://%s\n' "$(realpath -- "$f")"; done | xclip -selection clipboard
S3
cat > "$BIN/nemo-open-terminal.sh" <<'S4'
#!/bin/bash
dir="${1:-$HOME/桌面}"
[ -d "$dir" ] || dir="$(dirname -- "$dir")"
exec ptyxis --new-window -d "$dir"
S4
cat > "$BIN/nemo-open-code.sh" <<'S5'
#!/bin/bash
[ "$#" -gt 0 ] || exec code -n
exec code -n "$@"
S5
cat > "$BIN/nemo-sha256.sh" <<'S6'
#!/bin/bash
out=""
for f in "$@"; do
  [ -f "$f" ] || continue
  out+="$(sha256sum -- "$f")"$'\n'
done
[ -n "$out" ] || { notify-send "SHA-256" "没有可计算的文件（已跳过目录）"; exit 0; }
printf '%s' "$out" | xclip -selection clipboard
zenity --info --title="SHA-256（已复制）" --width=700 --text="$out" 2>/dev/null || true
S6
cat > "$BIN/nemo-zip.sh" <<'S7'
#!/bin/bash
[ "$#" -gt 0 ] || exit 0
base="$(basename -- "$1")"
[ "$#" -gt 1 ] && base="归档_$(date +%H%M%S)"
target="$base.zip"; n=1
while [ -e "$target" ]; do target="$base ($n).zip"; n=$((n+1)); done
zip -rq -- "$target" "$@" && notify-send "ZIP" "已创建：$(realpath -- "$target")"
S7
cat > "$BIN/nemo-trash-permanent.sh" <<'S8'
#!/bin/bash
[ "$#" -gt 0 ] || exit 0
list="$(printf '  %s\n' "$@")"
zenity --question --title="彻底删除" --width=500 \
  --text="以下内容将被永久删除（不进回收站）：\n\n$list" || exit 0
rm -rf -- "$@"
S8
cat > "$BIN/nemo-remove-links.sh" <<'S9'
#!/bin/bash
for f in "$@"; do
  [ -n "$f" ] || continue
  if [ -L "$f" ]; then gio trash "$f" 2>/dev/null || rm -- "$f"; fi
done
S9
cat > "$BIN/nemo-new-text.sh" <<'S10'
#!/bin/bash
dir="${1:-$HOME/桌面}"
[ -d "$dir" ] || dir="$HOME/桌面"
name="新建文本文档.txt"; n=1
while [ -e "$dir/$name" ]; do name="新建文本文档 ($n).txt"; n=$((n+1)); done
touch -- "$dir/$name"
S10
chmod +x "$BIN"/nemo-*.sh

# ---------- nemo actions ----------
mk() { cat > "$ACT/$1.nemo_action"; }

mk copy-path <<'A1'
[Nemo Action]
Active=true
Name=复制路径
Comment=复制所选文件的绝对路径
Exec=/home/USER/.local/bin/nemo-copy-path.sh %F
Icon-Name=edit-copy-symbolic
Selection=any
Extensions=any;
EscapeSpaces=true
A1
sed -i "s|/home/USER|$HOME|g" "$ACT/copy-path.nemo_action"

mk copy-name <<'A2'
[Nemo Action]
Active=true
Name=复制文件名
Exec=/home/USER/.local/bin/nemo-copy-name.sh %F
Icon-Name=edit-copy-symbolic
Selection=any
Extensions=any;
EscapeSpaces=true
A2
sed -i "s|/home/USER|$HOME|g" "$ACT/copy-name.nemo_action"

mk copy-uri <<'A3'
[Nemo Action]
Active=true
Name=复制文件 URI
Exec=/home/USER/.local/bin/nemo-copy-uri.sh %F
Icon-Name=edit-copy-symbolic
Selection=any
Extensions=any;
EscapeSpaces=true
A3
sed -i "s|/home/USER|$HOME|g" "$ACT/copy-uri.nemo_action"

mk copy-current-path <<'A4'
[Nemo Action]
Active=true
Name=复制桌面路径
Exec=/home/USER/.local/bin/nemo-copy-path.sh %P
Icon-Name=folder-symbolic
Selection=none
Extensions=any;
Conditions=desktop;
A4
sed -i "s|/home/USER|$HOME|g" "$ACT/copy-current-path.nemo_action"

mk terminal-here <<'A5'
[Nemo Action]
Active=true
Name=在终端中打开
Exec=/home/USER/.local/bin/nemo-open-terminal.sh %P
Icon-Name=utilities-terminal-symbolic
Selection=none
Extensions=any;
Conditions=desktop;
EscapeSpaces=true
A5
sed -i "s|/home/USER|$HOME|g" "$ACT/terminal-here.nemo_action"

mk terminal-folder <<'A6'
[Nemo Action]
Active=true
Name=在终端中打开
Exec=/home/USER/.local/bin/nemo-open-terminal.sh %F
Icon-Name=utilities-terminal-symbolic
Selection=s
Mimetypes=inode/directory;
EscapeSpaces=true
A6
sed -i "s|/home/USER|$HOME|g" "$ACT/terminal-folder.nemo_action"

mk code-open <<'A7'
[Nemo Action]
Active=true
Name=用 VS Code 打开
Exec=/home/USER/.local/bin/nemo-open-code.sh %F
Icon-Name=text-editor-symbolic
Selection=any
Extensions=any;
EscapeSpaces=true
A7
sed -i "s|/home/USER|$HOME|g" "$ACT/code-open.nemo_action"

mk sha256 <<'A8'
[Nemo Action]
Active=true
Name=计算 SHA-256
Exec=/home/USER/.local/bin/nemo-sha256.sh %F
Icon-Name=security-high-symbolic
Selection=any
Extensions=any;
EscapeSpaces=true
A8
sed -i "s|/home/USER|$HOME|g" "$ACT/sha256.nemo_action"

mk zip-here <<'A9'
[Nemo Action]
Active=true
Name=压缩为 ZIP
Exec=/home/USER/.local/bin/nemo-zip.sh %F
Icon-Name=package-x-generic-symbolic
Selection=any
Extensions=any;
EscapeSpaces=true
A9
sed -i "s|/home/USER|$HOME|g" "$ACT/zip-here.nemo_action"

mk remove-symlink <<'A10'
[Nemo Action]
Active=true
Name=删除软链接（只删链接）
Comment=把选中的软链接移到回收站，不影响目标
Exec=/home/USER/.local/bin/nemo-remove-links.sh %F
Icon-Name=edit-delete-symbolic
Selection=any
Mimetypes=inode/symlink;
EscapeSpaces=true
A10
sed -i "s|/home/USER|$HOME|g" "$ACT/remove-symlink.nemo_action"

mk permanent-delete <<'A11'
[Nemo Action]
Active=true
Name=彻底删除（不进回收站）…
Exec=/home/USER/.local/bin/nemo-trash-permanent.sh %F
Icon-Name=edit-delete-symbolic
Selection=any
Extensions=any;
EscapeSpaces=true
A11
sed -i "s|/home/USER|$HOME|g" "$ACT/permanent-delete.nemo_action"

mk new-text-file <<'A12'
[Nemo Action]
Active=true
Name=新建文本文件
Exec=/home/USER/.local/bin/nemo-new-text.sh %P
Icon-Name=document-new-symbolic
Selection=none
Extensions=any;
Conditions=desktop;
A12
sed -i "s|/home/USER|$HOME|g" "$ACT/new-text-file.nemo_action"

# ---------- nautilus extension ----------
cat > "$NAUT/winwall-menu.py" <<'PYEOF'
# -*- coding: utf-8 -*-
import gi, subprocess, shutil, os
gi.require_version('Gtk', '4.0')
gi.require_version('Gdk', '4.0')
gi.require_version('Nautilus', '4.1')
from gi.repository import Nautilus, GObject, Gio, Gdk


class WinwallMenu(GObject.Object, Nautilus.MenuProvider):
    def get_file_items(self, *args):
        files = args[-1]
        if not files:
            return []
        items = []

        def add(name, label, tip, cb):
            item = Nautilus.MenuItem(name=name, label=label, tip=tip)
            item.connect('activate', cb)
            items.append(item)

        paths = [f.get_location().get_path() for f in files]
        add('Winwall::CopyPath', '复制路径', '复制绝对路径', lambda *_: self.clip(paths))
        add('Winwall::CopyName', '复制文件名', '', lambda *_: self.clip([os.path.basename(p) for p in paths]))
        add('Winwall::CopyUri', '复制文件 URI', '', lambda *_: self.clip([Gio.File.new_for_path(p).get_uri() for p in paths]))
        add('Winwall::Terminal', '在终端中打开', '', lambda *_: self.run_terminal(paths[0]))
        add('Winwall::Code', '用 VS Code 打开', '', lambda *_: self.run(['code', '-n'] + paths))
        add('Winwall::Sha256', '计算 SHA-256', '', lambda *_: self.run(['/home/USER/.local/bin/nemo-sha256.sh'] + paths))
        add('Winwall::Zip', '压缩为 ZIP…', '在目标目录创建 zip', lambda *_: self.run(['/home/USER/.local/bin/nemo-zip.sh'] + paths))

        links = [f for f in files if self.is_link(f)]
        if links:
            link_paths = [f.get_location().get_path() for f in links]
            def _delete_links(*_):
                for p in link_paths:
                    g = Gio.File.new_for_path(p)
                    try:
                        g.trash(None)
                    except Exception:
                        try:
                            g.delete(None)
                        except Exception:
                            pass
            add('Winwall::DeleteLink', '删除软链接（只删链接）', '移到回收站，不影响目标', _delete_links)
        return items

    @staticmethod
    def is_link(f):
        try:
            info = Gio.File.new_for_uri(f.get_uri()).query_info(
                'standard::is-symlink', Gio.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, None)
            return info.get_is_symlink()
        except Exception:
            return False

    @staticmethod
    def clip(lines):
        Gdk.Display.get_default().get_clipboard().set('\n'.join(lines))

    @staticmethod
    def run(argv):
        subprocess.Popen(argv, start_new_session=True)

    def run_terminal(self, path):
        d = path if os.path.isdir(path) else os.path.dirname(path)
        if shutil.which('ptyxis'):
            self.run(['ptyxis', '--new-window', '-d', d])
        else:
            self.run(['x-terminal-emulator'])


PYEOF
sed -i "s|/home/USER|$HOME|g" "$NAUT/winwall-menu.py"
rm -rf "$NAUT/__pycache__" 2>/dev/null || true

echo "installed: $(ls "$ACT" | wc -l) nemo actions, nautilus extension updated"
