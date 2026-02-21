#!/bin/bash
#
# PVE Toolkit 完整版 - 单文件脚本
# 使用方法: 
#   curl -sL https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/pve-tool.sh | bash
#   或保存后执行: curl -sL https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/pve-tool.sh -o pve-tool.sh && bash pve-tool.sh
#
# 交互模式直接运行
# 命令行模式: bash pve-tool.sh <command>

set -e

VERSION="V0.21"

# 脚本目录（临时目录）
SCRIPT_DIR="/opt/pve-toolkit"
TEMP_DIR="/tmp/pve-toolkit-$$"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BRIGHT_WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_ask() { echo -e "${YELLOW}[询问]${NC} $1"; }

# 询问确认
ask_confirm() {
    local prompt="$1"
    local default="${2:-N}"
    local confirm
    echo -ne "${YELLOW}$prompt (y/N): ${NC}"
    read -r confirm
    [[ "$confirm" =~ ^[Yy]$ ]]
}

# 检查 root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_err "此脚本需要 root 权限"
        echo "请使用: su - root -c 'curl -sL https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/pve-tool.sh | bash'"
        exit 1
    fi
}

# 检查 PVE 版本
check_pve_version() {
    if command -v pveversion &>/dev/null; then
        local pve_ver=$(pveversion | grep -oP 'pve-manager/\K[0-9]+')
        if [[ -n "$pve_ver" ]] && [[ "$pve_ver" -ge 9 ]]; then
            log_ok "检测到 PVE 版本: $pve_ver"
            return 0
        else
            log_err "不支持的 PVE 版本 (需要 PVE 9.0+, 当前: $pve_ver)"
            exit 1
        fi
    else
        if [[ -f /etc/os-release ]]; then
            local version_id=$(grep -oP 'VERSION_ID=\K[0-9]+' /etc/os-release | head -1)
            if [[ "$version_id" -ge 9 ]]; then
                log_ok "检测到 Debian 版本: $version_id"
                return 0
            fi
        fi
        log_err "无法确定系统版本，请确保这是 PVE 9.0+ 系统"
        exit 1
    fi
}

# 检查依赖
check_dependencies() {
    for cmd in curl; do
        if ! command -v $cmd &>/dev/null; then
            log_err "需要安装 $cmd"
            exit 1
        fi
    done
    
    if ! command -v git &>/dev/null; then
        log_warn "未检测到 git，正在安装..."
        apt-get update -qq 2>/dev/null || true
        apt-get install -y -qq git 2>/dev/null || apt-get install -y git 2>/dev/null || true
    fi
}

# 下载模块
download_modules() {
    mkdir -p "$SCRIPT_DIR/modules" "$SCRIPT_DIR/config"
    
    local base_url="https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master"
    
    # 下载模块文件
    for module in backup.sh lxc.sh monitor.sh system.sh; do
        log_info "下载 $module..."
        curl -fsSL "$base_url/modules/$module" -o "$SCRIPT_DIR/modules/$module" || {
            log_err "下载 $module 失败"
            exit 1
        }
    done
    
    # 下载配置文件
    log_info "下载配置文件..."
    curl -fsSL "$base_url/config/settings.conf" -o "$SCRIPT_DIR/config/settings.conf" || {
        log_err "下载配置文件失败"
        exit 1
    }
    
    # 设置权限
    chmod +x "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR/modules"/*.sh 2>/dev/null || true
    
    log_ok "模块下载完成"
}

# 加载配置
load_config() {
    if [[ -f "${SCRIPT_DIR}/config/settings.conf" ]]; then
        source "${SCRIPT_DIR}/config/settings.conf"
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
    for module in "${SCRIPT_DIR}/modules"/*.sh; do
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
    echo -e "${WHITE}${BOLD}              Proxmox VE 管理工具集 $VERSION (适用于 PVE 9.*)${NC}"
}

# 显示分割线
show_separator() {
    echo -e "${WHITE}════════════════════════════════════════════════════════════════${NC}"
}

# 显示菜单
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
                if ask_confirm "是否进入备份管理？"; then
                    backup_interactive
                fi
                ;;
            2)
                echo ""
                echo -e "${GREEN}>>> 进入系统监控模块${NC}"
                if ask_confirm "是否进入系统监控？"; then
                    monitor_interactive
                fi
                ;;
            3)
                echo ""
                echo -e "${GREEN}>>> 进入 LXC 容器管理模块${NC}"
                if ask_confirm "是否进入 LXC 容器管理？"; then
                    lxc_interactive
                fi
                ;;
            4)
                echo ""
                echo -e "${GREEN}>>> 进入系统更新/镜像源管理模块${NC}"
                if ask_confirm "是否进入系统管理？"; then
                    system_interactive
                fi
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

# 显示帮助
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
    # 如果有命令行参数，直接执行命令模式
    if [[ $# -gt 0 ]]; then
        # 先确保模块已下载
        if [[ ! -d "$SCRIPT_DIR/modules" ]]; then
            check_root
            check_pve_version
            check_dependencies
            download_modules
        fi
        load_config
        load_modules
        
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
        check_root
        check_pve_version
        check_dependencies
        
        # 检查是否已安装
        if [[ ! -d "$SCRIPT_DIR/modules" ]]; then
            echo ""
            log_info "首次运行，正在初始化..."
            download_modules
        fi
        
        load_config
        load_modules
        interactive_main
    fi
}

main "$@"
