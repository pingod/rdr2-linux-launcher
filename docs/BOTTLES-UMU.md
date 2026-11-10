# 把 RDR2 注册进 Bottles 的 UMU 系统

Bottles（≥ 2025 版）自带 UMU 集成：除了普通的「Bottles」列表外，还有一个
**UMU Prefixes** 区域，条目存放在：

```
~/.local/share/bottles/umu/
├── games/<uuid>/game.yml      ← 条目定义（名称、可执行文件、proton、参数…）
├── prefixes/<uuid>/           ← 该条目的 Wine 前缀（UMU 管理）
└── covers/                    ← 封面图
```

本文档记录如何把本项目注册进去，让游戏能**直接在 Bottles 界面里点图标启动**。

---

## 一、注册（一条命令）

```bash
bottles-cli umu add \
  --name "Red Dead Redemption 2" \
  --executable ~/.local/rdr2-umu-run/Launcher.exe \
  --proton ~/.local/share/Steam/compatibilitytools.d/GE-Proton11-12 \
  --store none
```

返回一个 UUID（本文示例为 `06ae51f1-4d6b-4e29-b47d-51dd0139a93a`），
并自动创建 `games/<uuid>/game.yml` 和 `prefixes/<uuid>/`。

> ⚠️ `--executable` 必须指向 **本项目的 shim `Launcher.exe`**（父进程名绕过，
> 见主 README §1），不是游戏目录里那个真的 Rockstar Launcher.exe。

## 二、shim 的运行目录

shim 需要同目录的两个文件，放在一个**稳定路径**（别用 /tmp）：

```
~/.local/rdr2-umu-run/
├── Launcher.exe        ← 本仓库 bin/Launcher.exe 的拷贝
├── rdr2path.txt        ← 一行：RDR2.exe 的 Windows 绝对路径
└── rdr2shim.log        ← 运行时握手日志（自动生成）
```

`rdr2path.txt` 示例（Z: 是 Wine 的盘符映射）：

```
Z:\run\media\HDD2T01\Games\PCGames\Red Dead Redemption 2\RDR2.exe
```

生成命令：

```bash
mkdir -p ~/.local/rdr2-umu-run
cp <repo>/bin/Launcher.exe ~/.local/rdr2-umu-run/
printf 'Z:%s\\RDR2.exe\r\n' "$(echo /your/game/dir | tr '/' '\\')" \
  > ~/.local/rdr2-umu-run/rdr2path.txt
```

## 三、game.yml 关键字段

注册后编辑 `~/.local/share/bottles/umu/games/<uuid>/game.yml`：

```yaml
name: Red Dead Redemption 2
executable: /home/<you>/.local/rdr2-umu-run/Launcher.exe
proton: /home/<you>/.local/share/Steam/compatibilitytools.d/GE-Proton11-12
working_directory: /home/<you>/.local/rdr2-umu-run   # shim 的目录（不是游戏目录！）
game_id: umu-default          # 非 Steam 库游戏用默认值即可
store: none
state: ready
```

> `working_directory` 指向 shim 目录是安全的：shim 自己会把 **RDR2 的子进程
> 工作目录**设成 RDR2.exe 所在目录（主 README 问题 #3 的修复在 shim 内部）。

## 四、把已跑通的前缀搬进 Bottles（免重编译 shader / 免丢 cfg.dat）

如果游戏之前已经用 `umu-run` 直接跑通过，UMU 前缀会在
`~/Games/umu/<GAMEID>/`（默认 `~/Games/umu/umu-default/`）。
Bottles 注册时新建的前缀是**空壳**，直接搬过去即可继承：

```bash
UUID=06ae51f1-4d6b-4e29-b47d-51dd0139a93a
mv ~/Games/umu/umu-default \
   ~/.local/share/bottles/umu/prefixes/$UUID
```

两边前缀结构完全一致（都是 UMU 生成的：`config_info`、`drive_c`、
`system.reg`、`tracked_files`、`version`…），可直接互换。

搬完检查三样关键文件都在前缀里：

| 文件 | 位置 | 作用 |
|---|---|---|
| `cfg.dat` | `drive_c/users/steamuser/AppData/Roaming/.1911/Red Dead Redemption 2/profile/` | crack 密钥，缺了会「需要激活」 |
| `nvml.dll` | `drive_c/windows/system32/` | 缺了 RDR2 空转搜 NVML |
| `nvapi64.dll` | `drive_c/windows/system32/` | 同上（dxvk-nvapi） |

后两个可从 GE-Proton 拷：

```bash
P=~/.local/share/bottles/umu/prefixes/$UUID/drive_c/windows/system32
G=~/.local/share/Steam/compatibilitytools.d/GE-Proton11-12
cp $G/files/lib/wine/nvidia-libs/nvml/wine/x86_64-windows/nvml.dll $P/
cp $G/files/lib/wine/nvapi/x86_64-windows/nvapi64.dll $P/
```

## 五、在条目里套 gamescope（Bottles 界面启动也有全屏合成）

Bottles 直接启动 UMU 条目时**不带 gamescope**。在 Hyprland / 无正常
X 显示服务器的环境下会没画面。解决办法：利用 `arguments` 字段的
**命令包装模式**（`%command%` 占位符），在 Bottles GUI 的
「游戏属性 → 参数」里填，或直接改 game.yml：

```yaml
arguments:
- gamescope
- -W
- '2560'
- -H
- '1440'
- -f
- --force-grab-cursor
- --mangoapp          # 可选：MangoHud 帧率叠加
- --
- '%command%'
```

等价于运行 `gamescope -W 2560 -H 1440 -f --force-grab-cursor --mangoapp -- <原命令>`。

✅ 已实测：`bottles-cli umu run --game <uuid>` 会原样展开成
`gamescope ... -- /usr/bin/umu-run <executable>`，游戏窗口正常出现在
gamescope 的嵌套显示里。

## 六、启动

**GUI**：重开 Bottles（配置改动后需重启才刷新列表）→「UMU Prefixes」
→ 点 Red Dead Redemption 2 的播放键。

**CLI**：

```bash
bottles-cli umu run --game <uuid>
bottles-cli umu list                    # 查看所有条目
bottles-cli umu --game <uuid> status    # 查看单条详情
```

## 七、已知限制 / 注意事项

1. **GUI 缓存**：直接编辑 `game.yml` 后，正在运行的 Bottles 不会即时刷新，
   需重启 Bottles 窗口。
2. **没有删除子命令**：`bottles-cli umu` 只有 `list/status/add/install/run/set-executable`，
   删条目要手动 `rm -rf games/<uuid> prefixes/<uuid>`。
3. **改配置前先备份**：`cp -r ~/.local/share/bottles/umu/{games,prefixes} /tmp/backup/`。
4. **首次在新前缀跑仍会编译 shader**（搬旧前缀可跳过）。
5. `game_id: umu-default` 意味着 protonfixes 里查不到该游戏（日志会 WARN
   "Game title not found in CSV"），无害，可忽略。

---

## 附：本次实测记录

| 项 | 值 |
|---|---|
| 注册方式 | `bottles-cli umu add` |
| UUID | `06ae51f1-4d6b-4e29-b47d-51dd0139a93a` |
| 前缀来源 | 从 `~/Games/umu/umu-default` 整体 `mv` 迁入（335MB，含 cfg.dat + shader cache） |
| 补装 | `nvml.dll`（前缀里原本没有） |
| 启动验证 | `bottles-cli umu run` → 握手成功 → **RDR2 主菜单画面正常** |
