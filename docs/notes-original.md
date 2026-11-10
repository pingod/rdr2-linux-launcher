# RDR2 一键启动器（绕过 Launcher 检查 / ERR_NO_LAUNCHER）

## 这是什么
这套文件让 **Razor1911 破解版 Red Dead Redemption 2** 能在 Wine（Bottles / GE-Proton）里
越过 `ERR_NO_LAUNCHER`、跳过破片头 cracktro，直接启动游戏。

## 原理（一句话）
RDR2 检测「是不是由 Rockstar Launcher 启动」的判定 = **spawn 它的父进程映像名必须叫
`Launcher.exe`**。真正的 Rockstar Launcher 的开场 cracktro 需要 Wine 不支持的
DirectComposition（dcomp）合成语义，跑不通——但**我们根本不需要跑 cracktro**，只需要一个
**名叫 `Launcher.exe` 的小程序**去 spawn RDR2，并假装是 pipe 服务器完成
`RDR2Launcher_Pipe` 握手（`INIT:` → `TINI:launcher:`）。`Launcher.exe` 就是这个小程序。

## 文件
- `Launcher.exe` — 自制 shim（7680B，原生 PE32+）。建 `\\.\pipe\RDR2Launcher_Pipe` 服务器、
  spawn RDR2.exe、回写握手；从同目录 `rdr2path.txt` 读取 RDR2.exe 绝对路径。
- `rdr2-launch.sh` — 一键脚本：自动装 nvapi64.dll、把 shim 铺到 bottle 的 `drive_c/rdr2run/`、
  用 GE-Proton 的 wine + gamescope 全屏启动。
- `shim.c` / `libshim3.a` / `shim3.def` — shim 源码与编译产物（可复用/重新编译）。

## 用法
```bash
cd ~/rdr2-launch
./rdr2-launch.sh                     # 1280x720 全屏（gamescope）
./rdr2-launch.sh -W 2560 -H 1440     # 自定义分辨率
RDR2_WINDOWED=1 ./rdr2-launch.sh     # 不进 gamescope，直接窗口跑
```
首次启动要编译大量 shader，会卡 98% CPU 好几分钟，**别急着关**。握手日志见
`~/.local/share/bottles/bottles/demo/drive_c/rdr2run/rdr2shim.log`。

## 重建 shim（改了 shim.c 后）
```bash
clang --target=x86_64-windows-gnu -nostdlib -nodefaultlibs -fuse-ld=lld \
  -Wl,--entry,mainCRTStartup -o Launcher.exe shim.c libshim3.a
```

## 已知限制
- 在无头 / Hyprland+XWayland 桌面上，**必须用 gamescope** 才能给 RDR2 一个正常的全屏
  Vulkan 渲染表面；不加 gamescope RDR2 会在 D3D12 初始化后静默退出（写 exit_file.dat，
  不是崩溃、不是 launcher 问题）。
- shim 的 pipe 握手在实测中 RDR2 并没有真的来连（这版 crack 可能不依赖 pipe），但保留无妨；
  真正起作用的是「父进程名 = Launcher.exe」。

---

# ✅ 最终可用方案：UMU 版（已验证进入游戏）

**使用 `rdr2-umu-launch.sh`**，不是前面的 `rdr2-launch.sh`（后者卡在"设备建完不出画面"）。

## 与 Bottles 方案的关键差异（5 个缺一不可的修复）

| # | 问题 | 修复 |
|---|------|------|
| 1 | 用 Bottles 自带 runner → 设备建完卡死 | 改用 **UMU + GE-Proton**（`umu-run`），引擎真正跑起来 |
| 2 | 父进程名不是 Launcher.exe → ERR_NO_LAUNCHER | 自制 shim 命名 `Launcher.exe` 去 spawn RDR2 |
| 3 | shim 把 cwd 设成自己目录 → RDR2 相对路径读不到数据 → `0x129` 数据损坏 | shim 用 RDR2.exe 的所在目录作为工作目录 |
| 4 | 缺 `nvml.dll` → RDR2 空转找 GPU | 从 GE-Proton 拷 `nvml.dll` + `nvapi64.dll` |
| 5 | 缺 `cfg.dat` → Razor1911 激活校验失败（"需要激活"画面） | 从前缀铺 `.1911\Red Dead Redemption 2\profile\cfg.dat` |

## 实测结果
- 进程树：`umu.exe → Launcher.exe(shim) → RDR2.exe`
- pipe 握手成功：收到 `SCSI:26285943`，回复 `TINI:launcher:CSI:26285943`
- **进入游戏画面**：雪地开场，中文对白、小地图、HUD 全部正常
- GPU：RTX 5060 Ti，占用 25%，显存 5.2GB，温度 43°C

## 用法
```bash
cd ~/rdr2-launch
./rdr2-umu-launch.sh                    # 1280x720 全屏
./rdr2-umu-launch.sh -W 2560 -H 1440
RDR2_NO_GAMESCOPE=1 ./rdr2-umu-launch.sh
```

## 说明
- 前缀在 `~/Games/umu/umu-default`（UMU 管理）
- 首次启动要编译 shader，会卡 1-2 分钟纯 CPU，正常现象
- `cfg.dat` 若没有会自动从 bottle 复制；若都丢了，游戏会显示"需要激活"
