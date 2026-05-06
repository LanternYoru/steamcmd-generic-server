# steamcmd-generic-server

# 适用于steam游戏服务端容器化部署的通用模板 


## 部署教程

本项目用于通过 Docker 部署 SteamCMD 游戏服务端。

支持两种类型：

1. **Linux 原生服务端**
   - 适用于游戏官方提供 Linux Dedicated Server 的情况
   - 例如：Unturned Dedicated Server

2. **Windows 服务端 + Wine**
   - 适用于游戏只提供 Windows Dedicated Server，但希望部署在 Linux 服务器上的情况
   - 例如：Counter-Strike: Source Windows Dedicated Server 测试环境

---

## 1. 项目文件说明

项目目录通常包含以下文件：

```text
.
├─ Dockerfile.linux
├─ Dockerfile.windows
├─ entrypoint.linux.sh
├─ entrypoint.windows.sh
├─ servermanager.windows.sh
├─ docker-compose.linux.yml
├─ docker-compose.windows.yml
├─ game.linux.env
└─ game.windows.env
````

其中：

```text
Dockerfile.linux
    Linux 原生服务端镜像构建文件

Dockerfile.windows
    Windows 服务端 + Wine 镜像构建文件

docker-compose.linux.yml
    Linux 服务端启动配置

docker-compose.windows.yml
    Windows + Wine 服务端启动配置

game.linux.env
    Linux 服务端参数配置

game.windows.env
    Windows 服务端参数配置
```

---

# 一、Linux 原生服务端部署

## 2. Linux 服务端目录结构

Linux 服务端统一使用宿主机目录：

```bash
/steam-linux
```

首次使用前创建目录：

```bash
mkdir -p /steam-linux/steamcmd
mkdir -p /steam-linux/steamlibrary/steamapps/common
mkdir -p /steam-linux/home
mkdir -p /steam-linux/logs
mkdir -p /steam-linux/locks
```

运行后目录类似：

```text
/steam-linux/
├─ steamcmd/
├─ steamlibrary/
│  └─ steamapps/
│     └─ common/
│        └─ U3DS/
├─ home/
│  └─ U3DS/
├─ logs/
│  └─ U3DS/
└─ locks/
```

其中：

```text
/steam-linux/steamcmd
    保存 SteamCMD 本体

/steam-linux/steamlibrary/steamapps/common/<SERVER_DIR_NAME>
    保存具体游戏服务端文件

/steam-linux/home/<SERVER_DIR_NAME>
    保存 steam 用户运行数据

/steam-linux/logs/<SERVER_DIR_NAME>
    保存日志

/steam-linux/locks
    保存 SteamCMD 锁文件，避免多个容器同时更新冲突
```

---

## 3. Linux 服务端配置文件 game.linux.env

编辑：

```bash
nano game.linux.env
```

通用模板：

```env
# 每个服务端单独一个目录名
SERVER_DIR_NAME=my-linux-server

# Steam Dedicated Server AppID
STEAM_APP_ID=你的Linux服务端AppID

# 大多数服务端可以 anonymous
STEAM_LOGIN=anonymous
# STEAM_USERNAME=
# STEAM_PASSWORD=

# 启动时自动更新
UPDATE_ON_START=1

# 是否 validate，1 更稳但更慢
VALIDATE=0

# Linux 原生服务端启动命令
# 该命令会在 /steam/steamlibrary/steamapps/common/${SERVER_DIR_NAME} 内执行
SERVER_COMMAND='./start.sh'

# 崩溃后自动重启
RESTART_ON_CRASH=1
RESTART_DELAY=10

# 可选：启动前执行命令
# PRE_START='chmod +x ./start.sh'

# 可选：beta 分支
# STEAM_BETA=public
# STEAM_BETA_PASSWORD=

# 可选：额外 app_update 参数
# APP_UPDATE_EXTRA=
```

---

## 4. Linux 示例：Unturned Dedicated Server

如果要部署 Unturned Dedicated Server，可以使用下面这个示例：

```env
SERVER_DIR_NAME=U3DS

STEAM_APP_ID=1110390

STEAM_LOGIN=anonymous

UPDATE_ON_START=1
VALIDATE=0

SERVER_COMMAND='./ServerHelper.sh +LanServer testserver'

RESTART_ON_CRASH=1
RESTART_DELAY=10
```

说明：

```text
SERVER_DIR_NAME=U3DS
    服务端文件会保存到：
    /steam-linux/steamlibrary/steamapps/common/U3DS

STEAM_APP_ID=1110390
    Unturned Dedicated Server 的 SteamCMD AppID

SERVER_COMMAND='./ServerHelper.sh +LanServer testserver'
    启动 Unturned 的 LAN Server，服务器名为 testserver
```

---

## 5. Linux 服务端 docker-compose.linux.yml

Linux compose 示例：

```yaml
services:
  steam-linux-server:
    build:
      context: .
      dockerfile: Dockerfile.linux
      args:
        EXTRA_APT_PACKAGES: ""
    restart: unless-stopped

    env_file:
      - game.linux.env

    volumes:
      - "/steam-linux/steamcmd:/steam/steamcmd"
      - "/steam-linux/steamlibrary/steamapps/common/${SERVER_DIR_NAME:?SERVER_DIR_NAME is required}:/steam/steamlibrary/steamapps/common/${SERVER_DIR_NAME}"
      - "/steam-linux/home/${SERVER_DIR_NAME}:/steam/home"
      - "/steam-linux/logs/${SERVER_DIR_NAME}:/steam/logs/${SERVER_DIR_NAME}"
      - "/steam-linux/locks:/steam/locks"

    ports:
      - "27015:27015/udp"
      - "27016:27016/udp"

    stdin_open: true
    tty: true

    ulimits:
      nofile:
        soft: 100000
        hard: 100000
```

如果你的游戏端口不是 `27015/27016`，需要修改 `ports`。

例如游戏使用 `28015/udp`：

```yaml
ports:
  - "28015:28015/udp"
```

如果游戏需要多个端口，就继续添加：

```yaml
ports:
  - "27015:27015/udp"
  - "27016:27016/udp"
  - "27017:27017/tcp"
```

---

## 6. 构建 Linux 服务端镜像

首次构建：

```bash
docker compose --env-file game.linux.env -f docker-compose.linux.yml build --no-cache
```

如果没有修改 Dockerfile，以后一般不用每次都重新 build。

---

## 7. 启动 Linux 服务端

前台启动，适合测试：

```bash
docker compose --env-file game.linux.env -f docker-compose.linux.yml up --force-recreate
```

后台启动，适合正式运行：

```bash
docker compose --env-file game.linux.env -f docker-compose.linux.yml up -d
```

查看日志：

```bash
docker compose --env-file game.linux.env -f docker-compose.linux.yml logs -f
```

停止服务端：

```bash
docker compose --env-file game.linux.env -f docker-compose.linux.yml down
```

---

## 8. 查看 Linux 服务端文件

以 Unturned 为例：

```bash
ls -lah /steam-linux/steamlibrary/steamapps/common/U3DS
```

查看日志目录：

```bash
ls -lah /steam-linux/logs/U3DS
```

如果需要进入容器：

```bash
docker exec -it <容器名> bash
```

查看当前容器名：

```bash
docker ps
```

---

# 二、Windows 服务端 + Wine 部署

## 9. Windows 服务端目录结构

Windows 服务端统一使用宿主机目录：

```bash
/steam-windows
```

首次使用前创建目录：

```bash
mkdir -p /steam-windows/steamcmd
mkdir -p /steam-windows/home
mkdir -p /steam-windows/steamlibrary/steamapps/common
mkdir -p /steam-windows/wineprefixes
mkdir -p /steam-windows/protonprefixes
mkdir -p /steam-windows/logs
```

运行后目录类似：

```text
/steam-windows/
├─ steamcmd/
├─ home/
│  └─ Counter-Strike/
├─ steamlibrary/
│  └─ steamapps/
│     └─ common/
│        └─ Counter-Strike/
├─ wineprefixes/
│  └─ Counter-Strike/
├─ protonprefixes/
│  └─ Counter-Strike/
└─ logs/
   └─ Counter-Strike/
```

---

## 10. Windows 服务端配置文件 game.windows.env

编辑：

```bash
nano game.windows.env
```

通用模板：

```env
# 每个服务端单独一个目录名
SERVER_DIR_NAME=my-windows-server

# Windows Dedicated Server AppID
STEAM_APP_ID=你的Windows服务端AppID

# Windows 服务端通常需要强制下载 Windows depot
STEAMCMD_FORCE_PLATFORM=windows

# 大多数服务端可以 anonymous
STEAM_LOGIN=anonymous
# STEAM_USERNAME=
# STEAM_PASSWORD=

# 启动时自动更新
UPDATE_ON_START=1

# 是否 validate，1 更稳但更慢
VALIDATE=0

# wine 或 proton
COMPAT_LAYER=wine

# Wine 基础配置
WINEARCH=win64
WINEDEBUG=-all
WINE_USE_XVFB=1
DISPLAY=:99

# 宿主机普通用户 UID/GID
PUID=1000
PGID=1000

# 单端口服务端可直接使用
SERVER_PORT=27015

# Windows 服务端 exe，路径相对于服务端安装目录
WIN_SERVER_EXE=DedicatedServer.exe

# 服务端启动参数
WIN_SERVER_ARGS=

# 如果某个游戏需要完全自定义启动命令，可以用 SERVER_COMMAND 覆盖 WIN_SERVER_EXE
# SERVER_COMMAND='wine "/steam/steamlibrary/steamapps/common/my-windows-server/DedicatedServer.exe" -log'

# 可选：启动前执行命令
# PRE_START='ls -lah'

# 可选：把某个日志文件同步到 Docker 前台
# 路径相对于服务端安装目录
TAIL_LOG_ON_START=0
TAIL_LOG_PATH=
TAIL_LOG_LINES=80

# 崩溃后自动重启
RESTART_ON_CRASH=1
RESTART_DELAY=10

# Steam beta 分支，可选
# STEAM_BETA=
# STEAM_BETA_PASSWORD=

# app_update 额外参数，可选
# APP_UPDATE_EXTRA=

# Proton 可选：
# COMPAT_LAYER=proton
# PROTON_DIR=/proton/GE-Proton
```

---

## 11. Windows 示例：Counter-Strike: Source

`game.windows.env` 示例：

```env
SERVER_DIR_NAME=Counter-Strike

STEAM_APP_ID=232330
STEAMCMD_FORCE_PLATFORM=windows
STEAM_LOGIN=anonymous

UPDATE_ON_START=0
VALIDATE=0

COMPAT_LAYER=wine

WINEARCH=win64
WINEDEBUG=-all
WINE_USE_XVFB=1
DISPLAY=:99

PUID=1000
PGID=1000

SERVER_PORT=33333

WIN_SERVER_EXE=srcds.exe
WIN_SERVER_ARGS=-console -condebug -game cstrike -insecure -port 33333 +maxplayers 16 +map de_dust2 +password your_password

TAIL_LOG_ON_START=1
TAIL_LOG_PATH=cstrike/console.log
TAIL_LOG_LINES=80

RESTART_ON_CRASH=0
RESTART_DELAY=10
```

说明：

```text
-condebug
    让 SRCDS 把控制台日志写入 cstrike/console.log

TAIL_LOG_ON_START=1
    让 Docker 前台显示 cstrike/console.log

SERVER_PORT=33333
    映射宿主机和容器的 33333 端口

+password your_password
    设置服务器密码，请改成自己的密码
```

---

## 12. Windows 服务端 docker-compose.windows.yml

通用 compose 示例：

```yaml
services:
  steam-windows-server:
    build:
      context: .
      dockerfile: Dockerfile.windows
      args:
        EXTRA_APT_PACKAGES: ""

    restart: unless-stopped

    env_file:
      - game.windows.env

    volumes:
      - "/steam-windows/steamcmd:/home/steam/steamcmd"
      - "/steam-windows/home/${SERVER_DIR_NAME:?SERVER_DIR_NAME is required}:/home/steam"
      - "/steam-windows/steamlibrary/steamapps/common/${SERVER_DIR_NAME}:/steam/steamlibrary/steamapps/common/${SERVER_DIR_NAME}"
      - "/steam-windows/wineprefixes/${SERVER_DIR_NAME}:/steam/wineprefixes/${SERVER_DIR_NAME}"
      - "/steam-windows/protonprefixes/${SERVER_DIR_NAME}:/steam/protonprefixes/${SERVER_DIR_NAME}"
      - "/steam-windows/logs/${SERVER_DIR_NAME}:/steam/logs/${SERVER_DIR_NAME}"

      # Proton 可选：
      # - "/steam-proton:/proton:ro"

    ports:
      - "${SERVER_PORT:-27015}:${SERVER_PORT:-27015}/udp"
      - "${SERVER_PORT:-27015}:${SERVER_PORT:-27015}/tcp"

    stdin_open: true
    tty: true

    ulimits:
      nofile:
        soft: 100000
        hard: 100000
```

如果游戏需要多个端口，请直接写多行：

```yaml
ports:
  - "27015:27015/udp"
  - "27015:27015/tcp"
  - "27016:27016/udp"
  - "27017:27017/tcp"
```

---

## 13. 构建 Windows 服务端镜像

首次构建：

```bash
docker compose --env-file game.windows.env -f docker-compose.windows.yml build --no-cache
```

---

## 14. 启动 Windows 服务端

前台启动，适合测试：

```bash
docker compose --env-file game.windows.env -f docker-compose.windows.yml up --force-recreate
```

后台启动，适合正式运行：

```bash
docker compose --env-file game.windows.env -f docker-compose.windows.yml up -d
```

查看日志：

```bash
docker compose --env-file game.windows.env -f docker-compose.windows.yml logs -f
```

停止服务端：

```bash
docker compose --env-file game.windows.env -f docker-compose.windows.yml down
```

---

# 三、通用使用说明

## 15. 修改配置后如何重新启动

如果只修改了 `.env` 文件：

```bash
docker compose --env-file game.windows.env -f docker-compose.windows.yml down
docker compose --env-file game.windows.env -f docker-compose.windows.yml up --force-recreate
```

Linux 版本：

```bash
docker compose --env-file game.linux.env -f docker-compose.linux.yml down
docker compose --env-file game.linux.env -f docker-compose.linux.yml up --force-recreate
```

如果修改了 Dockerfile 或脚本文件，需要重新构建：

```bash
docker compose --env-file game.windows.env -f docker-compose.windows.yml build --no-cache
```

Linux 版本：

```bash
docker compose --env-file game.linux.env -f docker-compose.linux.yml build --no-cache
```

---

## 16. 如何更换游戏

### Linux 服务端

通常修改：

```env
SERVER_DIR_NAME=
STEAM_APP_ID=
SERVER_COMMAND=
```

例如：

```env
SERVER_DIR_NAME=U3DS
STEAM_APP_ID=1110390
SERVER_COMMAND='./ServerHelper.sh +LanServer testserver'
```

然后启动：

```bash
docker compose --env-file game.linux.env -f docker-compose.linux.yml up -d
```

### Windows 服务端

通常修改：

```env
SERVER_DIR_NAME=
STEAM_APP_ID=
WIN_SERVER_EXE=
WIN_SERVER_ARGS=
SERVER_PORT=
```

例如：

```env
SERVER_DIR_NAME=example-server
STEAM_APP_ID=123456
WIN_SERVER_EXE=DedicatedServer.exe
WIN_SERVER_ARGS=-port 27015 -log
SERVER_PORT=27015
```

然后启动：

```bash
docker compose --env-file game.windows.env -f docker-compose.windows.yml up -d
```

---

## 17. 如何查看端口

例如端口是 `33333`：

```bash
ss -lunpt | grep 33333
```

你可能会看到：

```text
udp   UNCONN 0 0 0.0.0.0:33333 0.0.0.0:*
tcp   LISTEN 0 4096 0.0.0.0:33333 0.0.0.0:*
```

说明：

```text
TCP 显示 LISTEN 是正常的
UDP 显示 UNCONN 是正常的
```

---

## 18. 如何查看服务端文件

Linux 示例：

```bash
ls -lah /steam-linux/steamlibrary/steamapps/common/U3DS
```

Windows 示例：

```bash
ls -lah /steam-windows/steamlibrary/steamapps/common/Counter-Strike
```

---

## 19. 如何查看日志

Docker 日志：

```bash
docker compose --env-file game.windows.env -f docker-compose.windows.yml logs -f
```

Linux 版本：

```bash
docker compose --env-file game.linux.env -f docker-compose.linux.yml logs -f
```

如果配置了 `TAIL_LOG_ON_START=1`，Docker 日志会显示游戏日志文件内容。

例如 CS:S：

```bash
tail -f /steam-windows/steamlibrary/steamapps/common/Counter-Strike/cstrike/console.log
```

---

## 20. TAIL_LOG_ON_START 怎么用

如果游戏会把日志写入文件，可以开启：

```env
TAIL_LOG_ON_START=1
TAIL_LOG_PATH=logs/server.log
```

`TAIL_LOG_PATH` 是相对于服务端目录的路径。

例如 CS:S：

```env
TAIL_LOG_ON_START=1
TAIL_LOG_PATH=cstrike/console.log
```

如果游戏没有日志文件，或者你不知道日志位置：

```env
TAIL_LOG_ON_START=0
TAIL_LOG_PATH=
```

---

## 21. 常见问题

### 21.1 SteamCMD 下载失败

先开启校验：

```env
VALIDATE=1
```

然后重新启动。

Windows：

```bash
docker compose --env-file game.windows.env -f docker-compose.windows.yml up --force-recreate
```

Linux：

```bash
docker compose --env-file game.linux.env -f docker-compose.linux.yml up --force-recreate
```

---



### 21.3 修改端口后不生效

修改 `game.windows.env` 或 `game.linux.env` 后，需要重新创建容器：

```bash
docker compose --env-file game.windows.env -f docker-compose.windows.yml down
docker compose --env-file game.windows.env -f docker-compose.windows.yml up --force-recreate
```

Linux：

```bash
docker compose --env-file game.linux.env -f docker-compose.linux.yml down
docker compose --env-file game.linux.env -f docker-compose.linux.yml up --force-recreate
```

---
