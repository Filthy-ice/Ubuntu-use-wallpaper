# Agent install guide

Purpose: on a fresh Ubuntu/GNOME Wayland machine, install this repo so that `wmctrl`-free, icon-friendly video/scene wallpapers work, then let the user pick wallpapers from their own Steam library.

## Hard constraints

- Do **not** commit or copy into the repo: `engine/`, `source-build/`, wallpapers, Steam assets. `.gitignore` already excludes them.
- Do **not** run `sudo` commands with askpass/GUI. If packages are missing, print the exact `sudo apt-get install -y ...` line and stop; the human runs it.
- Do **not** delete files under `engine/` without first reading `docs/RUNTIME-KEEP.md` (procedure: keep-list → move to backup → smoke test → delete).
- Extensions are cached per GNOME session: after changing `extension/*.js`, the human must log out and back in. Config-only changes use `./winwallctl.sh reload`.
- The user's wallpaper library stays at `~/.local/share/Steam/steamapps/workshop/content/431960/<id>/` (read-only reference; never move/copy it into the repo).

## Steps

1. Preconditions
   - `echo $XDG_SESSION_TYPE` is `wayland`; `gnome-shell --version` is 50 or 51.
   - `~/.local/share/Steam/steamapps/common/wallpaper_engine/assets` exists.
   - `mpv` installed.
2. Run `./scripts/setup.sh` from repo root.
   - Exit 3: missing apt packages printed; hand the command to the human, then re-run.
   - Exit 4: engine dependency check failed; run `LD_LIBRARY_PATH=engine ldd engine/linux-wallpaperengine | grep 'not found'` and compare with `docs/RUNTIME-KEEP.md`.
   - Expected duration: 5–20 min (CEF download 1.8 GB + build). Warn the human first.
3. First install only: ask the human to log out and back in, then `gnome-extensions enable winwall@zhanghaobing.local`.
4. Verification (must pass before reporting success):
   ```bash
   ./winwallctl.sh status     # extension ACTIVE, renderer process running, no "player exited"
   ./winwallctl.sh verify     # engine deps OK + 1280x720 scene screenshot produced
   ```
   A healthy log line looks like: `winwall: module vN loaded`, `capture 2560x1440`, `monitor 0 window ... managed`.
5. Wallpaper selection
   - GUI: `./winwallctl.sh pick` (or the "Winwall 壁纸" desktop entry).
   - CLI: `./winwallctl.sh use-scene <dir>` / `use-video <file>`.
6. Report: what was installed, engine size (`du -sh engine`), and the remaining limitations from README.

## Known pitfalls (full list in docs/VIDEO-WALLPAPER-PITFALLS.md)

- New extensions require logout/login; `gnome-extensions enable` on a fresh install says "extension does not exist" until then.
- `libkissfft-float.so.131` lives in `engine/`; deleting it breaks startup.
- `libcef.so` is linked at startup: stripping with `--strip-unneeded` breaks web wallpapers only (SIGTRAP `close symbol missing`); scenes/videos are fine.
- Scene speed follows `fps` for frame-based scenes; scene properties usually expose only `schemecolor`.
- Capture resolution must equal the monitor's native size or the wallpaper looks blurry (`capture WxH` log).
