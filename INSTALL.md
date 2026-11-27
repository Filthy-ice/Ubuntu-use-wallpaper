# 安装（手动步骤）

目标环境：Ubuntu 26.04 / GNOME 50.1 / Wayland。其他发行版需自行替换依赖包名。

## 0. 前置检查

```bash
gnome-shell --version        # 50 或 51
echo $XDG_SESSION_TYPE      # 必须是 wayland
mpv --version | head -1
ls ~/.local/share/Steam/steamapps/common/wallpaper_engine/assets   # 必须存在（WE 安装目录）
```

## 1. 依赖

```bash
sudo apt-get install -y \
  build-essential cmake git \
  libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev libgl-dev libglew-dev \
  freeglut3-dev libsdl2-dev liblz4-dev libxxf86vm-dev libglm-dev libglfw3-dev \
  libavcodec-dev libavformat-dev libavutil-dev libswscale-dev \
  libmpv-dev mpv libpulse-dev libpulse0 libfftw3-dev libfreetype-dev libpng-dev
```

## 2. 构建 linux-wallpaperengine（场景壁纸用；只用视频可跳过）

固定版本：`a0ddce586e9ff12e9d31ca6b103f6036cc1b68fe`（2026-11 验证）。

```bash
git clone https://github.com/Almamu/linux-wallpaperengine.git source-build
cd source-build
git fetch --depth 1 origin a0ddce586e9ff12e9d31ca6b103f6036cc1b68fe
git checkout FETCH_HEAD
# 子模块必须 --force，深度克隆常漏锁定提交
git submodule update --init --recursive --force

cmake -B build -DCMAKE_BUILD_TYPE=Release     # 会自动下载 CEF（约 1.8 GB，解压后）
cmake --build build -j"$(nproc)"              # 约 5–15 分钟
```

把产物挪到 kit 的 `engine/`（**不要把 output 整个目录留着，中间产物很大**）：

```bash
cd ..
mkdir -p engine
mv source-build/build/output/* engine/
```

### 精简（可选，强烈建议）

```bash
cd engine
# 场景/视频不用网页壁纸 → 可激进剥离；要用网页壁纸则改用 --strip-debug
objcopy --strip-unneeded libcef.so libcef.min.so && mv libcef.min.so libcef.so   # 1.4G → 220M
# 只留两种语言
find locales -type f ! -name en-US.pak ! -name zh-CN.pak -delete
# 删测试/基准产物
rm -f api-test testcpp-float psdpng-float bm_* fastconv* fastfilt-float run-test262 qjs qjsc function_source
# 写启动器（X11 + 固定库路径；窗口必须是 X11 才能清空输入区域）
cat > run-lwe.sh <<'EOF'
#!/bin/sh
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export DISPLAY="${DISPLAY:-:0}"
unset WAYLAND_DISPLAY
LD_LIBRARY_PATH="$HERE/glfw-x11/lib:$HERE" exec "$HERE/linux-wallpaperengine" "$@"
EOF
chmod +x run-lwe.sh
```

### X11-only GLFW（必须）

Ubuntu 的 libglfw 会坚持走 Wayland；而清空输入区域依赖 X11（X Shape），所以要在 kit 里放一份 X11-only GLFW：

```bash
git clone --depth 1 -b 3.4 https://github.com/glfw/glfw.git /tmp/glfw
cmake -S /tmp/glfw -B /tmp/glfw/build -DGLFW_BUILD_WAYLAND=OFF -DGLFW_BUILD_X11=ON \
  -DBUILD_SHARED_LIBS=ON -DGLFW_BUILD_EXAMPLES=OFF -DGLFW_BUILD_TESTS=OFF -DGLFW_BUILD_DOCS=OFF
cmake --build /tmp/glfw/build -j"$(nproc)"
mkdir -p engine/glfw-x11/lib && cp -a /tmp/glfw/build/src/libglfw.so* engine/glfw-x11/lib/
```

### 输入区域/窗口类型助手（必须）

```bash
mkdir -p bin && gcc bin/winwall-x11-setup.c -lX11 -lXext -o bin/winwall-x11-setup
```

它按 PID 找到渲染窗口，设置 `_NET_WM_WINDOW_TYPE_DESKTOP` 并清空输入区域；失败时扩展会直接杀掉渲染进程，避免盖住桌面。

删除任何文件前先读 [docs/RUNTIME-KEEP.md](docs/RUNTIME-KEEP.md)：`libkissfft-float.so.131` 等是运行期硬依赖，删了壁纸起不来。

## 3. 安装 GNOME 扩展

```bash
cd ..                          # 回到仓库根目录
./winwallctl.sh install        # 复制 extension/ 到 ~/.local/share/gnome-shell/extensions/winwall@zhanghaobing.local/
```

然后**注销重登一次**（GNOME 只在会话启动时扫描新扩展）。重登后：

```bash
gnome-extensions info winwall@zhanghaobing.local   # 状态应为 ACTIVE
```

> 之后每次修改扩展 JS 都要 `install` + 注销重登；只改配置不需要。

## 3.5 桌面图标改由 Nemo 提供（必需）

DING 会在每次叠层变化时把自己再沉一次，和壁纸窗口形成永久的抢层战争（表现：右键菜单闪退、图标时灵时不灵）。因此桌面图标交给 Nemo、背景设为透明：

```bash
./winwallctl.sh desktop-setup
```

脚本做三件事：停用 DING、写入 nemo-desktop 自启（3 秒延迟）、把 Cinnamon 桌面背景设为 `assets/transparent.png`，并安装「复制路径 / 删除软链接」右键动作。完成后注销重登一次。

## 4. 安装图形选择器（可选）

```bash
./scripts/install-picker.sh    # 生成 ~/.local/share/applications/winwall-picker.desktop
```

应用列表里搜「Winwall 壁纸」，或 `./winwallctl.sh pick`。

## 5. 选壁纸 / 配置

用选择器点选，或手写 `~/.config/winwall/config.json`（见 `config/config.example.json`）：

```json
{
  "renderer": "scene",
  "scene": "/home/<user>/.local/share/Steam/steamapps/workshop/content/431960/<id>",
  "assets": "/home/<user>/.local/share/Steam/steamapps/common/wallpaper_engine/assets",
  "fps": 60,
  "lwe": "/home/<user>/tools/winwall/engine/run-lwe.sh",
  "video": "",
  "panscan": 1.0
}
```

- `renderer`: `scene` 或 `video`
- `fps`: 场景速度/流畅度档位（30/60/120；帧率型场景速度随之变化）
- 路径必须写**绝对路径**（`~` 不会被展开）

改完 `./winwallctl.sh reload`（无需重登）。

## 6. 验证

```bash
./winwallctl.sh verify     # ldd 依赖检查 + 1280x720 出帧冒烟
./winwallctl.sh status     # 扩展 + 渲染进程 + 最近日志
```

健康日志：`module vN loaded`、`capture 2560x1440`、`monitor 0 window ... managed`；
周期性 `lower below Desktop Icons 1` 是堆叠守护，正常。

## 卸载

```bash
gnome-extensions disable winwall@zhanghaobing.local
rm -rf ~/.local/share/gnome-shell/extensions/winwall@zhanghaobing.local
rm -f ~/.local/share/applications/winwall-picker.desktop
rm -rf ~/.config/winwall
# 引擎/源码按需删：rm -rf engine source-build
```

## 常见故障

| 现象 | 原因/处理 |
|---|---|
| 启用时提示“扩展不存在” | 还没注销重登（新扩展只在登录时发现） |
| 壁纸不出现，日志 `player exited` | `ldd engine/linux-wallpaperengine` 看缺哪个库；最常见是 `libkissfft-float.so.131` 被误删 |
| 壁纸出来但图标点不了 | 堆叠守护未生效；检查日志是否有 `lower below Desktop Icons 1` |
| 画面发虚 | 抓帧分辨率必须是显示器原生（日志 `capture WxH`）；旧版有 1080p 上限 |
| 场景很慢 | 调 `fps`（帧率型场景）；或换场景 |
| 网页壁纸崩（SIGTRAP `close symbol missing`） | 精简 libcef 的已知代价，网页壁纸不支持 |
| 改 JS 不生效 | 注销重登（模块缓存），或确认 `winwallctl.sh install` 已同步 |
