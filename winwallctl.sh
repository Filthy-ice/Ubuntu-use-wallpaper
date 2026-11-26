#!/bin/bash
# Winwall kit control script. Local personal use.
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UUID="winwall@zhanghaobing.local"
DST="$HOME/.local/share/gnome-shell/extensions/$UUID"
CFG="$HOME/.config/winwall/config.json"
ENGINE="$KIT/engine"
LWE="$ENGINE/run-lwe.sh"
ASSETS="${WINWALL_ASSETS:-$HOME/.local/share/Steam/steamapps/common/wallpaper_engine/assets}"

write_cfg() {
  # $1=renderer $2=path
  python3 - "$CFG" "$1" "$2" "$ASSETS" "$LWE" <<'PY'
import json, os, pathlib, sys
cfg, renderer, path, assets, lwe = sys.argv[1:6]
p = pathlib.Path(cfg)
p.parent.mkdir(parents=True, exist_ok=True)
d = json.loads(p.read_text()) if p.exists() else {}
d.setdefault("video", "")
d.setdefault("panscan", 1.0)
d.setdefault("fps", 60)
d["renderer"] = renderer
d["assets"] = assets
d["lwe"] = lwe
d["scene" if renderer == "scene" else "video"] = os.path.abspath(path)
p.write_text(json.dumps(d, ensure_ascii=False, indent=2))
print(f"{renderer} -> {d['scene' if renderer == 'scene' else 'video']}")
PY
}

reload() {
  gnome-extensions disable "$UUID" >/dev/null 2>&1 || true
  sleep 1
  gnome-extensions enable "$UUID"
  echo "extension reloaded"
}

case "${1:-help}" in
  install)
    FIRST=0
    [ -d "$DST" ] || FIRST=1
    mkdir -p "$DST"
    cp "$KIT"/extension/{extension.js,background.js,compositing.js,metadata.json,COPYING} "$DST"/
    "$KIT/scripts/install-picker.sh" || true
    echo "installed -> $DST"
    if [ "$FIRST" = 1 ]; then
      echo "first install: log out and back in once so GNOME discovers it."
    else
      echo "JS changed? log out and back in. Config-only change? ./winwallctl.sh reload"
    fi
    ;;
  enable) gnome-extensions enable "$UUID" ;;
  disable) gnome-extensions disable "$UUID" ;;
  reload) reload ;;
  use-scene)
    [ -d "${2:-}" ] || { echo "usage: $0 use-scene <scene-dir>"; exit 1; }
    write_cfg scene "$2"
    reload
    ;;
  use-video)
    [ -f "${2:-}" ] || { echo "usage: $0 use-video <video-file>"; exit 1; }
    write_cfg video "$2"
    reload
    ;;
  verify)
    echo "== engine deps =="
    if LD_LIBRARY_PATH="$ENGINE" ldd "$ENGINE/linux-wallpaperengine" 2>/dev/null | grep -q 'not found'; then
      LD_LIBRARY_PATH="$ENGINE" ldd "$ENGINE/linux-wallpaperengine" | grep 'not found'
      echo "engine deps: FAIL"
      exit 1
    fi
    echo "engine deps: OK"
    RENDERER=$(python3 -c "
import json,pathlib
p=pathlib.Path('$CFG')
print(json.loads(p.read_text()).get('renderer','video') if p.exists() else 'video')")
    if [ "$RENDERER" = scene ]; then
      SCENE=$(python3 -c "import json,pathlib;print(json.loads(pathlib.Path('$CFG').read_text())['scene'])")
      OUT=/tmp/winwall-verify.png
      rm -f "$OUT"
      mkdir -p /tmp/winwall-verify && cd /tmp/winwall-verify
      timeout -k 3 45 "$LWE" --silent --fps 30 --window 0x0x1280x720 \
        --screenshot "$OUT" --screenshot-delay 60 --assets-dir "$ASSETS" "$SCENE" >/dev/null 2>&1 || true
      if [ -s "$OUT" ]; then
        echo "scene smoke: OK ($OUT, $(stat -c%s "$OUT") bytes)"
      else
        echo "scene smoke: FAIL (no screenshot)"
        exit 1
      fi
    else
      VIDEO=$(python3 -c "import json,pathlib;print(json.loads(pathlib.Path('$CFG').read_text())['video'])")
      if timeout 20 mpv --no-config --really-quiet --no-audio --vo=null --frames=1 -- "$VIDEO" >/dev/null 2>&1; then
        echo "video smoke: OK"
      else
        echo "video smoke: FAIL"
        exit 1
      fi
    fi
    ;;
  pick)
    exec gjs -m "$KIT/picker/picker.js"
    ;;
  status)
    echo "== extension =="
    gnome-extensions info "$UUID" 2>&1 | sed -n '1,8p'
    echo "== renderer process =="
    ps -eo pid,args | grep '[l]inux-wallpaperengine\|[m]pv --no-config.*winwall' | head -2 || true
    echo "== recent log =="
    journalctl --user -b --since '5 min ago' --no-pager 2>/dev/null | grep -aE 'winwall: (module|enabled|monitor|capture|player exited)' | tail -5 || true
    ;;
  help|*)
    sed -n '2,6p' "$0" >/dev/null
    cat <<'EOF'
Winwall kit commands:
  install                 sync extension/ to GNOME extensions dir (JS changes: log out after)
  reload                  disable+enable the extension (config changes take effect)
  enable|disable          toggle the extension
  use-scene <dir>         set a Wallpaper Engine scene dir (e.g. .../431960/<id>)
  use-video <file>        set a video file (mp4/webm)
  verify                  dependency check + 1280x720 smoke test
  pick                    open the GTK wallpaper picker
  status                  extension + renderer + recent logs
EOF
    ;;
esac
