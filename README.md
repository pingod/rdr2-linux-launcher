# rdr2-linux-launcher

**在 Linux（Wine / UMU / Proton）上启动 Razor1911 破解版《Red Dead Redemption 2》的完整解决方案。**

从这个游戏在 Linux 上的第一次黑屏报错，一路逆向到能真正进入游戏画面 —— 这里记录了全部过程、全部踩过的坑、和最终可复现的方案。

> 状态：✅ **已验证可进入游戏画面**（RTX 5060 Ti + GE-Proton + UMU + gamescope）

---

## 目录

- [TL;DR —— 直接能用的命令](#tldr--直接能用的命令)
- [五个核心问题（缺一不可）](#五个核心问题缺一不可)
- [技术原理](#技术原理)
  - [1. ERR_NO_LAUNCHER 的真面目](#1-err_no_launcher-的真面目)
  - [2. Launcher.exe 的 pipe 握手协议](#2-launcherexe-的-pipe-握手协议)
  - [3. 为什么 cracktro 那条路走不通](#3-为什么-cracktro-那条路走不通)
  - [4. Razor1911 的 cfg.dat](#4-razor1911-的-cfgdat)
- [排查过程中的死路（勿重复踩）](#排查过程中的死路勿重复踩)
- [文件说明](#文件说明)
- [自己编译 shim](#自己编译-shim)
- [环境要求](#环境要求)
- [常见问题](#常见问题)

---

## TL;DR —— 直接能用的命令

```bash
git clone https://github.com/pingod/rdr2-linux-launcher.git
cd rdr2-linux-launcher

# 指向你的游戏目录（含 RDR2.exe 的那个文件夹）
export GAME_DIR="/path/to/Red Dead Redemption 2"

./scripts/rdr2-umu-launch.sh                          # 1280x720 全屏
./scripts/rdr2-umu-launch.sh -W 2560 -H 1440          # 自定义分辨率
RDR2_NO_GAMESCOPE=1 ./scripts/rdr2-umu-launch.sh      # 不用 gamescope
```

也可以把 `GAME_DIR=...` 写在命令前面，不必 export。

首次启动会编译着色器，**卡 1~2 分钟纯 CPU 属正常**。

---

## 五个核心问题（缺一不可）

这不是一个 bug，是 **5 个独立问题叠加**。任何一个没解决，都会卡在不同阶段。

| # | 症状 | 根因 | 修复 |
|---|------|------|------|
| 1 | `page fault on read access to 0x8050`（Launcher.exe 崩） | Wine 的 `DCompositionCreateDevice` 是 **E_NOTIMPL 空桩**，Razor1911 的 cracktro 初始化失败后未判空直接解引用 | 不要走 cracktro 路线，改用自制 shim（见 #2） |
| 2 | 弹框「请使用 Rockstar Games Launcher 运行 Red Dead Redemption 2。」 | RDR2 检查**父进程映像名必须叫 `Launcher.exe`** | 自制 shim 命名为 `Launcher.exe` 去 spawn RDR2 |
| 3 | 弹框「Red Dead Redemption 2 意外退出了」（`exit_file.dat` 中 `ERR_PAR_INVALID_11`，行号 `0x129`） | shim 把**工作目录**设成了自己所在目录，RDR2 用相对路径 `update/x64/...` 读数据失败 → 判定数据损坏 | shim 用 RDR2.exe 所在目录作为 `lpCurrentDirectory` |
| 4 | 99% CPU 单线程空转，`+file` 日志里疯狂刷 `nvml.dll not found` | 缺 **`nvml.dll`**（NVIDIA 显存查询）+ `nvapi64.dll` | 从 GE-Proton 拷 `nvml.dll`、`nvapi64.dll` 进前缀 |
| 5 | 引擎正常渲染，但显示「**需要激活** — 验证游戏所有权失败」 | 缺 **`cfg.dat`** —— Razor1911 crack 的密钥文件，位于 `%APPDATA%\.1911\Red Dead Redemption 2\profile\` | 铺入 `cfg.dat` |

外加一个**环境层面**的问题：

| # | 症状 | 修复 |
|---|------|------|
| 6 | 设备创建完成后再无输出、静默退出；X11 下报 `X Error: BadWindow (X_UnmapWindow)` | 用 **UMU + GE-Proton**（而非 Bottles 自带 runner），并用 **gamescope** 提供正常的 Vulkan 全屏表面 |

---

## 技术原理

### 1. ERR_NO_LAUNCHER 的真面目

这是整个项目最反直觉的发现。

**它跟 pipe 无关，跟 cracktro 无关，跟 dcomp 无关。** 唯一条件是：

> **spawn `RDR2.exe` 的那个进程，其映像文件名必须叫 `Launcher.exe`。**

验证方法（A/B 对照）：

| 启动器进程名 | 结果 |
|---|---|
| `shim.exe` | ~35 秒后弹 `ERR_NO_LAUNCHER`（窗口类 `#32770`），RDR2 卡在对话框 |
| `Launcher.exe` | **不弹任何错误**，RDR2 持续运行、加载引擎 |

所以本文的 shim 是一个「什么都不做、只负责叫 Launcher.exe 并 spawn 游戏」的 8KB 小程序。

### 2. Launcher.exe 的 pipe 握手协议

原版 `Launcher.exe` 会创建命名管道 `\\.\pipe\RDR2Launcher_Pipe` 作为**服务端**，然后 spawn RDR2，RDR2 作为客户端连上来交换消息。

从 `Launcher.exe` 反汇编（`0x1400033e0` 处）还原的流程：

```
CreateProcessA("RDR2.exe")                    ← 先 spawn
CreateNamedPipeA("\\.\pipe\RDR2Launcher_Pipe", PIPE_ACCESS_DUPLEX, ...)
ConnectNamedPipe(...)  →  cmp eax, 0x102 (ERROR_PIPE_CONNECTED)
ReadFile(...)                                 ← 读 RDR2 发来的消息
  └─ 校验前 5 字节 == "INIT:"
     └─ 回复 "TINI:launcher:" + payload
WriteFile(...)
CloseHandle(...)  →  循环等待下一次连接
```

其中字符串常量在 `Launcher.exe` 里的位置：

| 内容 | VA |
|---|---|
| `\\.\pipe\RDR2Launcher_Pipe` | `0x140015930` |
| `INIT:` | `0x14001594c` |
| `TINI:launcher:` | `0x140015958` |

**实际观察到的情况**（这一点很有意思）：

RDR2 实际发来的是**带 4 字节长度前缀**的消息，而不是裸 `INIT:`：

```
.\x00\x00\x00SCSI:26285943        (17 字节)
^~~~~~~~~~ ^~~~~~~~~~~~~~~~~~
长度 13     真实载荷
```

我们的 shim 原样回 `TINI:launcher:` + payload 即可，实测：

```
ConnectNamedPipe=1
ReadFile=1
RECV: len=17  →  "\r\0\0\0SCSI:26285943"
SENT: len=26  →  "TINI:launcher:CSI:26285943"
```

游戏随后正常继续。**注意**：握手不是 `ERR_NO_LAUNCHER` 的判定条件（见 §1），但保持协议完整能让 crack 的校验链路更顺利。

### 3. 为什么 cracktro 那条路走不通

Razor1911 的 `Launcher.exe` 会先播放一段 cracktro（带音乐、Logo、滚动字幕的破解开场动画），渲染依赖 **DirectComposition v1**（`IDCompositionDevice`）。

实测结论：

```
Wine dcomp.dll 的 DCompositionCreateDevice：
  18000163b:  mov $0x80004001,%eax   ; E_NOTIMPL
  180001647:  ret
```

**所有 Wine / Proton 版本（GE-Proton、Proton Experimental、proton-cachyos、系统 wine 11.21）的 dcomp v1 都是无条件空桩。** 即使打开 `+dcomp` 调试通道，走到的「真逻辑」末尾依然返回 `0x80004001`。

我试过：

- ✅ 自己写了一个 fake `dcomp.dll`（`src/` 里没有收录，见下方说明）返回 S_OK + 全成功假 COM 对象
  - 结果：原始 `0x8050` 崩溃确实消失了 ✅
  - 但 launcher 只调用了 CreateDevice + **2 个 vtable 方法**就退出
  - 然后暴露下一个坑：`DxgiFactory::CreateSwapChainForComposition: Not implemented`
  - 打开 DXVK 的 `dxgi.enableDummyCompositionSwapchain=True` 后能造出 dummy swapchain，但仍不够
  - 继续修会级联出 `[rdi+0x18] == NULL` 读 `0x6be7` 崩溃、`execute fault at 0x180004000`

**根本原因**：cracktro 需要**真正可用的 DirectComposition 合成语义**（CreateVisual / CreateTargetForHwnd / SetContent / Commit / Present 全部要真对象真行为）。纯 S_OK 桩会不断撞新的崩溃。要做到这一步等于在 Wine 上实现一个迷你 DirectComposition —— 研究级工作量。

**结论：彻底放弃 cracktro 路线，改用 shim 直接 spawn RDR2。** 反正 cracktro 只是个开场动画。

### 4. Razor1911 的 cfg.dat

`cfg.dat` 是 Razor1911 crack 的密钥/签名文件：

```
路径：%APPDATA%\.1911\Red Dead Redemption 2\profile\cfg.dat
大小：1344 字节
内容：0x19 0x11 开头，后接重复的 "Razor1911" 字符串
```

没有它，游戏引擎会正常启动、正常渲染，但停在：

> **需要激活**
> 验证游戏所有权失败，无法加载您的离线激活数据。

`rdr2-umu-launch.sh` 会自动检测并尝试从已验证可用的位置复制。若丢失，可从**任意一个曾经成功运行过该 crack 的前缀**里取。

---

## 排查过程中的死路（勿重复踩）

| 尝试 | 结果 |
|---|---|
| 改 `Launcher.exe` 的 `Frame()` 跳过 cracktro 循环 | 能 spawn 游戏，但仍弹 `ERR_NO_LAUNCHER`（当时没意识到父进程名才是关键） |
| 给 `1911.dll` 打补丁 / 强制 native 加载 | Wine 加载的仍是内置副本，改写无效 |
| 用 relay 追 `user32` / `dcomp` 调用 | Wine 的 `RelayFromExclude` 会过滤 native PE 的部分调用，抓不到 |
| 在 `RDR2.exe` 里静态找 `ERR_NO_LAUNCHER` / pipe 字符串的 xref | 二进制高度混淆，字符串运行时解析，0 命中 |
| 装 proftpd / 各种 wine 版本 | 与问题无关 |
| 只换 proton-cachyos / Proton Experimental | 同样卡在 `0x129` 或设备初始化 |
| 加 `VKD3D_CONFIG=no_dxr`、`DXVK_FILTER_DEVICE_NAME` | 无效，DXR 仍上报 |
| 不用 gamescope，直接跑在 Xwayland | `X Error: BadWindow (X_UnmapWindow)` 早退 |

**关键教训**：从 `+file` 追踪里看到 RDR2 疯狂刷 `nvml.dll not found` 才意识到 #4；从 `exit_file.dat` 里读出 `ERR_PAR_INVALID_11` / `0x129` 才定位到 #3（工作目录）；「需要激活」画面才引出 #5。

---

## 文件说明

```
rdr2-linux-launcher/
├── scripts/
│   ├── rdr2-umu-launch.sh        ★ 主启动脚本（UMU 版，已验证）
│   └── legacy-bottles-launch.sh    旧版 Bottles 方案（卡在设备初始化，仅参考）
├── src/
│   ├── shim.c                     shim 源码（~150 行，freestanding C）
│   ├── shim3.def                  导入库定义（llvm-dlltool 用）
│   └── libshim3.a                 预编译导入库（kernel32 符号）
├── bin/
│   └── Launcher.exe              ★ 预编译 shim（PE32+ x64，8KB）
└── docs/
    └── README.orig.md            最初的工作笔记（英文/中英混杂）
```

### shim 做了什么

1. 建 `\\.\pipe\RDR2Launcher_Pipe` **服务端**
2. 从同目录 `rdr2path.txt` 读取 RDR2.exe 的**绝对路径**
3. 以 **RDR2 所在目录**为工作目录 `CreateProcessA` 启动游戏 ← 关键
4. 开后台线程：`ConnectNamedPipe → ReadFile → 回复 TINI:launcher: → DisconnectNamedPipe`，循环 8 次
5. 主线程 `WaitForSingleObject(游戏句柄, INFINITE)`，游戏退出后同样退出
6. 全流程日志写到同目录 `rdr2shim.log`

`rdr2path.txt` 由启动脚本生成，内容形如：

```
Z:\run\media\HDD2T01\Games\PCGames\Red Dead Redemption 2\RDR2.exe
```

---

## 自己编译 shim

不需要 mingw，只需要 clang + lld：

```bash
cd src
# 1) 生成 kernel32 导入库（只需一次）
llvm-dlltool -d shim3.def -l libshim3.a -m i386:x86-64

# 2) 编译（freestanding，无 CRT）
clang --target=x86_64-windows-gnu -nostdlib -nodefaultlibs -fuse-ld=lld \
      -Wl,--entry,mainCRTStartup -o ../bin/Launcher.exe shim.c libshim3.a
```

产物是标准 PE32+ x64 DLL/EXE，`file` 会识别为 `PE32+ executable for MS Windows 6.00 (console), x86-64`。

---

## 环境要求

- **Linux** + Wine 11.x（推荐用 GE-Proton 的 wine，附带 dxvk-nvapi / nvml）
- **umu-launcher**（Arch: `pacman -S umu-launcher`；其他发行版见 [Open-Wine-Components/umu-launcher](https://github.com/Open-Wine-Components/umu-launcher)）
- **gamescope**（可选但强烈推荐；在没有正常显示服务器的桌面环境如 Hyprland + XWayland 下几乎是必须的）
- **clang + lld + llvm-dlltool**（仅重新编译 shim 时需要）
- NVIDIA 显卡需能加载 `libnvidia-ml.so`

实测环境：
```
Host:    Linux 7.3.3-1-cachyos
GPU:     NVIDIA RTX 5060 Ti (driver 620.70.6)
Wine:    GE-Proton11-12 (wine-11.0 Staging) via umu-run
Game:    Razor1911 版 RDR2（含 1911.dll）
```

---

## 常见问题

**Q: 启动后黑屏 / 卡在 99% CPU 很久？**
A: 首次启动在编译着色器，1~2 分钟正常。若超过 5 分钟依旧无画面，检查 `rdr2shim.log` 里是否只有 `SHIM START` 没有 `ConnectNamedPipe=1`。

**Q: 显示「需要激活」？**
A: 缺 `cfg.dat`。参见 [§4](#4-razor1911-的-cfgdat)。

**Q: 显示「Red Dead Redemption 2 意外退出了」？**
A: 检查 `AppData\Local\Rockstar Games\Red Dead Redemption 2\exit_file.dat`：
- 有 `[ERROR_FILE_LINE] 0x00000129` → 工作目录不对（问题 #3）
- 只有 `[EXIT_CODE] 0x00000000` → 正常退出

**Q: 弹「请使用 Rockstar Games Launcher 运行」？**
A: 父进程名不是 `Launcher.exe`。确认用的是 `bin/Launcher.exe` 而不是自己改名的程序。

**Q: 卡在 `DxgiAdapter::QueryInterface` / 无 swapchain？**
A: 换 UMU + GE-Proton，并用 gamescope。

---

## License

本仓库内容（shim 源码、启动脚本、文档）为原创，可自由使用。  
游戏中涉及的二进制文件（`RDR2.exe`、`1911.dll`、`cfg.dat` 等）**不包含在本仓库中**，请自备合法来源。

## 致谢

- [umu-launcher](https://github.com/Open-Wine-Components/umu-launcher) —— 让 Wine 游戏在 Linux 上的启动变得规范
- [GE-Proton](https://github.com/GloriousEggroll/proton-ge-custom) —— 自带 dxvk-nvapi / nvml
- [gamescope](https://github.com/ValveSoftware/gamescope) —— 无 compositor 环境下救命的全屏表面
