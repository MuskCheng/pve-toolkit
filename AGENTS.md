# PVE Toolkit 项目上下文

## 项目概述

**PVE Toolkit** 是一个专为 Proxmox VE 9.1+ 打造的 LXC 容器管理工具，使用纯 Bash 脚本编写，提供交互式菜单界面，简化 PVE 日常运维操作。

- **版本**: V0.7.0
- **平台**: Proxmox VE 9.1+ (基于 Debian 13/Trixie)
- **语言**: Bash Shell Script
- **许可证**: MIT
- **仓库**: https://github.com/MuskCheng/pve-toolkit

## 目录结构

```
pve-toolkit/
├── pve-tool.sh          # 主脚本文件（约 2153 行）
├── install.sh           # 一键安装脚本
├── VERSION              # 版本号文件
├── README.md            # 项目说明文档
├── CHANGELOG.md         # 更新日志
├── LICENSE              # MIT 许可证
└── .github/
    ├── versions.json    # Docker/Compose 版本信息
    ├── hooks/
    │   └── post-merge   # Git pull 后自动清理旧文件
    └── workflows/
        └── release.yml  # 自动发布工作流
```

## 核心功能模块

### 1. 系统管理
- 系统状态监控（CPU/内存/磁盘/运行时间）
- 系统更新（apt update && apt upgrade）
- 系统清理（apt 缓存、旧内核、临时文件）
- 网络信息查看
- 存储信息查看
- 内核管理（查看/安装/设置默认内核）
- 系统日志查看
- 修复 Docker 源
- 屏蔽订阅提示

### 2. LXC 容器管理
- 容器列表查看（含 IP 地址、特权标识、运行状态）
- 创建新容器（自动下载最新 Debian 模板）
- 删除容器
- 容器操作（控制台/启动/停止/重启/克隆/修改资源）
- 网络配置修改（静态 IP / DHCP 切换）
- 容器类型转换（特权 ↔ 无特权）
- Docker 管理
  - 安装 Docker + Docker Compose
  - 安装 DPanel 面板
  - Docker 换源
  - Docker 容器管理（启动/停止/重启/日志/终端/删除）

### 3. 换源工具
- 支持 6 种国内镜像源：中科大、清华、阿里云、华为云、南京大学、腾讯云
- 自动检测 Debian/PVE 版本
- Ceph 源配置
- CT 模板源替换
- 企业源禁用处理
- 安全源选择（镜像站/官方）

## 安装与运行

### 一键安装（推荐）
```bash
# 加速源（国内推荐）
bash -c "$(curl -sL https://cdn.jsdelivr.net/gh/MuskCheng/pve-toolkit@master/install.sh)"

# 官方源
bash -c "$(curl -sL https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/install.sh)"
```

### 手动运行
```bash
curl -sL https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/pve-tool.sh -o /tmp/pve.sh
bash /tmp/pve.sh
```

### 调试模式
```bash
bash /tmp/pve.sh --debug
```

## 开发规范

### 环境要求
- Root 权限
- Proxmox VE 9.1+
- curl 依赖

### 颜色变量定义
```bash
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
WHITE=$'\033[1;37m'
NC=$'\033[0m'
```

### 关键函数
| 函数名 | 功能 |
|--------|------|
| `show_menu()` | 显示主菜单 |
| `system_menu()` | 系统管理子菜单 |
| `lxc_menu()` | LXC 容器管理子菜单 |
| `docker_menu()` | Docker 管理子菜单 |
| `change_source()` | 换源功能 |
| `check_and_install_docker()` | 检查并安装 Docker |
| `get_compose_cmd()` | 获取 Docker Compose 命令 |
| `backup_file()` | 备份文件到 /var/backups/pve-tools/ |
| `block_non_pve9()` | 拦截非 PVE9 环境的破坏性操作 |
| `pause_func()` | 暂停等待用户按键 |

### 版本发布流程
1. 更新 `VERSION` 文件
2. 推送到 main/master 分支
3. GitHub Actions 自动创建 Release

### Git Hook
- `post-merge`: 每次 `git pull` 后自动清理 `.bak` `.old` `.tmp` 文件

## 默认配置

| 配置项 | 默认值 |
|--------|--------|
| LXC 内存 | 2048 MB |
| LXC CPU 核心 | 2 |
| LXC 磁盘 | 8 GB |
| LXC 容器类型 | 特权容器（Docker 兼容最佳） |
| Docker 镜像源 | https://docker.1ms.run |
| 备份目录 | /var/backups/pve-tools/ |
| Debian 模板源 | http://download.proxmox.com/images/system/ |

## 注意事项

1. **权限要求**: 所有功能需要 root 权限
2. **数据安全**: 删除容器等操作不可逆，操作前请备份
3. **类型转换**: 特权→无特权会修改文件所有权，建议先备份
4. **版本限制**: 仅支持 PVE 9.1 或更高版本
5. **Docker Compose**: 支持 V1 (docker-compose) 和 V2 (docker compose plugin) 两种方式

## 常用 LXC 创建命令模板

```bash
pct create <ID> local:vztmpl/debian-13-standard_*.tar.zst \
    --hostname <名称> \
    --memory 2048 \
    --cores 2 \
    --rootfs local:8 \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --unprivileged 0 \
    --features nesting=1,keyctl=1 \
    --start 1
```

## 用户特定配置

- 用户的 PVE 版本: 9.1.1，基于 Debian 13 (Trixie)
- 使用中科大镜像源
- 已禁用企业源 (pve-enterprise.sources 和 ceph.sources)
- LXC 102 (lucky): 运行 Lucky 反代
  - docker-compose.yml: `/opt/lucky/docker-compose.yml`
  - 配置目录: `/opt/lucky/conf/`
  - 镜像: `gdy666/lucky:v2`
  - 管理端口: 16601
  - 升级命令: `cd /opt/lucky && docker compose down && docker compose up -d`
- LXC 103 (SafeLine): 已删除
- Docker 镜像源配置: `/etc/docker/daemon.json`
  - 镜像源: `https://docker.m.daocloud.io`, `https://hub.rat.dev`
