# 视频壁纸踩坑记录（GNOME 50 Wayland / Winwall 开发过程）

记录 2026-11-27 做“视频当 GNOME 动态壁纸”原型时踩过的坑。每条按 **现象 → 原因 → 解法** 写，末尾附排查清单和可复制的验证命令。

---

## 1. 静态抽帧 ≠ 动态壁纸

- **现象**：先用 ffmpeg 抽了一帧设成系统静态壁纸，用户反馈“是静态的”。
- **原因**：抽帧只能验证画面质量和流水线，不产生动画。
- **结论**：抽帧只适合做质量预检；动态必须走“持续渲染 + 合成”的链路。

## 2. 普通全屏窗口当壁纸 → 挡住桌面图标

- **现象**：mpv 窗口铺满桌面后，视频能看，但 DING 的桌面图标消失。
- **原因**：GNOME Shell 的背景层在所有窗口之下；任何真实的窗口（哪怕全屏、无边框）都会盖住图标。
- **误导点**：`window.set_type(Meta.WindowType.DESKTOP)` 能改窗口类型，但在 Wayland 下窗口层级/堆叠并不因此变成“背景”。
- **解法**：不要指望“让窗口看起来像壁纸”，而是：
  1. 把窗口 actor 的 `opacity` 强制置 0（不可见）；
  2. 用 Cogl 效果抓取该窗口的画面，画进 `Main.layoutManager._backgroundGroup`（Wallshader 的做法）。

## 3. 透明窗口仍然吃掉鼠标点击

- **现象**：图标重新可见后，无法选中、无法双击、右键无反应。
- **原因**：opacity=0 只影响绘制，不影响输入；窗口仍在 DING 图标窗口之上，指针事件被它截获。
- **解法**：把我们的窗口排到 DING 的图标窗口**之下**（`window.lower()`），并在 `restacked` 时持续校正。
- **坑中坑**：DING 自己会在被 raise 时自我 `lower()`（`emulateX11WindowType.js`），存在“谁最后 lower 谁在下面”的竞争，所以要做**幂等的堆叠守护**，并设上限（我们用了 40 次）防止死循环。

## 4. DING 会改写 `global.get_window_actors`，看不到它的图标窗口

- **现象**：用 `global.get_window_actors()` 打窗口栈，始终找不到 `Desktop Icons 1`，误判“DING 不是窗口”。
- **原因**：DING 的 Shell 扩展替换了 `Shell.Global.get_window_actors`，在返回列表里剔除桌面窗口（`gnomeShellOverride.js` 的 `removeDesktopWindowFromList`）。
- **解法**：用 `global.display.list_all_windows()` 取全量窗口，再用 `global.display.sort_windows_by_stacking()` 排序。
- **附带坑**：`JSON.stringify(Meta.Rectangle)` 输出 `{}`（结构体不是 GObject），日志里要手写 `.x/.y/.width/.height`。

## 5. GNOME 50 会话内缓存扩展模块：改代码不生效

- **现象**：改完 JS，`gnome-extensions disable` → `enable`，行为完全没变，日志里也没有新加的日志行。
- **原因**：GNOME 45+ 在 Shell 进程内缓存扩展模块（ESM import 缓存），同会话内 enable 不会重新读文件。
- **解法**：
  - **改 JS → 必须注销重登**（Wayland 下无法热重启 Shell，没有 Alt+F2 `r`）；
  - 改配置文件不需要重登，disable/enable 即可；
  - 验证新代码是否加载：模块顶层打一行 `module vN loaded`，看 journal。
- **代价**：本次调试因此注销了 5 次。以后迭代前尽量把诊断信息一次写全。

## 6. GObject 类型名冲突：两个扩展抢注册

- **现象**：新会话启动后扩展加载失败：`Error: Type name WallshaderFrameTexture is already registered`。
- **原因**：直接拷贝 Wallshader 的 `background.js`，`GTypeName` 重复；Wallshader 扩展也在同一 Shell 进程里注册同名类型。
- **解法**：改名为 `WinwallFrameTexture` / `WinwallBackgroundTexture`；失败信息会写进 journal，`gnome-extensions info` 看到 `状态: ERROR` 时先查 journal。

## 7. `Meta.WaylandClient.new_subprocess` 的窗口归属匹配

- **现象**：窗口创建了但扩展不接管。
- **原因**：子进程必须真的走 Wayland（`GDK_BACKEND=wayland`、`unset DISPLAY`），否则 `client.owns_window()` 为 false。
- **解法**：三重匹配兜底——`client.owns_window()` → 进程 pid 对比 → 窗口标题 `Winwall Desktop N`。

## 8. Wayland 窗口几何会被 configure 拉回工作区

- **现象**：铺满显示器后，窗口被缩到 work area（少了顶栏高度），或干脆不铺满。
- **解法**：监听 `shown / size-changed / position-changed / notify::fullscreen`，在 `GLib.timeout_add(0)` 里反复 `move_resize_frame(false, monitor.x, monitor.y, monitor.width, monitor.height)`；遇到 `is_fullscreen()` 先 `unmake_fullscreen()`（mutter 对全屏窗口会隐藏顶栏）。

## 9. 抓帧要离屏纹理，不是截图

- **做法**：`Clutter.Clone` 克隆源 actor → 自定义 `Clutter.Effect` 里用 `Cogl.Offscreen` + `Clutter.ActorNode` 渲染进纹理 → `BackgroundTexture` 效果把纹理画到每个 `Meta.BackgroundActor`。
- **注意**：
  - `resource_scale` 要参与尺寸计算，否则高分屏发虚；
  - 抓帧分辨率有像素预算（默认 1920×1080），4K 全量克隆开销过大；
  - 源窗口 opacity 置 0 后，Shell 的 map/overview 过渡可能把它改回来，要监听 `notify::opacity` 持续压回 0。

## 10. 全屏 surface 可能被 direct scanout 绕过合成

- **现象**：画面偶发闪烁/不刷新。
- **原因**：monitor 大小的 Wayland surface 可能满足直接扫描输出条件。
- **解法**：壁纸可见期间 `global.compositor.disable_unredirect()`，不可见时恢复（`CompositingHold`，引用计数）。

## 11. 调试通道大多被关掉了

- `org.gnome.Shell.Eval`：默认禁用（返回 `(false, '')`）。
- `org.gnome.Shell.Introspect.GetWindows`：拒绝访问（`AccessDenied`，只给 portal 用）。
- `xwininfo/xdotool`：只看得到 Xwayland 窗口，看不到 Wayland 窗口。
- 可用的：`journalctl`（扩展自己的 `console.log`）、`gnome-extensions info`、进程/`/proc` 指标、`gsettings`。
- 视觉确认只能交给用户；自动化侧用“进程在跑 + 解码速率 + 日志状态”判断。

## 12. 无头会话可以预演，但不能替代真机

- 命令：`dbus-run-session -- gnome-shell --headless --wayland --no-x11`
- 能验证：模块加载、GType 注册、配置读取、日志逻辑。
- 不能验证：mpv 窗口映射/铺满/堆叠（无头下 mpv 建不出可用的渲染 surface）。最终仍需注销后真机确认。

## 13. mpv 参数与进程管理

- 关键参数：`--no-config --really-quiet --no-audio --loop-file=inf --no-osc --no-input-default-bindings --no-border --hwdec=auto --panscan=<0-1> --title=Winwall Desktop N -- <file>`
- `--` 不能省：中文/空格路径安全。
- 进程退出要监听 `wait_async`；`set_type` 失败要主动杀进程，避免留下一个无边框视频窗口乱飘。
- 实测占用：4K60 硬解时约 CPU 3.5%、GPU 16%（未暂停）。

## 14. “改主题”遗留问题会伪装成壁纸问题

- 登录过一次 Plasma 后，GNOME 的 gtk/icon/cursor/sound 主题被改成 Breeze，`snapd-desktop-integration` 每次登录报 `Missing theme snaps` 并弹「主题丢失」提示。
- 解法：`gsettings` 恢复 `Yaru-prussiangreen-dark` / `Yaru`，并同步 `~/.config/gtk-3.0|gtk-4.0/settings.ini` 与 `~/.config/xsettingsd/xsettingsd.conf`；重启 `snap.snapd-desktop-integration...` 验证日志变为 `All available theme snaps installed`。
- 教训：壁纸/桌面异常先查“最近装过什么桌面/主题”，别只盯壁纸代码。

## 15. 场景壁纸不能“转换”，但可以“宿主”

- WE 的 `.pkg` 场景壁纸由 Wallpaper Engine 自家引擎（着色器/粒子/贴图）驱动，不能被转成 mp4。
- 解法：把 `linux-wallpaperengine` 作为渲染进程，用同一套“DESKTOP 窗口 + 抓帧进背景层”宿主它。已在本机实现（见第 16–19 条）；assets 用 Steam 副本即可（本机 91 MB 足够，不需要 Windows 安装里那份）。
- 视频类（mp4/webm）不需要转换，直接播即可。

## 16. 场景壁纸要自己编译 linux-wallpaperengine

- 没有 apt 包、没有官方 release。源码构建：依赖在 Ubuntu 26.04 上碰巧全齐（`apt-get install -s` 模拟 0 个新包），但构建时自动下载 **CEF 运行时 1.8 GB**，最终 `build/output/` 约 1.4 GB。
- 子模块坑：`git clone --depth 1` + `submodule update --depth 1` 会漏掉锁定的提交，`glslang-WallpaperEngine` / `SPIRV-Cross-WallpaperEngine` 目录为空，但 `git submodule status` 仍显示正常（无前缀）。
- 解法：`git submodule update --init --force -- <path>` 强制检出锁定提交，再重新 cmake。
- 网络：本机直连 GitHub 0.8 s 握手，比 gh-proxy 快；不要一律挂镜像。

## 17. 场景“很慢”多半是帧率耦合

- lwe 默认 `--fps 30`。按帧推进的场景（很多 120Hz 作品）会以一半/四分之一速度播放，看起来就是“慢动作”。
- 速度旋钮 = `--fps`：30 / 60 / 120。帧率型场景按比例变快，时间轴型场景只影响流畅度。
- 不是所有场景都能调速：`--list-properties` 多数只返回 `schemecolor`，没有 speed 参数。

## 18. 抓帧像素预算导致 1440p 发虚

- Wallshader 的 `FrameCapture` 默认上限 **1920×1080 像素**；2560×1440 屏会先降采样再放大，画面发虚。
- 修复：启动时 `setCaptureResolution({width, height})` 传显示器原生尺寸（日志 `winwall: capture 2560x1440`）。
- 仍发虚再按顺序查：场景贴图本身分辨率 → `--scaling` 模式 → GLEW 告警是否禁用了高质量路径。

## 19. lwe 的窗口特征与非致命告警

- 窗口标题是 `wallpaperengine`，**不能**靠 `Winwall Desktop N` 匹配；必须靠 `client.owns_window()` / pid 兜底。
- `Failed to initialize GLEW: Unknown error`、`GLFW error 65548: Wayland: The platform does not support setting the window position`、mutter 的 `Client provided invalid window geometry ... Working around` 都是非致命告警，不影响出帧。
- 窗口几何由扩展统一 `move_resize_frame` 到显示器矩形，lwe 自己的位置/尺寸参数只作初始值。

## 20. 清理第三方构建产物：先列保留清单，再删（本次血的教训）

- **事故**：为了省空间，直接“保留 `build/output`、删掉 `build/` 其他所有东西”。结果 `build/lib/libkissfft-float.so.131` 是 RUNPATH 里的运行期依赖，壁纸当场起不来；手工重编 kissfft 才恢复。
- **正确流程**：
  1. 生成运行期清单：`ldd` 闭包（主程序 + 主要 `.so`）+ CEF 资源清单（`libcef.so`、`*.pak`、`icudtl.dat`、`locales/`、`libEGL/GLESv2`、`vk_swiftshader`）；
  2. 把清单外的文件**移到备份目录**（不要直接 `rm`），保留一份 `RUNTIME-KEEP.md`；
  3. 冒烟测试：场景 `--screenshot` + 网页壁纸（如果要用）+ 扩展重启；
  4. 全部通过后再删备份。
- **精简 libcef 的边界**：
  - `--strip-debug`：1.4 GB → 368 MB，保留完整动态符号；
  - `--strip-unneeded`：→ 220 MB，但**网页壁纸会崩**（SIGTRAP，`close symbol missing` 来自 libcef，动态符号被裁）。场景壁纸不受影响。
  - 结论：要用网页壁纸就只做 `--strip-debug`；只用场景/视频可以 `--strip-unneeded`。
- 当前 `build/output` 运行期清单和体积见 `lwe-src/RUNTIME-KEEP.md`。

---

## 排查清单（下次出问题按这个顺序看）

1. `pgrep -x mpv -a`：播放器在不在？参数对不对？
2. `journalctl --user -b --since '5 min ago' | grep -a winwall`：
   - `module vN loaded` 没有 → 代码没加载（缓存/语法/import 错误）
   - `managed` 没有 → 窗口没被接管（WaylandClient/pid/标题匹配失败）
   - `lower below Desktop Icons` 持续出现 → 堆叠竞争，正常；超过 40 次会停止
   - `player exited` → mpv 崩了（解码/GL/文件问题）
3. `gnome-extensions info winwall@zhanghaobing.local`：状态是否 ERROR/OUT OF DATE。
4. 图标能不能点：不能点 → 堆叠/输入问题（见坑 3、4）。
5. 桌面是黑的：抓帧失败或背景效果没挂上（检查 `_backgroundGroup` 是否拿到 `Meta.BackgroundActor`）。
6. 概览里显示异常：已知限制，尚未接概览。

## 可复制命令

```bash
# 语法检查
cd ~/tools/winwall/extension
node --input-type=module --check < extension.js

# 部署 + 重启扩展（改 JS 后仍需注销才生效）
DST=~/.local/share/gnome-shell/extensions/winwall@zhanghaobing.local
cp extension.js background.js compositing.js metadata.json COPYING "$DST"/

# 无头预演（只验证加载）
rm -f /tmp/winwall-headless.log
timeout 45 dbus-run-session -- bash -c \
  'gnome-shell --headless --wayland --no-x11 >/tmp/winwall-headless.log 2>&1 & GS=$!; sleep 12; kill -TERM $GS; sleep 2; kill -KILL $GS 2>/dev/null'
grep -aE 'winwall|already registered|JS ERROR' /tmp/winwall-headless.log
```
