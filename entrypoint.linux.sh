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
STEAMCMD_DIR="${STEAMCMD_DIR:-${STEAM_ROOT}/steamcmd}"
STEAM_LIBRARY="${STEAM_LIBRARY:-${STEAM_ROOT}/steamlibrary}"
HOME="${HOME:-${STEAM_ROOT}/home}"
LOCK_DIR="${STEAM_ROOT}/locks"
SERVER_DIR_NAME="${SERVER_DIR_NAME:?请设置 SERVER_DIR_NAME，例如 SERVER_DIR_NAME=valheim}"
INSTALL_DIR="${STEAM_LIBRARY}/steamapps/common/${SERVER_DIR_NAME}"
LOG_DIR="${STEAM_ROOT}/logs/${SERVER_DIR_NAME}"
STEAM_LOCK="${LOCK_DIR}/steamcmd.lock"

STEAM_LOGIN="${STEAM_LOGIN:-anonymous}"
UPDATE_ON_START="${UPDATE_ON_START:-1}"
VALIDATE="${VALIDATE:-0}"
RESTART_ON_CRASH="${RESTART_ON_CRASH:-0}"
RESTART_DELAY="${RESTART_DELAY:-10}"

validate_server_dir_name() {
  if ! [[ "$SERVER_DIR_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
    fail "SERVER_DIR_NAME 只能包含英文、数字、点、下划线、中划线，当前值：${SERVER_DIR_NAME}"
  fi
}

prepare_dirs_as_root() {
  mkdir -p \
    "$STEAMCMD_DIR" \
    "$STEAM_LIBRARY/steamapps/common" \
    "$INSTALL_DIR" \
    "$HOME" \
    "$HOME/.steam/sdk32" \
    "$HOME/.steam/sdk64" \
    "$LOG_DIR" \
    "$LOCK_DIR"

  chown -R steam:steam \
    "$STEAMCMD_DIR" \
    "$INSTALL_DIR" \
    "$HOME" \
    "$LOG_DIR" \
    "$LOCK_DIR"
}

if [[ "$(id -u)" = "0" ]]; then
  validate_server_dir_name
  prepare_dirs_as_root
  exec gosu steam "$0" "$@"
fi

validate_server_dir_name

STEAMCMD="${STEAMCMD_DIR}/steamcmd.sh"

install_steamcmd_if_needed() {
  {
    flock -x 200

    if [[ ! -x "$STEAMCMD" ]]; then
      log "未检测到 SteamCMD，开始安装到：${STEAMCMD_DIR}"

      mkdir -p "$STEAMCMD_DIR"

      curl -fsSL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
        | tar -xz -C "$STEAMCMD_DIR"

      chmod +x "$STEAMCMD"
    fi

    log "初始化 SteamCMD"
    "$STEAMCMD" +quit || true

    mkdir -p "$HOME/.steam/sdk32" "$HOME/.steam/sdk64"

    if [[ -f "$STEAMCMD_DIR/linux32/steamclient.so" ]]; then
      ln -sf "$STEAMCMD_DIR/linux32/steamclient.so" "$HOME/.steam/sdk32/steamclient.so"
    fi

    if [[ -f "$STEAMCMD_DIR/linux64/steamclient.so" ]]; then
      ln -sf "$STEAMCMD_DIR/linux64/steamclient.so" "$HOME/.steam/sdk64/steamclient.so"
    fi

  } 200>"$STEAM_LOCK"
}

write_steamcmd_script() {
  local script_file="$1"

  {
    echo "@ShutdownOnFailedCommand 1"
    echo "@NoPromptForPassword 1"

    if [[ -n "${STEAMCMD_FORCE_PLATFORM:-}" ]]; then
      echo "@sSteamCmdForcePlatformType ${STEAMCMD_FORCE_PLATFORM}"
    fi

    echo "force_install_dir ${INSTALL_DIR}"

    if [[ "${STEAM_LOGIN}" == "anonymous" && -z "${STEAM_USERNAME:-}" ]]; then
      echo "login anonymous"
    else
      local username="${STEAM_USERNAME:-$STEAM_LOGIN}"

      if [[ -n "${STEAM_PASSWORD:-}" ]]; then
        echo "login \"${username}\" \"${STEAM_PASSWORD}\""
      else
        echo "login \"${username}\""
      fi
    fi

    local app_update_cmd="app_update ${STEAM_APP_ID}"

    if [[ -n "${STEAM_BETA:-}" ]]; then
      app_update_cmd="${app_update_cmd} -beta ${STEAM_BETA}"
    fi

    if [[ -n "${STEAM_BETA_PASSWORD:-}" ]]; then
      app_update_cmd="${app_update_cmd} -betapassword ${STEAM_BETA_PASSWORD}"
    fi

    if [[ -n "${APP_UPDATE_EXTRA:-}" ]]; then
      app_update_cmd="${app_update_cmd} ${APP_UPDATE_EXTRA}"
    fi

    if is_true "$VALIDATE"; then
      app_update_cmd="${app_update_cmd} validate"
    fi

    echo "${app_update_cmd}"
    echo "quit"
  } > "$script_file"

  chmod 600 "$script_file"
}

update_server() {
  [[ -n "${STEAM_APP_ID:-}" ]] || fail "请设置 STEAM_APP_ID"

  mkdir -p "$INSTALL_DIR"

  local script_file
  script_file="$(mktemp /tmp/steamcmd.XXXXXX)"

  write_steamcmd_script "$script_file"

  {
    flock -x 200

    log "开始安装/更新 Linux 服务端"
    log "AppID=${STEAM_APP_ID}"
    log "安装目录=${INSTALL_DIR}"

    "$STEAMCMD" +runscript "$script_file"

    log "服务端更新完成：${INSTALL_DIR}"

  } 200>"$STEAM_LOCK"

  rm -f "$script_file"
}

start_server_once() {
  cd "$INSTALL_DIR"

  if [[ -n "${PRE_START:-}" ]]; then
    log "执行 PRE_START"
    bash -lc "$PRE_START"
  fi

  if [[ "$#" -gt 0 ]]; then
    log "使用 docker command 启动服务端：$*"
    "$@"
    return $?
  fi

  [[ -n "${SERVER_COMMAND:-}" ]] || fail "请设置 SERVER_COMMAND，或者在 docker compose command 中指定启动命令"

  log "当前工作目录：$(pwd)"
  log "启动命令：${SERVER_COMMAND}"

  bash -lc "$SERVER_COMMAND"
}

start_server() {
  if is_true "$RESTART_ON_CRASH"; then
    while true; do
      start_server_once "$@"
      code=$?
      log "服务端退出，退出码=${code}，${RESTART_DELAY} 秒后重启"
      sleep "$RESTART_DELAY"
    done
  else
    start_server_once "$@"
  fi
}

log "SERVER_DIR_NAME=${SERVER_DIR_NAME}"
log "INSTALL_DIR=${INSTALL_DIR}"

install_steamcmd_if_needed

if is_true "$UPDATE_ON_START"; then
  update_server
else
  log "跳过 SteamCMD 更新，因为 UPDATE_ON_START=${UPDATE_ON_START}"
fi

start_server "$@"
