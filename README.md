# PVET - Proxmox VE 管理工具集

<div align="center">

```
██████╗ ██╗   ██╗███████╗    ████████╗ ██████╗  ██████╗ ██╗     
██╔══██╗██║   ██║██╔════╝    ╚══██╔══╝██╔═══██╗██╔═══██╗██║     
██████╔╝██║   ██║█████╗         ██║   ██║   ██║██║   ██║██║     
██╔═══╝ ╚██╗ ██╔╝██╔══╝         ██║   ██║   ██║██║   ██║██║     
██║      ╚████╔╝ ███████╗       ██║   ╚██████╔╝╚██████╔╝███████╗
╚═╝       ╚═══╝  ╚══════╝       ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝
```

[![GitHub stars](https://img.shields.io/github/stars/MuskCheng/pve-toolkit?style=flat)](https://github.com/MuskCheng/pve-toolkit/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/MuskCheng/pve-toolkit?style=flat)](https://github.com/MuskCheng/pve-toolkit/network)
[![GitHub license](https://img.shields.io/github/license/MuskCheng/pve-toolkit?style=flat)](https://github.com/MuskCheng/pve-toolkit/blob/master/LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Proxmox%20VE%209.x-blue)](#)
[![Version](https://img.shields.io/badge/Version-V0.22-green)](#)

</div>

## 📖 项目介绍

**PVE Toolkit** 是一款专为 **Proxmox VE 9.0+** 打造的 Bash 脚本管理工具集，旨在简化 PVE 日常运维工作。

Proxmox VE 9.0 是 Proxmox 于 2024 年底发布的最新版本，基于 **Debian 13 (Trixie)**，带来了多项重大更新：

- 🚀 基于 Debian 13 (Trixie)，使用最新 Linux 内核
- 💾 默认使用 zstd 压缩算法，备份性能大幅提升
- 🐳 原生支持 Docker 和容器化应用
- ⚡ 更高效的资源和网络管理
- 🔒 更好的安全性和稳定性

本工具针对 PVE 9.0 特性进行了深度优化，提供一键安装、交互式界面和命令行模式，让你的 PVE 运维更加高效便捷。

## ✨ 功能特性

| 模块 | 功能描述 |
|------|---------|
| 📦 **备份管理** | VM/LXC 备份创建、恢复、清理，支持 zstd 压缩 |
| 📊 **系统监控** | 系统状态、资源监控（CPU/内存/磁盘）、网络状态、日志查看 |
| 🖴 **LXC 容器管理** | 容器创建、启动、停止、删除、进入控制台、Docker 一键安装 |
| ⚙️ **系统管理** | 镜像源切换（PVE/DEB）、系统更新、清理 |

## 🚀 快速开始

### 环境要求

- Proxmox VE 9.0 或更高版本
- root 权限

### 一键运行

```bash
# 方式1: 直接管道运行（推荐）
su - root -c 'curl -sL https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/pve-tool.sh | bash'

# 方式2: 保存到本地后运行
curl -sL https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/pve-tool.sh -o pve-tool.sh
bash pve-tool.sh
```

### 交互模式

运行后将进入交互式菜单界面，通过数字键选择功能模块。

### 命令行模式

```bash
# 备份管理
bash pve-tool.sh backup --list
bash pve-tool.sh backup --create 100
bash pve-tool.sh backup --cleanup
bash pve-tool.sh backup --restore /var/lib/vz/dump/vzdump-100.vma.zst 100

# 系统监控
bash pve-tool.sh monitor --status
bash pve-tool.sh monitor --vm
bash pve-tool.sh monitor --lxc
bash pve-tool.sh monitor --resources
bash pve-tool.sh monitor --network
bash pve-tool.sh monitor --logs 100

# LXC 容器管理
bash pve-tool.sh lxc --list
bash pve-tool.sh lxc --create 104 web1 2048 2 20
bash pve-tool.sh lxc --start 104
bash pve-tool.sh lxc --stop 104
bash pve-tool.sh lxc --restart 104
bash pve-tool.sh lxc --delete 104
bash pve-tool.sh lxc --console 104
bash pve-tool.sh lxc --info 104
bash pve-tool.sh lxc --install-docker 104
bash pve-tool.sh lxc --install-compose 104

# 系统管理
bash pve-tool.sh system --sources
bash pve-tool.sh system --mirror
bash pve-tool.sh system --disable-enterprise
bash pve-tool.sh system --pve-community
bash pve-tool.sh system --update
bash pve-tool.sh system --cleanup
bash pve-tool.sh system --info
```

## 📋 功能详解

### 1️⃣ 备份管理

| 命令 | 说明 |
|:-----|:-----|
| `backup --list` | 列出所有 VM/LXC 备份 |
| `backup --create <ID>` | 创建指定 VM/LXC 的备份 |
| `backup --cleanup` | 清理已过期的备份（默认 7 天） |
| `backup --restore <文件> <ID>` | 恢复备份到指定 VM/LXC |

### 2️⃣ 系统监控

| 命令 | 说明 |
|:-----|:-----|
| `monitor --status` | 系统状态概览（CPU、内存、磁盘、VM/LXC 数量） |
| `monitor --vm` | 查看所有虚拟机状态 |
| `monitor --lxc` | 查看所有 LXC 容器状态 |
| `monitor --resources` | 资源使用阈值检查（CPU>90%、内存>90%、磁盘>85% 告警） |
| `monitor --network` | 网络接口状态和流量统计 |
| `monitor --logs [N]` | 查看最近 N 条系统日志（默认 50 条） |

### 3️⃣ LXC 容器管理

| 命令 | 说明 |
|:-----|:-----|
| `lxc --list` | 列出所有 LXC 容器 |
| `lxc --create <ID> <名称> [内存] [核心] [磁盘]` | 创建新的 LXC 容器 |
| `lxc --start <ID>` | 启动指定容器 |
| `lxc --stop <ID>` | 停止指定容器 |
| `lxc --restart <ID>` | 重启指定容器 |
| `lxc --delete <ID>` | 删除指定容器（会确认） |
| `lxc --console <ID>` | 进入容器控制台 |
| `lxc --info <ID>` | 查看容器详细信息和配置 |
| `lxc --install-docker <ID>` | 一键在容器中安装 Docker |
| `lxc --install-compose <ID>` | 一键在容器中安装 Docker Compose |

**Docker 安装特性**：
- 支持官方 Docker 源和系统自带 docker.io
- 自动配置 Docker 镜像加速（DaoCloud）
- 兼容 Debian 12/13 系统

### 4️⃣ 系统管理

| 命令 | 说明 |
|:-----|:-----|
| `system --sources` | 查看当前 APT 镜像源配置 |
| `system --mirror` | 交互式选择并切换镜像源 |
| `system --disable-enterprise` | 禁用 PVE 企业源 |
| `system --pve-community` | 配置 PVE 社区源（中科大镜像） |
| `system --update` | 更新系统软件包 |
| `system --cleanup` | 清理系统（删除缓存、旧包、日志） |
| `system --info` | 查看系统详细信息 |

**支持的镜像源**：
- ✅ 中科大镜像
- ✅ 清华大学镜像
- ✅ 阿里云镜像
- ✅ 华为云镜像
- ✅ 腾讯云镜像
- ✅ 网易镜像

## ⚠️ 使用注意

1. **操作前请备份数据** - 备份、恢复、删除等操作有风险
- 部分功能需要确认才能执行
- 建议在非生产时段进行系统更新

2. **权限要求**
- 所有功能需要 root 权限运行
- 请使用 `su - root` 切换后再执行

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

本项目基于 [MIT](LICENSE) 许可证开源。

---

<div align="center">

⭐ 如果这个工具对你有帮助，请 Star 支持一下！

</div>
