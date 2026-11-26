#!/bin/bash
# Build linux-wallpaperengine and install the GNOME extension + picker.
# Run from the repository root (or anywhere; paths are resolved from this file).
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LWE_COMMIT="a0ddce586e9ff12e9d31ca6b103f6036cc1b68fe"
ASSETS="${WINWALL_ASSETS:-$HOME/.local/share/Steam/steamapps/common/wallpaper_engine/assets}"
ENGINE="$KIT/engine"
SOURCE="$KIT/source-build"
UUID="winwall@zhanghaobing.local"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$UUID"
CFG="$HOME/.config/winwall/config.json"

DEPS=(
  build-essential cmake git libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev
  libgl-dev libglew-dev freeglut3-dev libsdl2-dev liblz4-dev libxxf86vm-dev
  libglm-dev libglfw3-dev libavcodec-dev libavformat-dev libavutil-dev
  libswscale-dev libmpv-dev mpv libpulse-dev libpulse0 libfftw3-dev
  libfreetype-dev libpng-dev
)

SKIP_BUILD=0; KEEP_WEB=0; NO_INSTALL=0; FORCE=0
for arg in "$@"; do
  case "$arg" in
    --skip-build) SKIP_BUILD=1 ;;
    --keep-web) KEEP_WEB=1 ;;
    --no-install) NO_INSTALL=1 ;;
    --force) FORCE=1 ;;
    -h|--help)
      cat <<'EOF'
setup.sh [--skip-build] [--keep-web] [--no-install] [--force]
  --skip-build  only install extension/picker (engine must already exist)
  --keep-web    keep CEF symbols (web wallpapers possible); default strips for smaller engine
  --no-install  build engine only
  --force       rebuild even if engine/ already exists
EOF
      exit 0 ;;
    *) echo "unknown option: $arg"; exit 2 ;;
  esac
done

log() { printf '\n== %s\n' "$*"; }

log "checking session"
[ "${XDG_SESSION_TYPE:-}" = wayland ] || echo "warning: XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unset}; Wayland is required"
[ -e "$ASSETS" ] || echo "warning: Wallpaper Engine assets not found at $ASSETS (scene wallpapers need it)"

if [ "$SKIP_BUILD" = 0 ]; then
  log "checking build dependencies"
  missing=()
  for pkg in "${DEPS[@]}"; do
    dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "missing packages: ${missing[*]}"
    echo "run this first (sudo password is yours):"
    echo "  sudo apt-get install -y ${missing[*]}"
    exit 3
  fi

  if [ -x "$ENGINE/linux-wallpaperengine" ] && [ "$FORCE" = 0 ]; then
    log "engine already present at $ENGINE (use --force to rebuild)"
  else
    log "fetching linux-wallpaperengine ($LWE_COMMIT)"
    if [ ! -d "$SOURCE/.git" ]; then
      git clone https://github.com/Almamu/linux-wallpaperengine.git "$SOURCE"
    fi
    git -C "$SOURCE" fetch --depth 1 origin "$LWE_COMMIT"
    git -C "$SOURCE" checkout -f FETCH_HEAD
    git -C "$SOURCE" submodule update --init --recursive --force

    log "building (CEF download ~1.8 GB, build 5-15 min)"
    cmake -B "$SOURCE/build" -S "$SOURCE" -DCMAKE_BUILD_TYPE=Release
    cmake --build "$SOURCE/build" -j"$(nproc)"

    log "installing engine files"
    mkdir -p "$ENGINE"
    cp -a "$SOURCE/build/output/." "$ENGINE/"

    log "trimming engine"
    ( cd "$ENGINE"
      if [ "$KEEP_WEB" = 1 ]; then
        objcopy --strip-debug libcef.so libcef.tmp.so && mv libcef.tmp.so libcef.so || true
      else
        objcopy --strip-unneeded libcef.so libcef.tmp.so && mv libcef.tmp.so libcef.so || true
      fi
      find locales -type f ! -name en-US.pak ! -name zh-CN.pak -delete
      rm -f api-test testcpp-float psdpng-float bm_* fastconv* fastfilt-float \
            run-test262 qjs qjsc function_source 2>/dev/null || true
      cat > run-lwe.sh <<'SH'
#!/bin/sh
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LD_LIBRARY_PATH="$HERE" exec "$HERE/linux-wallpaperengine" "$@"
SH
      chmod +x run-lwe.sh
    )
  fi
fi

if [ "$NO_INSTALL" = 0 ]; then
  log "installing GNOME extension"
  mkdir -p "$EXT_DIR"
  cp "$KIT"/extension/{extension.js,background.js,compositing.js,metadata.json,COPYING} "$EXT_DIR"/

  log "installing picker entry"
  "$KIT/scripts/install-picker.sh"

  log "writing default config (only if missing)"
  mkdir -p "$(dirname "$CFG")"
  [ -f "$CFG" ] || WINWALL_ASSETS="$ASSETS" python3 - "$CFG" "$KIT" <<'PY'
import json, pathlib, sys, os
cfg, kit = sys.argv[1], sys.argv[2]
pathlib.Path(cfg).write_text(json.dumps({
    "renderer": "video",
    "video": "",
    "panscan": 1.0,
    "scene": "",
    "assets": os.environ["WINWALL_ASSETS"],
    "fps": 60,
    "lwe": os.path.join(kit, "engine", "run-lwe.sh"),
}, ensure_ascii=False, indent=2) + "\n")
print("config written:", cfg)
PY

  if [ -x "$ENGINE/linux-wallpaperengine" ]; then
    log "engine dependency check"
    if LD_LIBRARY_PATH="$ENGINE" ldd "$ENGINE/linux-wallpaperengine" | grep -q 'not found'; then
      LD_LIBRARY_PATH="$ENGINE" ldd "$ENGINE/linux-wallpaperengine" | grep 'not found' || true
      echo "engine deps: FAIL"
      exit 4
    fi
    echo "engine deps: OK"
  fi

  cat <<EOF

Next steps:
  1. If this is the first install: log out and back in once (GNOME discovers new extensions at login).
  2. Enable:      gnome-extensions enable $UUID
  3. Pick a wallpaper:  ./winwallctl.sh pick
  4. Verify:      ./winwallctl.sh verify && ./winwallctl.sh status
EOF
fi
