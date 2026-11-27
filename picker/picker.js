#!/usr/bin/env gjs -m
// Winwall picker — browse Wallpaper Engine library and apply a wallpaper.
import Gtk from 'gi://Gtk?version=4.0';
import Gdk from 'gi://Gdk?version=4.0';
import GdkPixbuf from 'gi://GdkPixbuf?version=2.0';
import Adw from 'gi://Adw?version=1';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import System from 'system';

const HERE = GLib.path_get_dirname(GLib.filename_from_uri(import.meta.url)[0]);
const KIT = GLib.path_get_dirname(HERE);
const LWE = GLib.build_filenamev([KIT, 'engine', 'run-lwe.sh']);
const ASSETS = GLib.build_filenamev([
  GLib.get_home_dir(), '.local/share/Steam/steamapps/common/wallpaper_engine/assets',
]);
const ROOT = GLib.build_filenamev([
  GLib.get_home_dir(), '.local/share/Steam/steamapps/workshop/content/431960',
]);
const CFG = GLib.build_filenamev([GLib.get_home_dir(), '.config/winwall/config.json']);
const UUID = 'winwall@zhanghaobing.local';

function readJson(path) {
  try {
    const [, bytes] = GLib.file_get_contents(path);
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return null;
  }
}

function readConfig() {
  return readJson(CFG) ?? {};
}

function writeConfig(cfg) {
  GLib.mkdir_with_parents(GLib.path_get_dirname(CFG), 0o755);
  GLib.file_set_contents(CFG, JSON.stringify(cfg, null, 2) + '\n');
}

function scanLibrary() {
  const items = [];
  const root = Gio.File.new_for_path(ROOT);
  let enumerator;
  try {
    enumerator = root.enumerate_children(
      'standard::name,standard::type',
      Gio.FileQueryInfoFlags.NONE,
      null,
    );
  } catch {
    return items;
  }
  let info;
  while ((info = enumerator.next_file(null))) {
    if (info.get_file_type() !== Gio.FileType.DIRECTORY) continue;
    const dir = GLib.build_filenamev([ROOT, info.get_name()]);
    const project = readJson(GLib.build_filenamev([dir, 'project.json']));
    if (!project) continue;
    const type = String(project.type ?? '').toLowerCase();
    if (!['video', 'scene', 'web'].includes(type)) continue;
    const preview = project.preview
      ? GLib.build_filenamev([dir, project.preview])
      : '';
    items.push({
      id: info.get_name(),
      dir,
      type,
      title: project.title ?? info.get_name(),
      preview: GLib.file_test(preview, GLib.FileTest.EXISTS) ? preview : '',
      file: project.file ?? '',
    });
  }
  enumerator.close(null);
  items.sort((a, b) => a.title.localeCompare(b.title));
  return items;
}

function typeLabel(type) {
  return type === 'video' ? '视频' : type === 'scene' ? '场景' : type === 'web' ? '网页' : type;
}

function loadTexture(path) {
  try {
    const pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, 320, 180, true);
    return Gdk.Texture.new_for_pixbuf(pixbuf);
  } catch {
    return null;
  }
}

function currentKey() {
  const cfg = readConfig();
  if (cfg.renderer === 'scene') return cfg.scene ?? '';
  return cfg.video ?? '';
}

function applyItem(item, toast, subtitle) {
  if (item.type === 'web') {
    toast('网页壁纸不支持（已弃用 CEF）');
    return;
  }
  const cfg = readConfig();
  cfg.assets ||= ASSETS;
  cfg.lwe ||= LWE;
  cfg.fps ||= 60;
  cfg.panscan ??= 1.0;
  if (item.type === 'scene') {
    cfg.renderer = 'scene';
    cfg.scene = item.dir;
  } else {
    const file = item.file
      ? item.file
      : '';
    const path = file.startsWith('/')
      ? file
      : GLib.build_filenamev([item.dir, file]);
    cfg.renderer = 'video';
    cfg.video = path;
  }
  writeConfig(cfg);
  subtitle.set_subtitle(item.title);
  GLib.spawn_command_line_async(`gnome-extensions disable ${UUID}`);
  GLib.timeout_add(GLib.PRIORITY_DEFAULT, 900, () => {
    GLib.spawn_command_line_async(`gnome-extensions enable ${UUID}`);
    return GLib.SOURCE_REMOVE;
  });
  toast(`已切换到「${item.title}」`);
}

const ARGV_ = typeof ARGV !== 'undefined' ? ARGV : [];

if (ARGV_.includes('--check')) {
  const items = scanLibrary();
  const counts = {};
  for (const item of items) counts[item.type] = (counts[item.type] ?? 0) + 1;
  const cfg = readConfig();
  print(`library: ${ROOT}`);
  print(`items: ${items.length} ${JSON.stringify(counts)}`);
  print(`renderer: ${cfg.renderer ?? '?'} scene=${cfg.scene ?? ''} video=${cfg.video ?? ''}`);
  print(`lwe exists: ${GLib.file_test(LWE, GLib.FileTest.EXISTS)}`);
  print(`assets exists: ${GLib.file_test(ASSETS, GLib.FileTest.EXISTS)}`);
  System.exit(0);
}

const app = new Adw.Application({
  application_id: 'local.winwall.Picker',
  flags: Gio.ApplicationFlags.NON_UNIQUE,
});

let items = [];
let flow = null;
let search = null;
let typeFilter = null;
let countLabel = null;
let subtitle = null;

function buildCard(item) {
  const box = new Gtk.Box({
    orientation: Gtk.Orientation.VERTICAL,
    spacing: 6,
  });
  const picture = new Gtk.Picture({
    width_request: 240,
    height_request: 135,
    content_fit: Gtk.ContentFit.COVER,
    can_shrink: true,
    css_classes: ['card'],
  });
  if (item.preview) {
    let loaded = false;
    picture.connect('map', () => {
      if (loaded) return;
      loaded = true;
      const texture = loadTexture(item.preview);
      if (texture) picture.set_paintable(texture);
    });
  }
  const title = new Gtk.Label({
    label: item.title,
    wrap: true,
    lines: 2,
    ellipsize: 3,
    xalign: 0,
    max_width_chars: 30,
  });
  const meta = new Gtk.Label({
    label: `${typeLabel(item.type)} · ${item.id}`,
    xalign: 0,
    css_classes: ['dim-label', 'caption'],
  });
  if (GLib.build_filenamev([item.dir]) === currentKey().replace(/\/$/, '') ||
      item.dir === currentKey()) {
    title.set_label(`当前 · ${item.title}`);
  }
  box.append(picture);
  box.append(title);
  box.append(meta);
  const button = new Gtk.Button({
    css_classes: ['flat'],
    child: box,
    tooltip_text: item.title,
  });
  button.connect('clicked', () => applyItem(item, toastFn, subtitle));
  return button;
}

function rebuild() {
  if (!flow) return;
  let child = flow.get_first_child();
  while (child) {
    const next = child.get_next_sibling();
    flow.remove(child);
    child = next;
  }
  const query = (search?.text ?? '').trim().toLowerCase();
  const mode = typeFilter?.selected ?? 0;
  const wanted =
    mode === 1 ? 'video' : mode === 2 ? 'scene' : null;
  let shown = 0;
  for (const item of items) {
    if (wanted && item.type !== wanted) continue;
    if (query && !item.title.toLowerCase().includes(query)) continue;
    flow.append(buildCard(item));
    shown++;
  }
  countLabel.set_label(`${shown} / ${items.length}`);
}

let toastFn = null;

app.connect('activate', () => {
  const window = new Adw.ApplicationWindow({
    application: app,
    title: 'Winwall 壁纸',
    default_width: 1100,
    default_height: 760,
  });

  const toastOverlay = new Adw.ToastOverlay();
  const toolbar = new Adw.ToolbarView();
  toastOverlay.set_child(toolbar);
  window.set_content(toastOverlay);

  const header = new Adw.HeaderBar();
  const titleWidget = new Adw.WindowTitle({ title: 'Winwall 壁纸' });
  subtitle = titleWidget;
  header.set_title_widget(titleWidget);
  toolbar.add_top_bar(header);

  const toast = (message) => {
    toastOverlay.add_toast(new Adw.Toast({ title: message }));
  };
  toastFn = toast;

  search = new Gtk.SearchEntry({
    placeholder_text: '搜索标题…',
    hexpand: true,
    width_request: 260,
  });
  typeFilter = Gtk.DropDown.new_from_strings(['全部', '视频', '场景']);
  countLabel = new Gtk.Label({ css_classes: ['dim-label'] });

  const refresh = new Gtk.Button({
    icon_name: 'view-refresh-symbolic',
    tooltip_text: '重新扫描库',
  });

  const PAUSED_FILE = GLib.build_filenamev([
    GLib.get_home_dir(), '.cache/winwall/paused',
  ]);
  const rendererPid = () => {
    const [, out] = GLib.spawn_command_line_sync(
      "sh -c \"pgrep -f 'engine/[l]inux-wallpaperengine' | head -1\"",
    );
    return new TextDecoder().decode(out).trim();
  };
  const isPaused = () => GLib.file_test(PAUSED_FILE, GLib.FileTest.EXISTS);
  const extensionOn = () => {
    const [, out] = GLib.spawn_command_line_sync(
      'sh -c "gsettings get org.gnome.shell enabled-extensions" ',
    );
    return new TextDecoder().decode(out).includes('winwall@');
  };

  const pauseBtn = new Gtk.Button({ label: isPaused() ? '▶ 继续' : '⏸ 暂停' });
  pauseBtn.connect('clicked', () => {
    GLib.spawn_command_line_sync(`${KIT}/winwallctl.sh toggle`);
    pauseBtn.set_label(isPaused() ? '▶ 继续' : '⏸ 暂停');
    toast(isPaused() ? '壁纸已暂停（画面定格）' : '壁纸已继续');
  });
  const offBtn = new Gtk.Button({
    label: extensionOn() ? '⏻ 关闭壁纸' : '⏻ 开启壁纸',
  });

  const updateSwitches = () => {
    pauseBtn.set_label(isPaused() ? '▶ 继续' : '⏸ 暂停');
    offBtn.set_label(extensionOn() ? '⏻ 关闭壁纸' : '⏻ 开启壁纸');
  };
  updateSwitches();
  // 状态可能被外部（winwallctl / 扩展应用）改变：定时把按钮文字对齐到真实状态
  GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1500, () => {
    updateSwitches();
    return GLib.SOURCE_CONTINUE;
  });
  offBtn.connect('clicked', () => {
    if (extensionOn()) {
      if (isPaused()) GLib.spawn_command_line_sync(`${KIT}/winwallctl.sh resume`);
      GLib.spawn_command_line_async('gnome-extensions disable winwall@zhanghaobing.local');
      offBtn.set_label('⏻ 开启壁纸');
      toast('壁纸已关闭（静态桌面）；重新开启点本按钮');
    } else {
      GLib.spawn_command_line_async('gnome-extensions enable winwall@zhanghaobing.local');
      offBtn.set_label('⏻ 关闭壁纸');
      toast('壁纸已开启，稍等 1–2 秒');
    }
  });
  refresh.connect('clicked', () => {
    items = scanLibrary();
    rebuild();
    toast(`已重新扫描：${items.length} 项`);
  });

  const bar = new Gtk.Box({
    spacing: 8,
    margin_top: 8,
    margin_bottom: 8,
    margin_start: 12,
    margin_end: 12,
  });
  bar.append(search);
  bar.append(typeFilter);
  bar.append(countLabel);
  bar.append(pauseBtn);
  bar.append(offBtn);
  bar.append(refresh);
  toolbar.add_top_bar(bar);

  flow = new Gtk.FlowBox({
    selection_mode: Gtk.SelectionMode.NONE,
    homogeneous: true,
    column_spacing: 14,
    row_spacing: 14,
    margin_top: 12,
    margin_bottom: 12,
    margin_start: 12,
    margin_end: 12,
    min_children_per_line: 1,
    max_children_per_line: 6,
    valign: Gtk.Align.START,
  });
  const scroller = new Gtk.ScrolledWindow({
    hscrollbar_policy: Gtk.PolicyType.NEVER,
    child: flow,
    vexpand: true,
  });
  toolbar.set_content(scroller);

  search.connect('search-changed', rebuild);
  typeFilter.connect('notify::selected', rebuild);

  items = scanLibrary();
  subtitle.set_subtitle(`库：${items.length} 项`);
  rebuild();

  window.present();
});

app.run([System.programInvocationName, ...ARGV_]);
