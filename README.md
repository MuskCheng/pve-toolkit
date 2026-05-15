<div align="center">

# <img src="https://img.icons8.com/fluency/48/proxmox.png" alt="PVE Toolkit" width="40" valign="middle"/> PVE Toolkit

**LXC 容器管理工具**

```
██████╗ ██╗   ██╗███████╗    ████████╗ ██████╗  ██████╗ ██╗     
██╔══██╗██║   ██║██╔════╝    ╚══██╔══╝██╔═══██╗██╔═══██╗██║     
██████╔╝██║   ██║█████╗         ██║   ██║   ██║██║   ██║██║     
██╔═══╝ ╚██╗ ██╔╝██╔══╝         ██║   ██║   ██║██║   ██║██║     
██║      ╚████╔╝ ███████╗       ██║   ╚██████╔╝╚██████╔╝███████╗
╚═╝       ╚═══╝  ╚══════╝       ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝
```

🎯 专为 **Proxmox VE 9.1+** 打造的 LXC 容器管理工具

[![Version](https://img.shields.io/github/v/release/MuskCheng/pve-toolkit?display_name=tag&label=%E7%89%88%E6%9C%AC&sort=semver&color=blue&logo=github)](https://github.com/MuskCheng/pve-toolkit/releases/latest)
[![GitHub Stars](https://img.shields.io/github/stars/MuskCheng/pve-toolkit?style=flat&color=yellow&logo=github)](https://github.com/MuskCheng/pve-toolkit/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/MuskCheng/pve-toolkit?style=flat&logo=github)](https://github.com/MuskCheng/pve-toolkit/network)
[![License](https://img.shields.io/github/license/MuskCheng/pve-toolkit?style=flat&color=green&logo=mit)](https://github.com/MuskCheng/pve-toolkit/blob/master/LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Proxmox%20VE%209.x-orange?logo=proxmox)](#)

</div>

---

## 📑 目录

- [✨ 功能特性](#-功能特性)
- [🚀 快速开始](#-快速开始)
- [📋 菜单说明](#-菜单说明)
- [🔥 功能特点](#-功能特点)
- [⚠️ 注意事项](#️-注意事项)

---

## ✨ 功能特性

| 📦 LXC容器 | ⚙️ 系统管理 | 🔄 换源工具 | 📲 应用安装 |
|:---:|:---:|:---:|:---:|
| 创建/删除/操作 | 状态/更新/清理 | 6种镜像源 | OpenClaw (AI助手) |
| Docker管理 | 网络/存储/内核 | Ceph源配置 | Lucky 大吉 (反向代理) |
| 类型转换 | 修复Docker源 | 自动换源 | DPanel (Docker面板) |

---

## 🚀 快速开始

### 📋 环境要求

| 项目 | 要求 |
|:---:|:---:|
| 平台 | Proxmox VE 9.1+ |
| 权限 | root |

### ⚡ 一键安装

> 🌟 **国内服务器推荐使用加速源**

```bash
# 🚀 加速源（推荐）
bash -c "$(curl -sL https://cdn.jsdelivr.net/gh/MuskCheng/pve-toolkit@master/install.sh)"
```

<details>
<summary>🌐 其他安装方式</summary>

```bash
# 官方源
bash -c "$(curl -sL https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/install.sh)"

# 手动下载
curl -sL https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/pve-tool.sh -o /tmp/pve.sh
bash /tmp/pve.sh
```

</details>

---

## 📋 菜单说明

### 🏠 主菜单

```
═══════════════════════════════════════════════════
  PVE Toolkit - LXC 容器管理工具
═══════════════════════════════════════════════════
  [1] ⚙️  系统管理
  [2] 📦 LXC 容器管理
  [3] 🔄 换源工具
  [0] ❌ 退出
═══════════════════════════════════════════════════
```

---

### 📦 LXC 容器管理

```
════════════════════════ LXC 容器管理 ═════════════════
  [1] 📋 查看容器列表
  [2] ➕ 创建新容器          ← 选择特权/无特权容器
  [3] 🗑️  删除容器
  [4] ⚡ 容器操作
  [5] 🐳 Docker 管理
  [6] 📲 应用安装            ← OpenClaw / Lucky / DPanel
  [0] 🔙 返回
```

<details>
<summary>🔧 容器操作</summary>

```
═══════════════════════ 容器操作 ══════════════════
  [1] 💻 进入容器控制台
  [2] ▶️  启动容器
  [3] ⏹️  停止容器
  [4] 🔄 重启容器
  [5] 📦 克隆容器
  [6] ✏️  修改容器资源
  [7] 🌐 修改网络配置        ← 设置静态IP/DHCP
  [8] 🔀 转换容器类型        ← 特权/无特权互转
  [0] 🔙 返回
```

</details>

<details>
<summary>🐳 Docker 管理</summary>

```
═══════════════════════ Docker 管理 ══════════════════
  [1] 📥 安装 Docker (含 Docker Compose)
  [2] 🌐 Docker 换源
  [3] 🔧 Docker 容器管理      ← 操作/日志/终端
  [0] 🔙 返回
```

</details>

<details>
<summary>📲 应用安装</summary>

```
═══════════════════════ 应用安装 ══════════════════
  [1] 🤖 安装 OpenClaw (AI 助手)
  [2] 🍀 安装 Lucky 大吉 (反向代理)
  [3] 📊 安装 DPanel 面板 (Docker 管理)
  [0] 🔙 返回
```

</details>

---

### ⚙️ 系统管理

```
═══════════════════════ 系统管理 ══════════════════
  [1] 📊 系统状态
  [2] 🔄 系统更新
  [3] 🧹 清理系统            ← apt缓存/旧内核/临时文件
  [4] 🌐 网络信息
  [5] 💾 存储信息
  [6] 🖥️  内核管理
  [7] 📝 系统日志
  [8] 🔧 修复 Docker 源
  [0] 🔙 返回
```

---

### 🔄 换源工具

```
════════════════════════ 换源工具 ═════════════════
  [1] 🇨🇳 中科大源
  [2] 🎓 清华源
  [3] ☁️  阿里云源
  [4] 🔷 华为云源
  [5] 🎓 南京大学源
  [6] ☁️ 腾讯云源
  [7] 🦑 Ceph源配置
  [0] 🔙 返回
```

---

## 🔥 功能特点

### 📦 容器类型对比

| 特性 | 🔓 特权容器 | 🔒 无特权容器 |
|:---:|:---:|:---:|
| **安全性** | ⚠️ 较低 | ✅ 高 |
| **Docker** | ✅ 完美支持 | ⚠️ 需额外配置 |
| **systemd** | ✅ 完全兼容 | ⚠️ 部分兼容 |
| **适用场景** | 🐳 Docker/开发测试 | 🏢 生产/安全敏感 |

> 💡 创建容器时可选择类型，后续可通过"转换容器类型"功能互转

### 🆕 容器创建

| 功能 | 描述 |
|:---:|:---|
| 📥 自动下载 | 自动检测并下载最新 Debian 模板 |
| ⚙️ 自定义配置 | 内存、CPU 核心、磁盘大小 |
| 🔐 类型选择 | 特权/无特权容器类型 |

### 🌐 网络配置

支持静态 IP / DHCP 切换，显示子网掩码、网络地址、广播地址

### 🐳 Docker 环境

Docker Compose V1/V2 兼容，自动安装/一键换源/容器管理

---

## ⚠️ 注意事项

| ⚠️ 事项 | 📝 说明 |
|:---:|:---|
| 💾 数据备份 | 删除容器等操作不可逆，操作前请备份 |
| 👤 权限要求 | 所有功能需要 root 权限 |
| 🔀 类型转换 | 特权→无特权会修改文件所有权，建议先备份 |

---

<div align="center">

## 🤝 贡献

欢迎提交 [Issue](https://github.com/MuskCheng/pve-toolkit/issues) 和 [Pull Request](https://github.com/MuskCheng/pve-toolkit/pulls)

---

## 📄 许可证

本项目基于 **MIT** 许可证开源

[![License](https://img.shields.io/github/license/MuskCheng/pve-toolkit?style=flat)](LICENSE)

---

### 🌟 如果这个工具对你有帮助，请 Star 支持一下！

[![Star](https://img.shields.io/github/stars/MuskCheng/pve-toolkit?style=social)](https://github.com/MuskCheng/pve-toolkit/stargazers)

</div>
