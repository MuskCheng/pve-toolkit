#!/bin/bash
#
# PVE Toolkit - Proxmox VE 管理工具集
# 版本: V0.27
# 使用方法: curl -sL https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/pve-tool.sh | bash

VERSION="V0.27"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }

# 检查 root
check_root() {
    [[ $EUID -ne 0 ]] && { log_err "需要 root 权限"; exit 1; }
}

# 检查 PVE 版本
check_pve_version() {
    if command -v pveversion &>/dev/null; then
        local v=$(pveversion | grep -oP 'pve-manager/\K[0-9]+')
        [[ -n "$v" && "$v" -ge 9 ]] && { log_ok "PVE $v"; return 0; }
    fi
    log_err "需要 PVE 9.0+"; exit 1
}

# 默认配置
BACKUP_DIR="/var/lib/vz/dump"
BACKUP_RETENTION_DAYS=7
BACKUP_COMPRESS="zstd"
LXC_DEFAULT_MEMORY=2048
LXC_DEFAULT_CORES=2
LXC_DEFAULT_DISK=20

# ========== 备份管理 ==========
backup_list() {
    echo -e "${BLUE}=== 备份列表 ===${NC}"
    ls -lh "$BACKUP_DIR"/*.vma.zst 2>/dev/null || echo "无 VM 备份"
    ls -lh "$BACKUP_DIR"/*.tar.zst 2>/dev/null || echo "无 LXC 备份"
}

backup_create() {
    [[ -z "$1" ]] && { echo "需要 VM ID"; return 1; }
    echo "正在备份 $1..."; vzdump "$1" --mode snapshot --compress "$BACKUP_COMPRESS" --storage local
}

backup_cleanup() {
    echo "清理 $BACKUP_RETENTION_DAYS 天前备份..."
    find "$BACKUP_DIR" -name "*.vma.zst" -mtime +$BACKUP_RETENTION_DAYS -delete 2>/dev/null
    find "$BACKUP_DIR" -name "*.tar.zst" -mtime +$BACKUP_RETENTION_DAYS -delete 2>/dev/null
    echo "完成"
}

backup_main() {
    case "$1" in
        --list|-l) backup_list ;;
        --create|-c) backup_create "$2" ;;
        --cleanup) backup_cleanup ;;
        *) echo "命令: --list, --create, --cleanup" ;;
    esac
}

# ========== 监控 ==========
monitor_status() {
    echo -e "${BLUE}=== 系统状态 ===${NC}"
    echo "主机: $(hostname) | PVE: $(pveversion 2>/dev/null | grep -oP 'pve-manager/\K[0-9.]+')"
    echo "内核: $(uname -r)"
    echo "CPU: $(nproc) 核心"
    echo "内存: $(free -h | awk 'NR==2{print $3\"/\"$2}')"
    echo "磁盘: $(df -h / | awk 'NR==2{print $3\"/\"$2\"(\"$5\")\"}')"
    echo "VM: $(qm list 2>/dev/null | grep running | wc -l) | LXC: $(pct list 2>/dev/null | grep running | wc -l)"
}

monitor_main() {
    case "$1" in
        --status|-s) monitor_status ;;
        --vm) qm list ;;
        --lxc) pct list ;;
        *) echo "命令: --status, --vm, --lxc" ;;
    esac
}

# ========== LXC ==========
lxc_list() { pct list; }

lxc_create() {
    [[ -z "$1" || -z "$2" ]] && { echo "用法: lxc --create <ID> <主机名>"; return; }
    echo "创建 LXC $1 ($2)..."
    pct create "$1" local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst \
        --hostname "$2" --memory $LXC_DEFAULT_MEMORY --cores $LXC_DEFAULT_CORES \
        --rootfs local:$LXC_DEFAULT_DISK --net0 "name=eth0,bridge=vmbr0,ip=dhcp" \
        --unprivileged 0 --features "nesting=1" --start 1 && echo "完成"
}

lxc_main() {
    case "$1" in
        --list|-l) lxc_list ;;
        --create|-c) lxc_create "$2" "$3" ;;
        --start) pct start "$2" && echo "已启动" ;;
        --stop) pct stop "$2" && echo "已停止" ;;
        --restart) pct restart "$2" && echo "已重启" ;;
        --delete) pct stop "$2" 2>/dev/null; pct destroy "$2" && echo "已删除" ;;
        --console) pct enter "$2" ;;
        --info) pct config "$2" ;;
        --install-docker)
            echo "安装 Docker..."
            pct exec "$2" -- bash -c 'apt update && apt install -y docker.io && systemctl enable docker && systemctl start docker'
            pct exec "$2" -- docker --version
            ;;
        *) echo "命令: --list, --create, --start, --stop, --restart, --delete, --console, --info, --install-docker" ;;
    esac
}

# ========== 系统 ==========
system_info() {
    echo -e "${BLUE}=== 系统信息 ===${NC}"
    pveversion -v 2>/dev/null
    echo "主机: $(hostname) | IP: $(hostname -I | awk '{print $1}')"
}

system_update() {
    echo "更新系统..."
    apt update && apt list --upgradable | head -5
    read -p "确认升级? (y/N): " c
    [[ "$c" == "y" ]] && apt dist-upgrade -y
}

system_main() {
    case "$1" in
        --info|-i) system_info ;;
        --sources) cat /etc/apt/sources.list ;;
        --update|-u) system_update ;;
        --cleanup) apt autoremove -y && apt autoclean && echo "完成" ;;
        *) echo "命令: --info, --sources, --update, --cleanup" ;;
    esac
}

# ========== 菜单 ==========
show_menu() {
    echo ""
    echo -e "${BOLD}====== PVE Toolkit $VERSION ======${NC}"
    echo -e "${GREEN}[1]${NC} 备份管理"
    echo -e "${GREEN}[2]${NC} 系统监控"
    echo -e "${GREEN}[3]${NC} LXC 管理"
    echo -e "${GREEN}[4]${NC} 系统管理"
    echo -e "${GREEN}[0]${NC} 退出"
    echo -e "${YELLOW}⚠ 操作前请备份数据${NC}"
}

main() {
    if [[ $# -gt 0 ]]; then
        case "$1" in
            backup) shift; backup_main "$@" ;;
            monitor) shift; monitor_main "$@" ;;
            lxc) shift; lxc_main "$@" ;;
            system) shift; system_main "$@" ;;
            help|-h) echo "用法: $0 <backup|monitor|lxc|system> [选项]" ;;
            *) echo "错误: 未知命令"; exit 1 ;;
        esac
        return
    fi
    
    check_root
    check_pve_version
    log_ok "PVE Toolkit $VERSION"
    
    while true; do
        show_menu
        echo -ne "${CYAN}选择 [0-4]: ${NC}"
        read -r c
        
        case "$c" in
            1) backup_main --list; echo -ne "${YELLOW}按回车继续...${NC}"; read ;;
            2) monitor_main --status; echo -ne "${YELLOW}按回车继续...${NC}"; read ;;
            3) lxc_main --list; echo -ne "${YELLOW}按回车继续...${NC}"; read ;;
            4) system_main --info; echo -ne "${YELLOW}按回车继续...${NC}"; read ;;
            0) echo "再见"; exit 0 ;;
            *) echo "无效" ;;
        esac
    done
}

main "$@"
