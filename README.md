# gnome-winwall

把 **本地视频** 或 **Wallpaper Engine 场景壁纸（.pkg）** 当作 GNOME 桌面动态壁纸，同时桌面图标、Dock、窗口操作保持正常。

- 视频：`mpv` 播放（WE 的 video 类壁纸本身就是 mp4/webm）
- 场景：`linux-wallpaperengine` 实时渲染（外部依赖，**不随仓库分发**，由安装脚本构建）
- 桌面图标可点选/双击/右键，Alt-Tab 无多余窗口
- 渲染窗口跑在 Xwayland 上并清空输入区域：点击/右键直接穿透，不会和桌面图标抢层
- 附一个 GTK4 图形选择器（搜索/筛选/缩略图点选）

> 本仓库只放代码和文档。壁纸库、引擎二进制、CEF 等依赖一律不提交。

## 要求

- GNOME 50 / 51，**Wayland** 会话（Ubuntu 26.04 已验证）
- 已安装 mpv
- 已通过 Steam 拥有并安装 Wallpaper Engine（提供 `assets` 目录）
- 首次安装需约 6 GB 临时磁盘（源码 + CEF 下载 1.8 GB），最终运行时约 300 MB

## 快速开始

```bash
git clone git@github.com:Filthy-ice/gnome-winwall.git
cd gnome-winwall
./scripts/setup.sh          # 构建引擎 + 安装扩展/选择器（缺依赖时脚本会打印 sudo 命令）
# 注销重登一次（GNOME 只在登录时扫描新扩展）
./winwallctl.sh pick        # 或应用列表搜「Winwall 壁纸」
```

手动逐步安装见 [INSTALL.md](INSTALL.md)；给自动化 agent 的说明见 [AGENTS.md](AGENTS.md)。

## 使用

```bash
./winwallctl.sh pick                    # 图形选择器
./winwallctl.sh use-scene  ~/.local/share/Steam/steamapps/workshop/content/431960/<id>
./winwallctl.sh use-video  /path/to/video.mp4
./winwallctl.sh reload                  # 配置变更生效
./winwallctl.sh verify                  # 依赖检查 + 出帧冒烟测试
./winwallctl.sh status                  # 扩展/进程/日志
./winwallctl.sh install                 # 同步 extension/ 到 GNOME（改过 JS 后，需注销重登）
```

配置：`~/.config/winwall/config.json`（选择器会自动写）。速度档位 = `fps`（场景 30/60/120）。

## 仓库结构

```
extension/      GNOME Shell 扩展源码（背景抓帧派生自 Wallshader，GPL-3.0）
picker/         GTK4 壁纸选择器
scripts/        setup.sh 一键构建+安装
docs/           WINWALL.md（功能/配置/验证）、VIDEO-WALLPAPER-PITFALLS.md（踩坑）、RUNTIME-KEEP.md（引擎保留清单）
winwallctl.sh   命令行入口
config/         配置模板
```

不包含：`engine/`（构建产物）、`source-build/`（引擎源码，脚本会克隆）、任何壁纸文件。

## 工作原理（一句话）

扩展启动 mpv / linux-wallpaperengine → 窗口改成桌面层、actor 透明度置 0、排到桌面图标窗口之下 → Cogl 效果抓帧画进 GNOME 背景层（按显示器原生分辨率）→ 桌面动起来，图标与输入不受影响。

细节与 20 条踩坑记录见 [docs/](docs/)。

## 已知限制

- 网页壁纸（WE 的 web 类型）不支持（精简 libcef 后弃用）
- 概览/锁屏仍是静态图；被窗口完全覆盖时不暂停；无自动轮播
- 选择器不自动匹配横版/最高分辨率（手动挑）
- 修改扩展 JS 后必须注销重登（GNOME 会话内缓存扩展模块）

## 许可与致谢

- 本仓库：GPL-3.0（`COPYING`）
- `extension/background.js`、`compositing.js` 派生自 [Wallshader](https://github.com/stonega/wallshader)（GPL-3.0）
- 场景渲染依赖 [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine)（GPL-3.0，外部构建，不随仓库分发）
- Wallpaper Engine 及壁纸素材版权归 Valve / 原作者，需自行购买与下载
