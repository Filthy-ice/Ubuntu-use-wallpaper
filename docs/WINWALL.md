# Winwall — GNOME 视频壁纸插件（原型状态）

把本地视频（mp4 / webm）或 Wallpaper Engine 场景壁纸（.pkg）变成 GNOME 桌面的动态壁纸，同时桌面图标、顶栏、Dock、窗口操作都保持正常。

- **视频**：mpv 直接播放（WE 视频类壁纸本身就是 mp4/webm，天然兼容）
- **场景**：自编译的 `linux-wallpaperengine` 渲染（WE 场景类 .pkg），接管方式与视频完全相同

- 扩展 UUID：`winwall@zhanghaobing.local`
- 适用环境：GNOME 50 / 51，Wayland 会话（当前机器：Ubuntu 26.04 / GNOME 50.1 / 无 X11 会话）
- 许可：GPL-3.0（`background.js` 派生自 Wallshader / stonega，COPYING 已随附）

## 1. 它做了什么

1. 扩展启动 `mpv`（无声、循环、硬解、无边框），每台显示器一个进程。
2. mpv 的窗口被改成 `Meta.WindowType.DESKTOP` 类型、粘到所有工作区、从窗口列表隐藏、铺满显示器。
3. 该窗口的 actor **透明度被强制置 0**——屏幕上永远看不见它，因此不会遮挡任何东西。
4. 用自定义 Cogl 效果把窗口画面抓成纹理，再画进 GNOME 的**背景层**（`Main.layoutManager._backgroundGroup`），位置在图标窗口之下。
5. 用一个堆叠守护确保该窗口排在 DING 的图标窗口（`Desktop Icons N`）之下，保证鼠标点击落到图标上而不是被透明窗口吃掉。
6. `CompositingHold` 在壁纸可见期间禁用 unredirect，避免全屏 surface 被直接扫描输出导致闪烁。

效果：桌面动起来，图标可点选/双击/右键，Alt-Tab 无多余窗口，概览页里不会多出窗口。

## 2. 文件清单

工程目录：`~/tools/winwall/extension/`（kit 总目录 `~/tools/winwall/`，不要拆散）

| 文件 | 作用 |
|---|---|
| `extension.js` | 扩展主体：读配置、拉起 mpv、窗口重定型/铺满、堆叠守护、显示器变化重建、退出清理 |
| `background.js` | 抓帧与绘制：`FrameCapture`（Clutter.Clone + Cogl 离屏纹理）、`LiveBackground`、`DesktopWallpapers`（含把源窗口 opacity 置 0） |
| `compositing.js` | `CompositingHold`：引用计数式 `disable_unredirect()` / `enable_unredirect()` |
| `metadata.json` | 扩展元数据（uuid / shell-version 50、51） |
| `COPYING` | GPL-3.0 许可证（含 Wallshader 代码来源） |

安装位置：`~/.local/share/gnome-shell/extensions/winwall@zhanghaobing.local/`

## 3. 安装 / 启用 / 停用

```bash
cd ~/tools/winwall
./winwallctl.sh install    # 同步 extension/ 到 GNOME（改过 JS 后需注销重登一次）
./winwallctl.sh reload     # 只改配置时生效
./winwallctl.sh disable    # 临时停用
```

注意：**改 JS 代码必须注销重登**（GNOME 50 会在会话内缓存扩展模块，`disable` → `enable` 不会重新读文件）；只改配置文件则不需要重登。

## 4. 配置

`~/.config/winwall/config.json`（不存在时使用内置默认值）：

```json
{
  "renderer": "scene",
  "scene": "/home/<user>/.local/share/Steam/steamapps/workshop/content/431960/<workshop-id>",
  "assets": "/home/<user>/.local/share/Steam/steamapps/common/wallpaper_engine/assets",
  "fps": 60,
  "lwe": "/home/<user>/tools/winwall/engine/run-lwe.sh",
  "video": "/绝对路径/到/视频.mp4",
  "panscan": 1.0
}
```

| 字段 | 说明 |
|---|---|
| `renderer` | `"video"`（mpv）或 `"scene"`（linux-wallpaperengine） |
| `video` | 视频模式的文件路径（mpv 能解码的 mp4/webm/mkv） |
| `panscan` | 视频模式铺满方式，0.0–1.0，1.0 = 裁切铺满 |
| `scene` | 场景模式：WE 壁纸目录（含 scene.pkg / project.json）或创意工坊 ID 目录 |
| `assets` | WE 资源目录（Steam 安装的 `wallpaper_engine/assets`） |
| `fps` | 场景渲染帧率，**同时也是帧率型场景的速度档位**：30/60/120（30 ≈ 原速一半，60 ≈ 原速，120 = 2 倍；对时间轴型场景只影响流畅度） |
| `lwe` | 自编译的 linux-wallpaperengine 可执行文件路径 |

改完执行 `gnome-extensions disable winwall@zhanghaobing.local && gnome-extensions enable winwall@zhanghaobing.local` 生效（无需重登）。

场景壁纸必须是**已经下载到本地**的创意工坊目录；`--list-properties` 可以查场景可调参数（多数场景只有 `schemecolor`，没有速度参数）。

## 4.1 图形选择器（入口）

应用列表里搜 **Winwall 壁纸**（`~/.local/share/applications/winwall-picker.desktop`），或终端：

```bash
~/tools/winwall/winwallctl.sh pick
```

- 扫描 `431960` 全库，显示缩略图/标题/类型（视频/场景），支持搜索和类型筛选；
- 点卡片即切换（写入配置并自动重载扩展，约 2 秒）；
- 网页壁纸会提示不支持（CEF 已弃用）；无“自动选横版/最高分辨率”，需手动挑。

## 5. 验证与排障

```bash
# 播放器是否在跑
pgrep -x mpv -a

# 扩展日志（关键字：module vN loaded / managed / stack# / lower below / player exited）
journalctl --user -b --since '5 min ago' | grep -a winwall

# 扩展状态
gnome-extensions info winwall@zhanghaobing.local

# 语法检查（改代码后先跑）
cd winwall && node --input-type=module --check < extension.js
```

健康状态的日志特征：

- `winwall: module vN loaded` + `winwall: capture WxH` + `winwall: enabled, renderer=...`：加载正常，抓帧分辨率是显示器原生尺寸
- `winwall: monitor 0 window ... managed`：渲染窗口已接管（视频是 mpv，场景是 linux-wallpaperengine）
- 周期性 `winwall: lower below Desktop Icons 1`：堆叠守护在把窗口压到图标层之下（正常，不是错误）
- 场景模式下 journal 里会有渲染器自己的输出（`Resolving require module ...`、非致命的 `Failed to initialize GLEW`）；`player exited` 才是真故障

## 6. 已知限制

| 限制 | 说明 |
|---|---|
| 概览 / 锁屏 | 仍是静态壁纸（只替换了桌面背景层，未接 OverviewWallpapers） |
| 省电 | 被窗口完全盖住时渲染器仍照常出帧，未做暂停（视频约 CPU 3.5% / GPU 16%；场景约 CPU 2–3% / GPU 10%） |
| 多显示器 | 支持为每台显示器铺同一个壁纸，但未做“不同显示器不同壁纸” |
| 轮播 | 无随机/定时切换 |
| 速度 | 只有 `fps` 一个旋钮；时间轴驱动的场景调速无效 |
| 音频 | 固定无声（视频天然无声，场景用 `--silent`） |
| 依赖 | 场景模式依赖自编译的 linux-wallpaperengine（约 1.4 GB 构建产物，含 CEF） |

## 7. 与 Wallshader 的关系

- 本项目的“隐藏窗口 + 抓帧进背景层”机制来自 Wallshader（GPL-3.0），`background.js` 为其派生版本，GObject 类型名已改为 `WinwallFrameTexture` / `WinwallBackgroundTexture`，可与 Wallshader 扩展同时启用。
- 排查期间 Wallshader 的扩展曾被临时停用；恢复：`gnome-extensions enable wallshader@wallshader.github.io`。
- 两者用途不同：Wallshader 播放 Paper 着色器动画；Winwall 播放任意视频。

## 8. 后续可做

1. 被覆盖时 SIGSTOP/SIGCONT 暂停（省电，约 30 分钟）
2. 视频壁纸库 + 缩略图 + 切换界面（导入文件夹即用）
3. 概览 / 锁屏同步（移植 OverviewWallpapers）
4. 场景壁纸可行性验证（linux-wallpaperengine 作为渲染源 + 同一套窗口宿主）
