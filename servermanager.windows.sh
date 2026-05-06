#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

is_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

STEAM_ROOT="${STEAM_ROOT:-/steam}"
STEAMCMD_DIR="${STEAMCMD_DIR:-/home/steam/steamcmd}"
STEAM_LIBRARY="${STEAM_LIBRARY:-${STEAM_ROOT}/steamlibrary}"
HOME="${HOME:-/home/steam}"

SERVER_DIR_NAME="${SERVER_DIR_NAME:?请设置 SERVER_DIR_NAME，例如 SERVER_DIR_NAME=palserver}"

INSTALL_DIR="${STEAM_LIBRARY}/steamapps/common/${SERVER_DIR_NAME}"
WINEPREFIX="${STEAM_ROOT}/wineprefixes/${SERVER_DIR_NAME}"
PROTON_COMPAT_DATA_PATH="${STEAM_ROOT}/protonprefixes/${SERVER_DIR_NAME}"
LOG_DIR="${STEAM_ROOT}/logs/${SERVER_DIR_NAME}"

WINEARCH="${WINEARCH:-win64}"
WINEDEBUG="${WINEDEBUG:--all}"
DISPLAY="${DISPLAY:-:99}"

STEAM_LOGIN="${STEAM_LOGIN:-anonymous}"
STEAMCMD_FORCE_PLATFORM="${STEAMCMD_FORCE_PLATFORM:-windows}"
UPDATE_ON_START="${UPDATE_ON_START:-1}"
VALIDATE="${VALIDATE:-0}"

COMPAT_LAYER="${COMPAT_LAYER:-wine}"
WINE_USE_XVFB="${WINE_USE_XVFB:-1}"

RESTART_ON_CRASH="${RESTART_ON_CRASH:-1}"
RESTART_DELAY="${RESTART_DELAY:-10}"

TAIL_LOG_ON_START="${TAIL_LOG_ON_START:-0}"
TAIL_LOG_PATH="${TAIL_LOG_PATH:-}"
TAIL_LOG_LINES="${TAIL_LOG_LINES:-80}"

export HOME
export USER=steam
export LOGNAME=steam
export LANG="${LANG:-en_US.UTF-8}"
export LANGUAGE="${LANGUAGE:-en_US:en}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

export WINEPREFIX
export WINEARCH
export WINEDEBUG
export DISPLAY

STEAMCMD="${STEAMCMD_DIR}/steamcmd.sh"

dump_steamcmd_logs() {
  log "输出 SteamCMD 日志"

  echo "========== id =========="
  id || true

  echo "========== env =========="
  echo "HOME=${HOME}"
  echo "USER=${USER}"
  echo "LOGNAME=${LOGNAME}"
  echo "STEAMCMD_DIR=${STEAMCMD_DIR}"
  echo "INSTALL_DIR=${INSTALL_DIR}"

  echo "========== stderr.txt =========="
  if [[ -f "${HOME}/Steam/logs/stderr.txt" ]]; then
    cat "${HOME}/Steam/logs/stderr.txt" || true
  else
    echo "不存在：${HOME}/Steam/logs/stderr.txt"
  fi

  echo "========== content_log.txt =========="
  if [[ -f "${HOME}/Steam/logs/content_log.txt" ]]; then
    tail -n 300 "${HOME}/Steam/logs/content_log.txt" || true
  else
    echo "不存在：${HOME}/Steam/logs/content_log.txt"
  fi

  echo "========== appinfo_log.txt =========="
  if [[ -f "${HOME}/Steam/logs/appinfo_log.txt" ]]; then
    tail -n 300 "${HOME}/Steam/logs/appinfo_log.txt" || true
  else
    echo "不存在：${HOME}/Steam/logs/appinfo_log.txt"
  fi
}

ensure_dirs() {
  mkdir -p \
    "$STEAMCMD_DIR" \
    "$STEAM_LIBRARY/steamapps/common" \
    "$INSTALL_DIR" \
    "$WINEPREFIX" \
    "$PROTON_COMPAT_DATA_PATH" \
    "$LOG_DIR" \
    "$HOME/.steam/sdk32" \
    "$HOME/.steam/sdk64"
}

install_steamcmd_if_needed() {
  if [[ ! -x "$STEAMCMD" ]]; then
    log "未检测到 SteamCMD，开始安装到 ${STEAMCMD_DIR}"

    curl -fsSL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
      | tar -xz -C "$STEAMCMD_DIR"

    chmod +x "$STEAMCMD"
  else
    log "检测到已有 SteamCMD：${STEAMCMD}"
  fi

  if [[ -f "$STEAMCMD_DIR/linux32/steamclient.so" ]]; then
    ln -sf "$STEAMCMD_DIR/linux32/steamclient.so" "$HOME/.steam/sdk32/steamclient.so"
  fi

  if [[ -f "$STEAMCMD_DIR/linux64/steamclient.so" ]]; then
    ln -sf "$STEAMCMD_DIR/linux64/steamclient.so" "$HOME/.steam/sdk64/steamclient.so"
  fi
}

build_steamcmd_command() {
  STEAMCMD_UPDATE_CMD=()

  STEAMCMD_UPDATE_CMD+=("$STEAMCMD")
  STEAMCMD_UPDATE_CMD+=("+@ShutdownOnFailedCommand" "1")
  STEAMCMD_UPDATE_CMD+=("+@NoPromptForPassword" "1")

  if [[ -n "${STEAMCMD_FORCE_PLATFORM:-}" ]]; then
    STEAMCMD_UPDATE_CMD+=("+@sSteamCmdForcePlatformType" "$STEAMCMD_FORCE_PLATFORM")
  fi

  STEAMCMD_UPDATE_CMD+=("+force_install_dir" "$INSTALL_DIR")

  if [[ "$STEAM_LOGIN" == "anonymous" && -z "${STEAM_USERNAME:-}" ]]; then
    STEAMCMD_UPDATE_CMD+=("+login" "anonymous")
  else
    local username="${STEAM_USERNAME:-$STEAM_LOGIN}"

    if [[ -n "${STEAM_PASSWORD:-}" ]]; then
      STEAMCMD_UPDATE_CMD+=("+login" "$username" "$STEAM_PASSWORD")
    else
      STEAMCMD_UPDATE_CMD+=("+login" "$username")
    fi
  fi

  STEAMCMD_UPDATE_CMD+=("+app_update" "$STEAM_APP_ID")

  if [[ -n "${STEAM_BETA:-}" ]]; then
    STEAMCMD_UPDATE_CMD+=("-beta" "$STEAM_BETA")
  fi

  if [[ -n "${STEAM_BETA_PASSWORD:-}" ]]; then
    STEAMCMD_UPDATE_CMD+=("-betapassword" "$STEAM_BETA_PASSWORD")
  fi

  if [[ -n "${APP_UPDATE_EXTRA:-}" ]]; then
    read -r -a extra_args <<< "$APP_UPDATE_EXTRA"
    STEAMCMD_UPDATE_CMD+=("${extra_args[@]}")
  fi

  if is_true "$VALIDATE"; then
    STEAMCMD_UPDATE_CMD+=("validate")
  fi

  STEAMCMD_UPDATE_CMD+=("+quit")
}

update_server() {
  [[ -n "${STEAM_APP_ID:-}" ]] || fail "请设置 STEAM_APP_ID"

  mkdir -p "$INSTALL_DIR" "$LOG_DIR"

  build_steamcmd_command

  {
    echo "========== SteamCMD update command =========="
    printf '%q ' "${STEAMCMD_UPDATE_CMD[@]}"
    echo
    echo
    echo "STEAM_APP_ID=${STEAM_APP_ID}"
    echo "STEAMCMD_FORCE_PLATFORM=${STEAMCMD_FORCE_PLATFORM}"
    echo "INSTALL_DIR=${INSTALL_DIR}"
    echo "VALIDATE=${VALIDATE}"
  } > "${LOG_DIR}/steamcmd-update-command.txt"

  log "开始安装/更新 Windows 服务端"
  log "AppID=${STEAM_APP_ID}"
  log "安装目录=${INSTALL_DIR}"
  log "强制平台=${STEAMCMD_FORCE_PLATFORM}"
  log "执行 SteamCMD 命令："
  printf '%q ' "${STEAMCMD_UPDATE_CMD[@]}"
  echo

  set +e
  "${STEAMCMD_UPDATE_CMD[@]}"
  local code=$?
  set -e

  if [[ "$code" -ne 0 ]]; then
    log "SteamCMD 更新失败，退出码=${code}"
    dump_steamcmd_logs
    exit "$code"
  fi

  log "Windows 服务端更新完成"
}

start_xvfb_if_needed() {
  if is_true "$WINE_USE_XVFB"; then
    if ! pgrep -x Xvfb >/dev/null 2>&1; then
      log "启动 Xvfb，DISPLAY=${DISPLAY}"
      Xvfb "$DISPLAY" -screen 0 1024x768x16 >"${LOG_DIR}/xvfb.log" 2>&1 &
      sleep 2
    fi
  fi
}

init_wineprefix_if_needed() {
  if [[ "$COMPAT_LAYER" != "wine" ]]; then
    return 0
  fi

  if [[ ! -f "${WINEPREFIX}/system.reg" ]]; then
    log "初始化 Wine 环境：${WINEPREFIX}"

    set +e
    wineboot --init
    local code=$?
    set -e

    if [[ "$code" -ne 0 ]]; then
      log "Wine 初始化失败，退出码=${code}"
      exit "$code"
    fi

    sleep 3
  else
    log "检测到已有 Wine 环境，跳过初始化"
  fi
}

resolve_tail_log_path() {
  if [[ -z "$TAIL_LOG_PATH" ]]; then
    return 1
  fi

  if [[ "$TAIL_LOG_PATH" = /* ]]; then
    echo "$TAIL_LOG_PATH"
  else
    echo "${INSTALL_DIR}/${TAIL_LOG_PATH}"
  fi
}

tail_log_while_process_running() {
  local server_pid="$1"
  local log_file="$2"

  mkdir -p "$(dirname "$log_file")"
  touch "$log_file"

  log "开始跟踪日志文件：${log_file}"

  tail -n "$TAIL_LOG_LINES" -F "$log_file" &
  local tail_pid=$!

  trap 'kill "$tail_pid" "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; exit 143' TERM INT

  wait "$server_pid"
  local code=$?

  kill "$tail_pid" 2>/dev/null || true
  wait "$tail_pid" 2>/dev/null || true

  return "$code"
}

run_with_wine() {
  cd "$INSTALL_DIR"

  if [[ -n "${SERVER_COMMAND:-}" ]]; then
    log "使用自定义 SERVER_COMMAND 启动：${SERVER_COMMAND}"

    if is_true "$TAIL_LOG_ON_START" && [[ -n "$TAIL_LOG_PATH" ]]; then
      local log_file
      log_file="$(resolve_tail_log_path)"

      set +e
      bash -lc "$SERVER_COMMAND" &
      local server_pid=$!

      tail_log_while_process_running "$server_pid" "$log_file"
      local code=$?
      set -e

      return "$code"
    else
      bash -lc "$SERVER_COMMAND"
      return $?
    fi
  fi

  [[ -n "${WIN_SERVER_EXE:-}" ]] || fail "请设置 WIN_SERVER_EXE，例如 WIN_SERVER_EXE=DedicatedServer.exe"

  local exe_path="${INSTALL_DIR}/${WIN_SERVER_EXE}"

  [[ -f "$exe_path" ]] || fail "找不到 Windows 服务端程序：${exe_path}"

  log "当前工作目录：$(pwd)"
  log "使用 Wine 启动：${WIN_SERVER_EXE} ${WIN_SERVER_ARGS:-}"

  if is_true "$TAIL_LOG_ON_START" && [[ -n "$TAIL_LOG_PATH" ]]; then
    local log_file
    log_file="$(resolve_tail_log_path)"

    set +e
    wine "$exe_path" ${WIN_SERVER_ARGS:-} &
    local server_pid=$!

    tail_log_while_process_running "$server_pid" "$log_file"
    local code=$?
    set -e

    return "$code"
  else
    set +e
    wine "$exe_path" ${WIN_SERVER_ARGS:-}
    local code=$?
    set -e

    return "$code"
  fi
}

run_with_proton() {
  cd "$INSTALL_DIR"

  [[ -n "${PROTON_DIR:-}" ]] || fail "使用 Proton 时必须设置 PROTON_DIR，例如 PROTON_DIR=/proton/GE-Proton"
  [[ -x "${PROTON_DIR}/proton" ]] || fail "找不到 Proton 启动脚本：${PROTON_DIR}/proton"
  [[ -n "${WIN_SERVER_EXE:-}" ]] || fail "请设置 WIN_SERVER_EXE，例如 WIN_SERVER_EXE=DedicatedServer.exe"

  local exe_path="${INSTALL_DIR}/${WIN_SERVER_EXE}"

  [[ -f "$exe_path" ]] || fail "找不到 Windows 服务端程序：${exe_path}"

  mkdir -p "$PROTON_COMPAT_DATA_PATH"

  log "当前工作目录：$(pwd)"
  log "使用 Proton 启动：${WIN_SERVER_EXE} ${WIN_SERVER_ARGS:-}"

  if is_true "$TAIL_LOG_ON_START" && [[ -n "$TAIL_LOG_PATH" ]]; then
    local log_file
    log_file="$(resolve_tail_log_path)"

    set +e
    STEAM_COMPAT_DATA_PATH="$PROTON_COMPAT_DATA_PATH" \
    STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAMCMD_DIR" \
    "${PROTON_DIR}/proton" run "$exe_path" ${WIN_SERVER_ARGS:-} &
    local server_pid=$!

    tail_log_while_process_running "$server_pid" "$log_file"
    local code=$?
    set -e

    return "$code"
  else
    set +e
    STEAM_COMPAT_DATA_PATH="$PROTON_COMPAT_DATA_PATH" \
    STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAMCMD_DIR" \
    "${PROTON_DIR}/proton" run "$exe_path" ${WIN_SERVER_ARGS:-}
    local code=$?
    set -e

    return "$code"
  fi
}

start_server_once() {
  if [[ -n "${PRE_START:-}" ]]; then
    log "执行 PRE_START：${PRE_START}"
    bash -lc "$PRE_START"
  fi

  case "$COMPAT_LAYER" in
    wine)
      run_with_wine
      ;;
    proton)
      run_with_proton
      ;;
    *)
      fail "未知 COMPAT_LAYER=${COMPAT_LAYER}，只能是 wine 或 proton"
      ;;
  esac
}

start_server() {
  if is_true "$RESTART_ON_CRASH"; then
    while true; do
      start_server_once
      local code=$?
      log "服务端退出，退出码=${code}，${RESTART_DELAY} 秒后重启"
      sleep "$RESTART_DELAY"
    done
  else
    start_server_once
  fi
}

log "SERVER_DIR_NAME=${SERVER_DIR_NAME}"
log "INSTALL_DIR=${INSTALL_DIR}"
log "WINEPREFIX=${WINEPREFIX}"
log "COMPAT_LAYER=${COMPAT_LAYER}"
log "HOME=${HOME}"
log "运行用户：$(id)"

ensure_dirs
install_steamcmd_if_needed

if is_true "$UPDATE_ON_START"; then
  update_server
else
  log "跳过 SteamCMD 更新，因为 UPDATE_ON_START=${UPDATE_ON_START}"
fi

start_xvfb_if_needed
init_wineprefix_if_needed
start_server
