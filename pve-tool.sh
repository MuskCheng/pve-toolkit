#!/bin/bash
#
# PVE Toolkit - Proxmox VE 管理工具集
# 版本: V0.22
# 使用方法: curl -sL https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/pve-tool.sh | bash

set -e

VERSION="V0.24"

# 检测管道执行并自动保存
if [[ ! -t 0 ]] && [[ -z "$PVE_TOOL_SAVED" ]]; then
    echo "[INFO] 检测到管道执行，正在保存脚本..."
    SCRIPT_PATH="/tmp/pve-tool-$(date +%s).sh"
    cat > "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    echo "[INFO] 脚本已保存到: $SCRIPT_PATH"
    echo "[INFO] 请使用以下命令运行:"
    echo "    bash $SCRIPT_PATH"
    exec bash "$SCRIPT_PATH"
fi

export PVE_TOOL_SAVED=1

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
    echo -ne "${YELLOW}$prompt (y/N): ${NC}"
    if [[ -t 0 ]]; then
        read -r confirm
    else
        read -r confirm || confirm="n"
    fi
    [[ "$confirm" =~ ^[Yy]$ ]]
}

# 检查 root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_err "此脚本需要 root 权限"
        echo "请使用 root 用户运行或加 sudo"
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

# 默认配置
BACKUP_DIR="/var/lib/vz/dump"
BACKUP_RETENTION_DAYS=7
BACKUP_COMPRESS="zstd"
MONITOR_INTERVAL=60
ALERT_THRESHOLD_CPU=90
ALERT_THRESHOLD_MEM=90
ALERT_THRESHOLD_DISK=85
LXC_DEFAULT_MEMORY=2048
LXC_DEFAULT_CORES=2
LXC_DEFAULT_DISK=20

# ========== 备份管理模块 ==========

backup_list() {
    echo -e "${BLUE}=== 备份列表 ===${NC}"
    if [[ -d "$BACKUP_DIR" ]]; then
        ls -lh "$BACKUP_DIR"/*.vma.zst 2>/dev/null || echo -e "${YELLOW}无 VM 备份${NC}"
        ls -lh "$BACKUP_DIR"/*.tar.zst 2>/dev/null || echo -e "${YELLOW}无 LXC 备份${NC}"
    else
        echo -e "${RED}备份目录不存在: $BACKUP_DIR${NC}"
    fi
}

backup_create() {
    local vmid="$1"
    local mode="${2:-snapshot}"
    
    if [[ -z "$vmid" ]]; then
        echo -e "${RED}错误: 请指定 VM/LXC ID${NC}"
        return 1
    fi
    
    echo -e "${GREEN}正在备份 $vmid (模式: $mode)...${NC}"
    vzdump "$vmid" --mode "$mode" --compress "$BACKUP_COMPRESS" --storage local
}

backup_cleanup() {
    echo -e "${BLUE}清理 ${BACKUP_RETENTION_DAYS} 天前的备份...${NC}"
    find "$BACKUP_DIR" -name "*.vma.zst" -mtime +${BACKUP_RETENTION_DAYS} -delete 2>/dev/null || true
    find "$BACKUP_DIR" -name "*.tar.zst" -mtime +${BACKUP_RETENTION_DAYS} -delete 2>/dev/null || true
    echo -e "${GREEN}清理完成${NC}"
}

backup_restore() {
    local backup_file="$1"
    local vmid="$2"
    
    if [[ -z "$backup_file" ]] || [[ -z "$vmid" ]]; then
        echo -e "${RED}错误: 请指定备份文件和目标 VM ID${NC}"
        return 1
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        echo -e "${RED}错误: 备份文件不存在: $backup_file${NC}"
        return 1
    fi
    
    local restore_cmd=""
    if [[ "$backup_file" == *.vma.zst ]]; then
        restore_cmd="qmrestore"
    elif [[ "$backup_file" == *.tar.zst ]]; then
        restore_cmd="pctrestore"
    else
        echo -e "${RED}错误: 未知的备份文件格式${NC}"
        return 1
    fi
    
    if ask_confirm "警告: 这将覆盖现有的 VM/LXC $vmid，是否继续？"; then
        if [[ "$restore_cmd" == "qmrestore" ]]; then
            qmrestore "$backup_file" "$vmid" --storage local
        else
            pctrestore "$vmid" "$backup_file" --storage local
        fi
    fi
}

backup_help() {
    echo -e "${BLUE}备份管理命令:${NC}"
    echo "  --list              列出所有备份"
    echo "  --create <ID>       创建备份"
    echo "  --cleanup           清理旧备份"
    echo "  --restore <file> <ID> 恢复备份"
}

backup_main() {
    case "${1:-}" in
        --list|-l) backup_list ;;
        --create|-c) backup_create "$2" "$3" ;;
        --cleanup) backup_cleanup ;;
        --restore|-r) backup_restore "$2" "$3" ;;
        --help|-h) backup_help ;;
        *) echo -e "${RED}错误: 未知备份命令${NC}"; backup_help; return 1 ;;
    esac
}

backup_interactive() {
    while true; do
        echo ""
        echo -e "${BLUE}═══════════════════════════════════════${NC}"
        echo -e "${BOLD}            备份管理${NC}"
        echo -e "${BLUE}═══════════════════════════════════════${NC}"
        echo ""
        echo -e "  ${GREEN}[1]${NC} 列出所有备份"
        echo -e "  ${GREEN}[2]${NC} 创建备份"
        echo -e "  ${GREEN}[3]${NC} 清理旧备份"
        echo -e "  ${GREEN}[4]${NC} 恢复备份"
        echo -e "  ${GREEN}[0]${NC} 返回主菜单"
        echo ""
        echo -ne "${CYAN}请选择 [0-4]: ${NC}"
        read -r choice
        
        case "$choice" in
            1) backup_list ;;
            2)
                echo -ne "请输入 VM/LXC ID: "; read -r vmid
                echo -ne "备份模式 (snapshot/suspend/stop) [snapshot]: "; read -r mode
                backup_create "$vmid" "${mode:-snapshot}"
                ;;
            3) backup_cleanup ;;
            4)
                backup_list
                echo -ne "请输入备份文件路径: "; read -r backup_file
                echo -ne "请输入目标 VM ID: "; read -r vmid
                backup_restore "$backup_file" "$vmid"
                ;;
            0) return 0 ;;
            *) echo -e "${RED}无效选择${NC}" ;;
        esac
        
        echo ""; echo -ne "${YELLOW}按回车键继续...${NC}"; read -r
    done
}

# ========== 系统监控模块 ==========

monitor_status() {
    echo -e "${BLUE}=== PVE 系统状态 ===${NC}"
    echo ""
    echo -e "${GREEN}主机信息:${NC}"
    echo "  主机名: $(hostname)"
    echo "  PVE 版本: $(pveversion 2>/dev/null || echo 'N/A')"
    echo "  内核版本: $(uname -r)"
    echo ""
    
    local cpu_usage
    if command -v mpstat &>/dev/null; then
        cpu_usage=$(mpstat 1 1 | awk 'END {print 100 - $NF}')
    else
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 || echo "N/A")
    fi
    echo -e "${GREEN}CPU:${NC}"
    echo "  使用率: ${cpu_usage}%"
    echo "  核心数: $(nproc)"
    echo ""
    
    echo -e "${GREEN}内存:${NC}"
    free -h | awk 'NR==2{printf "  已用: %s / %s (%.1f%%)\n", $3, $2, $3*100/$2}'
    echo ""
    
    echo -e "${GREEN}磁盘:${NC}"
    df -h | grep -E "^/dev/" | awk '{printf "  %s: %s / %s (%s)\n", $1, $3, $2, $5}'
    echo ""
    
    echo -e "${GREEN}虚拟机/容器:${NC}"
    echo "  运行中 VM: $(qm list 2>/dev/null | grep running | wc -l || echo 0)"
    echo "  运行中 LXC: $(pct list 2>/dev/null | grep running | wc -l || echo 0)"
}

monitor_vm() {
    echo -e "${BLUE}=== 虚拟机状态 ===${NC}"
    qm list 2>/dev/null || echo "无法获取 VM 列表"
}

monitor_lxc() {
    echo -e "${BLUE}=== LXC 容器状态 ===${NC}"
    pct list 2>/dev/null || echo "无法获取 LXC 列表"
}

monitor_resources() {
    echo -e "${BLUE}=== 资源使用详情 ===${NC}"
    echo ""
    
    local cpu_usage=0
    if command -v mpstat &>/dev/null; then
        cpu_usage=$(mpstat 1 1 | awk 'END {print int(100 - $NF)}')
    else
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | cut -d'.' -f1 || echo 0)
    fi
    if [[ "$cpu_usage" =~ ^[0-9]+$ ]] && [[ "$cpu_usage" -gt "$ALERT_THRESHOLD_CPU" ]]; then
        echo -e "${RED}⚠ CPU 使用率超过阈值: ${cpu_usage}% > ${ALERT_THRESHOLD_CPU}%${NC}"
    else
        echo -e "${GREEN}✓ CPU 使用率正常: ${cpu_usage}%${NC}"
    fi
    
    local mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [[ "$mem_usage" -gt "$ALERT_THRESHOLD_MEM" ]]; then
        echo -e "${RED}⚠ 内存使用率超过阈值: ${mem_usage}% > ${ALERT_THRESHOLD_MEM}%${NC}"
    else
        echo -e "${GREEN}✓ 内存使用率正常: ${mem_usage}%${NC}"
    fi
    
    local disk_usage=$(df / | awk 'NR==2{print $5}' | tr -d '%')
    if [[ "$disk_usage" -gt "$ALERT_THRESHOLD_DISK" ]]; then
        echo -e "${RED}⚠ 磁盘使用率超过阈值: ${disk_usage}% > ${ALERT_THRESHOLD_DISK}%${NC}"
    else
        echo -e "${GREEN}✓ 磁盘使用率正常: ${disk_usage}%${NC}"
    fi
}

monitor_network() {
    echo -e "${BLUE}=== 网络状态 ===${NC}"
    ip -brief addr 2>/dev/null || echo "无法获取网络信息"
    echo ""
    echo -e "${GREEN}网络流量:${NC}"
    cat /proc/net/dev | grep -E "vmbr|eth|enp" | awk '{printf "  %s: 接收 %s / 发送 %s\n", $1, $2, $10}' 2>/dev/null || true
}

monitor_logs() {
    local lines="${1:-50}"
    echo -e "${BLUE}=== 最近 $lines 条系统日志 ===${NC}"
    journalctl -n "$lines" --no-pager 2>/dev/null || echo "无法获取日志"
}

monitor_help() {
    echo -e "${BLUE}监控命令:${NC}"
    echo "  --status       显示系统状态概览"
    echo "  --vm           显示虚拟机状态"
    echo "  --lxc          显示 LXC 容器状态"
    echo "  --resources    检查资源使用阈值"
    echo "  --network      显示网络状态"
    echo "  --logs [N]     显示最近 N 条日志 (默认 50)"
}

monitor_main() {
    case "${1:-}" in
        --status|-s) monitor_status ;;
        --vm) monitor_vm ;;
        --lxc) monitor_lxc ;;
        --resources|-r) monitor_resources ;;
        --network|-n) monitor_network ;;
        --logs|-l) monitor_logs "$2" ;;
        --help|-h) monitor_help ;;
        *) echo -e "${RED}错误: 未知监控命令${NC}"; monitor_help; return 1 ;;
    esac
}

monitor_interactive() {
    while true; do
        echo ""
        echo -e "${BLUE}═══════════════════════════════════════${NC}"
        echo -e "${BOLD}            系统监控${NC}"
        echo -e "${BLUE}═══════════════════════════════════════${NC}"
        echo ""
        echo -e "  ${GREEN}[1]${NC} 系统状态概览"
        echo -e "  ${GREEN}[2]${NC} 虚拟机状态"
        echo -e "  ${GREEN}[3]${NC} LXC 容器状态"
        echo -e "  ${GREEN}[4]${NC} 资源阈值检查"
        echo -e "  ${GREEN}[5]${NC} 网络状态"
        echo -e "  ${GREEN}[6]${NC} 系统日志"
        echo -e "  ${GREEN}[0]${NC} 返回主菜单"
        echo ""
        echo -ne "${CYAN}请选择 [0-6]: ${NC}"
        read -r choice
        
        case "$choice" in
            1) monitor_status ;;
            2) monitor_vm ;;
            3) monitor_lxc ;;
            4) monitor_resources ;;
            5) monitor_network ;;
            6)
                echo -ne "显示日志条数 [50]: "; read -r lines
                monitor_logs "${lines:-50}"
                ;;
            0) return 0 ;;
            *) echo -e "${RED}无效选择${NC}" ;;
        esac
        
        echo ""; echo -ne "${YELLOW}按回车键继续...${NC}"; read -r
    done
}

# ========== LXC 管理模块 ==========

lxc_list() {
    echo -e "${BLUE}=== LXC 容器列表 ===${NC}"
    pct list 2>/dev/null || echo "无法获取 LXC 列表"
}

lxc_create() {
    local vmid="$1"
    local hostname="$2"
    local memory="${3:-$LXC_DEFAULT_MEMORY}"
    local cores="${4:-$LXC_DEFAULT_CORES}"
    local disk="${5:-$LXC_DEFAULT_DISK}"
    
    if [[ -z "$vmid" ]] || [[ -z "$hostname" ]]; then
        echo -e "${RED}错误: 请指定容器 ID 和主机名${NC}"
        echo "用法: $0 lxc --create <ID> <主机名> [内存] [核心数] [磁盘大小]"
        return 1
    fi
    
    echo -e "${GREEN}创建 LXC 容器 $vmid...${NC}"
    echo "  主机名: $hostname"
    echo "  内存: ${memory}MB"
    echo "  核心数: $cores"
    echo "  磁盘: ${disk}GB"
    
    pct create "$vmid" "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst" \
        --hostname "$hostname" \
        --memory "$memory" \
        --cores "$cores" \
        --rootfs "local:${disk}" \
        --net0 "name=eth0,bridge=vmbr0,ip=dhcp" \
        --unprivileged 0 \
        --features "nesting=1,keyctl=1" \
        --start 1
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}容器 $vmid 创建成功并已启动${NC}"
    else
        echo -e "${RED}容器创建失败${NC}"
        return 1
    fi
}

lxc_start() {
    local vmid="$1"
    if [[ -z "$vmid" ]]; then
        echo -e "${RED}错误: 请指定容器 ID${NC}"
        return 1
    fi
    pct start "$vmid"
    echo -e "${GREEN}容器 $vmid 已启动${NC}"
}

lxc_stop() {
    local vmid="$1"
    if [[ -z "$vmid" ]]; then
        echo -e "${RED}错误: 请指定容器 ID${NC}"
        return 1
    fi
    pct stop "$vmid"
    echo -e "${GREEN}容器 $vmid 已停止${NC}"
}

lxc_restart() {
    local vmid="$1"
    if [[ -z "$vmid" ]]; then
        echo -e "${RED}错误: 请指定容器 ID${NC}"
        return 1
    fi
    pct restart "$vmid"
    echo -e "${GREEN}容器 $vmid 已重启${NC}"
}

lxc_delete() {
    local vmid="$1"
    local force="$2"
    
    if [[ -z "$vmid" ]]; then
        echo -e "${RED}错误: 请指定容器 ID${NC}"
        return 1
    fi
    
    if [[ "$force" == "-f" ]] || [[ "$force" == "--force" ]]; then
        pct stop "$vmid" 2>/dev/null || true
        pct destroy "$vmid"
        echo -e "${GREEN}容器 $vmid 已删除${NC}"
    else
        if ask_confirm "警告: 这将删除容器 $vmid 及其所有数据，是否继续？"; then
            pct stop "$vmid" 2>/dev/null || true
            pct destroy "$vmid"
            echo -e "${GREEN}容器 $vmid 已删除${NC}"
        fi
    fi
}

lxc_console() {
    local vmid="$1"
    if [[ -z "$vmid" ]]; then
        echo -e "${RED}错误: 请指定容器 ID${NC}"
        return 1
    fi
    pct enter "$vmid"
}

lxc_info() {
    local vmid="$1"
    if [[ -z "$vmid" ]]; then
        echo -e "${RED}错误: 请指定容器 ID${NC}"
        return 1
    fi
    echo -e "${BLUE}=== 容器 $vmid 详情 ===${NC}"
    pct config "$vmid" 2>/dev/null || echo "无法获取容器信息"
}

lxc_install_docker() {
    local vmid="$1"
    if [[ -z "$vmid" ]]; then
        echo -e "${RED}错误: 请指定容器 ID${NC}"
        return 1
    fi
    
    echo -e "${GREEN}正在为容器 $vmid 安装 Docker...${NC}"
    
    pct exec "$vmid" -- bash -c '
        apt update && apt install -y curl ca-certificates gnupg lsb-release
        
        CODENAME=$(lsb_release -cs)
        mkdir -p /etc/apt/keyrings
        
        if curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null; then
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${CODENAME} stable" > /etc/apt/sources.list.d/docker.list
            if apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null; then
                DOCKER_OK=1
            fi
        fi
        
        if [[ "$DOCKER_OK" != "1" ]]; then
            rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
            apt install -y docker.io 2>/dev/null || true
        fi
        
        systemctl enable docker 2>/dev/null || systemctl enable docker.io 2>/dev/null || true
        systemctl start docker 2>/dev/null || systemctl start docker.io 2>/dev/null || true
    '
    
    if [[ $? -eq 0 ]]; then
        pct exec "$vmid" -- bash -c "mkdir -p /etc/docker && echo '{\"registry-mirrors\":[\"https://docker.m.daocloud.io\",\"https://hub.rat.dev\"]}' > /etc/docker/daemon.json"
        pct exec "$vmid" -- bash -c "systemctl restart docker 2>/dev/null || systemctl restart docker.io 2>/dev/null || true"
        echo -e "${GREEN}Docker 安装完成${NC}"
        pct exec "$vmid" -- docker --version 2>/dev/null || pct exec "$vmid" -- docker.io --version 2>/dev/null
    else
        echo -e "${RED}Docker 安装失败${NC}"
        return 1
    fi
}

lxc_install_docker_compose() {
    local vmid="$1"
    if [[ -z "$vmid" ]]; then
        echo -e "${RED}错误: 请指定容器 ID${NC}"
        return 1
    fi
    
    echo -e "${GREEN}正在为容器 $vmid 安装 Docker Compose...${NC}"
    pct exec "$vmid" -- bash -c "apt update && apt install -y python3-pip && pip3 install docker-compose --break-system-packages" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Docker Compose 安装完成${NC}"
        pct exec "$vmid" -- docker-compose --version 2>/dev/null
    else
        echo -e "${RED}Docker Compose 安装失败${NC}"
        return 1
    fi
}

lxc_help() {
    echo -e "${BLUE}LXC 容器管理命令:${NC}"
    echo "  --list                     列出所有容器"
    echo "  --create <ID> <名称> [内存] [核心] [磁盘]  创建新容器"
    echo "  --start <ID>               启动容器"
    echo "  --stop <ID>                停止容器"
    echo "  --restart <ID>             重启容器"
    echo "  --delete <ID> [-f]        删除容器"
    echo "  --console <ID>            进入容器控制台"
    echo "  --install-docker <ID>     安装 Docker"
    echo "  --install-compose <ID>    安装 Docker Compose"
    echo "  --info <ID>               显示容器详情"
}

lxc_main() {
    case "${1:-}" in
        --list|-l) lxc_list ;;
        --create|-c) lxc_create "$2" "$3" "$4" "$5" "$6" ;;
        --start) lxc_start "$2" ;;
        --stop) lxc_stop "$2" ;;
        --restart) lxc_restart "$2" ;;
        --delete|-d) lxc_delete "$2" "$3" ;;
        --console) lxc_console "$2" ;;
        --install-docker) lxc_install_docker "$2" ;;
        --install-compose) lxc_install_docker_compose "$2" ;;
        --info|-i) lxc_info "$2" ;;
        --help|-h) lxc_help ;;
        *) echo -e "${RED}错误: 未知 LXC 命令${NC}"; lxc_help; return 1 ;;
    esac
}

lxc_interactive() {
    while true; do
        echo ""
        echo -e "${WHITE}═══════════════════════════════════════${NC}"
        echo -e "${BOLD}          LXC 容器管理${NC}"
        echo -e "${WHITE}═══════════════════════════════════════${NC}"
        echo ""
        echo -e "  ${GREEN}[1]${NC} 列出所有容器"
        echo -e "  ${GREEN}[2]${NC} 创建容器"
        echo -e "  ${GREEN}[3]${NC} 启动容器"
        echo -e "  ${GREEN}[4]${NC} 停止容器"
        echo -e "  ${GREEN}[5]${NC} 重启容器"
        echo -e "  ${GREEN}[6]${NC} 删除容器"
        echo -e "  ${GREEN}[7]${NC} 安装 Docker"
        echo -e "  ${GREEN}[8]${NC} 安装 Docker Compose"
        echo -e "  ${GREEN}[9]${NC} 容器详情"
        echo -e "  ${GREEN}[0]${NC} 返回主菜单"
        echo ""
        echo -ne "${WHITE}请选择 [0-9]: ${NC}"
        read -r choice
        
        case "$choice" in
            1) lxc_list ;;
            2)
                echo -ne "请输入容器 ID: "; read -r vmid
                echo -ne "请输入主机名: "; read -r hostname
                echo -ne "内存 (MB) [2048]: "; read -r memory
                echo -ne "核心数 [2]: "; read -r cores
                echo -ne "磁盘大小 (GB) [20]: "; read -r disk
                lxc_create "$vmid" "$hostname" "${memory:-2048}" "${cores:-2}" "${disk:-20}"
                ;;
            3)
                lxc_list
                echo -ne "请输入容器 ID: "; read -r vmid
                lxc_start "$vmid"
                ;;
            4)
                lxc_list
                echo -ne "请输入容器 ID: "; read -r vmid
                lxc_stop "$vmid"
                ;;
            5)
                lxc_list
                echo -ne "请输入容器 ID: "; read -r vmid
                lxc_restart "$vmid"
                ;;
            6)
                lxc_list
                echo -ne "请输入容器 ID: "; read -r vmid
                lxc_delete "$vmid"
                ;;
            7)
                lxc_list
                echo -ne "请输入容器 ID: "; read -r vmid
                lxc_install_docker "$vmid"
                ;;
            8)
                lxc_list
                echo -ne "请输入容器 ID: "; read -r vmid
                lxc_install_docker_compose "$vmid"
                ;;
            9)
                lxc_list
                echo -ne "请输入容器 ID: "; read -r vmid
                lxc_info "$vmid"
                ;;
            0) return 0 ;;
            *) echo -e "${RED}无效选择${NC}" ;;
        esac
        
        echo ""; echo -ne "${YELLOW}按回车键继续...${NC}"; read -r
    done
}

# ========== 系统管理模块 ==========

get_debian_codename() {
    grep -oP '\(\K[^)]+' /etc/os-release 2>/dev/null || echo "bookworm"
}

system_show_sources() {
    echo -e "${BLUE}=== APT 镜像源配置 ===${NC}"
    echo ""
    echo -e "${GREEN}Debian 源:${NC}"
    cat /etc/apt/sources.list 2>/dev/null | grep -v "^#" | grep -v "^$" || echo "无"
    echo ""
    echo -e "${GREEN}PVE 源:${NC}"
    cat /etc/apt/sources.list.d/pve*.list 2>/dev/null | grep -v "^#" | grep -v "^$" || echo "无"
}

system_set_mirror() {
    local mirror_name="$1"
    local mirror_url="$2"
    local codename=$(get_debian_codename)
    
    if ask_confirm "切换镜像源到 ${mirror_name}，是否继续？"; then
        echo -e "${YELLOW}切换到 ${mirror_name} 镜像源...${NC}"
        
        cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null || true
        
        cat > /etc/apt/sources.list << EOF
# ${mirror_name}镜像源
deb ${mirror_url}/debian/ ${codename} main contrib non-free non-free-firmware
deb ${mirror_url}/debian/ ${codename}-updates main contrib non-free non-free-firmware
deb ${mirror_url}/debian-security/ ${codename}-security main contrib non-free non-free-firmware
EOF
        
        echo -e "${GREEN}镜像源已切换到 ${mirror_name}${NC}"
    fi
}

system_mirror_menu() {
    while true; do
        echo ""
        echo -e "${WHITE}═══════════════════════════════════════${NC}"
        echo -e "${BOLD}           选择镜像源${NC}"
        echo -e "${WHITE}═══════════════════════════════════════${NC}"
        echo ""
        echo -e "  ${GREEN}[1]${NC} 中科大镜像"
        echo -e "  ${GREEN}[2]${NC} 清华大学镜像"
        echo -e "  ${GREEN}[3]${NC} 阿里云镜像"
        echo -e "  ${GREEN}[4]${NC} 华为云镜像"
        echo -e "  ${GREEN}[5]${NC} 腾讯云镜像"
        echo -e "  ${GREEN}[6]${NC} 网易镜像"
        echo -e "  ${GREEN}[0]${NC} 返回上级"
        echo ""
        echo -ne "${WHITE}请选择 [0-6]: ${NC}"
        read -r choice
        
        case "$choice" in
            1) system_set_mirror "中科大" "https://mirrors.ustc.edu.cn" ;;
            2) system_set_mirror "清华大学" "https://mirrors.tuna.tsinghua.edu.cn" ;;
            3) system_set_mirror "阿里云" "https://mirrors.aliyun.com" ;;
            4) system_set_mirror "华为云" "https://mirrors.huaweicloud.com" ;;
            5) system_set_mirror "腾讯云" "https://mirrors.cloud.tencent.com" ;;
            6) system_set_mirror "网易" "https://mirrors.163.com" ;;
            0) return 0 ;;
            *) echo -e "${RED}无效选择${NC}" ;;
        esac
        
        echo ""; echo -ne "${YELLOW}按回车键继续...${NC}"; read -r
    done
}

system_disable_enterprise() {
    if [[ -f /etc/apt/sources.list.d/pve-enterprise.list ]]; then
        if ask_confirm "禁用 PVE 企业源，是否继续？"; then
            sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list
            echo -e "${GREEN}已禁用 pve-enterprise.list${NC}"
        fi
    else
        echo -e "${GREEN}pve-enterprise.list 不存在或已禁用${NC}"
    fi
}

system_set_pve_community() {
    if ask_confirm "配置 PVE 社区源（中科大镜像），是否继续？"; then
        cat > /etc/apt/sources.list.d/pve-no-subscription.list << EOF
# PVE 社区源 (中科大镜像)
deb https://mirrors.ustc.edu.cn/proxmox/debian/pve bookworm pve-no-subscription
EOF
        echo -e "${GREEN}PVE 社区源已配置${NC}"
    fi
}

system_update() {
    if ask_confirm "更新系统软件包，是否继续？"; then
        echo -e "${BLUE}=== 系统更新 ===${NC}"
        echo -e "${GREEN}更新软件包列表...${NC}"
        apt update
        
        echo ""
        echo -e "${GREEN}可升级的软件包:${NC}"
        apt list --upgradable 2>/dev/null | head -20 || true
        
        if ask_confirm "是否执行升级？"; then
            echo -e "${GREEN}执行系统升级...${NC}"
            apt dist-upgrade -y
            echo -e "${GREEN}升级完成${NC}"
        fi
    fi
}

system_cleanup() {
    if ask_confirm "清理系统，是否继续？"; then
        echo -e "${BLUE}=== 系统清理 ===${NC}"
        echo -e "${GREEN}清理不需要的软件包...${NC}"
        apt autoremove -y 2>/dev/null || true
        apt autoclean 2>/dev/null || true
        
        echo -e "${GREEN}清理 APT 缓存...${NC}"
        apt clean 2>/dev/null || true
        
        echo -e "${GREEN}清理日志文件...${NC}"
        journalctl --vacuum-time="7days" 2>/dev/null || true
        
        echo -e "${GREEN}清理完成${NC}"
    fi
}

system_info() {
    echo -e "${BLUE}=== PVE 系统信息 ===${NC}"
    echo ""
    echo -e "${GREEN}版本信息:${NC}"
    pveversion -v 2>/dev/null || echo "无法获取版本信息"
    echo ""
    echo -e "${GREEN}主机信息:${NC}"
    echo "  主机名: $(hostname)"
    echo "  IP 地址: $(hostname -I | awk '{print $1}')"
    echo "  内核版本: $(uname -r)"
    echo "  系统运行时间: $(uptime -p 2>/dev/null || uptime)"
    echo ""
    echo -e "${GREEN}存储信息:${NC}"
    pvesm status 2>/dev/null || echo "无法获取存储信息"
}

system_help() {
    echo -e "${BLUE}系统管理命令:${NC}"
    echo "  --sources              显示当前镜像源配置"
    echo "  --mirror              镜像源选择菜单"
    echo "  --disable-enterprise   禁用 PVE 企业源"
    echo "  --pve-community        配置 PVE 社区源"
    echo "  --update               更新系统"
    echo "  --cleanup              清理系统"
    echo "  --info                 显示系统信息"
}

system_main() {
    case "${1:-}" in
        --sources) system_show_sources ;;
        --mirror) system_mirror_menu ;;
        --disable-enterprise) system_disable_enterprise ;;
        --pve-community) system_set_pve_community ;;
        --update|-u) system_update ;;
        --cleanup|-c) system_cleanup ;;
        --info|-i) system_info ;;
        --help|-h) system_help ;;
        *) echo -e "${RED}错误: 未知系统命令${NC}"; system_help; return 1 ;;
    esac
}

system_interactive() {
    while true; do
        echo ""
        echo -e "${WHITE}═══════════════════════════════════════${NC}"
        echo -e "${BOLD}        系统更新/镜像源管理${NC}"
        echo -e "${WHITE}═══════════════════════════════════════${NC}"
        echo ""
        echo -e "  ${GREEN}[1]${NC} 显示系统信息"
        echo -e "  ${GREEN}[2]${NC} 显示镜像源配置"
        echo -e "  ${GREEN}[3]${NC} 切换镜像源"
        echo -e "  ${GREEN}[4]${NC} 禁用 PVE 企业源"
        echo -e "  ${GREEN}[5]${NC} 配置 PVE 社区源"
        echo -e "  ${GREEN}[6]${NC} 更新系统"
        echo -e "  ${GREEN}[7]${NC} 清理系统"
        echo -e "  ${GREEN}[0]${NC} 返回主菜单"
        echo ""
        echo -ne "${WHITE}请选择 [0-7]: ${NC}"
        read -r choice
        
        case "$choice" in
            1) system_info ;;
            2) system_show_sources ;;
            3) system_mirror_menu ;;
            4) system_disable_enterprise ;;
            5) system_set_pve_community ;;
            6) system_update ;;
            7) system_cleanup ;;
            0) return 0 ;;
            *) echo -e "${RED}无效选择${NC}" ;;
        esac
        
        echo ""; echo -ne "${YELLOW}按回车键继续...${NC}"; read -r
    done
}

# ========== 主程序 ==========

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

show_separator() {
    echo -e "${WHITE}════════════════════════════════════════════════════════════════${NC}"
}

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

interactive_main() {
    while true; do
        show_logo
        show_menu
        
        echo -ne "    ${WHITE}请选择功能 [0-4]: ${NC}"
        if [[ -t 0 ]]; then
            read -r choice
        else
            read -r choice || choice=""
        fi
        
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

show_help() {
    echo -e "${BLUE}PVE Toolkit - Proxmox VE 管理工具集 $VERSION${NC}"
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

main() {
    # 检测是否为管道执行
    if [[ ! -t 0 ]]; then
        export FORCE_INTERACTIVE=1
    fi
    
    if [[ $# -gt 0 ]]; then
        case "${1:-}" in
            backup) shift; backup_main "$@" ;;
            monitor) shift; monitor_main "$@" ;;
            lxc) shift; lxc_main "$@" ;;
            system) shift; system_main "$@" ;;
            help|--help|-h) show_help ;;
            *) echo -e "${RED}错误: 未知命令 '${1:-}'${NC}"; show_help; exit 1 ;;
        esac
    else
        check_root
        check_pve_version
        
        # 如果没有 TTY 但需要交互，提示用户
        if [[ ! -t 0 ]] && [[ "$FORCE_INTERACTIVE" != "1" ]]; then
            log_warn "检测到非交互模式，使用命令行模式"
            echo ""
            echo "用法: $0 <命令> [选项]"
            echo "示例: $0 monitor --status"
            echo "帮助: $0 help"
            exit 0
        fi
        
        interactive_main
    fi
}

main "$@"
