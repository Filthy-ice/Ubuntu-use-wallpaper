// Winwall — plays a video as the GNOME desktop wallpaper.
// Background capture/painting derived from Wallshader (GPL-3.0, stonega).
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import { DesktopWallpapers, setCaptureResolution } from './background.js';
import { CompositingHold } from './compositing.js';

const LOG = 'winwall';
console.log(`${LOG}: module v8 loaded`);
const CONFIG_PATH = GLib.build_filenamev([
  GLib.get_user_config_dir(),
  'winwall',
  'config.json',
]);
const HOME = GLib.get_home_dir();
const DEFAULT_VIDEO = '';
const DEFAULT_ASSETS = GLib.build_filenamev([
  HOME, '.local/share/Steam/steamapps/common/wallpaper_engine/assets',
]);
const DEFAULT_LWE = GLib.build_filenamev([
  HOME, 'tools/winwall/engine/run-lwe.sh',
]);

function readConfig() {
  const fallback = {
    renderer: 'video',
    video: DEFAULT_VIDEO,
    panscan: 1.0,
    scene: '',
    assets: DEFAULT_ASSETS,
    fps: 30,
    lwe: DEFAULT_LWE,
  };
  try {
    const file = Gio.File.new_for_path(CONFIG_PATH);
    if (!file.query_exists(null)) return fallback;
    const [, bytes] = file.load_contents(null);
    const json = JSON.parse(new TextDecoder().decode(bytes));
    const str = (value, fallbackValue) =>
      typeof value === 'string' && value ? value : fallbackValue;
    return {
      renderer: json.renderer === 'scene' ? 'scene' : 'video',
      video: str(json.video, fallback.video),
      panscan:
        typeof json.panscan === 'number' ? json.panscan : fallback.panscan,
      scene: str(json.scene, fallback.scene),
      assets: str(json.assets, fallback.assets),
      fps: typeof json.fps === 'number' ? json.fps : fallback.fps,
      lwe: str(json.lwe, fallback.lwe),
    };
  } catch (error) {
    console.warn(`${LOG}: config ${CONFIG_PATH}: ${error.message}`);
    return fallback;
  }
}

export default class WinwallExtension extends Extension {
  enable() {
    this._enabled = true;
    this._clients = new Map();
    this._processes = new Map();
    this._windows = new Map();
    this._signals = [];
    this._stackQueued = 0;
    this._stackLogs = 0;
    this._stackFixes = 0;
    this._config = readConfig();
    let captureWidth = 0;
    let captureHeight = 0;
    for (const monitor of Main.layoutManager.monitors) {
      captureWidth = Math.max(captureWidth, monitor.width);
      captureHeight = Math.max(captureHeight, monitor.height);
    }
    if (captureWidth && captureHeight) {
      setCaptureResolution({ width: captureWidth, height: captureHeight });
      console.log(`${LOG}: capture ${captureWidth}x${captureHeight}`);
    }
    this._compositing = new CompositingHold(global.compositor);
    this._desktop = new DesktopWallpapers((index) =>
      this._sourceForMonitor(index),
    );
    this._watch(
      global.display,
      global.display.connect('window-created', (_display, window) =>
        this._manage(window),
      ),
    );
    this._watch(
      global.window_manager,
      global.window_manager.connect('map', (_manager, actor) =>
        this._manage(actor.meta_window),
      ),
    );
    this._watch(
      Main.layoutManager,
      Main.layoutManager.connect('monitors-changed', () => this._restart()),
    );
    this._watch(
      global.display,
      global.display.connect('restacked', () => this._queueStackFix()),
    );
    console.log(
      `${LOG}: enabled, renderer=${this._config.renderer} ` +
        `source=${this._config.renderer === 'scene' ? this._config.scene : this._config.video}`,
    );
    this._start();
  }

  _watch(object, id) {
    this._signals.push([object, id]);
  }

  _sourceForMonitor(index) {
    for (const [window, managed] of this._windows) {
      if (managed.index !== index) continue;
      const actor = window.get_compositor_private();
      if (actor) return actor;
    }
    return null;
  }

  _start() {
    for (const monitor of Main.layoutManager.monitors) this._spawn(monitor);
  }

  _restart() {
    this._stop();
    if (this._enabled) this._start();
  }

  _rendererArgs(monitor) {
    if (this._config.renderer === 'scene') {
      if (!this._config.scene) {
        console.warn(`${LOG}: renderer=scene but scene path is empty`);
        return null;
      }
      return [
        this._config.lwe,
        '--silent',
        '--no-fullscreen-pause',
        '--disable-mouse',
        '--fps',
        String(this._config.fps),
        '--window',
        `0x0x${monitor.width}x${monitor.height}`,
        '--assets-dir',
        this._config.assets,
        this._config.scene,
      ];
    }
    if (!this._config.video) {
      console.warn(`${LOG}: renderer=video but video path is empty`);
      return null;
    }
    return [
      'mpv',
      '--no-config',
      '--really-quiet',
      '--no-audio',
      '--loop-file=inf',
      '--no-osc',
      '--no-input-default-bindings',
      '--no-border',
      '--hwdec=auto',
      `--panscan=${this._config.panscan}`,
      `--title=Winwall Desktop ${monitor.index}`,
      '--',
      this._config.video,
    ];
  }

  _spawn(monitor) {
    const args = this._rendererArgs(monitor);
    if (!args) return;
    const launcher = new Gio.SubprocessLauncher({
      flags: Gio.SubprocessFlags.NONE,
    });
    launcher.setenv('GDK_BACKEND', 'wayland', true);
    launcher.unsetenv('DISPLAY');
    launcher.unsetenv('XDG_ACTIVATION_TOKEN');
    launcher.unsetenv('DESKTOP_STARTUP_ID');
    try {
      const client = Meta.WaylandClient.new_subprocess(
        global.context,
        launcher,
        args,
      );
      const process = client.get_subprocess();
      this._clients.set(client, monitor.index);
      this._processes.set(client, process);
      process.wait_async(null, (child, result) => {
        try {
          child.wait_finish(result);
        } catch (error) {
          console.warn(`${LOG}: ${error.message}`);
        }
        if (this._processes.get(client) !== process) return;
        console.warn(`${LOG}: monitor ${monitor.index} player exited`);
        this._processes.delete(client);
        this._clients.delete(client);
      });
    } catch (error) {
      console.warn(`${LOG}: monitor ${monitor.index}: ${error.message}`);
    } finally {
      launcher.close();
    }
  }

  _clientIndex(window) {
    for (const [client, index] of this._clients) {
      if (client.owns_window(window)) return index;
    }
    const pid = window.get_pid();
    if (pid > 0) {
      for (const [client, index] of this._clients) {
        const process = this._processes.get(client);
        if (process && Number(process.get_identifier()) === pid) return index;
      }
    }
    const match = /^Winwall Desktop (\d+)$/.exec(window.get_title() ?? '');
    if (match && Main.layoutManager.monitors[Number(match[1])])
      return Number(match[1]);
    return null;
  }

  _manage(window) {
    if (this._windows.has(window)) return;
    const index = this._clientIndex(window);
    if (index === null) return;
    const monitor = Main.layoutManager.monitors[index];
    if (!monitor) return;
    try {
      window.set_type(Meta.WindowType.DESKTOP);
    } catch (error) {
      console.warn(`${LOG}: set_type failed: ${error.message}`);
      this._killIndex(index);
      return;
    }
    window.unmaximize();
    window.hide_from_window_list();
    window.stick();
    window.move_to_monitor(index);
    const managed = { index, placement: 0, signals: [] };
    const place = () => {
      if (window.is_fullscreen()) window.unmake_fullscreen();
      const rect = window.get_frame_rect();
      if (
        rect.x === monitor.x &&
        rect.y === monitor.y &&
        rect.width === monitor.width &&
        rect.height === monitor.height
      )
        return;
      window.move_resize_frame(
        false,
        monitor.x,
        monitor.y,
        monitor.width,
        monitor.height,
      );
    };
    const queuePlacement = () => {
      if (managed.placement) return;
      managed.placement = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 0, () => {
        managed.placement = 0;
        place();
        return GLib.SOURCE_REMOVE;
      });
    };
    managed.signals = [
      window.connect('shown', () => {
        queuePlacement();
        window.lower();
        this._desktop.sync();
        this._queueStackFix();
      }),
      window.connect('size-changed', queuePlacement),
      window.connect('position-changed', queuePlacement),
      window.connect('notify::fullscreen', queuePlacement),
      window.connect('unmanaged', () => this._release(window)),
    ];
    this._windows.set(window, managed);
    place();
    this._desktop.sync();
    this._compositing.setRequired(true);
    this._queueStackFix();
    console.log(
      `${LOG}: monitor ${index} window ${window.get_id()} managed`,
    );
  }

  _queueStackFix() {
    if (this._stackQueued || !this._enabled) return;
    this._stackQueued = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 100, () => {
      this._stackQueued = 0;
      this._syncStacking();
      return GLib.SOURCE_REMOVE;
    });
  }

  _syncStacking() {
    if (!this._enabled || !this._windows.size) return;
    const windows = global.display
      .list_all_windows()
      .filter(
        (window) =>
          this._windows.has(window) ||
          window.get_window_type() === Meta.WindowType.DESKTOP,
      );
    const order = global.display.sort_windows_by_stacking(windows);
    const label = (window) =>
      `${(window.get_title() ?? '?').slice(0, 22)}` +
      (this._windows.has(window) ? '<OURS>' : '');
    if ((this._stackLogs ?? 0) < 10) {
      this._stackLogs = (this._stackLogs ?? 0) + 1;
      console.log(`${LOG}: stack#${this._stackLogs} ${order.map(label).join(' | ')}`);
    }
    const others = order.filter((window) => !this._windows.has(window));
    for (const window of this._windows.keys()) {
      const index = order.indexOf(window);
      const below = others.filter((other) => order.indexOf(other) < index);
      if (!below.length) continue;
      if ((this._stackFixes ?? 0) >= 40) continue;
      this._stackFixes = (this._stackFixes ?? 0) + 1;
      console.log(
        `${LOG}: lower below ${below.map(label).join(',')}`,
      );
      window.set_type(Meta.WindowType.DESKTOP);
      window.lower();
      this._queueStackFix();
      return;
    }
  }

  _killIndex(index) {
    for (const [client, clientIndex] of [...this._clients]) {
      if (clientIndex !== index) continue;
      const process = this._processes.get(client);
      if (process) process.send_signal(15);
      this._processes.delete(client);
      this._clients.delete(client);
    }
  }

  _release(window) {
    const managed = this._windows.get(window);
    if (!managed) return;
    this._windows.delete(window);
    if (managed.placement) GLib.source_remove(managed.placement);
    for (const id of managed.signals) window.disconnect(id);
    this._desktop.sync();
    if (!this._windows.size) this._compositing.setRequired(false);
  }

  _stop() {
    for (const window of [...this._windows.keys()]) this._release(window);
    for (const process of this._processes.values()) process.send_signal(15);
    this._processes.clear();
    this._clients.clear();
    this._desktop.clear();
    this._compositing.setRequired(false);
  }

  disable() {
    this._enabled = false;
    if (this._stackQueued) GLib.source_remove(this._stackQueued);
    this._stackQueued = 0;
    this._stop();
    this._desktop.destroy();
    for (const [object, id] of this._signals) object.disconnect(id);
    this._signals = [];
    console.log(`${LOG}: disabled`);
  }
}
