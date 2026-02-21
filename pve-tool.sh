#!/bin/bash
#
# PVE Toolkit - Proxmox VE 管理工具集
# 版本: V0.28
# 使用: 
#   curl -sL https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/pve-tool.sh -o /tmp/pve.sh && bash /tmp/pve.sh
#   或
#   curl -sL https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/pve-tool.sh | bash -s -- 命令行参数

VERSION="V0.28-fix"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# 检查 root
[[ $EUID -ne 0 ]] && { echo -e "${RED}需要 root 权限${NC}"; exit 1; }

# 检查 PVE 版本
command -v pveversion &>/dev/null && pveversion | grep -q "pve-manager/9" || { echo -e "${RED}需要 PVE 9.0+${NC}"; exit 1; }

# 配置
BACKUP_DIR="/var/lib/vz/dump"
LXC_MEM=2048; LXC_CORES=2; LXC_DISK=20

# 备份模块
backup() {
    case "$1" in
        --list)
            echo -e "${BLUE}=== 备份列表 ===${NC}"
            ls -lh "$BACKUP_DIR"/*.vma.zst 2>/dev/null || echo "无 VM 备份"
            ls -lh "$BACKUP_DIR"/*.tar.zst 2>/dev/null || echo "无 LXC 备份"
            ;;
        --create)
            [[ -z "$2" ]] && { echo "用法: $0 backup --create <ID>"; exit 1; }
            echo "正在备份 VM $2..."
            vzdump "$2" --mode snapshot --compress zstd --storage local
            ;;
        --cleanup)
            echo "清理 7 天前备份..."
            find "$BACKUP_DIR" -name "*.vma.zst" -mtime +7 -delete 2>/dev/null
            find "$BACKUP_DIR" -name "*.tar.zst" -mtime +7 -delete 2>/dev/null
            echo "完成"
            ;;
        *)
            echo -e "${BLUE}备份命令:${NC} --list, --create <ID>, --cleanup"
            ;;
    esac
}

# 监控模块
monitor() {
    case "$1" in
        --status|-s)
            echo -e "${BLUE}=== 系统状态 ===${NC}"
            echo "主机: $(hostname) | PVE: $(pveversion | grep -oP 'pve-manager/\K[0-9.]+')"
            echo "内核: $(uname -r)"
            echo "CPU: $(nproc) 核心 | 内存: $(free -h | awk 'NR==2{print $3\"/\"$2}')"
            echo "磁盘: $(df -h / | awk 'NR==2{print $3\"/\"$2\"(\"$5\")\"}')"
            echo "VM: $(qm list 2>/dev/null | grep running | wc -l) | LXC: $(pct list 2>/dev/null | grep running | wc -l)"
            ;;
        --vm) qm list ;;
        --lxc) pct list ;;
        *) echo -e "${BLUE}监控命令:${NC} --status, --vm, --lxc" ;;
    esac
}

# LXC 模块
lxc() {
    case "$1" in
        --list) pct list ;;
        --create)
            [[ -z "$2" || -z "$3" ]] && { echo "用法: $0 lxc --create <ID> <主机名>"; exit 1; }
            echo "创建 LXC $2 ($3)..."
            pct create "$2" local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst \
                --hostname "$3" --memory $LXC_MEM --cores $LXC_CORES --rootfs local:$LXC_DISK \
                --net0 "name=eth0,bridge=vmbr0,ip=dhcp" --unprivileged 0 --features "nesting=1" --start 1
            ;;
        --start) pct start "$2" ;;
        --stop) pct stop "$2" ;;
        --restart) pct restart "$2" ;;
        --delete)
            pct stop "$2" 2>/dev/null; pct destroy "$2"
            ;;
        --console) pct enter "$2" ;;
        --info) pct config "$2" ;;
        --install-docker)
            [[ -z "$2" ]] && { echo "用法: $0 lxc --install-docker <ID>"; exit 1; }
            echo "安装 Docker 到容器 $2..."
            pct exec "$2" -- bash -c 'apt update && apt install -y docker.io && systemctl enable docker && systemctl start docker'
            pct exec "$2" -- docker --version
            ;;
        *) echo -e "${BLUE}LXC命令:${NC} --list, --create, --start, --stop, --restart, --delete, --console, --info, --install-docker" ;;
    esac
}

# 系统模块
system() {
    case "$1" in
        --info|-i)
            echo -e "${BLUE}=== 系统信息 ===${NC}"
            pveversion -v
            echo "主机: $(hostname) | IP: $(hostname -I | awk '{print $1}')"
            ;;
        --sources)
            echo -e "${BLUE}=== 镜像源 ===${NC}"
            grep -v "^#" /etc/apt/sources.list | grep -v "^$"
            ;;
        --update)
            echo "更新系统..."
            apt update && apt list --upgradable | head -5
            ;;
        --cleanup)
            apt autoremove -y && apt autoclean
            ;;
        *) echo -e "${BLUE}系统命令:${NC} --info, --sources, --update, --cleanup" ;;
    esac
}

# 显示帮助
help() {
    echo -e "${GREEN}PVE Toolkit $VERSION${NC}"
    echo "用法: $0 <模块> <命令> [参数]"
    echo ""
    echo "模块:"
    echo "  backup   备份管理"
    echo "  monitor  系统监控"
    echo "  lxc      LXC 管理"
    echo "  system   系统管理"
    echo ""
    echo "示例:"
    echo "  $0 backup --list"
    echo "  $0 monitor --status"
    echo "  $0 lxc --list"
    echo "  $0 system --info"
    echo ""
    echo "交互模式:"
    echo "  curl -sL https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/pve-tool.sh -o /tmp/pve.sh && bash /tmp/pve.sh"
}

# 主程序
case "$1" in
    backup) shift; backup "$@" ;;
    monitor) shift; monitor "$@" ;;
    lxc) shift; lxc "$@" ;;
    system) shift; system "$@" ;;
    help|-h) help ;;
    *) help ;;
esac
