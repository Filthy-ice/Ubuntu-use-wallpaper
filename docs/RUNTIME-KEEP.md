# linux-wallpaperengine 运行期保留清单

运行时目录：`~/tools/winwall/engine/`（当前 313 MB）。**只能动清单外的文件**，删前先移到备份目录并做冒烟测试。

## 必须保留

| 文件 | 说明 |
|---|---|
| `linux-wallpaperengine` | 主程序 |
| `liblinux-wallpaperengine-lib.so` | 引擎主库 |
| `libkissfft-float.so.131` | RUNPATH 运行依赖（曾在 `build/lib`，全删后壁纸起不来） |
| `libcef.so` | CEF（网页壁纸需要；场景也会被链接加载）。当前为 `--strip-unneeded` 220 MB 版本，**网页壁纸会崩** |
| `libEGL.so` / `libGLESv2.so` / `libvk_swiftshader.so` / `vk_swiftshader_icd.json` | CEF 图形后端 |
| `chrome_100_percent.pak` / `chrome_200_percent.pak` / `resources.pak` / `icudtl.dat` / `v8_context_snapshot.bin` | CEF 资源 |
| `chrome-sandbox` | CEF 沙箱文件（保留，避免权限告警） |
| `locales/en-US.pak`、`locales/zh-CN.pak` | 只留两个语言包（原 55 个 44 MB） |
| `glslang`、`spirv-cross`、`spirv-remap` | 着色器翻译相关（保守保留） |

## 已移除（测试/基准产物，约 7 MB，2026-11-27 验证通过后删除）

`api-test`、`testcpp-float`、`psdpng-float`、`bm_fftw-float`、`bm_kiss-float`、`fastconv-float`、`fastconvr-float`、`fastfilt-float`、`run-test262`、`qjs`、`qjsc`、`function_source`。

网页壁纸已放弃，但 `libcef.so` 仍被主程序链接，**不能删**；要彻底去掉需要改 CMake/源码做无 CEF 构建（预计 30–60 分钟，产物约 70 MB，失去 4 张网页壁纸）。

## 清理前检查命令

```bash
cd ~/tools/winwall/engine
# 1) 本地依赖闭包
{ ldd build/output/linux-wallpaperengine; ldd build/output/liblinux-wallpaperengine-lib.so; } 2>/dev/null \
  | awk -F'=>' '/=>/ {split($2,a," "); if (a[1] ~ /lwe-src/) print a[1]}' | sort -u
# 2) 确认没有 not found
ldd build/output/linux-wallpaperengine | grep 'not found'
# 3) 冒烟：场景出帧（不弹窗、自动退出）
mkdir -p /tmp/lwe-check && cd /tmp/lwe-check && \
  <path>/run-lwe.sh --silent --fps 30 --window 0x0x1280x720 \
  --screenshot /tmp/lwe-check/s.png --screenshot-delay 60 \
  --assets-dir ~/.local/share/Steam/steamapps/common/wallpaper_engine/assets \
  ~/.local/share/Steam/steamapps/workshop/content/431960/<id>
ls -lh /tmp/lwe-check/s.png
```

## 现状与已知限制

- 场景壁纸：正常（已用《云虫 WLOP 月牙儿》截图验证，961 KB 非黑屏）。
- 视频壁纸：与 lwe 无关，走 mpv，正常。
- 网页壁纸（库里 4 张）：当前 `--strip-unneeded` 的 libcef 会导致 SIGTRAP（`close symbol missing`）。要恢复需重新获取 CEF 并用 `--strip-debug`（368 MB），或保留原始 1.4 GB 版本。
- 构建中间产物已删（原 4.1 GB → 712 MB）；再次重建需要重新下载 CEF 1.8 GB。
