# PVET - Proxmox VE 管理工具集

<div align="center">

[![GitHub stars](https://img.shields.io/github/stars/MuskCheng/pve-toolkit?style=flat)](https://github.com/MuskCheng/pve-toolkit/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/MuskCheng/pve-toolkit?style=flat)](https://github.com/MuskCheng/pve-toolkit/network)
[![GitHub license](https://img.shields.io/github/license/MuskCheng/pve-toolkit?style=flat)](https://github.com/MuskCheng/pve-toolkit/blob/master/LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Proxmox%20VE%209.x-blue)](#)
[![Language](https://img.shields.io/badge/Language-Bash-green)](#)

一个简洁高效的 Proxmox VE 管理工具集，提供备份管理、系统监控、LXC 容器管理、系统更新等功能。

</div>

## ✨ 功能特性

| 模块 | 功能描述 |
|------|---------|
| 📦 **备份管理** | VM/LXC 备份创建、恢复、清理 |
| 📊 **系统监控** | 系统状态、资源监控、网络状态、日志查看 |
| 🖴 **LXC 容器管理** | 容器创建、启动、停止、删除、Docker 安装 |
| ⚙️ **系统管理** | 镜像源切换、系统更新、清理 |

## 🚀 快速开始

### 环境要求

- Proxmox VE 9.0+
- root 权限

### 一键安装/运行

```bash
# 直接运行（推荐）
su - root -c 'curl -sL https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/pve-tool.sh | bash'

# 或保存到本地后运行
curl -sL https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/pve-tool.sh -o pve-tool.sh
bash pve-tool.sh
```

## 📖 使用方法

### 交互模式

直接运行脚本进入交互模式：

```bash
bash pve-tool.sh
```

### 命令行模式

#### 备份管理

```bash
bash pve-tool.sh backup --list
bash pve-tool.sh backup --create 100
bash pve-tool.sh backup --cleanup
bash pve-tool.sh backup --restore /var/lib/vz/dump/vzdump-100.vma.zst 100
```

#### 系统监控

```bash
bash pve-tool.sh monitor --status
bash pve-tool.sh monitor --vm
bash pve-tool.sh monitor --lxc
bash pve-tool.sh monitor --resources
bash pve-tool.sh monitor --network
bash pve-tool.sh monitor --logs 100
```

#### LXC 容器管理

```bash
bash pve-tool.sh lxc --list
bash pve-tool.sh lxc --create 104 web1 2048 2 20
bash pve-tool.sh lxc --start 104
bash pve-tool.sh lxc --stop 104
bash pve-tool.sh lxc --restart 104
bash pve-tool.sh lxc --delete 104
bash pve-tool.sh lxc --info 104
bash pve-tool.sh lxc --install-docker 104
bash pve-tool.sh lxc --install-compose 104
```

#### 系统管理

```bash
bash pve-tool.sh system --sources
bash pve-tool.sh system --mirror
bash pve-tool.sh system --disable-enterprise
bash pve-tool.sh system --pve-community
bash pve-tool.sh system --update
bash pve-tool.sh system --cleanup
bash pve-tool.sh system --info
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
| 删除容器 | `lxc --delete <ID>` |
| 容器详情 | `lxc --info <ID>` |
| 安装 Docker | `lxc --install-docker <ID>` |
| 安装 Docker Compose | `lxc --install-compose <ID>` |

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

## 📁 目录结构

```
pve-toolkit/
└── pve-tool.sh    # 完整工具集（单文件）
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

本项目基于 [MIT](LICENSE) 许可证开源。

---

<div align="center">

⭐ Star 本项目以示支持

</div>
