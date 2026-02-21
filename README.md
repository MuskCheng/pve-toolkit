# PVET - Proxmox VE 管理工具集

<div align="center">

[![GitHub stars](https://img.shields.io/github/stars/MuskCheng/pve-toolkit?style=flat)](https://github.com/MuskCheng/pve-toolkit/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/MuskCheng/pve-toolkit?style=flat)](https://github.com/MuskCheng/pve-toolkit/network)
[![GitHub issues](https://img.shields.io/github/issues/MuskCheng/pve-toolkit?style=flat)](https://github.com/MuskCheng/pve-toolkit/issues)
[![GitHub license](https://img.shields.io/github/license/MuskCheng/pve-toolkit?style=flat)](https://github.com/MuskCheng/pve-toolkit/blob/main/LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Proxmox%20VE%209.x-blue?style=flat)](#)
[![Language](https://img.shields.io/badge/Language-Bash-green?style=flat)](#)

一个简洁高效的 Proxmox VE 管理工具集，提供备份管理、系统监控、LXC 容器管理、系统更新等功能。

</div>

## ✨ 功能特性

| 模块 | 功能描述 |
|------|---------|
| 📦 **备份管理** | VM/LXC 备份创建、恢复、清理 |
| 📊 **系统监控** | 系统状态、资源监控、网络状态、日志查看 |
| 🖴 **LXC 容器管理** | 容器创建、启动、停止、删除、软件安装 |
| ⚙️ **系统管理** | 镜像源切换、系统更新、清理 |

## 🚀 快速开始

### 环境要求

- Proxmox VE 9.x
- root 权限

### 安装

```bash
# 一键安装（推荐）
curl -sL https://raw.githubusercontent.com/MuskCheng/pve-toolkit/main/install.sh | bash

# 或手动安装
git clone https://github.com/MuskCheng/pve-toolkit.git /opt/pve-toolkit
cd /opt/pve-toolkit
chmod +x pve-tool.sh
./pve-tool.sh
```

## 📖 使用方法

### 交互模式

直接运行脚本进入交互模式：

```bash
./pve-tool.sh
```

### 命令行模式

#### 备份管理

```bash
./pve-tool.sh backup --list
./pve-tool.sh backup --create 100
./pve-tool.sh backup --cleanup
./pve-tool.sh backup --restore /var/lib/vz/dump/vzdump-100.vma.zst 100
```

#### 系统监控

```bash
./pve-tool.sh monitor --status
./pve-tool.sh monitor --vm
./pve-tool.sh monitor --lxc
./pve-tool.sh monitor --resources
./pve-tool.sh monitor --network
./pve-tool.sh monitor --logs 100
```

#### LXC 容器管理

```bash
./pve-tool.sh lxc --list
./pve-tool.sh lxc --create 104 web1 2048 2 20
./pve-tool.sh lxc --start 104
./pve-tool.sh lxc --stop 104
./pve-tool.sh lxc --restart 104
./pve-tool.sh lxc --delete 104
./pve-tool.sh lxc --console 104
./pve-tool.sh lxc --info 104
./pve-tool.sh lxc --install-docker 104
./pve-tool.sh lxc --install-compose 104
```

#### 系统管理

```bash
./pve-tool.sh system --sources
./pve-tool.sh system --mirror
./pve-tool.sh system --disable-enterprise
./pve-tool.sh system --pve-community
./pve-tool.sh system --update
./pve-tool.sh system --cleanup
./pve-tool.sh system --info
```

## 📋 功能模块

### 1️⃣ 备份管理

| 功能 | 命令 |
|:-----|:-----|
| 列出所有备份 | `backup --list` |
| 创建备份 | `backup --create <ID>` |
| 清理旧备份 | `backup --cleanup` |
| 恢复备份 | `backup --restore <file> <ID>` |

### 2️⃣ 系统监控

| 功能 | 命令 |
|:-----|:-----|
| 系统状态概览 | `monitor --status` |
| 虚拟机状态 | `monitor --vm` |
| LXC 容器状态 | `monitor --lxc` |
| 资源阈值检查 | `monitor --resources` |
| 网络状态 | `monitor --network` |
| 系统日志 | `monitor --logs [N]` |

### 3️⃣ LXC 容器管理

| 功能 | 命令 |
|:-----|:-----|
| 列出容器 | `lxc --list` |
| 创建容器 | `lxc --create <ID> <名称> [内存] [核心] [磁盘]` |
| 启动容器 | `lxc --start <ID>` |
| 停止容器 | `lxc --stop <ID>` |
| 重启容器 | `lxc --restart <ID>` |
| 删除容器 | `lxc --delete <ID> [-f]` |
| 进入控制台 | `lxc --console <ID>` |
| 容器详情 | `lxc --info <ID>` |
| 安装 Docker | `lxc --install-docker <ID>` |
| 安装 Docker Compose | `lxc --install-compose <ID>` |

#### Docker 集成

- **Docker 安装** - 使用阿里云镜像源，安装后自动配置镜像加速
- **Docker Compose 安装** - 安装后提供使用引导和模板创建
- **Docker 换源** - 提供 DaoCloud、阿里云、腾讯云、华为云、网易、中科大镜像源
- **Docker 容器管理** - 镜像搜索、拉取、容器运行、状态查看

### 4️⃣ 系统管理

| 功能 | 命令 |
|:-----|:-----|
| 显示镜像源配置 | `system --sources` |
| 切换镜像源 | `system --mirror` |
| 禁用 PVE 企业源 | `system --disable-enterprise` |
| 配置 PVE 社区源 | `system --pve-community` |
| 更新系统 | `system --update` |
| 清理系统 | `system --cleanup` |
| 系统信息 | `system --info` |

#### 支持的镜像源

- ✅ 中科大镜像
- ✅ 清华大学镜像
- ✅ 阿里云镜像
- ✅ 华为云镜像
- ✅ 腾讯云镜像
- ✅ 网易镜像

## ⚙️ 配置文件

配置文件位于 `config/settings.conf`：

```bash
# 备份设置
BACKUP_DIR="/var/lib/vz/dump"
BACKUP_RETENTION_DAYS=7
BACKUP_COMPRESS="zstd"

# 监控设置
MONITOR_INTERVAL=60
ALERT_THRESHOLD_CPU=90
ALERT_THRESHOLD_MEM=90
ALERT_THRESHOLD_DISK=85

# LXC 容器模板
LXC_TEMPLATE="local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
LXC_DEFAULT_MEMORY=2048
LXC_DEFAULT_CORES=2
LXC_DEFAULT_DISK=20
```

## 📁 目录结构

```
pve-toolkit/
├── pve-tool.sh              # 主脚本
├── config/
│   └── settings.conf        # 配置文件
├── modules/
│   ├── backup.sh            # 备份管理模块
│   ├── monitor.sh           # 系统监控模块
│   ├── lxc.sh               # LXC 容器管理模块
│   └── system.sh            # 系统管理模块
└── README.md                # 项目文档
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/xxx`)
3. 提交更改 (`git commit -m 'Add xxx'`)
4. 推送分支 (`git push origin feature/xxx`)
5. 打开 Pull Request

## 📄 许可证

本项目基于 [MIT](LICENSE) 许可证开源。

---

<div align="center">

⭐ Star 本项目以示支持

</div>
