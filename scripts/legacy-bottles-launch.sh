#!/usr/bin/env bash
# =============================================================================
# rdr2-launch.sh  —  Red Dead Redemption 2 (Razor1911 crack) 一键启动器
#
# 原理：RDR2 的 ERR_NO_LAUNCHER 判定 = 「spawn 它的父进程映像名必须是
# Launcher.exe」。本脚本把自制 shim 命名为 Launcher.exe，由它建
# \\.\pipe\RDR2Launcher_Pipe、spawn RDR2.exe、完成 INIT:/TINI:launcher: 握手，
# 从而跳过 Razor1911 的开场 cracktro（cracktro 会需要 Wine 缺失的 DirectComposition，
# 跑不通），也不再弹 ERR_NO_LAUNCHER。再用 gamescope 提供正常的全屏渲染表面。
#
# 用法：
#   ./rdr2-launch.sh                      # 默认 1280x720 全屏(gamescope)
#   ./rdr2-launch.sh -W 2560 -H 1440      # 自定义分辨率
#   RDR2_WINDOWED=1 ./rdr2-launch.sh      # 不进 gamescope，直接窗口跑
# =============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- 可改配置 ----------
GAME_DIR="/run/media/HDD2T01/Games/PCGames/Red Dead Redemption 2"
BOTTLE="demo"
BOTTLE_DIR="$HOME/.local/share/bottles/bottles/$BOTTLE"
PROTON_DIR="${PROTON_DIR:-$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton11-12}"
WINE="$PROTON_DIR/files/bin/wine"
if [ -n "${RDR2_NO_RUNNER:-}" ]; then RUNNER="";
else RUNNER="${RUNNER:-$HOME/.local/share/Steam/steamapps/common/SteamLinuxRuntime_4/_v2-entry-point}"; fi
SHIM="$HERE/Launcher.exe"
# -----------------------------

GW=1280; GH=720
ARGS=("$@")
for ((i=0;i<${#ARGS[@]};i++)); do
  case "${ARGS[i]}" in
    -W) GW="${ARGS[i+1]}";;
    -H) GH="${ARGS[i+1]}";;
  esac
done

die(){ echo "错误: $*" >&2; exit 1; }

# ---------- 前置检查 ----------
[ -d "$GAME_DIR" ]           || die "游戏目录不存在: $GAME_DIR"
[ -x "$WINE" ]               || die "找不到 wine: $WINE"
[ -f "$GAME_DIR/RDR2.exe" ]  || die "找不到 $GAME_DIR/RDR2.exe"
[ -f "$SHIM" ]               || die "找不到 shim: $SHIM"

DRIVE_C="$BOTTLE_DIR/drive_c"
SYS32="$DRIVE_C/windows/system32"

# ---------- 1) 确保 nvapi64.dll 已装（否则 RDR2 NVAPI 空转死循环）----------
if [ ! -f "$SYS32/nvapi64.dll" ]; then
  NV_SRC="$PROTON_DIR/files/lib/wine/nvapi/x86_64-windows/nvapi64.dll"
  [ -f "$NV_SRC" ] && cp "$NV_SRC" "$SYS32/nvapi64.dll" && echo "[+] 已安装 nvapi64.dll"
fi

# ---------- 2) 在 bottle drive_c 下准备独立运行目录（不污染游戏目录）----------
RUN_DIR="$DRIVE_C/rdr2run"
mkdir -p "$RUN_DIR"
cp "$SHIM" "$RUN_DIR/Launcher.exe"

# shim 通过自身同目录的 rdr2path.txt 读取 RDR2.exe 的绝对路径（Windows 路径）。
# 把 Z: 盘映射的绝对路径写进去，这样 Launcher.exe 无需与 RDR2.exe 同目录。
GAME_DIR_WIN="Z:$(printf '%s' "$GAME_DIR" | tr '/' '\\')"
RDR2_WIN="$GAME_DIR_WIN\\RDR2.exe"
printf '%s\r\n' "$RDR2_WIN" > "$RUN_DIR/rdr2path.txt"

LAUNCH_EXE_WIN="Z:$(printf '%s' "$RUN_DIR/Launcher.exe" | tr '/' '\\')"

echo "[*] RDR2 一键启动"
echo "    游戏:      $GAME_DIR"
echo "    shim:      $RUN_DIR/Launcher.exe  ->  $RDR2_WIN"
echo "    握手日志:  $RUN_DIR/rdr2shim.log"

# ---------- 3) 组装 GE-Proton/bottle 的 wine 运行环境 ----------
export BOTTLE
export WINEPREFIX="$BOTTLE_DIR"
export WINEARCH=win64
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="winemenubuilder="
export WINE_LARGE_ADDRESS_AWARE=1
export STAGING_SHARED_MEMORY=1
export WINEFSYNC=1
export PROTON_NO_NTSYNC=1
export DXVK_SHADER_CACHE_PATH="$BOTTLE_DIR/cache/dxvk_shader"
export VKD3D_SHADER_CACHE_PATH="$BOTTLE_DIR/cache/vkd3d_shader"
export __GL_SHADER_DISK_CACHE=1
export __GL_SHADER_DISK_CACHE_PATH="$BOTTLE_DIR/cache/gl_shader"
export MESA_SHADER_CACHE_DIR="$BOTTLE_DIR/cache/mesa_shader"
export DISABLE_LFX=1
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json
export LD_LIBRARY_PATH="$PROTON_DIR/files/lib:$PROTON_DIR/files/lib64:$PROTON_DIR/files/lib/wine/x86_64-unix:$PROTON_DIR/files/lib/wine/i386-unix"
export DISPLAY="${DISPLAY:-:0}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
mkdir -p "$BOTTLE_DIR/cache"

# ---------- 4) 启动 ----------
if [ -n "${RDR2_WINDOWED:-}" ] || ! command -v gamescope >/dev/null 2>&1; then
  echo "[*] 直接运行（无 gamescope）"
  if [ -x "$RUNNER" ]; then exec "$RUNNER" -- "$WINE" "$LAUNCH_EXE_WIN"
  else exec "$WINE" "$LAUNCH_EXE_WIN"; fi
else
  echo "[*] gamescope 全屏 ${GW}x${GH}"
  if [ -x "$RUNNER" ]; then
    exec gamescope -W "$GW" -H "$GH" -f -- "$RUNNER" -- "$WINE" "$LAUNCH_EXE_WIN"
  else
    exec gamescope -W "$GW" -H "$GH" -f -- "$WINE" "$LAUNCH_EXE_WIN"
  fi
fi
