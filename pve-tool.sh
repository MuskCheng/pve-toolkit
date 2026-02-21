#!/bin/bash
#
# PVE Toolkit - Proxmox VE 管理工具集
# 版本: V0.26
# 使用方法: curl -sL https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/pve-tool.sh | bash

VERSION="V0.26"

# 检测管道执行并自动保存
if [[ ! -t 0 ]] && [[ -z "$PVE_TOOL_SAVED" ]]; then
    echo "[INFO] 检测到管道执行，正在保存脚本..."
    SCRIPT_PATH="/tmp/pve-tool-$$-$(date +%s).sh"
    cat > "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    echo "[INFO] 脚本已保存到: $SCRIPT_PATH"
    echo "[INFO] 请运行: bash $SCRIPT_PATH"
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

# 询问确认
ask_confirm() {
    local prompt="$1"
    echo -ne "${YELLOW}$prompt (y/N): ${NC}"
    read -r confirm
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
    [[ -z "$vmid" ]] && { echo -e "${RED}错误: 请指定 VM/LXC ID${NC}"; return 1; }
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
    local backup_file="$1" vmid="$2"
    [[ -z "$backup_file" || -z "$vmid" ]] && { echo -e "${RED}错误: 请指定备份文件和目标 VM ID${NC}"; return 1; }
    [[ ! -f "$backup_file" ]] && { echo -e "${RED}错误: 备份文件不存在: $backup_file${NC}"; return 1; }
    
    local restore_cmd=""
    [[ "$backup_file" == *.vma.zst ]] && restore_cmd="qmrestore" || [[ "$backup_file" == *.tar.zst ]] && restore_cmd="pctrestore"
    [[ -z "$restore_cmd" ]] && { echo -e "${RED}错误: 未知的备份文件格式${NC}"; return 1; }
    
    if ask_confirm "警告: 这将覆盖现有的 VM/LXC $vmid，是否继续？"; then
        [[ "$restore_cmd" == "qmrestore" ]] && qmrestore "$backup_file" "$vmid" --storage local || pctrestore "$vmid" "$backup_file" --storage local
    fi
}

backup_main() {
    case "${1:-}" in
        --list|-l) backup_list ;;
        --create|-c) backup_create "$2" "$3" ;;
        --cleanup) backup_cleanup ;;
        --restore|-r) backup_restore "$2" "$3" ;;
        --help|-h) echo -e "${BLUE}备份命令: --list, --create <ID>, --cleanup, --restore <file> <ID>${NC}" ;;
        *) echo -e "${RED}错误: 未知备份命令${NC}"; return 1 ;;
    esac
}

backup_interactive() {
    while true; do
        echo ""
        echo -e "${BLUE}═══════════════════════════════════════${NC}"
        echo -e "${BOLD}            备份管理${NC}"
        echo -e "${BLUE}═══════════════════════════════════════${NC}"
        echo -e "  ${GREEN}[1]${NC} 列出所有备份  ${GREEN}[2]${NC} 创建备份"
        echo -e "  ${GREEN}[3]${NC} 清理旧备份    ${GREEN}[4]${NC} 恢复备份"
        echo -e "  ${GREEN}[0]${NC} 返回主菜单"
        echo ""
        echo -ne "${CYAN}请选择 [0-4]: ${NC}"
        read -r choice
        
        case "$choice" in
            1) backup_list ;;
            2) echo -ne "请输入 VM/LXC ID: "; read -r vmid; backup_create "$vmid" ;;
            3) backup_cleanup ;;
            4) backup_list; echo -ne "备份文件路径: "; read -r f; echo -ne "目标 VM ID: "; read -r id; backup_restore "$f" "$id" ;;
            0) return 0 ;;
            *) echo -e "${RED}无效选择${NC}" ;;
        esac
        [[ "$choice" != "0" ]] && { echo ""; echo -ne "${YELLOW}按回车继续...${NC}"; read -r; }
    done
}

# ========== 系统监控模块 ==========

monitor_status() {
    echo -e "${BLUE}=== PVE 系统状态 ===${NC}"
    echo -e "${GREEN}主机:${NC} $(hostname) | PVE: $(pveversion 2>/dev/null | grep -oP 'pve-manager/\K[0-9.]+' || echo 'N/A')"
    echo -e "${GREEN}内核:${NC} $(uname -r)"
    echo ""
    echo -e "${GREEN}CPU: ${NC}$(nproc) 核心 | 使用率: $(top -bn1 2>/dev/null | grep "Cpu" | awk '{print $2}' | cut -d'%' -f1 || echo 'N/A')%"
    echo -e "${GREEN}内存:${NC} $(free -h | awk 'NR==2{printf "%s / %s (%.1f%%)", $3, $2, $3*100/$2}')"
    echo -e "${GREEN}磁盘:${NC} $(df -h / | awk 'NR==2{printf "%s / %s (%s)", $3, $2, $5}')"
    echo ""
    echo -e "${GREEN}运行中: ${NC}VM: $(qm list 2>/dev/null | grep running | wc -l) | LXC: $(pct list 2>/dev/null | grep running | wc -l)"
}

monitor_vm() { echo -e "${BLUE}=== 虚拟机状态 ===${NC}"; qm list 2>/dev/null || echo "无法获取"; }
monitor_lxc() { echo -e "${BLUE}=== LXC 容器状态 ===${NC}"; pct list 2>/dev/null || echo "无法获取"; }

monitor_resources() {
    echo -e "${BLUE}=== 资源阈值检查 ===${NC}"
    local cpu=$(top -bn1 2>/dev/null | grep "Cpu" | awk '{print int($2)}' || echo 0)
    local mem=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    local disk=$(df / | awk 'NR==2{print $5}' | tr -d '%')
    
    [[ $cpu -gt $ALERT_THRESHOLD_CPU ]] && echo -e "${RED}⚠ CPU: ${cpu}%${NC}" || echo -e "${GREEN}✓ CPU: ${cpu}%${NC}"
    [[ $mem -gt $ALERT_THRESHOLD_MEM ]] && echo -e "${RED}⚠ 内存: ${mem}%${NC}" || echo -e "${GREEN}✓ 内存: ${mem}%${NC}"
    [[ $disk -gt $ALERT_THRESHOLD_DISK ]] && echo -e "${RED}⚠ 磁盘: ${disk}%${NC}" || echo -e "${GREEN}✓ 磁盘: ${disk}%${NC}"
}

monitor_network() { echo -e "${BLUE}=== 网络状态 ===${NC}"; ip -brief addr 2>/dev/null || ip addr; }
monitor_logs() { echo -e "${BLUE}=== 系统日志 ===${NC}"; journalctl -n "${1:-50}" --no-pager 2>/dev/null || echo "无法获取日志"; }

monitor_main() {
    case "${1:-}" in
        --status|-s) monitor_status ;;
        --vm) monitor_vm ;;
        --lxc) monitor_lxc ;;
        --resources|-r) monitor_resources ;;
        --network|-n) monitor_network ;;
        --logs|-l) monitor_logs "$2" ;;
        --help|-h) echo -e "${BLUE}监控命令: --status, --vm, --lxc, --resources, --network, --logs [N]${NC}" ;;
        *) echo -e "${RED}错误: 未知监控命令${NC}"; return 1 ;;
    esac
}

monitor_interactive() {
    while true; do
        echo ""
        echo -e "${BLUE}═══════════════════════════════════════${NC}"
        echo -e "${BOLD}            系统监控${NC}"
        echo -e "${BLUE}═══════════════════════════════════════${NC}"
        echo -e "  ${GREEN}[1]${NC} 系统状态    ${GREEN}[2]${NC} VM状态    ${GREEN}[3]${NC} LXC状态"
        echo -e "  ${GREEN}[4]${NC} 资源检查    ${GREEN}[5]${NC} 网络状态 ${GREEN}[6]${NC} 系统日志"
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
            6) echo -ne "日志条数 [50]: "; read -r n; monitor_logs "${n:-50}" ;;
            0) return 0 ;;
            *) echo -e "${RED}无效选择${NC}" ;;
        esac
        [[ "$choice" != "0" ]] && { echo ""; echo -ne "${YELLOW}按回车继续...${NC}"; read -r; }
    done
}

# ========== LXC 管理模块 ==========

lxc_list() { echo -e "${BLUE}=== LXC 容器列表 ===${NC}"; pct list 2>/dev/null || echo "无法获取"; }

lxc_create() {
    local vmid="$1" hostname="$2" memory="${3:-$LXC_DEFAULT_MEMORY}" cores="${4:-$LXC_DEFAULT_CORES}" disk="${5:-$LXC_DEFAULT_DISK}"
    [[ -z "$vmid" || -z "$hostname" ]] && { echo -e "${RED}错误: 需要 ID 和主机名${NC}"; return 1; }
    echo -e "${GREEN}创建 LXC $vmid ($hostname) 内存:$memory 核心:$cores 磁盘:${disk}GB${NC}"
    pct create "$vmid" "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst" \
        --hostname "$hostname" --memory "$memory" --cores "$cores" --rootfs "local:${disk}" \
        --net0 "name=eth0,bridge=vmbr0,ip=dhcp" --unprivileged 0 --features "nesting=1,keyctl=1" --start 1 \
        && echo -e "${GREEN}创建成功${NC}" || echo -e "${RED}创建失败${NC}"
}

lxc_start() { [[ -z "$1" ]] && { echo -e "${RED}错误: 需要 ID${NC}"; return 1; }; pct start "$1"; echo -e "${GREEN}已启动${NC}"; }
lxc_stop() { [[ -z "$1" ]] && { echo -e "${RED}错误: 需要 ID${NC}"; return 1; }; pct stop "$1"; echo -e "${GREEN}已停止${NC}"; }
lxc_restart() { [[ -z "$1" ]] && { echo -e "${RED}错误: 需要 ID${NC}"; return 1; }; pct restart "$1"; echo -e "${GREEN}已重启${NC}"; }

lxc_delete() {
    [[ -z "$1" ]] && { echo -e "${RED}错误: 需要 ID${NC}"; return 1; }
    if [[ "$2" == "-f" ]] || ask_confirm "警告: 删除容器 $1 及其数据，是否继续？"; then
        pct stop "$1" 2>/dev/null || true; pct destroy "$1"; echo -e "${GREEN}已删除${NC}"
    fi
}

lxc_console() { [[ -z "$1" ]] && { echo -e "${RED}错误: 需要 ID${NC}"; return 1; }; pct enter "$1"; }
lxc_info() { [[ -z "$1" ]] && { echo -e "${RED}错误: 需要 ID${NC}"; return 1; }; echo -e "${BLUE}=== 容器 $1 详情 ===${NC}"; pct config "$1" 2>/dev/null; }

lxc_install_docker() {
    [[ -z "$1" ]] && { echo -e "${RED}错误: 需要 ID${NC}"; return 1; }
    echo -e "${GREEN}正在安装 Docker...${NC}"
    pct exec "$1" -- bash -c '
        apt update && apt install -y curl ca-certificates gnupg lsb-release
        CODENAME=$(lsb_release -cs)
        mkdir -p /etc/apt/keyrings
        if curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null; then
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${CODENAME} stable" > /etc/apt/sources.list.d/docker.list
            apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || apt install -y docker.io
        else
            apt install -y docker.io
        fi
        systemctl enable docker 2>/dev/null; systemctl start docker 2>/dev/null
    '
    pct exec "$1" -- bash -c "mkdir -p /etc/docker && echo '{\"registry-mirrors\":[\"https://docker.m.daocloud.io\"]}' > /etc/docker/daemon.json"
    pct exec "$1" -- systemctl restart docker 2>/dev/null || true
    echo -e "${GREEN}Docker 安装完成${NC}"
    pct exec "$1" -- docker --version 2>/dev/null || pct exec "$1" -- docker.io --version 2>/dev/null
}

lxc_install_compose() {
    [[ -z "$1" ]] && { echo -e "${RED}错误: 需要 ID${NC}"; return 1; }
    echo -e "${GREEN}安装 Docker Compose...${NC}"
    pct exec "$1" -- bash -c "apt update && apt install -y python3-pip && pip3 install docker-compose --break-system-packages" 2>/dev/null \
        && echo -e "${GREEN}完成${NC}" || echo -e "${RED}失败${NC}"
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
        --info|-i) lxc_info "$2" ;;
        --install-docker) lxc_install_docker "$2" ;;
        --install-compose) lxc_install_compose "$2" ;;
        --help|-h) echo -e "${BLUE}LXC命令: --list, --create, --start, --stop, --restart, --delete, --console, --info, --install-docker, --install-compose${NC}" ;;
        *) echo -e "${RED}错误: 未知命令${NC}"; return 1 ;;
    esac
}

lxc_interactive() {
    while true; do
        echo ""
        echo -e "${WHITE}═══════════════════════════════════════${NC}"
        echo -e "${BOLD}          LXC 容器管理${NC}"
        echo -e "${WHITE}═══════════════════════════════════════${NC}"
        echo -e "  ${GREEN}[1]${NC} 列表    ${GREEN}[2]${NC} 创建    ${GREEN}[3]${NC} 启动"
        echo -e "  ${GREEN}[4]${NC} 停止    ${GREEN}[5]${NC} 重启    ${GREEN}[6]${NC} 删除"
        echo -e "  ${GREEN}[7]${NC} Docker  ${GREEN}[8]${NC} Compose ${GREEN}[9]${NC} 详情"
        echo -e "  ${GREEN}[0]${NC} 返回"
        echo ""
        echo -ne "${CYAN}请选择 [0-9]: ${NC}"
        read -r choice
        
        case "$choice" in
            1) lxc_list ;;
            2) echo -ne "ID: "; read -r id; echo -ne "主机名: "; read -r hn; lxc_create "$id" "$hn" ;;
            3) lxc_list; echo -ne "ID: "; read -r id; lxc_start "$id" ;;
            4) lxc_list; echo -ne "ID: "; read -r id; lxc_stop "$id" ;;
            5) lxc_list; echo -ne "ID: "; read -r id; lxc_restart "$id" ;;
            6) lxc_list; echo -ne "ID: "; read -r id; lxc_delete "$id" ;;
            7) lxc_list; echo -ne "ID: "; read -r id; lxc_install_docker "$id" ;;
            8) lxc_list; echo -ne "ID: "; read -r id; lxc_install_compose "$id" ;;
            9) lxc_list; echo -ne "ID: "; read -r id; lxc_info "$id" ;;
            0) return 0 ;;
            *) echo -e "${RED}无效选择${NC}" ;;
        esac
        [[ "$choice" != "0" ]] && { echo ""; echo -ne "${YELLOW}按回车继续...${NC}"; read -r; }
    done
}

# ========== 系统管理模块 ==========

get_debian_codename() { grep -oP '\(\K[^)]+' /etc/os-release 2>/dev/null || echo "bookworm"; }

system_show_sources() {
    echo -e "${BLUE}=== APT 镜像源 ===${NC}"
    echo -e "${GREEN}Debian:${NC}"; grep -v "^#" /etc/apt/sources.list 2>/dev/null | grep -v "^$" || echo "无"
    echo -e "${GREEN}PVE:${NC}"; grep -v "^#" /etc/apt/sources.list.d/pve*.list 2>/dev/null | grep -v "^$" || echo "无"
}

system_set_mirror() {
    local name="$1" url="$2" codename=$(get_debian_codename)
    if ask_confirm "切换到 $name，是否继续？"; then
        cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%Y%m%d) 2>/dev/null || true
        cat > /etc/apt/sources.list << EOF
deb ${url}/debian/ ${codename} main contrib non-free non-free-firmware
deb ${url}/debian/ ${codename}-updates main contrib non-free non-free-firmware
deb ${url}/debian-security/ ${codename}-security main contrib non-free non-free-firmware
EOF
        echo -e "${GREEN}已切换到 $name${NC}"
    fi
}

system_mirror_menu() {
    while true; do
        echo ""
        echo -e "${WHITE}═══════════════════════════════════════${NC}"
        echo -e "${BOLD}       选择镜像源${NC}"
        echo -e "${WHITE}═══════════════════════════════════════${NC}"
        echo -e "  ${GREEN}[1]${NC} 中科大  ${GREEN}[2]${NC} 清华  ${GREEN}[3]${NC} 阿里云"
        echo -e "  ${GREEN}[4]${NC} 华为云  ${GREEN}[5]${NC} 腾讯云 ${GREEN}[6]${NC} 网易"
        echo -e "  ${GREEN}[0]${NC} 返回"
        echo ""
        echo -ne "${CYAN}请选择 [0-6]: ${NC}"
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
        [[ "$choice" != "0" ]] && { echo ""; echo -ne "${YELLOW}按回车继续...${NC}"; read -r; }
    done
}

system_disable_enterprise() {
    if [[ -f /etc/apt/sources.list.d/pve-enterprise.list ]]; then
        ask_confirm "禁用 PVE 企业源？" && sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list && echo -e "${GREEN}已禁用${NC}"
    else
        echo -e "${GREEN}已禁用或不存在${NC}"
    fi
}

system_set_pve_community() {
    ask_confirm "配置 PVE 社区源？" && cat > /etc/apt/sources.list.d/pve-no-subscription.list << 'EOF'
deb https://mirrors.ustc.edu.cn/proxmox/debian/pve bookworm pve-no-subscription
EOF
    echo -e "${GREEN}已配置${NC}"
}

system_update() {
    ask_confirm "更新系统？" || return
    echo -e "${GREEN}更新软件包...${NC}"
    apt update && apt list --upgradable 2>/dev/null | head -5
    ask_confirm "确认升级？" && apt dist-upgrade -y && echo -e "${GREEN}完成${NC}"
}

system_cleanup() {
    ask_confirm "清理系统？" || return
    apt autoremove -y && apt autoclean && apt clean && journalctl --vacuum-time=7days 2>/dev/null
    echo -e "${GREEN}清理完成${NC}"
}

system_info() {
    echo -e "${BLUE}=== PVE 系统信息 ===${NC}"
    pveversion -v 2>/dev/null || echo "无法获取"
    echo -e "主机: $(hostname) | IP: $(hostname -I | awk '{print $1}')"
    echo -e "内核: $(uname -r)"
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
        --help|-h) echo -e "${BLUE}系统命令: --sources, --mirror, --disable-enterprise, --pve-community, --update, --cleanup, --info${NC}" ;;
        *) echo -e "${RED}错误: 未知命令${NC}"; return 1 ;;
    esac
}

system_interactive() {
    while true; do
        echo ""
        echo -e "${WHITE}═══════════════════════════════════════${NC}"
        echo -e "${BOLD}        系统管理${NC}"
        echo -e "${WHITE}═══════════════════════════════════════${NC}"
        echo -e "  ${GREEN}[1]${NC} 系统信息  ${GREEN}[2]${NC} 镜像源  ${GREEN}[3]${NC} 切换源"
        echo -e "  ${GREEN}[4]${NC} 禁用企业源 ${GREEN}[5]${NC} 社区源"
        echo -e "  ${GREEN}[6]${NC} 更新系统 ${GREEN}[7]${NC} 清理系统"
        echo -e "  ${GREEN}[0]${NC} 返回"
        echo ""
        echo -ne "${CYAN}请选择 [0-7]: ${NC}"
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
        [[ "$choice" != "0" ]] && { echo ""; echo -ne "${YELLOW}按回车继续...${NC}"; read -r; }
    done
}

# ========== 主程序 ==========

show_logo() {
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
    echo -e "${WHITE}${BOLD}         Proxmox VE 管理工具集 $VERSION (PVE 9.*)${NC}"
}

show_separator() { echo -e "${WHITE}════════════════════════════════════════════════════════${NC}"; }

show_menu() {
    echo ""
    show_separator
    echo -e "   ${WHITE}[1]${NC} 备份管理    ${WHITE}[2]${NC} 系统监控    ${WHITE}[3]${NC} LXC管理"
    echo -e "   ${WHITE}[4]${NC} 系统管理    ${WHITE}[0]${NC} 退出"
    show_separator
    echo -e "        ${YELLOW}⚠ 操作前请备份重要数据${NC}"
}

show_help() {
    echo -e "${BLUE}PVE Toolkit $VERSION${NC}"
    echo "用法: $0 <命令> [选项]"
    echo "命令: backup, monitor, lxc, system, help"
    echo "示例: $0 monitor --status"
}

interactive_main() {
    while true; do
        show_logo
        show_menu
        echo -ne "${CYAN}请选择 [0-4]: ${NC}"
        read -r choice
        
        case "$choice" in
            1) echo -e "${GREEN}>>> 备份管理${NC}"; backup_interactive ;;
            2) echo -e "${GREEN}>>> 系统监控${NC}"; monitor_interactive ;;
            3) echo -e "${GREEN}>>> LXC管理${NC}"; lxc_interactive ;;
            4) echo -e "${GREEN}>>> 系统管理${NC}"; system_interactive ;;
            0) echo -e "${GREEN}再见!${NC}"; exit 0 ;;
            *) echo -e "${RED}无效选择${NC}" ;;
        esac
    done
}

main() {
    if [[ $# -gt 0 ]]; then
        case "${1:-}" in
            backup) shift; backup_main "$@" ;;
            monitor) shift; monitor_main "$@" ;;
            lxc) shift; lxc_main "$@" ;;
            system) shift; system_main "$@" ;;
            help|--help|-h) show_help ;;
            *) echo -e "${RED}错误: 未知命令 '${1}'${NC}"; show_help; exit 1 ;;
        esac
    else
        check_root
        check_pve_version
        interactive_main
    fi
}

main "$@"
