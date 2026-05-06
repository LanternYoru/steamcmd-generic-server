#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

APP_USER="${APP_USER:-steam}"
APP_GROUP="${APP_GROUP:-steam}"
APP_HOME="${APP_HOME:-/home/steam}"

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

STEAM_ROOT="${STEAM_ROOT:-/steam}"
STEAMCMD_DIR="${STEAMCMD_DIR:-/home/steam/steamcmd}"
STEAM_LIBRARY="${STEAM_LIBRARY:-${STEAM_ROOT}/steamlibrary}"

SERVER_DIR_NAME="${SERVER_DIR_NAME:?请设置 SERVER_DIR_NAME，例如 SERVER_DIR_NAME=palserver}"

INSTALL_DIR="${STEAM_LIBRARY}/steamapps/common/${SERVER_DIR_NAME}"
WINEPREFIX="${STEAM_ROOT}/wineprefixes/${SERVER_DIR_NAME}"
PROTON_COMPAT_DATA_PATH="${STEAM_ROOT}/protonprefixes/${SERVER_DIR_NAME}"
LOG_DIR="${STEAM_ROOT}/logs/${SERVER_DIR_NAME}"

validate_server_dir_name() {
  if ! [[ "$SERVER_DIR_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
    fail "SERVER_DIR_NAME 只能包含英文、数字、点、下划线、中划线，当前值：${SERVER_DIR_NAME}"
  fi
}

if [[ "${EUID}" -ne 0 ]]; then
  fail "Windows 模板需要容器以 root 启动，然后 entrypoint 会切换到 steam 用户"
fi

validate_server_dir_name

if [[ "$PUID" -eq 0 ]] || [[ "$PGID" -eq 0 ]]; then
  fail "不建议把 PUID/PGID 设置为 0，请使用普通用户，例如 PUID=1000 PGID=1000"
fi

CURRENT_UID="$(id -u "$APP_USER")"
CURRENT_GID="$(id -g "$APP_USER")"

if [[ "$CURRENT_GID" -ne "$PGID" ]]; then
  log "修改 ${APP_GROUP} 组 GID：${CURRENT_GID} -> ${PGID}"
  groupmod -o -g "$PGID" "$APP_GROUP"
fi

if [[ "$CURRENT_UID" -ne "$PUID" ]]; then
  log "修改 ${APP_USER} 用户 UID：${CURRENT_UID} -> ${PUID}"
  usermod -o -u "$PUID" -g "$PGID" "$APP_USER"
fi

mkdir -p \
  "$APP_HOME" \
  "$STEAMCMD_DIR" \
  "$STEAM_LIBRARY/steamapps/common" \
  "$INSTALL_DIR" \
  "$WINEPREFIX" \
  "$PROTON_COMPAT_DATA_PATH" \
  "$LOG_DIR"

log "修正目录所有者为 ${APP_USER}:${APP_GROUP}"

chown -R "$APP_USER:$APP_GROUP" \
  "$APP_HOME" \
  "$STEAMCMD_DIR" \
  "$INSTALL_DIR" \
  "$WINEPREFIX" \
  "$PROTON_COMPAT_DATA_PATH" \
  "$LOG_DIR"

log "当前 steam 用户信息：$(id "$APP_USER")"
log "SERVER_DIR_NAME=${SERVER_DIR_NAME}"
log "INSTALL_DIR=${INSTALL_DIR}"
log "WINEPREFIX=${WINEPREFIX}"
log "STEAMCMD_DIR=${STEAMCMD_DIR}"

exec gosu "$APP_USER:$APP_GROUP" "$@"
