#!/bin/bash
#
# PVE Toolkit - Proxmox VE 管理工具集
# 适用于 PVE 9.*
#

set -e

# 检查 root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 此脚本需要 root 权限运行${NC}"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 脚本目录 exit 1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
MODULES_DIR="${SCRIPT_DIR}/modules"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BRIGHT_WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 加载配置
load_config() {
    if [[ -f "${CONFIG_DIR}/settings.conf" ]]; then
        source "${CONFIG_DIR}/settings.conf"
    else
        echo -e "${YELLOW}警告: 配置文件不存在，使用默认配置${NC}"
    fi
    
    : "${BACKUP_DIR:=/var/lib/vz/dump}"
    : "${BACKUP_RETENTION_DAYS:=7}"
    : "${BACKUP_COMPRESS:=zstd}"
    : "${MONITOR_INTERVAL:=60}"
    : "${ALERT_THRESHOLD_CPU:=90}"
    : "${ALERT_THRESHOLD_MEM:=90}"
    : "${ALERT_THRESHOLD_DISK:=85}"
    : "${LXC_DEFAULT_MEMORY:=2048}"
    : "${LXC_DEFAULT_CORES:=2}"
    : "${LXC_DEFAULT_DISK:=20}"
}

# 加载模块
load_modules() {
    for module in "${MODULES_DIR}"/*.sh; do
        if [[ -f "$module" ]]; then
            source "$module"
        fi
    done
}

# 显示 Logo
show_logo() {
    clear
    echo -e "${BRIGHT_WHITE}"
    cat << "EOF"
██████╗ ██╗   ██╗███████╗    ████████╗ ██████╗  ██████╗ ██╗     
██╔══██╗██║   ██║██╔════╝    ╚══██╔══╝██╔═══██╗██╔═══██╗██║     
██████╔╝██║   ██║█████╗         ██║   ██║   ██║██║   ██║██║     
██╔═══╝ ╚██╗ ██╔╝██╔══╝         ██║   ██║   ██║██║   ██║██║     
██║      ╚████╔╝ ███████╗       ██║   ╚██████╔╝╚██████╔╝███████╗
╚═╝       ╚═══╝  ╚══════╝       ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝
                                                                
EOF
    echo -e "${NC}"
    echo -e "${WHITE}${BOLD}              Proxmox VE 管理工具集 V0.17 (适用于 PVE 9.*)${NC}"
}

# 显示分割线
show_separator() {
    echo -e "${WHITE}════════════════════════════════════════════════════════════════${NC}"
}

# 显示交互菜单
show_menu() {
    echo ""
    show_separator
    echo -e "               ${WHITE}[1]${NC} 备份管理"
    echo -e "               ${WHITE}[2]${NC} 系统监控"
    echo -e "               ${WHITE}[3]${NC} LXC 容器管理"
    echo -e "               ${WHITE}[4]${NC} 系统更新/镜像源"
    echo -e "               ${WHITE}[0]${NC} 退出"
    show_separator
    echo -e "        ${YELLOW}[!] 操作前请确认已备份重要数据${NC}"
    echo ""
}

# 交互式主循环
interactive_main() {
    while true; do
        show_logo
        show_menu
        
        echo -ne "    ${WHITE}请选择功能 [0-4]: ${NC}"
        read -r choice
        
        case "$choice" in
            1)
                echo ""
                echo -e "${GREEN}>>> 进入备份管理模块${NC}"
                backup_interactive
                ;;
            2)
                echo ""
                echo -e "${GREEN}>>> 进入系统监控模块${NC}"
                monitor_interactive
                ;;
            3)
                echo ""
                echo -e "${GREEN}>>> 进入 LXC 容器管理模块${NC}"
                lxc_interactive
                ;;
            4)
                echo ""
                echo -e "${GREEN}>>> 进入系统更新/镜像源管理模块${NC}"
                system_interactive
                ;;
            0)
                echo ""
                echo -e "${GREEN}感谢使用 PVE Toolkit，再见！${NC}"
                exit 0
                ;;
            *)
                echo ""
                echo -e "${RED}无效选择，请输入 0-4${NC}"
                ;;
        esac
        
        echo ""
        echo -ne "${YELLOW}按回车键继续...${NC}"
        read -r
    done
}

# 显示帮助信息
show_help() {
    echo -e "${BLUE}PVE Toolkit - Proxmox VE 管理工具集${NC}"
    echo ""
    echo "用法: $0 <命令> [选项]"
    echo ""
    echo "命令:"
    echo "  backup    备份管理"
    echo "  monitor   系统监控"
    echo "  lxc       LXC 容器管理"
    echo "  system    系统更新/镜像源管理"
    echo "  help      显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 backup --list"
    echo "  $0 monitor --status"
    echo "  $0 lxc --list"
    echo "  $0 system --update"
}

# 主函数
main() {
    check_root
    load_config
    load_modules

    # 如果有命令行参数，直接执行命令模式
    if [[ $# -gt 0 ]]; then
        case "${1:-}" in
            backup)
                shift
                backup_main "$@"
                ;;
            monitor)
                shift
                monitor_main "$@"
                ;;
            lxc)
                shift
                lxc_main "$@"
                ;;
            system)
                shift
                system_main "$@"
                ;;
            help|--help|-h)
                show_help
                ;;
            *)
                echo -e "${RED}错误: 未知命令 '${1:-}'${NC}"
                show_help
                exit 1
                ;;
        esac
    else
        # 无参数时启动交互模式
        interactive_main
    fi
}

main "$@"
