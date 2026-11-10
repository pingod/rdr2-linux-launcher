# 排查全过程（时间线）

> 从"Launcher.exe 崩了"到"进游戏画面"的完整 debug 日志。保留失败尝试，方便后来者少走弯路。

---

## 阶段 0：最初的报错

```
Unhandled exception: page fault on read access to 0x0000000000008050
in 64-bit code (0x006ffffe5f6202)

Register dump:
 rip:00006ffffe5f6202 rsp:000000000010fb10 rbp:000000000010fc69
 rax:0000000000000000 rbx:00000000007a8fc0 rdi:0000000000000000

0x006ffffe5f6202 launcher+0x6202: cmpb $0, 0x8050(%rdi)
```

**第一反应**：`rdi = 0`，`cmpb $0, 0x8050(%rdi)` 就是在读 `0x8050` —— 典型的**空指针解引用**。

### 反汇编定位

```
1400061fb:  mov  rdi, QWORD PTR [rsi+0x118]    ; this->intro_player
140006202:  cmpb $0, 0x8050(%rdi)              ; rdi == NULL → 崩
```

`[app+0x118]` 是 cracktro 播放器对象。往前看它的创建过程：

```
1400069e8:  call  DCompositionCreateDevice(NULL, &IID_IDCompositionDevice, ...)
1400069ee:  test  eax, eax
            jns   ok            ; 失败 → 跳过 cracktro 对象创建 → 后续 NULL 解引用
```

### 找到真凶：Wine 的 dcomp 是空桩

```
$ objdump -d GE-Proton11-12/files/lib/wine/x86_64-windows/dcomp.dll

180001620 <DCompositionCreateDevice>:
  180001632:  testb $0x1, __wine_dbch_dcomp     ; 只有开了调试通道才打 FIXME
  180001639:  jne   180001650                    ; 跳到"真逻辑"
  18000163b:  mov   $0x80004001, %eax            ; ← E_NOTIMPL
  180001647:  ret                                ; ← 无条件返回
```

用 `+relay` 证实：

```
0100:Call dcomp.DCompositionCreateDevice(00000000, ...) ret=...69ee
0100:Ret  dcomp.DCompositionCreateDevice() retval=80004001   ← E_NOTIMPL
wine: Unhandled page fault on read access to 0x8050 ...
```

**确认根因：Wine 的 DirectComposition v1 是空桩，Razor1911 的 cracktro 初始化失败后不判空。**

---

## 阶段 1：所有 Wine 版本的 dcomp 都是空桩

| 来源 | DCompositionCreateDevice |
|---|---|
| GE-Proton11-12 | `mov $0x80004001, %eax; ret` |
| Proton Experimental (wine-11.0) | 同上 |
| proton-cachyos-slr | 同上 |
| 系统 wine 11.21 | 同上（调试通道里的"真逻辑"末尾也是 E_NOTIMPL） |

→ **换 Proton 版本没意义。**

---

## 阶段 2：试着"补 dcomp"（失败，但学到很多）

### 2.1 造一个 fake dcomp

用 clang 直接交叉编译（**不需要 mingw**）：

```bash
clang --target=x86_64-windows-gnu -shared -nostdlib -nodefaultlibs \
      -fuse-ld=lld -Wl,--entry,DllMainCRTStartup \
      -o dcomp.dll dcomp.c dcomp.def
```

第一版：所有 vtable 槽都指向一个 `uni_method`，返回 S_OK，若第二参数像指针就写个假对象进去。

**结果**：`write access to 0x10068 at 0x180001204` —— 有个方法第二参数是数值 `0x10068`，被我当成指针写了。

### 2.2 收紧判据

```c
if (a2 && (u64)a2 >= 0x100000000ULL) *((void**)a2) = &child;
```

**结果**：换了崩溃点 —— `0x140006be7`，`rcx = [rdi+0x18]` 是 NULL，读 `[0]`。

### 2.3 对 a2/a3/a4 全写

**结果**：`execute access to 0x180004000` —— 把某个回调指针覆盖了。

### 2.4 加日志看清调用序列

用 `CreateFileA` + `WriteFile` + `SetFilePointer` 往 `C:\dclog.txt` 追加日志（freestanding 里没有 printf）。
先踩了坑：`OutputDebugStringA` 版本在自己的 hex 格式化里越界崩了。

**终于拿到数据**：

```
D          ← DCompositionCreateDevice 被调用
M          ← 第一个 vtable 方法
M          ← 第二个 vtable 方法
(然后 launcher 就退出了)
```

只有 **2 次** vtable 调用就被中断。而完整 cracktro 需要 10+ 次。

### 2.5 看 launcher 到底在调什么

```
1400069e8:  call [0x1400155b0]   = DCompositionCreateDevice
140006a25:  call [rax+0x40]      = IDCompositionDevice::CreateTargetForHwnd
140006b8a:  call [rax+0x30]      = CreateVisual / CreateSurface
140006bba:  call [rax+0x38]      = 同上另一路
140006be3:  mov  rcx, [rdi+0x18] ; 这里 NULL → 崩
            call [rax+0x78]      = SetContent(swapchain)
```

**结论**：launcher 需要的是**真实可用的 DirectComposition 合成树**（target → visual → content → commit → present）。桩做不到。

### 2.6 试 DXVK 的 dummy swapchain

发现 DXVK 藏了个开关：

```
dxgi.enableDummyCompositionSwapchain
```

打开后：

```
warn:  DxgiFactory::CreateSwapChainForComposition: Creating dummy swap chain
info:vkd3d-proton:dxgi_vk_swap_chain_init: Creating swapchain (1024 x 1024), BufferCount = 2.
```

swapchain 造出来了，但 launcher 依然在后续崩溃。

### ❌ 最终结论：此路不通

在 Wine 上实现可用的 DirectComposition = 写一个迷你合成器。**研究级工作量，放弃。**

> 附带收获：这个 fake dcomp 确实能把原始 `0x8050` 崩溃消掉 —— 说明诊断是对的，只是方向不划算。

---

## 阶段 3：转向 shim（关键转折）

### 3.1 发现「自写 Launcher」的思路

既然 cracktro 只是**开场动画**，那我们根本不需要它 —— 只需要：

1. 有个叫 `Launcher.exe` 的进程
2. 它 spawn `RDR2.exe`
3. 顺便当 pipe 服务端应付握手

### 3.2 逆向 Launcher 的 launch 函数

`0x1400033e0` 处的完整流程（详见主 README 的 §2）。

顺带确认了：**CreateProcessA 的 command line 就是 `"RDR2.exe"`，没有任何特殊参数**。所以命令行参数不是判定依据。

### 3.3 第一版 shim

freestanding C，只用 kernel32：

```c
CreateNamedPipeA("\\.\pipe\RDR2Launcher_Pipe", 3|0x80000, 0, 0xff, 0x1000, 0x1000, 0, NULL);
CreateProcessA("...\\RDR2.exe", "RDR2.exe", ..., &si, &pi);
CreateThread(NULL, 0, pipeThread, ...);     // ConnectNamedPipe → ReadFile → WriteFile
WaitForSingleObject(pi.hProcess, INFINITE);
```

### 3.4 A/B 对照实验（转折点）

| shim 文件名 | 结果 |
|---|---|
| `shim.exe` | ~35 秒弹 **ERR_NO_LAUNCHER**（`#32770` 对话框），RDR2 卡死 |
| **`Launcher.exe`** | **不弹错误**，RDR2 跑满 CPU 2 分钟以上，加载到 D3D12 |

**这就是 ERR_NO_LAUNCHER 的真相：父进程映像名。**

截图确认对话框内容：
> 请使用 Rockstar Games Launcher 运行 Red Dead Redemption 2。

---

## 阶段 4：进了引擎但不出画面

### 4.1 现象

- RDR2 持续 99% CPU，日志停在 79 行
- 没有 swapchain 调用
- `AppData\Local\Rockstar Games\Red Dead Redemption 2\exit_file.dat`：

```
[ERROR_FILE_HASH]
0x07DCDBDD
[ERROR_FILE_LINE]
0x00000129        ← 297
[ERROR_TITLE]
错误
[ERROR_MESSAGE]
Red Dead Redemption 2 意外退出了！
```

### 4.2 解码 0x129

查 `x64/data/errorcodes/chinesesimp.txt`，第 297 行对应：

```
[ERR_PAR_INVALID_11]
{Corrupt game data. Please reboot, verify the game data, or reinstall the game.}
游戏数据损坏。请重启电脑，验证游戏数据，或重新安装该游戏。
```

**「游戏数据损坏」—— 但我们没改动过游戏文件。**

### 4.3 用 `+file` 找到线索

日志里 RDR2 访问的是：

```
L"update/x64/data/errorcodes/chinesesimp.txt"
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
相对路径！
```

**猛然醒悟**：我们的 shim 里 `CreateProcessA(..., lpCurrentDirectory = g_dir, ...)`，而 `g_dir` 是 shim 自己所在的目录（`rdr2run\`），**不是游戏目录**！

### 4.4 修复

```c
/* working directory = folder that contains RDR2.exe */
int last = -1;
for (int k = 0; k < n2; k++) if (g_rdr2[k] == '\\') last = k;
for (int k = 0; k <= last; k++) g_cwd[k] = g_rdr2[k];
g_cwd[last+1] = 0;

CreateProcessA(g_rdr2, "RDR2.exe", ..., g_cwd /* ← 改这里 */, &si, &pi);
```

**效果**：日志从 **79 行 → 2314 行**，游戏开始真正读数据；`exit_file.dat` 里的错误字段消失。

---

## 阶段 5：99% CPU 空转 → nvml

修复工作目录后仍然卡。`+file` 日志显示：

```
NtCreateFile ... "nvml.dll" not found (c0000034)     ← 刷了几百万行
NtCreateFile ... "C:\windows\system32\nvml.dll" not found
NtCreateFile ... "C:\Program Files (x86)\Steam\nvml.dll" not found
...
```

**RDR2 在疯狂搜索 NVML**（NVIDIA Management Library，查显存用）。

GE-Proton 里有：

```
files/lib/wine/nvidia-libs/nvml/wine/x86_64-windows/nvml.dll
files/lib/wine/nvapi/x86_64-windows/nvapi64.dll
```

拷进前缀 system32 → 循环消失。

---

## 阶段 6：UMU + gamescope（最后一块拼图）

即便修完上面所有，Bottles 自带 runner 依然卡在「设备建完、无 swapchain、单线程 NtDelayExecution 空转」。

### 6.1 检查驱动环境

```bash
$ ls -la /dev/dri/
crw-rw----+ card0   → amdgpu (核显)
crw-rw----+ card1   → nvidia
crw-rw-rw- renderD128 → nvidia
crw-rw-rw- renderD129 → amdgpu
```

双显卡 + DXVK 的 "Hiding actual GPU" 修复在每次枚举时打 544 行日志。

### 6.2 换 UMU

```bash
PROTONPATH=$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton11-12 \
GAMEID=umu-default \
umu-run /path/to/Launcher.exe
```

**立刻见效**：进程树 `umu.exe → Launcher.exe → RDR2.exe`，**并且 pipe 握手成功**：

```
ConnectNamedPipe=1
ReadFile=1
RECV: len=17  →  "\r\0\0\0SCSI:26285943"
SENT: len=26  →  "TINI:launcher:CSI:26285943"
```

### 6.3 gamescope 出画面

```bash
gamescope -W 1280 -H 720 -f -- umu-run Launcher.exe
```

窗口出现：`Red Dead Redemption 2 | Geometry: 1280x720`

但画面是黑的 —— 显示的是：

> **需要激活**
> 验证游戏所有权失败，无法加载您的离线激活数据。

---

## 阶段 7：cfg.dat（最后一道关）

### 7.1 对比两个前缀

```
bottle:  .1911/Red Dead Redemption 2/profile/
           cfg.dat           ← 有
           ProfileSettings
umu:     .1911/Red Dead Redemption 2/profile/
           ProfileSettings   ← 只有这个
```

### 7.2 看 cfg.dat 内容

```bash
$ xxd cfg.dat | head -2
00000000: 1911 5261 7a6f 7231 3931 3152 617a 6f72  ..Razor1911Razor
00000010: 3139 3131 5261 7a6f 7231 3931 3152 617a  1911Razor1911Raz
```

`0x19 0x11` + 重复的 `Razor1911` —— crack 的签名/密钥文件。

### 7.3 拷过去

```bash
cp bottle/.../profile/cfg.dat ~/Games/umu/umu-default/drive_c/users/steamuser/AppData/Roaming/.1911/"Red Dead Redemption 2"/profile/
```

**重启游戏 —— 直接进入开场雪地场景。** 🎉

---

## 最终可复现配置

```yaml
宿主:      Linux 7.3.3-1-cachyos
GPU:       NVIDIA RTX 5060 Ti, driver 620.70.6
Wine:      GE-Proton11-12 (wine-11.0 Staging)
启动器:    umu-run 1.4.3 + GE-Proton11-12
显示:      gamescope 3.17.0, 1280x720 全屏
前缀:      ~/Games/umu/umu-default
关键文件:  cfg.dat (1344B) @ %APPDATA%\.1911\Red Dead Redemption 2\profile\
           nvml.dll / nvapi64.dll @ system32
实测:      GPU 25%, VRAM 5.2GB, 43°C, 稳定运行
```

---

## 一句话总结

> **crack 的关卡不是 dcomp，不是 pipe，是父进程名。**
> 剩下四个坑是：工作目录、nvml、cfg.dat、显示环境。
