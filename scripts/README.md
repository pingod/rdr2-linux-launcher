# scripts/

## `rdr2-umu-launch.sh` ★ 主启动脚本

已验证可进游戏。全部路径都可以用环境变量覆盖：

```bash
GAME_DIR="/path/to/Red Dead Redemption 2" \
PROTON_DIR="$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton11-12" \
UMU_PREFIX="$HOME/Games/umu/umu-default" \
./rdr2-umu-launch.sh -W 2560 -H 1440
```

| 变量 | 默认值 | 说明 |
|---|---|---|
| `GAME_DIR` | `/run/media/HDD2T01/Games/PCGames/Red Dead Redemption 2` | 游戏目录（含 RDR2.exe） |
| `PROTON_DIR` | `.../compatibilitytools.d/GE-Proton11-12` | 使用的质子 |
| `UMU_PREFIX` | `$HOME/Games/umu/umu-default` | UMU 前缀（可自动创建） |
| `GAMEID` | `umu-default` | 传给 umu-run 的 GAMEID |
| `RUN_DIR` | `<仓库>/run` | shim + 日志的放置目录（仓库自包含，已入库） |
| `CFG_REF` | bottle 里的那份 | cfg.dat 的来源路径 |
| `SHIM_SRC` | 自动探测 `../bin/Launcher.exe` | shim 可执行文件位置 |
| `RDR2_NO_GAMESCOPE` | 未设置 | 设为 1 则不用 gamescope |
| `WINEDEBUG` | `-all` | 调试时改成 `+file` 等 |

## `legacy-bottles-launch.sh`

早期基于 Bottles + SteamLinuxRuntime 的方案。**会在 D3D12 设备创建后卡死**，
仅作为排查记录保留。请用 `rdr2-umu-launch.sh`。
