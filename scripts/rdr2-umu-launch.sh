#!/usr/bin/env bash
# =============================================================================
# rdr2-umu-launch.sh —— RDR2 (Razor1911) 一键启动器【UMU 版 · 已验证可进游戏】
#
# 为什么这条路能成（对照 bottle 方案的差异）：
#   1) 用 UMU + Proton（protonics 的 umu-run），而不是 Bottles 自己的 runner；
#   2) 父进程名必须叫 Launcher.exe —— 由自制 shim 冒充（绕过 ERR_NO_LAUNCHER）；
#   3) 工作目录必须是游戏根目录（RDR2 用相对路径读 update/x64/... 数据）；
#   4) 前缀里必须有人生成了 cfg.dat（Razor1911 crack 的密钥文件）；
#   5) 需要 nvml.dll / nvapi64.dll，否则 RDR2 会空转找 GPU 信息。
#
# 用法：
#   ./rdr2-umu-launch.sh                 # 1280x720 全屏（gamescope）
#   ./rdr2-umu-launch.sh -W 2560 -H 1440
#   RDR2_NO_GAMESCOPE=1 ./rdr2-umu-launch.sh   # 不要 gamescope
# =============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"   # 仓库根目录

# ---------------- 配置 ----------------
GAME_DIR="${GAME_DIR:-/run/media/HDD2T01/Games/PCGames/Red Dead Redemption 2}"
PROTON_DIR="${PROTON_DIR:-$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton11-12}"
UMU_PREFIX="${UMU_PREFIX:-$HOME/Games/umu/umu-default}"
GAMEID="${GAMEID:-umu-default}"
# shim 位于仓库 bin/；也允许放在脚本同目录（兼容旧布局）
SHIM_SRC="${SHIM_SRC:-}"
if [ -z "$SHIM_SRC" ]; then
  for c in "$REPO/bin/Launcher.exe" "$HERE/Launcher.exe"; do
    [ -f "$c" ] && { SHIM_SRC="$c"; break; }
  done
fi
RUN_DIR="${RUN_DIR:-$HOME/.local/rdr2-umu-run}"
# 参考 crack 密钥（从已验证可用的 bottle 里取；若你的机器没有，会跳过）
CFG_REF="${CFG_REF:-$HOME/.local/share/bottles/bottles/demo/drive_c/users/pavia/AppData/Roaming/.1911/Red Dead Redemption 2/profile/cfg.dat}"
# --------------------------------------

GW=1280; GH=720
ARGS=("$@")
for ((i=0;i<${#ARGS[@]};i++)); do
  case "${ARGS[i]}" in
    -W) GW="${ARGS[i+1]}";;
    -H) GH="${ARGS[i+1]}";;
  esac
done

die(){ echo "错误: $*" >&2; exit 1; }

[ -d "$GAME_DIR" ]          || die "游戏目录不存在: $GAME_DIR"
[ -f "$GAME_DIR/RDR2.exe" ] || die "找不到 RDR2.exe"
[ -f "$SHIM_SRC" ]          || die "找不到 shim: $SHIM_SRC"
command -v umu-run >/dev/null || die "没装 umu-run（pacman -S umu-launcher）"

# ---- 1) 准备 shim 运行目录 ----
mkdir -p "$RUN_DIR"
cp -f "$SHIM_SRC" "$RUN_DIR/Launcher.exe"
# shim 通过同目录 rdr2path.txt 读 RDR2.exe 绝对路径（Windows 风格）
printf 'Z:%s\\RDR2.exe\r\n' "$(printf '%s' "$GAME_DIR" | tr '/' '\\')" > "$RUN_DIR/rdr2path.txt"

# ---- 2) 确保 UMU 前缀里有 cfg.dat（Razor1911 密钥）----
PROFILE="$UMU_PREFIX/drive_c/users/steamuser/AppData/Roaming/.1911/Red Dead Redemption 2/profile"
mkdir -p "$PROFILE"
if [ ! -f "$PROFILE/cfg.dat" ] && [ -f "$CFG_REF" ]; then
  cp "$CFG_REF" "$PROFILE/cfg.dat" && echo "[+] 已铺 cfg.dat (crack 密钥)"
fi

# ---- 3) 环境 ----
export DISPLAY="${DISPLAY:-:0}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export PROTONPATH="$PROTON_DIR"
export GAMEID
export WINEDEBUG="${WINEDEBUG:--all}"
# 避免 DXVK 在双显卡下反复枚举/卡住
export DXVK_FILTER_DEVICE_NAME="${DXVK_FILTER_DEVICE_NAME:-}"

echo "[*] RDR2 (UMU) 启动"
echo "    游戏:   $GAME_DIR"
echo "    shim:   $RUN_DIR/Launcher.exe  ->  RDR2.exe"
echo "    前缀:   $UMU_PREFIX"
echo "    Proton: $PROTON_DIR"
echo "    日志:   $RUN_DIR/rdr2shim.log"

cd "$RUN_DIR" || die "无法进入 $RUN_DIR"

if [ -n "${RDR2_NO_GAMESCOPE:-}" ] || ! command -v gamescope >/dev/null 2>&1; then
  echo "[*] 直接运行（无 gamescope）"
  exec umu-run "$RUN_DIR/Launcher.exe"
else
  echo "[*] gamescope 全屏 ${GW}x${GH}"
  exec gamescope -W "$GW" -H "$GH" -f -- umu-run "$RUN_DIR/Launcher.exe"
fi
