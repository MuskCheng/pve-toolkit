#!/bin/bash
#
# PVE Toolkit - Proxmox VE 管理工具集
# 使用: curl -sL https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/pve-tool.sh -o /tmp/pve.sh && bash /tmp/pve.sh

# 读取本地版本
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
    VERSION=$(cat "$SCRIPT_DIR/VERSION")
else
    VERSION="V0.5.27"
fi

# 查询 GitHub 最新版本
get_latest_version() {
    local latest
    latest=$(curl -sS "https://api.github.com/repos/MuskCheng/pve-toolkit/releases/latest" 2>/dev/null | grep -oP '"tag_name":\s*"\K[^"]+' || echo "")
    echo "$latest"
}

LATEST_VERSION=$(get_latest_version)
if [[ -z "$LATEST_VERSION" ]]; then
    LATEST_VERSION="$VERSION"
fi

get_latest_debian_template() {
    local template_url="http://download.proxmox.com/images/system/"
    local templates
    templates=$(curl -sS "$template_url" 2>/dev/null | grep -oP 'debian-13-standard_[0-9.]+-[0-9]+_amd64\.tar\.zst' | sort -V | tail -1)
    echo "$templates"
}

download_latest_debian_template() {
    local template_url="http://download.proxmox.com/images/system/"
    local cache_dir="/var/lib/vz/template/cache"
    local latest_template
    latest_template=$(get_latest_debian_template)
    
    if [[ -z "$latest_template" ]]; then
        echo -e "${RED}无法获取最新 Debian 模板信息${NC}"
        return 1
    fi
    
    if [[ -f "$cache_dir/$latest_template" ]]; then
        echo "$latest_template"
        return 0
    fi
    
    mkdir -p "$cache_dir"
    
    if curl -fSL "$template_url$latest_template" -o "$cache_dir/$latest_template" 2>/dev/null; then
        ls "$cache_dir"/debian-*-standard_*.tar.zst 2>/dev/null | grep -v "$latest_template" | while read -r old_template; do
            rm -f "$old_template"
        done
    else
        rm -f "$cache_dir/$latest_template"
        return 1
    fi
    
    echo "$latest_template"
}

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

# 全局变量（从环境变量继承或重新检测）
PVE_MAJOR_VERSION="${PVE_MAJOR_VERSION:-}"
PVE_FULL_VERSION="${PVE_FULL_VERSION:-}"
DEBUG_MODE=false

# 检查调试模式
for arg in "$@"; do
    if [[ "$arg" == "--debug" ]]; then
        DEBUG_MODE=true
        echo -e "${YELLOW}调试模式已启用${NC}"
    fi
done

# 如果环境变量为空，重新检测（兼容直接运行）
if [[ -z "$PVE_MAJOR_VERSION" ]]; then
    if command -v pveversion &>/dev/null; then
        PVE_FULL_VERSION=$(pveversion | head -n1 | cut -d'/' -f2 | cut -d'-' -f1)
        PVE_MAJOR_VERSION=$(echo "$PVE_FULL_VERSION" | cut -d'.' -f1)
    fi
fi

# 拦截非 PVE9 环境的破坏性操作
block_non_pve9() {
    local feature="$1"
    if [[ "$DEBUG_MODE" == "true" ]]; then
        return 0
    fi
    if [[ "${PVE_MAJOR_VERSION:-}" != "9" ]]; then
        echo -e "${RED}已拦截: 非 PVE9 环境禁止执行「$feature」${NC}"
        return 1
    fi
    return 0
}

get_compose_cmd() {
    local lxc_id=$1
    if pct exec "$lxc_id" -- test -x /usr/local/bin/docker-compose 2>/dev/null; then
        echo "/usr/local/bin/docker-compose"
    elif pct exec "$lxc_id" -- bash -lc 'command -v docker-compose &>/dev/null' 2>/dev/null; then
        echo "docker-compose"
    elif pct exec "$lxc_id" -- bash -lc 'docker compose version &>/dev/null' 2>/dev/null; then
        echo "docker compose"
    else
        echo ""
    fi
}

# 备份函数
backup_file() {
    local file="$1"
    local backup_dir="/var/backups/pve-tools"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    
    mkdir -p "$backup_dir"
    local backup_path="${backup_dir}/$(basename "$file").${timestamp}.bak"
    
    if cp -a "$file" "$backup_path" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# 暂停函数
pause_func() {
    echo -ne "${YELLOW}按任意键继续...${NC} "
    read -n 1 -s
    echo
}

# 检查 root
[[ $EUID -ne 0 ]] && { echo -e "${RED}需要 root 权限${NC}"; exit 1; }

# 检查 PVE 版本
if ! command -v pveversion &>/dev/null; then
    echo -e "${RED}抱歉，不支持此系统${NC}"
    echo -e "${YELLOW}本工具仅支持 Proxmox VE 9.1+${NC}"
    exit 1
fi

PVE_VER=$(pveversion | grep -oP 'pve-manager/\K[0-9.]+' | cut -d. -f1,2)
PVE_MINOR=$(echo "$PVE_VER" | cut -d. -f2)
if [[ -z "$PVE_VER" || "$PVE_MINOR" -lt 1 ]]; then
    echo -e "${RED}抱歉，不支持此版本${NC}"
    echo -e "${YELLOW}当前版本: $(pveversion | grep -oP 'pve-manager/\K[0-9.]+')"
    echo -e "${YELLOW}本工具仅支持 Proxmox VE 9.1 或更高版本${NC}"
    exit 1
fi

# 配置
BACKUP_DIR="/var/lib/vz/dump"
LXC_MEM=2048; LXC_CORES=2; LXC_DISK=20

# 显示菜单
show_menu() {
    clear
    echo -e "${BOLD}"
    cat << 'EOF'
██████╗ ██╗   ██╗███████╗    ████████╗ ██████╗  ██████╗ ██╗     
██╔══██╗██║   ██║██╔════╝    ╚══██╔══╝██╔═══██╗██╔═══██╗██║     
██████╔╝██║   ██║█████╗         ██║   ██║   ██║██║   ██║██║     
██╔═══╝ ╚██╗ ██╔╝██╔══╝         ██║   ██║   ██║██║   ██║██║     
██║      ╚████╔╝ ███████╗       ██║   ╚██████╔╝╚██████╔╝███████╗
╚═╝       ╚═══╝  ╚══════╝       ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝
EOF
    echo -e "${NC}"
    echo -e "${GREEN}PVE Toolkit 一键脚本${NC}"
    echo -e "${YELLOW}Proxmox VE 管理工具集，简化日常运维${NC}"
    echo -e "${CYAN}当前版本: ${VERSION} | 最新版本: ${LATEST_VERSION}${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}请选择您需要的功能:${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "  ${GREEN}[1]${NC} 系统管理"
    echo -e "  ${GREEN}[2]${NC} LXC 容器管理"
    echo -e "  ${GREEN}[3]${NC} 换源工具"
    echo -e "  ${GREEN}[0]${NC} 退出"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${RED}⚠️  安全提示: 操作前请备份重要数据，删除/恢复等操作不可逆${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
}

# LXC 管理
lxc_menu() {
    while true; do
        clear
        echo -e "${BLUE}════════ LXC 容器管理 ════════${NC}"
        echo -e "  ${GREEN}[1]${NC} 查看容器列表"
        echo -e "  ${GREEN}[2]${NC} 创建新容器"
        echo -e "  ${GREEN}[3]${NC} 删除容器"
        echo -e "  ${GREEN}[4]${NC} 容器操作"
        echo -e "  ${GREEN}[5]${NC} Docker 管理"
        echo -e "  ${GREEN}[6]${NC} 安装常用工具"
        echo -e "  ${GREEN}[0]${NC} 返回"
        echo -ne "${CYAN}选择: ${NC}"
        read c
        echo
        
        case "$c" in
            1) pct list; pause_func ;;
            2)
                echo -e "${YELLOW}=== 检查并下载最新 Debian 模板 ===${NC}"
                latest_template=$(get_latest_debian_template)
                
                if [[ -z "$latest_template" ]]; then
                    echo -e "${RED}无法获取最新 Debian 模板信息${NC}"
                    pause_func
                    continue
                fi
                
                echo -e "${CYAN}检测到最新 Debian 模板: ${GREEN}$latest_template${NC}"
                
                cache_dir="/var/lib/vz/template/cache"
                if [[ -f "$cache_dir/$latest_template" ]]; then
                    echo -e "${GREEN}模板已存在，跳过下载${NC}"
                else
                    echo -e "${YELLOW}正在下载最新模板...${NC}"
                    mkdir -p "$cache_dir"
                    if curl -fSL "http://download.proxmox.com/images/system/$latest_template" -o "$cache_dir/$latest_template" 2>/dev/null; then
                        echo -e "${GREEN}模板下载完成: $latest_template${NC}"
                        ls "$cache_dir"/debian-*-standard_*.tar.zst 2>/dev/null | grep -v "$latest_template" | while read -r old_template; do
                            echo -e "  ${RED}删除旧模板: ${NC}$(basename "$old_template")"
                            rm -f "$old_template"
                        done
                    else
                        echo -e "${RED}模板下载失败${NC}"
                        rm -f "$cache_dir/$latest_template"
                        pause_func
                        continue
                    fi
                fi
                
                echo -e "${YELLOW}=== 可用 LXC 模板 ===${NC}"
                if ls /var/lib/vz/template/cache/*.tar.zst 2>/dev/null; then
                    echo ""
                else
                    echo -e "${YELLOW}未找到本地模板${NC}"
                fi
                echo -e "${YELLOW}=== 当前 LXC 容器 ===${NC}"
                pct list
                echo ""
                echo -ne "容器 ID: "; read id
                echo -ne "主机名: "; read hn
                echo -ne "内存(MB) [2048]: "; read mem
                echo -ne "CPU核心 [2]: "; read cores
                echo -e "${CYAN}建议: 基础运行 4GB, 常规使用 8GB, 开发环境 16GB+${NC}"
                echo -ne "磁盘(GB) [8]: "; read disk
                echo -e "${YELLOW}使用模板: $latest_template${NC}"
                template=$latest_template
                mem=${mem:-2048}; cores=${cores:-2}; disk=${disk:-8}
                
                echo ""
                echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
                echo -e "${YELLOW}  容器类型说明${NC}"
                echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
                echo -e "  ${GREEN}[1]${NC} 特权容器"
                echo -e "      • Docker 支持最佳，无需额外配置"
                echo -e "      • systemd 完全兼容"
                echo -e "      • ${RED}安全性较低 (容器 root = 宿主机 root)${NC}"
                echo ""
                echo -e "  ${GREEN}[2]${NC} 无特权容器"
                echo -e "      • 安全性高 (容器 root 映射为 uid 100000+)"
                echo -e "      • ${RED}Docker 需额外配置${NC}"
                echo -e "      • ${RED}部分应用可能不兼容${NC}"
                echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
                echo -ne "容器类型 [1]: "; read ct_type
                ct_type=${ct_type:-1}
                
                if [[ "$ct_type" == "2" ]]; then
                    unpriv_flag="--unprivileged 1"
                else
                    unpriv_flag="--unprivileged 0"
                fi
                
                if [[ -n "$id" && -n "$hn" ]]; then
                    pct create "$id" local:vztmpl/"$template" \
                        --hostname "$hn" --memory "$mem" --cores "$cores" --rootfs local:"$disk" \
                        --net0 "name=eth0,bridge=vmbr0,ip=dhcp" $unpriv_flag --features nesting=1,keyctl=1 --start 1
                    
                    if [[ $? -eq 0 ]]; then
                        echo ""
                        echo -e "${GREEN}容器创建成功!${NC}"
                    fi
                fi
                pause_func
                ;;
            3)
                pct list
                echo -ne "请输入要删除的容器 ID: "; read id
                if [[ -n "$id" ]]; then
                    echo -e "${RED}警告: 将删除容器 $id 及其所有数据!${NC}"
                    echo -ne "确认删除? (y/N): "; read confirm
                    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                        pct stop "$id" 2>/dev/null
                        pct destroy "$id"
                        echo -e "${GREEN}容器 $id 已删除${NC}"
                    fi
                fi
                pause_func
                ;;
            4) lxc_operate_menu ;;
            5) docker_menu ;;
            6) install_tools_menu ;;
            0) break ;;
        esac
    done
}

# 容器类型转换
lxc_convert_type() {
    clear
    echo -e "${BLUE}═══ 转换容器类型 ═══${NC}"
    
    pct list
    echo ""
    echo -ne "请输入容器 ID: "; read id
    
    if [[ -z "$id" ]]; then
        echo -e "${RED}未输入容器 ID${NC}"
        pause_func
        return
    fi
    
    if ! pct status "$id" &>/dev/null; then
        echo -e "${RED}容器 $id 不存在${NC}"
        pause_func
        return
    fi
    
    local config_file="/etc/pve/lxc/${id}.conf"
    local current_type=$(grep "^unprivileged:" "$config_file" 2>/dev/null | awk '{print $2}')
    
    if [[ "$current_type" == "1" ]]; then
        current_type_str="无特权容器"
        target_type_str="特权容器"
        target_value=0
    else
        current_type_str="特权容器"
        target_type_str="无特权容器"
        target_value=1
    fi
    
    echo ""
    echo -e "${CYAN}当前类型: ${GREEN}$current_type_str${NC}"
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  容器类型说明${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
    echo -e "  ${GREEN}特权容器${NC}"
    echo -e "      • Docker 支持最佳，无需额外配置"
    echo -e "      • systemd 完全兼容"
    echo -e "      • ${RED}安全性较低 (容器 root = 宿主机 root)${NC}"
    echo ""
    echo -e "  ${GREEN}无特权容器${NC}"
    echo -e "      • 安全性高 (容器 root 映射为 uid 100000+)"
    echo -e "      • ${RED}Docker 需额外配置${NC}"
    echo -e "      • ${RED}部分应用可能不兼容${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}将转换为: ${GREEN}$target_type_str${NC}"
    
    if [[ "$target_value" == "1" ]]; then
        echo ""
        echo -e "${RED}⚠️  警告: 特权 → 无特权转换${NC}"
        echo -e "${RED}   • 容器内所有文件的所有权将被重新映射${NC}"
        echo -e "${RED}   • 建议先备份重要数据${NC}"
        echo -e "${RED}   • 转换后部分应用可能无法正常运行${NC}"
    fi
    
    echo ""
    echo -ne "确认转换? (y/N): "; read confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}已取消${NC}"
        pause_func
        return
    fi
    
    echo ""
    echo -e "${YELLOW}正在停止容器...${NC}"
    pct stop "$id" 2>/dev/null
    
    echo -e "${YELLOW}正在修改配置...${NC}"
    
    if grep -q "^unprivileged:" "$config_file"; then
        sed -i "s/^unprivileged:.*/unprivileged: $target_value/" "$config_file"
    else
        echo "unprivileged: $target_value" >> "$config_file"
    fi
    
    if [[ "$target_value" == "1" ]]; then
        echo -e "${YELLOW}正在转换文件所有权...${NC}"
        local rootfs=$(grep "^rootfs:" "$config_file" | awk '{print $2}' | cut -d',' -f1)
        if [[ -n "$rootfs" && -d "$rootfs" ]]; then
            chown -R 100000:100000 "$rootfs" 2>/dev/null
            find "$rootfs" -type d -exec chmod 755 {} \; 2>/dev/null
        fi
    fi
    
    echo -e "${YELLOW}正在启动容器...${NC}"
    pct start "$id"
    
    if [[ $? -eq 0 ]]; then
        echo ""
        echo -e "${GREEN}转换完成!${NC}"
        echo -e "${GREEN}容器类型已从 $current_type_str 转换为 $target_type_str${NC}"
    else
        echo -e "${RED}容器启动失败，请检查配置${NC}"
    fi
    
    pause_func
}

# 容器操作
lxc_operate_menu() {
    while true; do
        clear
        echo -e "${BLUE}════════ 容器操作 ════════${NC}"
        echo -e "${YELLOW}当前容器:${NC}"
        pct list
        echo ""
        echo -e "  ${GREEN}[1]${NC} 进入容器控制台"
        echo -e "  ${GREEN}[2]${NC} 启动容器"
        echo -e "  ${GREEN}[3]${NC} 停止容器"
        echo -e "  ${GREEN}[4]${NC} 重启容器"
        echo -e "  ${GREEN}[5]${NC} 克隆容器"
        echo -e "  ${GREEN}[6]${NC} 修改容器资源"
        echo -e "  ${GREEN}[7]${NC} 修改网络配置"
        echo -e "  ${GREEN}[8]${NC} 转换容器类型"
        echo -e "  ${GREEN}[0]${NC} 返回"
        echo -ne "${CYAN}选择: ${NC}"
        read c
        echo
        
        case "$c" in
            1)
                echo -ne "请输入要进入的容器 ID: "; read id
                [[ -n "$id" ]] && pct enter "$id"
                pause_func
                ;;
            2)
                echo -ne "请输入要启动的容器 ID: "; read id
                [[ -n "$id" ]] && pct start "$id"
                pause_func
                ;;
            3)
                echo -ne "请输入要停止的容器 ID: "; read id
                [[ -n "$id" ]] && pct stop "$id"
                pause_func
                ;;
            4)
                echo -ne "请输入要重启的容器 ID: "; read id
                [[ -n "$id" ]] && pct reboot "$id"
                pause_func
                ;;
            5)
                echo -ne "请输入源容器 ID: "; read src_id
                echo -ne "请输入目标容器 ID: "; read dst_id
                echo -ne "请输入目标主机名: "; read dst_hn
                if [[ -n "$src_id" && -n "$dst_id" && -n "$dst_hn" ]]; then
                    echo "克隆中..."
                    pct clone "$src_id" "$dst_id" --hostname "$dst_hn" --full
                    echo -e "${GREEN}克隆完成${NC}"
                fi
                pause_func
                ;;
            6)
                echo -ne "请输入要修改的容器 ID: "; read id
                if [[ -n "$id" ]]; then
                    echo "当前配置:"
                    pct config "$id" | grep -E "^(memory|cores|rootfs)"
                    echo -ne "新内存(MB, 回车跳过): "; read new_mem
                    echo -ne "新CPU核心(回车跳过): "; read new_cores
                    [[ -n "$new_mem" ]] && pct set "$id" -memory "$new_mem"
                    [[ -n "$new_cores" ]] && pct set "$id" -cores "$new_cores"
                    echo -e "${GREEN}配置已更新${NC}"
                fi
                pause_func
                ;;
            7)
                lxc_change_network
                ;;
            8)
                lxc_convert_type
                ;;
            0) break ;;
        esac
    done
}

cidr_to_netmask() {
    local cidr=$1
    local mask=""
    local full_octets=$((cidr / 8))
    local partial_octet=$((cidr % 8))
    
    for ((i=0; i<4; i++)); do
        if ((i < full_octets)); then
            mask+="255"
        elif ((i == full_octets)); then
            mask+="$((256 - 2**(8-partial_octet)))"
        else
            mask+="0"
        fi
        ((i < 3)) && mask+="."
    done
    echo "$mask"
}

lxc_change_network() {
    clear
    echo -e "${BLUE}═══ 修改网络配置 ═══${NC}"
    
    pct list
    echo ""
    echo -ne "请输入容器 ID: "; read id
    
    if [[ -z "$id" ]]; then
        echo -e "${RED}错误: 请输入容器 ID${NC}"
        pause_func
        return
    fi
    
    CURRENT_NET=$(pct config "$id" | grep "^net0:" | head -1)
    
    if [[ -z "$CURRENT_NET" ]]; then
        echo -e "${RED}错误: 无法获取网络配置${NC}"
        pause_func
        return
    fi
    
    NET_NAME=$(echo "$CURRENT_NET" | grep -oP 'name=\K[^,]+' || echo "eth0")
    NET_BRIDGE=$(echo "$CURRENT_NET" | grep -oP 'bridge=\K[^,]+' || echo "vmbr0")
    NET_IP_RAW=$(echo "$CURRENT_NET" | grep -oP 'ip=\K[^,]+' || echo "")
    NET_GW=$(echo "$CURRENT_NET" | grep -oP 'gw=\K[^,]+' || echo "")
    
    CONTAINER_RUNNING=$(pct status "$id" 2>/dev/null | grep -c "running" || echo "0")
    
    if [[ "$NET_IP_RAW" == "dhcp" ]]; then
        CONFIG_MODE="DHCP (自动获取)"
        
        if [[ "$CONTAINER_RUNNING" -eq 1 ]]; then
            ACTUAL_IP=$(pct exec "$id" -- ip -4 addr show "$NET_NAME" 2>/dev/null | grep -oP 'inet \K[0-9.]+/[0-9]+' | head -1)
            ACTUAL_GW=$(pct exec "$id" -- ip route 2>/dev/null | grep default | grep -oP 'via \K[0-9.]+')
            
            if [[ -n "$ACTUAL_IP" && "$ACTUAL_IP" =~ ^([0-9.]+)/([0-9]+)$ ]]; then
                IP_ADDR="${BASH_REMATCH[1]}"
                CIDR="${BASH_REMATCH[2]}"
                NETMASK=$(cidr_to_netmask "$CIDR")
                [[ -z "$NET_GW" && -n "$ACTUAL_GW" ]] && NET_GW="$ACTUAL_GW"
                
                if command -v ipcalc &>/dev/null; then
                    NETWORK=$(ipcalc -n "${IP_ADDR}/${CIDR}" 2>/dev/null | cut -d'=' -f2)
                    BROADCAST=$(ipcalc -b "${IP_ADDR}/${CIDR}" 2>/dev/null | cut -d'=' -f2)
                else
                    NETWORK="-"
                    BROADCAST="-"
                fi
            else
                IP_ADDR="-"
                CIDR="-"
                NETMASK="-"
                NETWORK="-"
                BROADCAST="-"
            fi
        else
            IP_ADDR="容器未运行"
            CIDR="-"
            NETMASK="-"
            NETWORK="-"
            BROADCAST="-"
            [[ -z "$NET_GW" ]] && NET_GW="-"
        fi
        
    elif [[ "$NET_IP_RAW" =~ ^([0-9.]+)/([0-9]+)$ ]]; then
        IP_ADDR="${BASH_REMATCH[1]}"
        CIDR="${BASH_REMATCH[2]}"
        CONFIG_MODE="静态IP"
        NETMASK=$(cidr_to_netmask "$CIDR")
        
        if command -v ipcalc &>/dev/null; then
            NETWORK=$(ipcalc -n "$NET_IP_RAW" 2>/dev/null | cut -d'=' -f2)
            BROADCAST=$(ipcalc -b "$NET_IP_RAW" 2>/dev/null | cut -d'=' -f2)
        else
            NETWORK="-"
            BROADCAST="-"
        fi
    else
        CONFIG_MODE="未配置"
        IP_ADDR="-"
        CIDR="-"
        NETMASK="-"
        NETWORK="-"
        BROADCAST="-"
        NET_GW="-"
    fi
    
    echo ""
    echo -e "${YELLOW}当前网络配置:${NC}"
    echo "──────────────────────────────────"
    echo -e "  ${WHITE}接口名称:${NC} ${CYAN}$NET_NAME${NC}"
    echo -e "  ${WHITE}网桥:${NC}     ${CYAN}$NET_BRIDGE${NC}"
    echo "──────────────────────────────────"
    echo -e "  ${WHITE}配置模式:${NC} ${CYAN}$CONFIG_MODE${NC}"
    echo -e "  ${WHITE}IP 地址:${NC}  ${CYAN}$IP_ADDR${NC}"
    echo -e "  ${WHITE}子网掩码:${NC} ${CYAN}$NETMASK${NC}"
    echo -e "  ${WHITE}网络地址:${NC} ${CYAN}$NETWORK${NC}"
    echo -e "  ${WHITE}广播地址:${NC} ${CYAN}$BROADCAST${NC}"
    echo -e "  ${WHITE}网关:${NC}     ${CYAN}$NET_GW${NC}"
    echo "──────────────────────────────────"
    echo ""
    
    echo -e "${YELLOW}选择配置方式:${NC}"
    echo -e "  ${GREEN}[1]${NC} 设置静态 IP"
    echo -e "  ${GREEN}[2]${NC} 设置 DHCP"
    echo -e "  ${GREEN}[0]${NC} 取消"
    echo -ne "${CYAN}选择: ${NC}"
    read net_choice
    echo
    
    case "$net_choice" in
        1)
            echo -e "${YELLOW}=== 设置静态 IP ===${NC}"
            echo -ne "IP 地址 (如 192.168.1.100): "; read new_ip
            echo -ne "子网掩码 (如 24): "; read new_mask
            echo -ne "网关 (如 192.168.1.1): "; read new_gw
            
            if [[ -z "$new_ip" || -z "$new_mask" || -z "$new_gw" ]]; then
                echo -e "${RED}错误: 请填写完整信息${NC}"
                pause_func
                return
            fi
            
            echo ""
            echo -e "${YELLOW}确认配置:${NC}"
            echo -e "  IP: ${CYAN}${new_ip}/${new_mask}${NC}"
            echo -e "  网关: ${CYAN}${new_gw}${NC}"
            echo ""
            echo -ne "确认修改? (y/N): "; read confirm
            
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                if pct set "$id" -net0 "name=${NET_NAME},bridge=${NET_BRIDGE},ip=${new_ip}/${new_mask},gw=${new_gw}" 2>/dev/null; then
                    echo -e "${GREEN}配置已更新!${NC}"
                    echo -ne "是否重启容器使配置生效? (y/N): "; read restart_confirm
                    if [[ "$restart_confirm" == "y" || "$restart_confirm" == "Y" ]]; then
                        echo "重启容器中..."
                        pct reboot "$id" 2>/dev/null || { pct stop "$id" && sleep 2 && pct start "$id"; }
                        echo -e "${GREEN}容器已重启${NC}"
                    fi
                else
                    echo -e "${RED}配置失败${NC}"
                fi
            else
                echo "已取消"
            fi
            ;;
        2)
            echo -e "${YELLOW}=== 设置 DHCP ===${NC}"
            echo ""
            echo -ne "确认切换到 DHCP 模式? (y/N): "; read confirm
            
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                if pct set "$id" -net0 "name=${NET_NAME},bridge=${NET_BRIDGE},ip=dhcp" 2>/dev/null; then
                    echo -e "${GREEN}配置已更新!${NC}"
                    echo -ne "是否重启容器使配置生效? (y/N): "; read restart_confirm
                    if [[ "$restart_confirm" == "y" || "$restart_confirm" == "Y" ]]; then
                        echo "重启容器中..."
                        pct reboot "$id" 2>/dev/null || { pct stop "$id" && sleep 2 && pct start "$id"; }
                        echo -e "${GREEN}容器已重启${NC}"
                    fi
                else
                    echo -e "${RED}配置失败${NC}"
                fi
            else
                echo "已取消"
            fi
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            ;;
    esac
    
    pause_func
}

# 获取最新 Docker Compose 版本号
get_latest_compose_version() {
    local version
    version=$(curl -sL "https://api.github.com/repos/docker/compose/releases/latest" 2>/dev/null | grep -oP '"tag_name":\s*"\K[^"]+' || echo "")
    echo "$version"
}

# Docker 离线安装（静默模式）
install_docker_offline_silent() {
    local lxc_id=$1
    local offline_dir="/var/lib/vz/template/cache/pve-toolkit-offline"
    local offline_file="$offline_dir.tar.gz"
    
    if [[ -z "$lxc_id" ]]; then
        return 1
    fi
    
    if ! pct status "$lxc_id" &>/dev/null; then
        return 1
    fi
    
    if [[ ! -d "$offline_dir" || ! -f "$offline_dir/docker/docker-ce.deb" ]]; then
        if [[ ! -f "$offline_file" ]]; then
            echo -e "${YELLOW}正在下载离线包...${NC}"
            local OFFLINE_URL="https://ghproxy.com/https://github.com/MuskCheng/pve-toolkit/releases/download/${LATEST_VERSION}/pve-toolkit-offline-${LATEST_VERSION}-amd64.tar.gz"
            
            mkdir -p "$(dirname $offline_file)"
            if ! curl -L --progress-bar -fSL --connect-timeout 30 --max-time 600 "$OFFLINE_URL" -o "$offline_file"; then
                echo -e "${RED}离线包下载失败${NC}"
                rm -f "$offline_file"
                return 1
            fi
        fi
        
        echo -e "${YELLOW}解压离线包...${NC}"
        rm -rf "$offline_dir"
        mkdir -p "$offline_dir"
        tar -xzf "$offline_file" -C "$offline_dir"
    fi
    
    echo -e "${YELLOW}复制文件到容器...${NC}"
    pct exec "$lxc_id" -- mkdir -p /tmp/docker /tmp/images
    pct push "$lxc_id" "$offline_dir/docker/" /tmp/docker/ --recursive 2>/dev/null || return 1
    pct push "$lxc_id" "$offline_dir/images/" /tmp/images/ --recursive 2>/dev/null || true
    
    echo -e "${YELLOW}安装 Docker...${NC}"
    pct exec "$lxc_id" -- bash -c '
        cd /tmp/docker
        for deb in *.deb; do
            echo "  安装 $deb..."
            dpkg -i "$deb" 2>/dev/null || true
        done
        apt-get install -f -y
    '
    
    pct exec "$lxc_id" -- systemctl enable docker 2>/dev/null || true
    pct exec "$lxc_id" -- systemctl start docker 2>/dev/null || true
    
    echo -e "${YELLOW}加载 Lucky V2 镜像...${NC}"
    pct exec "$lxc_id" -- docker load -i /tmp/images/lucky.tar 2>/dev/null || true
    
    pct exec "$lxc_id" -- rm -rf /tmp/docker /tmp/images
    
    if pct exec "$lxc_id" -- docker --version &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# 安装常用工具菜单
install_tools_menu() {
    while true; do
        clear
        echo -e "${BLUE}════════ 安装常用工具 ════════${NC}"
        echo -e "  ${GREEN}[1]${NC} 🍀 Lucky V2 (反向代理/端口转发/DDNS)"
        echo -e "  ${GREEN}[2]${NC} 更多工具... (敬请期待)"
        echo -e "  ${GREEN}[0]${NC} 返回"
        echo -ne "${CYAN}选择: ${NC}"
        read c
        echo
        
        case "$c" in
            1) install_lucky ;;
            2) echo -e "${YELLOW}敬请期待${NC}"; pause_func ;;
            0) break ;;
        esac
    done
}

# 安装 Lucky V2
install_lucky() {
    echo -e "${BLUE}════════ 安装 Lucky V2 ════════${NC}"
    echo ""
    
    pct list
    echo ""
    echo -ne "请输入容器 ID: "; read lxc_id
    
    if [[ -z "$lxc_id" ]]; then
        echo -e "${RED}未输入容器 ID${NC}"
        pause_func
        return
    fi
    
    if ! pct status "$lxc_id" &>/dev/null; then
        echo -e "${RED}容器 $lxc_id 不存在${NC}"
        pause_func
        return
    fi
    
    echo -e "${YELLOW}检查 Docker 环境...${NC}"
    if ! pct exec "$lxc_id" -- command -v docker &>/dev/null; then
        echo -e "${RED}容器中未安装 Docker${NC}"
        echo -ne "是否安装 Docker? (Y/n): "; read install_docker
        
        if [[ "$install_docker" != "n" && "$install_docker" != "N" ]]; then
            if install_docker_offline_silent "$lxc_id"; then
                echo -e "${GREEN}Docker 安装完成${NC}"
            else
                echo -e "${RED}Docker 安装失败${NC}"
                pause_func
                return
            fi
        else
            pause_func
            return
        fi
    else
        echo -e "${GREEN}Docker 已安装${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}配置参数 (回车使用默认值):${NC}"
    
    echo -ne "  端口 [16601]: "; read lucky_port
    lucky_port=${lucky_port:-16601}
    
    echo -ne "  配置目录 [/opt/lucky]: "; read lucky_dir
    lucky_dir=${lucky_dir:-/opt/lucky}
    
    echo -ne "  容器名称 [lucky]: "; read lucky_name
    lucky_name=${lucky_name:-lucky}
    
    echo ""
    echo -e "${YELLOW}确认安装到容器 $lxc_id?${NC}"
    echo -e "  端口: ${GREEN}$lucky_port${NC}"
    echo -e "  配置目录: ${GREEN}$lucky_dir${NC}"
    echo -e "  容器名称: ${GREEN}$lucky_name${NC}"
    echo ""
    echo -ne "确认? (Y/n): "; read confirm
    
    if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
        echo -e "${YELLOW}已取消${NC}"
        pause_func
        return
    fi
    
    echo ""
    echo -e "${YELLOW}检查 Lucky V2 镜像...${NC}"
    
    if ! pct exec "$lxc_id" -- docker images gdy666/lucky:v2 --format "{{.ID}}" 2>/dev/null | grep -q .; then
        local offline_dir="/var/lib/vz/template/cache/pve-toolkit-offline"
        local image_loaded=0
        
        if [[ -f "$offline_dir/images/lucky.tar" ]]; then
            echo -e "${YELLOW}从离线包加载镜像...${NC}"
            pct exec "$lxc_id" -- mkdir -p /tmp/images
            pct push "$lxc_id" "$offline_dir/images/lucky.tar" /tmp/images/lucky.tar
            if pct exec "$lxc_id" -- docker load -i /tmp/images/lucky.tar 2>/dev/null; then
                image_loaded=1
                pct exec "$lxc_id" -- rm -f /tmp/images/lucky.tar
            fi
        fi
        
        if [[ $image_loaded -eq 0 ]]; then
            echo -e "${YELLOW}在线拉取镜像...${NC}"
            if ! pct exec "$lxc_id" -- docker pull gdy666/lucky:v2; then
                echo -e "${RED}镜像拉取失败${NC}"
                pause_func
                return
            fi
        fi
    else
        echo -e "${GREEN}镜像已存在${NC}"
    fi
    
    echo -e "${YELLOW}创建配置目录...${NC}"
    pct exec "$lxc_id" -- mkdir -p "$lucky_dir"
    
    echo -e "${YELLOW}启动 Lucky V2 容器...${NC}"
    pct exec "$lxc_id" -- docker rm -f "$lucky_name" 2>/dev/null || true
    
    pct exec "$lxc_id" -- docker run -d \
        --name "$lucky_name" \
        --restart=always \
        --net=host \
        -v "$lucky_dir:/goodluck" \
        gdy666/lucky:v2
    
    if [[ $? -eq 0 ]]; then
        local container_ip=$(pct exec "$lxc_id" -- hostname -I 2>/dev/null | awk '{print $1}')
        
        echo ""
        echo -e "${GREEN}═══════════════════════════════════════${NC}"
        echo -e "${GREEN}  Lucky V2 安装完成!${NC}"
        echo -e "${GREEN}═══════════════════════════════════════${NC}"
        echo ""
        if [[ -n "$container_ip" ]]; then
            echo -e "${CYAN}访问地址: http://${container_ip}:${lucky_port}${NC}"
        else
            echo -e "${CYAN}访问地址: http://<容器IP>:${lucky_port}${NC}"
        fi
        echo ""
        echo -e "${YELLOW}首次登录请设置管理员密码${NC}"
    else
        echo -e "${RED}Lucky V2 安装失败${NC}"
    fi
    
    pause_func
}

# Docker 离线安装
install_docker_offline() {
    local offline_dir="/var/lib/vz/template/cache/pve-toolkit-offline"
    local offline_file="$offline_dir.tar.gz"
    
    echo -e "${BLUE}════════ Docker 离线安装 ════════${NC}"
    echo ""
    
    pct list
    echo ""
    echo -ne "请输入容器 ID: "; read lxc_id
    
    if [[ -z "$lxc_id" ]]; then
        echo -e "${RED}未输入容器 ID${NC}"
        return 1
    fi
    
    if ! pct status "$lxc_id" &>/dev/null; then
        echo -e "${RED}容器 $lxc_id 不存在${NC}"
        return 1
    fi
    
    echo ""
    echo -e "${YELLOW}检查容器系统版本...${NC}"
    OS_INFO=$(pct exec "$lxc_id" -- cat /etc/os-release 2>/dev/null || echo "")
    if [[ ! "$OS_INFO" =~ "trixie" && ! "$OS_INFO" =~ "Debian GNU/Linux 13" ]]; then
        echo -e "${YELLOW}警告: 容器可能不是 Debian 13 (Trixie)${NC}"
        echo -e "${YELLOW}离线包仅支持 Debian 13 (Trixie) / amd64 架构${NC}"
        echo -ne "继续安装? (y/N): "; read confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            return 1
        fi
    fi
    
    local use_local="n"
    if [[ -f "$offline_file" ]]; then
        echo ""
        echo -e "${GREEN}检测到本地离线包: $offline_file${NC}"
        ls -lh "$offline_file" 2>/dev/null
        echo -ne "使用本地离线包? (Y/n): "; read use_local
    fi
    
    if [[ "$use_local" != "n" && "$use_local" != "N" ]]; then
        echo ""
        echo -e "${YELLOW}解压本地离线包...${NC}"
        rm -rf "$offline_dir"
        mkdir -p "$offline_dir"
        tar -xzf "$offline_file" -C "$offline_dir"
    else
        echo ""
        echo -e "${YELLOW}选择下载源:${NC}"
        echo -e "  ${GREEN}[1]${NC} GitHub 代理 (ghproxy.com) - 国内推荐"
        echo -e "  ${GREEN}[2]${NC} GitHub 原始 - 国外推荐"
        echo -e "  ${GREEN}[3]${NC} 本地文件 (已下载)"
        echo -ne "选择: "; read source_choice
        
        OFFLINE_URL=""
        case "$source_choice" in
            1)
                OFFLINE_URL="https://ghproxy.com/https://github.com/MuskCheng/pve-toolkit/releases/download/${LATEST_VERSION}/pve-toolkit-offline-${LATEST_VERSION}-amd64.tar.gz"
                ;;
            2)
                OFFLINE_URL="https://github.com/MuskCheng/pve-toolkit/releases/download/${LATEST_VERSION}/pve-toolkit-offline-${LATEST_VERSION}-amd64.tar.gz"
                ;;
            3)
                echo -ne "请输入离线包路径: "; read offline_path
                if [[ -f "$offline_path" ]]; then
                    cp "$offline_path" "$offline_file"
                    echo -e "${GREEN}已复制到: $offline_file${NC}"
                else
                    echo -e "${RED}文件不存在: $offline_path${NC}"
                    return 1
                fi
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                return 1
                ;;
        esac
        
        if [[ -n "$OFFLINE_URL" ]]; then
            echo ""
            echo -e "${YELLOW}下载离线包...${NC}"
            echo -e "${CYAN}URL: $OFFLINE_URL${NC}"
            
            DOWNLOAD_SUCCESS=0
            
            if command -v curl &>/dev/null; then
                if curl -L --progress-bar -fSL --connect-timeout 30 --max-time 600 "$OFFLINE_URL" -o "$offline_file"; then
                    DOWNLOAD_SUCCESS=1
                fi
            elif command -v wget &>/dev/null; then
                if wget --timeout=600 -O "$offline_file" "$OFFLINE_URL"; then
                    DOWNLOAD_SUCCESS=1
                fi
            fi
            
            if [[ $DOWNLOAD_SUCCESS -eq 0 ]]; then
                echo -e "${RED}下载失败${NC}"
                echo -e "${YELLOW}请手动下载离线包:${NC}"
                echo -e "  ${CYAN}https://github.com/MuskCheng/pve-toolkit/releases${NC}"
                rm -f "$offline_file"
                return 1
            fi
            
            echo -e "${GREEN}下载完成${NC}"
            ls -lh "$offline_file"
            
            echo ""
            echo -e "${YELLOW}解压离线包...${NC}"
            rm -rf "$offline_dir"
            mkdir -p "$offline_dir"
            tar -xzf "$offline_file" -C "$offline_dir"
        fi
    fi
    
    if [[ ! -d "$offline_dir" ]]; then
        echo -e "${RED}离线包目录不存在${NC}"
        return 1
    fi
    
    echo ""
    echo -e "${YELLOW}[1/4] 复制文件到容器...${NC}"
    pct exec "$lxc_id" -- mkdir -p /tmp/docker /tmp/images
    pct push "$lxc_id" "$offline_dir/docker/" /tmp/docker/ --recursive 2>/dev/null || {
        echo -e "${RED}复制 Docker 包失败${NC}"
        return 1
    }
    pct push "$lxc_id" "$offline_dir/images/" /tmp/images/ --recursive 2>/dev/null || {
        echo -e "${RED}复制镜像文件失败${NC}"
        return 1
    }
    
    echo -e "${YELLOW}[2/4] 安装 Docker...${NC}"
    pct exec "$lxc_id" -- bash -c '
        cd /tmp/docker
        for deb in *.deb; do
            echo "  安装 $deb..."
            dpkg -i "$deb" 2>/dev/null || true
        done
        apt-get install -f -y
    '
    
    echo -e "${YELLOW}[3/4] 启动 Docker 服务...${NC}"
    pct exec "$lxc_id" -- systemctl enable docker 2>/dev/null || true
    pct exec "$lxc_id" -- systemctl start docker 2>/dev/null || true
    
    echo -e "${YELLOW}[4/4] 加载 Lucky V2 镜像...${NC}"
    pct exec "$lxc_id" -- docker load -i /tmp/images/lucky.tar 2>/dev/null || {
        echo -e "${YELLOW}警告: Lucky 镜像加载失败，可能是文件不存在${NC}"
    }
    
    pct exec "$lxc_id" -- rm -rf /tmp/docker /tmp/images
    
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo -e "${GREEN}  安装完成${NC}"
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo ""
    echo -e "${GREEN}Docker 版本:${NC}"
    pct exec "$lxc_id" -- docker --version 2>/dev/null || echo -e "${RED}Docker 未正确安装${NC}"
    echo ""
    echo -e "${GREEN}Docker Compose 版本:${NC}"
    pct exec "$lxc_id" -- docker compose version 2>/dev/null || echo -e "${YELLOW}Docker Compose 未安装${NC}"
    echo ""
    echo -e "${GREEN}Lucky V2 镜像已加载${NC}"
    echo ""
    echo -e "${CYAN}启动 Lucky V2 命令:${NC}"
    echo -e "  docker run -d --name lucky --restart=always --net=host gdy666/lucky:v2"
    echo ""
}

# 检查并安装 Docker 和 Docker Compose
check_and_install_docker() {
    local lxc_id=$1
    
    if [[ -z "$lxc_id" ]]; then
        echo -e "${RED}错误: 请提供容器 ID${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}检查 Docker 环境...${NC}"
    
    DOCKER_AVAILABLE=0
    
    if pct exec "$lxc_id" -- bash -lc 'command -v docker &>/dev/null' 2>/dev/null || \
       pct exec "$lxc_id" -- test -x /usr/bin/docker 2>/dev/null || \
       pct exec "$lxc_id" -- test -x /usr/local/bin/docker 2>/dev/null; then
        echo -e "${GREEN}Docker 已安装${NC}"
        pct exec "$lxc_id" -- docker --version 2>/dev/null || pct exec "$lxc_id" -- /usr/bin/docker --version 2>/dev/null || true
        DOCKER_AVAILABLE=1
        
        echo -e "${YELLOW}尝试启动 Docker 服务...${NC}"
        pct exec "$lxc_id" -- bash -lc 'systemctl enable docker 2>/dev/null || true'
        pct exec "$lxc_id" -- bash -lc 'systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true'
        
        if pct exec "$lxc_id" -- docker info &>/dev/null; then
            echo -e "${GREEN}Docker 服务运行正常${NC}"
        else
            echo -e "${YELLOW}Docker 服务未运行，尝试直接使用 docker 命令...${NC}"
        fi
    else
        echo -e "${YELLOW}Docker 未安装，开始安装...${NC}"
        echo -e "${YELLOW}安装 Docker...${NC}"
        
        if pct exec "$lxc_id" -- bash -lc 'apt update && apt install -y docker.io' 2>&1; then
            pct exec "$lxc_id" -- bash -lc 'systemctl enable docker 2>/dev/null || true'
            pct exec "$lxc_id" -- bash -lc 'systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true'
            
            if pct exec "$lxc_id" -- bash -lc 'command -v docker &>/dev/null' 2>/dev/null || \
               pct exec "$lxc_id" -- test -x /usr/bin/docker 2>/dev/null; then
                echo -e "${GREEN}Docker 安装完成${NC}"
                pct exec "$lxc_id" -- docker --version 2>/dev/null || true
                DOCKER_AVAILABLE=1
            fi
        fi
    fi
    
    if [[ $DOCKER_AVAILABLE -eq 0 ]]; then
        echo -e "${RED}Docker 安装失败${NC}"
        return 1
    fi
    
    COMPOSE_VERSION=""
    COMPOSE_CMD=""
    
    if pct exec "$lxc_id" -- test -x /usr/local/bin/docker-compose 2>/dev/null; then
        COMPOSE_CMD="/usr/local/bin/docker-compose"
        echo -e "${GREEN}Docker Compose 已安装 (docker-compose)${NC}"
        pct exec "$lxc_id" -- /usr/local/bin/docker-compose --version 2>/dev/null || true
    elif pct exec "$lxc_id" -- bash -lc 'command -v docker-compose &>/dev/null' 2>/dev/null; then
        COMPOSE_CMD="docker-compose"
        echo -e "${GREEN}Docker Compose 已安装 (docker-compose)${NC}"
        pct exec "$lxc_id" -- docker-compose --version 2>/dev/null || true
    elif pct exec "$lxc_id" -- bash -lc 'docker compose version &>/dev/null' 2>/dev/null; then
        COMPOSE_CMD="docker compose"
        echo -e "${GREEN}Docker Compose 已安装 (docker compose plugin)${NC}"
        pct exec "$lxc_id" -- docker compose version 2>/dev/null || true
    else
        echo -e "${YELLOW}Docker Compose 未安装，开始安装...${NC}"
        COMPOSE_INSTALL_SUCCESS=0
        
        echo -e "${YELLOW}安装必要工具 (curl/wget)...${NC}"
        CURL_INSTALL_LOG=$(pct exec "$lxc_id" -- bash -lc 'apt update && apt install -y curl wget 2>&1' || true)
        
        HAS_CURL=0
        HAS_WGET=0
        if pct exec "$lxc_id" -- bash -lc 'command -v curl &>/dev/null' 2>/dev/null || \
           pct exec "$lxc_id" -- test -x /usr/bin/curl 2>/dev/null; then
            HAS_CURL=1
            echo -e "${GREEN}curl 已安装${NC}"
        fi
        if pct exec "$lxc_id" -- bash -lc 'command -v wget &>/dev/null' 2>/dev/null || \
           pct exec "$lxc_id" -- test -x /usr/bin/wget 2>/dev/null; then
            HAS_WGET=1
            echo -e "${GREEN}wget 已安装${NC}"
        fi
        
        if [[ $HAS_CURL -eq 0 && $HAS_WGET -eq 0 ]]; then
            echo -e "${YELLOW}curl/wget 不可用，尝试使用 pip 安装...${NC}"
            if pct exec "$lxc_id" -- bash -lc 'command -v pip3 &>/dev/null' 2>/dev/null || \
               pct exec "$lxc_id" -- test -x /usr/bin/pip3 2>/dev/null; then
                if pct exec "$lxc_id" -- pip3 install docker-compose --break-system-packages 2>&1; then
                    PIP_COMPOSE_PATH=$(pct exec "$lxc_id" -- bash -lc 'command -v docker-compose 2>/dev/null' || echo "")
                    if [[ -n "$PIP_COMPOSE_PATH" ]]; then
                        echo -e "${GREEN}Docker Compose (pip) 安装完成: $PIP_COMPOSE_PATH${NC}"
                        COMPOSE_CMD="$PIP_COMPOSE_PATH"
                        pct exec "$lxc_id" -- docker-compose --version 2>/dev/null || true
                        COMPOSE_INSTALL_SUCCESS=1
                    fi
                fi
            fi
            
            if [[ $COMPOSE_INSTALL_SUCCESS -eq 0 ]]; then
                echo -e "${RED}Docker Compose 安装失败，请手动安装${NC}"
                echo -e "${YELLOW}手动安装命令:${NC}"
                echo -e "  apt update && apt install -y curl"
                echo -e "  curl -L \"https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64\" -o /usr/local/bin/docker-compose"
                echo -e "  chmod +x /usr/local/bin/docker-compose"
                return 1
            fi
        else
            echo -e "${YELLOW}获取 Docker Compose 最新版本...${NC}"
            if [[ $HAS_CURL -eq 1 ]]; then
                API_RESULT=$(pct exec "$lxc_id" -- bash -lc 'curl -sL --connect-timeout 10 "https://api.github.com/repos/docker/compose/releases/latest" 2>&1' || echo "")
                COMPOSE_VERSION=$(echo "$API_RESULT" | grep -oP '"tag_name":\s*"\K[^"]+' || echo "")
                if [[ -z "$COMPOSE_VERSION" ]]; then
                    echo -e "${YELLOW}GitHub API 访问失败，网络可能受限${NC}"
                fi
            fi
            
            if [[ -z "$COMPOSE_VERSION" ]]; then
                COMPOSE_VERSION="v2.24.0"
                echo -e "${YELLOW}无法获取最新版本，使用默认版本: $COMPOSE_VERSION${NC}"
            else
                echo -e "${GREEN}最新版本: $COMPOSE_VERSION${NC}"
            fi
            
            echo -e "${YELLOW}尝试使用二进制方式安装...${NC}"
            COMPOSE_URLS=(
                "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64"
                "https://mirrors.ustc.edu.cn/docker-compose/${COMPOSE_VERSION}/docker-compose-Linux-x86_64"
                "https://ghproxy.com/https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64"
                "https://mirror.ghproxy.com/https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64"
                "https://gh.xxooo.cf/https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64"
                "https://edgeone.gh-proxy.org/https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64"
                "https://gh.nxnow.top/https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64"
            )
            
            for url in "${COMPOSE_URLS[@]}"; do
                echo -e "${CYAN}尝试: $url${NC}"
                DOWNLOAD_SUCCESS=0
                DOWNLOAD_LOG=""
                
                pct exec "$lxc_id" -- bash -lc 'rm -f /usr/local/bin/docker-compose' 2>/dev/null || true
                
                if [[ $HAS_CURL -eq 1 ]]; then
                    DOWNLOAD_LOG=$(pct exec "$lxc_id" -- bash -lc "curl -L --connect-timeout 10 --max-time 120 -fSL '$url' -o /usr/local/bin/docker-compose 2>&1" || true)
                elif [[ $HAS_WGET -eq 1 ]]; then
                    DOWNLOAD_LOG=$(pct exec "$lxc_id" -- bash -lc "wget --timeout=120 -O /usr/local/bin/docker-compose '$url' 2>&1" || true)
                fi
                
                FILE_SIZE=$(pct exec "$lxc_id" -- stat -c%s /usr/local/bin/docker-compose 2>/dev/null || echo "0")
                FILE_HEAD=$(pct exec "$lxc_id" -- head -c 4 /usr/local/bin/docker-compose 2>/dev/null | xxd -p 2>/dev/null || echo "")
                
                IS_HTML=0
                if [[ "$FILE_HEAD" == "3c21444f" || "$FILE_HEAD" == "3c68746d" || "$FILE_HEAD" =~ ^3c21 || "$FILE_HEAD" =~ ^3c68 ]]; then
                    IS_HTML=1
                fi
                
                if [[ "$FILE_SIZE" -gt 1000000 && $IS_HTML -eq 0 ]]; then
                    DOWNLOAD_SUCCESS=1
                    echo -e "${GREEN}下载完成，文件大小: ${FILE_SIZE} bytes${NC}"
                else
                    echo -e "${RED}下载的文件无效 (大小: ${FILE_SIZE} bytes, head: ${FILE_HEAD})${NC}"
                    pct exec "$lxc_id" -- bash -lc 'rm -f /usr/local/bin/docker-compose' 2>/dev/null || true
                fi
                
                if [[ $DOWNLOAD_SUCCESS -eq 1 ]]; then
                    pct exec "$lxc_id" -- bash -lc 'chmod +x /usr/local/bin/docker-compose' 2>&1
                    
                    IS_ELF=$(pct exec "$lxc_id" -- file /usr/local/bin/docker-compose 2>/dev/null | grep -i "elf\|executable" || echo "")
                    if [[ -z "$IS_ELF" ]]; then
                        echo -e "${RED}文件不是有效的可执行文件${NC}"
                        pct exec "$lxc_id" -- bash -lc 'rm -f /usr/local/bin/docker-compose' 2>/dev/null || true
                        DOWNLOAD_SUCCESS=0
                    fi
                fi
                
                if [[ $DOWNLOAD_SUCCESS -eq 1 ]]; then
                    VERIFY_OUTPUT=$(pct exec "$lxc_id" -- bash -lc '/usr/local/bin/docker-compose --version 2>&1' || true)
                    if [[ "$VERIFY_OUTPUT" =~ Docker\ Compose ]]; then
                        echo -e "${GREEN}Docker Compose (二进制) 安装完成: $VERIFY_OUTPUT${NC}"
                        COMPOSE_CMD="/usr/local/bin/docker-compose"
                        COMPOSE_INSTALL_SUCCESS=1
                        break
                    else
                        echo -e "${RED}验证失败: $VERIFY_OUTPUT${NC}"
                        pct exec "$lxc_id" -- bash -lc 'rm -f /usr/local/bin/docker-compose' 2>/dev/null || true
                    fi
                fi
                echo -e "${RED}此源下载失败，尝试下一个...${NC}"
            done
            
            if [[ $COMPOSE_INSTALL_SUCCESS -eq 0 ]]; then
                echo -e "${RED}所有下载方式均失败，尝试 pip 安装...${NC}"
                if pct exec "$lxc_id" -- bash -lc 'command -v pip3 &>/dev/null' 2>/dev/null || \
                   pct exec "$lxc_id" -- test -x /usr/bin/pip3 2>/dev/null; then
                    if pct exec "$lxc_id" -- pip3 install docker-compose --break-system-packages 2>&1; then
                        PIP_COMPOSE_PATH=$(pct exec "$lxc_id" -- bash -lc 'command -v docker-compose 2>/dev/null' || echo "")
                        if [[ -n "$PIP_COMPOSE_PATH" ]]; then
                            echo -e "${GREEN}Docker Compose (pip) 安装完成: $PIP_COMPOSE_PATH${NC}"
                            COMPOSE_CMD="$PIP_COMPOSE_PATH"
                            pct exec "$lxc_id" -- docker-compose --version 2>/dev/null || true
                            COMPOSE_INSTALL_SUCCESS=1
                        fi
                    fi
                fi
            fi
            
            if [[ $COMPOSE_INSTALL_SUCCESS -eq 0 ]]; then
                echo -e "${RED}Docker Compose 安装失败，请手动安装${NC}"
                echo -e "${YELLOW}手动安装命令:${NC}"
                echo -e "  apt update && apt install -y curl"
                echo -e "  curl -L \"https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64\" -o /usr/local/bin/docker-compose"
                echo -e "  chmod +x /usr/local/bin/docker-compose"
                return 1
            fi
        fi
    fi
    
    return 0
}

# Docker 管理
docker_menu() {
    while true; do
        clear
        echo -e "${BLUE}════════ Docker 管理 ════════${NC}"
        echo -e "  ${GREEN}[1]${NC} 安装 Docker (含 Docker Compose)"
        echo -e "  ${GREEN}[2]${NC} Docker 部署向导"
        echo -e "  ${GREEN}[3]${NC} Docker Compose 部署向导"
        echo -e "  ${GREEN}[4]${NC} 一键升级镜像"
        echo -e "  ${GREEN}[5]${NC} Docker 换源"
        echo -e "  ${GREEN}[6]${NC} Docker 容器管理"
        echo -e "  ${GREEN}[7]${NC} 安装 Docker (离线包)"
        echo -e "  ${GREEN}[0]${NC} 返回"
        echo -ne "${CYAN}选择: ${NC}"
        read c
        echo
        
        case "$c" in
            1)
                pct list
                echo -ne "请输入要安装 Docker 的容器 ID: "; read id
                if [[ -n "$id" ]]; then
                    check_and_install_docker "$id"
                fi
                pause_func
                ;;
            2)
                docker_run_deploy
                ;;
            3)
                docker_deploy_menu
                ;;
            4)
                pct list
                echo -ne "请输入要升级镜像的容器 ID: "; read id
                if [[ -n "$id" ]]; then
                    if ! pct exec "$id" -- command -v docker &>/dev/null; then
                        echo -e "${RED}错误: 容器中未安装 Docker${NC}"
                        pause_func
                        continue
                    fi
                    
                    echo ""
                    echo -e "${YELLOW}请输入 docker-compose.yml 所在目录:${NC}"
                    echo -e "${CYAN}示例: /opt/wordpress 或 /opt/nginx${NC}"
                    echo -ne "目录路径: "; read compose_dir
                    
                    if [[ -z "$compose_dir" ]]; then
                        echo -e "${RED}错误: 请输入目录路径${NC}"
                        pause_func
                        continue
                    fi
                    
                    if ! pct exec "$id" -- test -f "$compose_dir/docker-compose.yml"; then
                        echo -e "${RED}错误: $compose_dir/docker-compose.yml 不存在${NC}"
                        pause_func
                        continue
                    fi
                    
                    echo ""
                    echo -e "${YELLOW}=== 升级流程 ===${NC}"
                    
                    COMPOSE_CMD=$(get_compose_cmd "$id")
                    if [[ -z "$COMPOSE_CMD" ]]; then
                        echo -e "${RED}Docker Compose 未安装${NC}"
                        pause_func
                        continue
                    fi
                    
                    echo -e "1. 停止容器..."
                    pct exec "$id" -- bash -c "cd $compose_dir && $COMPOSE_CMD stop"
                    
                    echo -e "2. 拉取最新镜像..."
                    pct exec "$id" -- bash -c "cd $compose_dir && $COMPOSE_CMD pull"
                    
                    echo -e "3. 重启容器..."
                    pct exec "$id" -- bash -c "cd $compose_dir && $COMPOSE_CMD up -d"
                    
                    echo ""
                    echo -e "${YELLOW}=== 升级后的容器状态 ===${NC}"
                    pct exec "$id" -- bash -c "cd $compose_dir && $COMPOSE_CMD ps"
                    
                    echo ""
                    echo -e "${GREEN}镜像升级完成！${NC}"
                    echo -e "${YELLOW}注意: volumes 数据和配置文件不会丢失${NC}"
                fi
                pause_func
                ;;
            5)
                docker_change_registry
                ;;
            6)
                docker_container_menu
                ;;
            7)
                install_docker_offline
                ;;
            0) break ;;
        esac
    done
}

docker_container_menu() {
    clear
    echo -e "${BLUE}════════ Docker 容器管理 ════════${NC}"
    
    pct list
    echo ""
    echo -ne "选择 LXC 容器 ID: "; read lxc_id
    
    if [[ -z "$lxc_id" ]]; then
        echo -e "${RED}错误: 请输入容器 ID${NC}"
        pause_func
        return
    fi
    
    if ! pct exec "$lxc_id" -- bash -lc 'command -v docker &>/dev/null' 2>/dev/null && \
       ! pct exec "$lxc_id" -- test -x /usr/bin/docker 2>/dev/null; then
        echo -e "${RED}错误: 容器中未安装 Docker${NC}"
        pause_func
        return
    fi
    
    while true; do
        clear
        echo -e "${BLUE}════════ Docker 容器管理 [LXC: $lxc_id] ════════${NC}"
        
        echo -e "${YELLOW}Docker 容器列表:${NC}"
        pct exec "$lxc_id" -- docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{range .Ports}}{{.PublicPort}} {{end}}' 2>/dev/null || echo "无法获取容器列表"
        echo ""
        
        echo -e "  ${GREEN}[1]${NC} 查看容器详情"
        echo -e "  ${GREEN}[2]${NC} 启动容器"
        echo -e "  ${GREEN}[3]${NC} 停止容器"
        echo -e "  ${GREEN}[4]${NC} 重启容器"
        echo -e "  ${GREEN}[5]${NC} 查看容器日志"
        echo -e "  ${GREEN}[6]${NC} 进入容器终端"
        echo -e "  ${GREEN}[7]${NC} 删除容器"
        echo -e "  ${GREEN}[8]${NC} 清理无用容器/镜像"
        echo -e "  ${GREEN}[0]${NC} 返回"
        echo -ne "${CYAN}选择: ${NC}"
        read c
        echo
        
        case "$c" in
            1) docker_container_inspect "$lxc_id" ;;
            2) docker_container_start "$lxc_id" ;;
            3) docker_container_stop "$lxc_id" ;;
            4) docker_container_restart "$lxc_id" ;;
            5) docker_container_logs "$lxc_id" ;;
            6) docker_container_exec "$lxc_id" ;;
            7) docker_container_rm "$lxc_id" ;;
            8) docker_container_prune "$lxc_id" ;;
            0) break ;;
        esac
    done
}

docker_container_inspect() {
    local lxc_id=$1
    echo -ne "请输入容器名称: "; read container_name
    if [[ -n "$container_name" ]]; then
        pct exec "$lxc_id" -- docker inspect "$container_name" 2>/dev/null | head -100
    fi
    pause_func
}

docker_container_start() {
    local lxc_id=$1
    echo -ne "请输入容器名称: "; read container_name
    if [[ -n "$container_name" ]]; then
        if pct exec "$lxc_id" -- docker start "$container_name" 2>/dev/null; then
            echo -e "${GREEN}容器 $container_name 已启动${NC}"
        else
            echo -e "${RED}启动失败${NC}"
        fi
    fi
    pause_func
}

docker_container_stop() {
    local lxc_id=$1
    echo -ne "请输入容器名称: "; read container_name
    if [[ -n "$container_name" ]]; then
        if pct exec "$lxc_id" -- docker stop "$container_name" 2>/dev/null; then
            echo -e "${GREEN}容器 $container_name 已停止${NC}"
        else
            echo -e "${RED}停止失败${NC}"
        fi
    fi
    pause_func
}

docker_container_restart() {
    local lxc_id=$1
    echo -ne "请输入容器名称: "; read container_name
    if [[ -n "$container_name" ]]; then
        if pct exec "$lxc_id" -- docker restart "$container_name" 2>/dev/null; then
            echo -e "${GREEN}容器 $container_name 已重启${NC}"
        else
            echo -e "${RED}重启失败${NC}"
        fi
    fi
    pause_func
}

docker_container_logs() {
    local lxc_id=$1
    echo -ne "请输入容器名称: "; read container_name
    if [[ -n "$container_name" ]]; then
        echo -e "${YELLOW}最近 100 行日志:${NC}"
        pct exec "$lxc_id" -- docker logs --tail 100 "$container_name" 2>&1
    fi
    pause_func
}

docker_container_exec() {
    local lxc_id=$1
    echo -ne "请输入容器名称: "; read container_name
    if [[ -n "$container_name" ]]; then
        if pct exec "$lxc_id" -- docker exec -it "$container_name" sh 2>/dev/null; then
            :
        elif pct exec "$lxc_id" -- docker exec -it "$container_name" bash 2>/dev/null; then
            :
        else
            echo -e "${RED}无法进入容器终端${NC}"
        fi
    fi
    pause_func
}

docker_container_rm() {
    local lxc_id=$1
    echo -ne "请输入容器名称: "; read container_name
    if [[ -n "$container_name" ]]; then
        echo -e "${RED}警告: 将删除容器 $container_name${NC}"
        echo -ne "确认删除? (y/N): "; read confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            if pct exec "$lxc_id" -- docker rm -f "$container_name" 2>/dev/null; then
                echo -e "${GREEN}容器 $container_name 已删除${NC}"
            else
                echo -e "${RED}删除失败${NC}"
            fi
        fi
    fi
    pause_func
}

docker_container_prune() {
    local lxc_id=$1
    echo -e "${YELLOW}清理停止的容器、无用网络和镜像...${NC}"
    echo -ne "确认清理? (y/N): "; read confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        pct exec "$lxc_id" -- docker system prune -f
        echo -e "${GREEN}清理完成${NC}"
    fi
    pause_func
}

docker_change_registry() {
    clear
    echo -e "${BLUE}════════ Docker 换源 ════════${NC}"
    
    pct list
    echo ""
    echo -ne "选择 LXC 容器 ID: "; read lxc_id
    
    if [[ -z "$lxc_id" ]]; then
        echo -e "${RED}错误: 请输入容器 ID${NC}"
        pause_func
        return
    fi
    
    if ! pct exec "$lxc_id" -- bash -lc 'command -v docker &>/dev/null' 2>/dev/null && \
       ! pct exec "$lxc_id" -- test -x /usr/bin/docker 2>/dev/null; then
        echo -e "${RED}错误: 容器中未安装 Docker${NC}"
        pause_func
        return
    fi
    
    echo ""
    echo -e "${YELLOW}当前 Docker 镜像源配置:${NC}"
    CURRENT_MIRROR=$(pct exec "$lxc_id" -- cat /etc/docker/daemon.json 2>/dev/null || echo "未配置")
    echo "$CURRENT_MIRROR"
    echo ""
    
    echo -e "${YELLOW}选择镜像源:${NC}"
    echo -e "  ${GREEN}[1]${NC} DaoCloud (推荐)"
    echo -e "  ${GREEN}[2]${NC} 轩辕镜像免费版"
    echo -e "  ${GREEN}[3]${NC} KSpeeder"
    echo -e "  ${GREEN}[4]${NC} 自定义镜像源"
    echo -e "  ${GREEN}[0]${NC} 取消"
    echo -ne "${CYAN}选择: ${NC}"
    read registry_choice
    echo
    
    REGISTRY_MIRRORS=""
    case "$registry_choice" in
        1)
            REGISTRY_MIRRORS="https://docker.m.daocloud.io"
            echo -e "${GREEN}已选择: DaoCloud 镜像源${NC}"
            ;;
        2)
            REGISTRY_MIRRORS="https://docker.xuanyuan.me"
            echo -e "${GREEN}已选择: 轩辕镜像免费版${NC}"
            ;;
        3)
            REGISTRY_MIRRORS="https://registry.linkease.net:5443"
            echo -e "${GREEN}已选择: KSpeeder 镜像源${NC}"
            ;;
        4)
            echo -ne "请输入镜像源地址: "; read REGISTRY_MIRRORS
            if [[ -z "$REGISTRY_MIRRORS" ]]; then
                echo -e "${RED}错误: 请输入镜像源地址${NC}"
                pause_func
                return
            fi
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            pause_func
            return
            ;;
    esac
    
    echo ""
    echo -e "${YELLOW}正在配置 Docker 镜像源...${NC}"
    
    pct exec "$lxc_id" -- bash -lc 'mkdir -p /etc/docker' 2>/dev/null
    
    pct exec "$lxc_id" -- bash -lc "echo '{\"registry-mirrors\": [\"$REGISTRY_MIRRORS\"]}' > /etc/docker/daemon.json"
    
    echo -e "${YELLOW}验证配置文件...${NC}"
    CONFIG_CONTENT=$(pct exec "$lxc_id" -- cat /etc/docker/daemon.json 2>/dev/null)
    echo "$CONFIG_CONTENT"
    
    if ! echo "$CONFIG_CONTENT" | grep -q "registry-mirrors"; then
        echo -e "${RED}配置文件写入失败${NC}"
        pause_func
        return
    fi
    
    echo ""
    echo -e "${YELLOW}重启 Docker 服务...${NC}"
    pct exec "$lxc_id" -- bash -lc 'systemctl daemon-reload 2>/dev/null || true'
    pct exec "$lxc_id" -- bash -lc 'systemctl restart docker 2>/dev/null || service docker restart 2>/dev/null || true'
    
    sleep 3
    
    echo ""
    echo -e "${YELLOW}检查 Docker 服务状态...${NC}"
    if pct exec "$lxc_id" -- bash -lc 'systemctl is-active docker &>/dev/null' 2>/dev/null || \
       pct exec "$lxc_id" -- bash -lc 'service docker status &>/dev/null' 2>/dev/null; then
        echo -e "${GREEN}Docker 服务运行正常${NC}"
    else
        echo -e "${RED}Docker 服务异常，请检查日志${NC}"
        pct exec "$lxc_id" -- journalctl -u docker --no-pager -n 10 2>/dev/null || true
        pause_func
        return
    fi
    
    echo ""
    echo -e "${YELLOW}验证镜像源是否生效...${NC}"
    DOCKER_INFO=$(pct exec "$lxc_id" -- docker info 2>/dev/null | grep -A 5 "Registry Mirrors" || echo "")
    if [[ -n "$DOCKER_INFO" ]]; then
        echo -e "${GREEN}镜像源配置生效:${NC}"
        echo "$DOCKER_INFO"
    else
        echo -e "${YELLOW}无法通过 docker info 确认，但配置文件已写入${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}测试拉取镜像 (hello-world)...${NC}"
    if pct exec "$lxc_id" -- docker pull hello-world 2>&1 | head -5; then
        echo ""
        echo -e "${GREEN}Docker 镜像源配置成功！${NC}"
    else
        echo -e "${YELLOW}测试拉取失败，请检查网络或尝试其他镜像源${NC}"
    fi
    
    pause_func
}

# Docker 部署向导
docker_run_deploy() {
    clear
    echo -e "${BLUE}════════ Docker 部署向导 ════════${NC}"
    echo -e "${YELLOW}此向导将引导您使用 docker run 部署单个容器${NC}"
    echo ""
    
    pct list
    echo ""
    echo -ne "选择 LXC 容器 ID: "; read lxc_id
    
    if [[ -z "$lxc_id" ]]; then
        echo -e "${RED}错误: 请输入容器 ID${NC}"
        pause_func
        return
    fi
    
    if ! pct status "$lxc_id" | grep -q "running"; then
        echo -e "${RED}错误: 容器 $lxc_id 未运行，请先启动${NC}"
        pause_func
        return
    fi
    
    check_and_install_docker "$lxc_id"
    
    echo ""
    echo "=== 选择镜像 ==="
    echo "请选择要部署的镜像:"
    echo ""
    echo -e "  ${GREEN}[1]${NC} nginx        - Web 服务器"
    echo -e "  ${GREEN}[2]${NC} mysql        - MySQL 数据库"
    echo -e "  ${GREEN}[3]${NC} postgres     - PostgreSQL 数据库"
    echo -e "  ${GREEN}[4]${NC} redis        - Redis 缓存"
    echo -e "  ${GREEN}[5]${NC} mongo        - MongoDB 数据库"
    echo -e "  ${GREEN}[6]${NC} mariadb      - MariaDB 数据库"
    echo -e "  ${GREEN}[7]${NC} rabbitmq     - RabbitMQ 消息队列"
    echo -e "  ${GREEN}[8]${NC} elasticsearch - Elasticsearch 搜索引擎"
    echo -e "  ${GREEN}[9]${NC} portainer    - Portainer 容器管理"
    echo -e "  ${GREEN}[10]${NC} jellyfin    - Jellyfin 媒体服务器"
    echo -e "  ${GREEN}[11]${NC} nextcloud   - Nextcloud 云盘"
    echo -e "  ${GREEN}[12]${NC} custom      - 自定义镜像"
    echo -ne "${CYAN}选择: ${NC}"
    read image_choice
    
    case "$image_choice" in
        1) IMAGE="nginx:latest" ;;
        2) IMAGE="mysql:8" ;;
        3) IMAGE="postgres:16" ;;
        4) IMAGE="redis:alpine" ;;
        5) IMAGE="mongo:7" ;;
        6) IMAGE="mariadb:10" ;;
        7) IMAGE="rabbitmq:3-management" ;;
        8) IMAGE="elasticsearch:8" ;;
        9) IMAGE="portainer/portainer-ce:latest" ;;
        10) IMAGE="jellyfin/jellyfin:latest" ;;
        11) IMAGE="nextcloud:latest" ;;
        12)
            echo -ne "请输入自定义镜像 (如 nginx:latest): "; read IMAGE
            if [[ -z "$IMAGE" ]]; then
                echo -e "${RED}错误: 请输入镜像${NC}"
                pause_func
                return
            fi
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            pause_func
            return
            ;;
    esac
    
    echo ""
    echo "=== 容器配置 ==="
    echo -ne "容器名称 (留空自动生成): "; read container_name
    echo -ne "端口映射 (格式: 8080:80, 多个用逗号分隔): "; read ports
    echo -ne "环境变量 (格式: MYSQL_ROOT_PASSWORD=123456, 多个用逗号分隔): "; read envs
    echo -ne "卷挂载 (格式: /host/path:/container/path, 多个用逗号分隔): "; read volumes
    echo -e "重启策略: "
    echo -e "  ${GREEN}[1]${NC} always (推荐，容器自动重启)"
    echo -e "  ${GREEN}[2]${NC} no (不重启)"
    echo -e "  ${GREEN}[3]${NC} unless-stopped (除非手动停止)"
    echo -ne "选择 [1]: "; read restart_choice
    restart_choice=${restart_choice:-1}
    case "$restart_choice" in
        1) RESTART="always" ;;
        2) RESTART="no" ;;
        3) RESTART="unless-stopped" ;;
        *) RESTART="always" ;;
    esac
    
    echo ""
    echo "=== 确认配置 ==="
    echo -e "${YELLOW}镜像:${NC} $IMAGE"
    echo -e "${YELLOW}容器名称:${NC} ${container_name:-自动生成}"
    echo -e "${YELLOW}端口:${NC} ${ports:-无}"
    echo -e "${YELLOW}环境变量:${NC} ${envs:-无}"
    echo -e "${YELLOW}卷挂载:${NC} ${volumes:-无}"
    echo -e "${YELLOW}重启策略:${NC} $RESTART"
    echo ""
    echo -ne "确认部署? (y/N): "; read confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "已取消"
        pause_func
        return
    fi
    
    echo ""
    echo "=== 部署容器 ==="
    
    DOCKER_CMD="docker run -d --restart=$RESTART"
    
    if [[ -n "$container_name" ]]; then
        DOCKER_CMD+=" --name $container_name"
    fi
    
    if [[ -n "$ports" ]]; then
        IFS=',' read -ra PORT_ARRAY <<< "$ports"
        for port in "${PORT_ARRAY[@]}"; do
            port=$(echo "$port" | xargs)
            DOCKER_CMD+=" -p $port"
        done
    fi
    
    if [[ -n "$envs" ]]; then
        IFS=',' read -ra ENV_ARRAY <<< "$envs"
        for env in "${ENV_ARRAY[@]}"; do
            env=$(echo "$env" | xargs)
            DOCKER_CMD+=" -e $env"
        done
    fi
    
    if [[ -n "$volumes" ]]; then
        IFS=',' read -ra VOL_ARRAY <<< "$volumes"
        for vol in "${VOL_ARRAY[@]}"; do
            vol=$(echo "$vol" | xargs)
            DOCKER_CMD+=" -v $vol"
        done
    fi
    
    DOCKER_CMD+=" $IMAGE"
    
    echo "执行命令: $DOCKER_CMD"
    pct exec "$lxc_id" -- bash -c "$DOCKER_CMD"
    
    if [[ $? -eq 0 ]]; then
        echo ""
        echo -e "${GREEN}部署完成!${NC}"
        echo -e "查看容器状态: ${CYAN}pct exec $lxc_id -- docker ps${NC}"
        CONTAINER_NAME=${container_name:-$(pct exec "$lxc_id" -- docker ps --format '{{.Names}}' | tail -1)}
        echo -e "查看日志: ${CYAN}pct exec $lxc_id -- docker logs $CONTAINER_NAME${NC}"
    else
        echo -e "${RED}部署失败${NC}"
    fi
    
    pause_func
}

# Docker Compose 部署向导
docker_deploy_menu() {
    while true; do
        clear
        echo -e "${BLUE}════════ Docker Compose 部署向导 ════════${NC}"
        echo -e "${YELLOW}此向导将引导您交互式创建 docker-compose.yml 并部署${NC}"
        echo ""
        echo -e "  ${GREEN}[1]${NC} 新建服务部署"
        echo -e "  ${GREEN}[2]${NC} 已有模板部署"
        echo -e "  ${GREEN}[3]${NC} 自定义部署 (粘贴 docker-compose.yml)"
        echo -e "  ${GREEN}[0]${NC} 返回"
        echo -ne "${CYAN}选择: ${NC}"
        read c
        echo
        
        case "$c" in
            1) docker_deploy_new ;;
            2) docker_deploy_template ;;
            3) docker_deploy_custom ;;
            0) break ;;
        esac
    done
}

docker_deploy_new() {
    clear
    echo -e "${BLUE}═══ 新建服务部署 ═══${NC}"
    
    pct list
    echo ""
    echo -ne "选择 LXC 容器 ID: "; read lxc_id
    
    if [[ -z "$lxc_id" ]]; then
        echo -e "${RED}错误: 请输入容器 ID${NC}"
        pause_func
        return
    fi
    
    if ! pct status "$lxc_id" | grep -q "running"; then
        echo -e "${RED}错误: 容器 $lxc_id 未运行，请先启动${NC}"
        pause_func
        return
    fi
    
    echo ""
    if ! check_and_install_docker "$lxc_id"; then
        echo -e "${RED}Docker 环境检查失败，无法继续部署${NC}"
        pause_func
        return
    fi
    
    echo ""
    echo "=== 第1步: 服务基础配置 ==="
    echo -ne "服务名称 (用于容器名): "; read service_name
    if [[ -z "$service_name" ]]; then
        echo -e "${RED}错误: 请输入服务名称${NC}"
        pause_func
        return
    fi
    
    echo -ne "镜像 (如 nginx:latest, mysql:8, redis:alpine): "; read image
    if [[ -z "$image" ]]; then
        echo -e "${RED}错误: 请输入镜像${NC}"
        pause_func
        return
    fi
    
    echo ""
    echo "=== 第2步: 端口映射 ==="
    echo -e "${YELLOW}格式: 主机端口:容器端口 (如 8080:80)${NC}"
    echo -e "${YELLOW}多个端口用逗号分隔 (如 80:80, 443:443)${NC}"
    echo -ne "端口映射 (直接回车跳过): "; read ports
    port_config=""
    if [[ -n "$ports" ]]; then
        IFS=',' read -ra PORT_ARRAY <<< "$ports"
        for port in "${PORT_ARRAY[@]}"; do
            port=$(echo "$port" | xargs)
            port_config+="      - \"$port\"\n"
        done
    fi
    
    echo ""
    echo "=== 第3步: 环境变量 ==="
    echo -e "${YELLOW}格式: KEY=VALUE (如 MYSQL_ROOT_PASSWORD=123456)${NC}"
    echo -e "${YELLOW}多个变量用逗号分隔${NC}"
    echo -ne "环境变量 (直接回车跳过): "; read envs
    env_config=""
    if [[ -n "$envs" ]]; then
        IFS=',' read -ra ENV_ARRAY <<< "$envs"
        for env in "${ENV_ARRAY[@]}"; do
            env=$(echo "$env" | xargs)
            env_config+="      - \"$env\"\n"
        done
    fi
    
    echo ""
    echo "=== 第4步: 卷挂载 ==="
    echo -e "${YELLOW}格式: 主机路径:容器路径 (如 /data:/app/data)${NC}"
    echo -e "${YELLOW}多个卷用逗号分隔${NC}"
    echo -ne "卷挂载 (直接回车跳过): "; read volumes
    volume_config=""
    if [[ -n "$volumes" ]]; then
        IFS=',' read -ra VOL_ARRAY <<< "$volumes"
        for vol in "${VOL_ARRAY[@]}"; do
            vol=$(echo "$vol" | xargs)
            volume_config+="      - $vol\n"
        done
    fi
    
    echo ""
    echo "=== 第5步: 重启策略 ==="
    echo -e "  ${GREEN}[1]${NC} always (推荐，容器自动重启)"
    echo -e "  ${GREEN}[2]${NC} on-failure (失败时重启)"
    echo -e "  ${GREEN}[3]${NC} unless-stopped (除非手动停止)"
    echo -ne "选择重启策略 [1]: "; read restart_choice
    restart_choice=${restart_choice:-1}
    case "$restart_choice" in
        1) restart_policy="always" ;;
        2) restart_policy="on-failure" ;;
        3) restart_policy="unless-stopped" ;;
        *) restart_policy="always" ;;
    esac
    
    echo ""
    echo "=== 确认配置 ==="
    echo -e "${YELLOW}服务名称:${NC} $service_name"
    echo -e "${YELLOW}镜像:${NC} $image"
    echo -e "${YELLOW}端口:${NC} ${ports:-无}"
    echo -e "${YELLOW}环境变量:${NC} ${envs:-无}"
    echo -e "${YELLOW}卷挂载:${NC} ${volumes:-无}"
    echo -e "${YELLOW}重启策略:${NC} $restart_policy"
    echo ""
    echo -ne "确认部署? (y/N): "; read confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "已取消"
        pause_func
        return
    fi
    
    COMPOSE_FILE="services:
  $service_name:
    image: $image
    container_name: $service_name
    restart: $restart_policy"
    
    if [[ -n "$port_config" ]]; then
        COMPOSE_FILE+="
    ports:"
        COMPOSE_FILE+=$'\n'"$port_config"
    fi
    
    if [[ -n "$env_config" ]]; then
        COMPOSE_FILE+="
    environment:"
        COMPOSE_FILE+=$'\n'"$env_config"
    fi
    
    if [[ -n "$volume_config" ]]; then
        COMPOSE_FILE+="
    volumes:"
        COMPOSE_FILE+=$'\n'"$volume_config"
    fi
    
    echo ""
    echo "=== 生成 docker-compose.yml ==="
    echo "$COMPOSE_FILE"
    echo ""
    
    echo "正在部署到 LXC $lxc_id ..."
    echo "$COMPOSE_FILE" | pct exec "$lxc_id" -- bash -c 'cat > /tmp/docker-compose.yml'
    
    COMPOSE_CMD=$(get_compose_cmd "$lxc_id")
    if [[ -z "$COMPOSE_CMD" ]]; then
        echo -e "${RED}Docker Compose 未安装${NC}"
        pause_func
        return
    fi
    
    if pct exec "$lxc_id" -- bash -c "cd /tmp && $COMPOSE_CMD -f /tmp/docker-compose.yml up -d" 2>&1; then
        echo ""
        echo -e "${GREEN}部署完成!${NC}"
        echo -e "查看容器状态: ${CYAN}pct exec $lxc_id -- docker ps${NC}"
        echo -e "查看日志: ${CYAN}pct exec $lxc_id -- docker logs $service_name${NC}"
    else
        echo ""
        echo -e "${RED}部署失败，请检查配置是否正确${NC}"
    fi
    
    pause_func
}

docker_deploy_template() {
    clear
    echo -e "${BLUE}═══ 模板部署 ═══${NC}"
    echo -e "${YELLOW}选择要部署的模板:${NC}"
    echo ""
    echo -e "  ${GREEN}[1]${NC} Nginx (Web服务器)"
    echo -e "  ${GREEN}[2]${NC} MySQL (数据库)"
    echo -e "  ${GREEN}[3]${NC} PostgreSQL (数据库)"
    echo -e "  ${GREEN}[4]${NC} Redis (缓存)"
    echo -e "  ${GREEN}[5]${NC} MongoDB (数据库)"
    echo -e "  ${GREEN}[6]${NC} Portainer (容器管理)"
    echo -e "  ${GREEN}[7]${NC} Nginx Proxy Manager (反向代理)"
    echo -e "  ${GREEN}[8]${NC} WordPress (博客)"
    echo -e "  ${GREEN}[9]${NC} Uptime Kuma (监控)"
        echo -e "  ${GREEN}[0]${NC} 返回"
        echo -e "${YELLOW}💡 提示: 请先创建 LXC 容器，或使用已有容器${NC}"
        echo -ne "${CYAN}选择: ${NC}"
    read t
    echo
    
    case "$t" in
        1) TEMPLATE="nginx" ;;
        2) TEMPLATE="mysql" ;;
        3) TEMPLATE="postgresql" ;;
        4) TEMPLATE="redis" ;;
        5) TEMPLATE="mongodb" ;;
        6) TEMPLATE="portainer" ;;
        7) TEMPLATE="npm" ;;
        8) TEMPLATE="wordpress" ;;
        9) TEMPLATE="uptimekuma" ;;
        0) return ;;
        *) echo "无效选择"; pause_func; return ;;
    esac
    
    pct list
    echo ""
    echo -ne "选择 LXC 容器 ID: "; read lxc_id
    
    if [[ -z "$lxc_id" ]]; then
        echo -e "${RED}错误: 请输入容器 ID${NC}"
        pause_func
        return
    fi
    
    if ! pct status "$lxc_id" | grep -q "running"; then
        echo -e "${RED}错误: 容器 $lxc_id 未运行，请先启动${NC}"
        pause_func
        return
    fi
    
    echo ""
    if ! check_and_install_docker "$lxc_id"; then
        echo -e "${RED}Docker 环境检查失败，无法继续部署${NC}"
        pause_func
        return
    fi
    
    echo ""
    
    case "$TEMPLATE" in
        nginx)
            COMPOSE_FILE="services:
  nginx:
    image: nginx:latest
    container_name: nginx-web
    restart: always
    ports:
      - \"80:80\"
      - \"443:443\"
    volumes:
      - nginx-data:/etc/nginx"
            ;;
        mysql)
            echo -ne "设置 MySQL root 密码: "; read -s mysql_pwd
            echo
            COMPOSE_FILE="services:
  mysql:
    image: mysql:8
    container_name: mysql-db
    restart: always
    ports:
      - \"3306:3306\"
    environment:
      - MYSQL_ROOT_PASSWORD=$mysql_pwd
    volumes:
      - mysql-data:/var/lib/mysql"
            ;;
        postgresql)
            echo -ne "设置 PostgreSQL 密码: "; read -s pg_pwd
            echo
            COMPOSE_FILE="services:
  postgresql:
    image: postgres:16
    container_name: postgresql-db
    restart: always
    ports:
      - \"5432:5432\"
    environment:
      - POSTGRES_PASSWORD=$pg_pwd
    volumes:
      - postgresql-data:/var/lib/postgresql/data"
            ;;
        redis)
            COMPOSE_FILE="services:
  redis:
    image: redis:alpine
    container_name: redis-cache
    restart: always
    ports:
      - \"6379:6379\"
    volumes:
      - redis-data:/data"
            ;;
        mongodb)
            echo -ne "设置 MongoDB 用户名: "; read mongo_user
            echo -ne "设置 MongoDB 密码: "; read -s mongo_pwd
            echo
            COMPOSE_FILE="services:
  mongodb:
    image: mongo:7
    container_name: mongodb
    restart: always
    ports:
      - \"27017:27017\"
    environment:
      - MONGO_INITDB_ROOT_USERNAME=$mongo_user
      - MONGO_INITDB_ROOT_PASSWORD=$mongo_pwd
    volumes:
      - mongodb-data:/data/db"
            ;;
        portainer)
            COMPOSE_FILE="services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: always
    ports:
      - \"9000:9000\"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer-data:/data"
            ;;
        npm)
            COMPOSE_FILE="services:
  npm:
    image: jc21/nginx-proxy-manager:latest
    container_name: npm
    restart: always
    ports:
      - \"80:80\"
      - \"443:443\"
      - \"81:81\"
    volumes:
      - npm-data:/data
      - npm-letsencrypt:/etc/letsencrypt
    environment:
      - DB_SQLITE_FILE=/data/database.db"
            ;;
        wordpress)
            echo -ne "设置 WordPress 数据库密码: "; read -s wp_db_pwd
            echo
            COMPOSE_FILE="services:
  wordpress:
    image: wordpress:latest
    container_name: wordpress
    restart: always
    ports:
      - \"8080:80\"
    environment:
      - WORDPRESS_DB_HOST=db
      - WORDPRESS_DB_USER=wordpress
      - WORDPRESS_DB_PASSWORD=$wp_db_pwd
      - WORDPRESS_DB_NAME=wordpress
    volumes:
      - wordpress-data:/var/www/html
  db:
    image: mysql:8
    container_name: wordpress-db
    restart: always
    environment:
      - MYSQL_ROOT_PASSWORD=$wp_db_pwd
      - MYSQL_DATABASE=wordpress
      - MYSQL_USER=wordpress
      - MYSQL_PASSWORD=$wp_db_pwd
    volumes:
      - mysql-wordpress-data:/var/lib/mysql"
            ;;
        uptimekuma)
            COMPOSE_FILE="services:
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    restart: always
    ports:
      - \"3001:3001\"
    volumes:
      - uptimekuma-data:/app/data"
            ;;
    esac
    
    echo ""
    echo "=== 部署模板: $TEMPLATE ==="
    echo "$COMPOSE_FILE"
    echo ""
    echo -ne "确认部署? (y/N): "; read confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "已取消"
        pause_func
        return
    fi
    
    echo "正在部署..."
    echo "$COMPOSE_FILE" | pct exec "$lxc_id" -- bash -c 'cat > /tmp/docker-compose.yml'
    
    COMPOSE_CMD=$(get_compose_cmd "$lxc_id")
    if [[ -z "$COMPOSE_CMD" ]]; then
        echo -e "${RED}Docker Compose 未安装${NC}"
        pause_func
        return
    fi
    
    if pct exec "$lxc_id" -- bash -c "cd /tmp && $COMPOSE_CMD -f /tmp/docker-compose.yml up -d" 2>&1; then
        echo ""
        echo -e "${GREEN}部署完成!${NC}"
        echo -e "查看容器: ${CYAN}pct exec $lxc_id -- docker ps${NC}"
    else
        echo ""
        echo -e "${RED}部署失败，请检查配置是否正确${NC}"
    fi
    
    pause_func
}

# 自定义 docker-compose 部署
docker_deploy_custom() {
    clear
    echo -e "${BLUE}═══ 自定义部署 ═══${NC}"
    echo -e "${YELLOW}请输入您准备好的 docker-compose.yml 内容${NC}"
    echo ""
    
    pct list
    echo ""
    echo -ne "选择 LXC 容器 ID: "; read lxc_id
    
    if [[ -z "$lxc_id" ]]; then
        echo -e "${RED}错误: 请输入容器 ID${NC}"
        pause_func
        return
    fi
    
    if ! pct status "$lxc_id" | grep -q "running"; then
        echo -e "${RED}错误: 容器 $lxc_id 未运行，请先启动${NC}"
        pause_func
        return
    fi
    
    echo ""
    if ! check_and_install_docker "$lxc_id"; then
        echo -e "${RED}Docker 环境检查失败，无法继续部署${NC}"
        pause_func
        return
    fi
    
    echo ""
    echo "=== 输入 docker-compose.yml 内容 ==="
    echo -e "${YELLOW}请粘贴 docker-compose.yml 内容（完成后按 Ctrl+D）:${NC}"
    echo ""
    
    COMPOSE_CONTENT=$(cat)
    
    if [[ -z "$COMPOSE_CONTENT" ]]; then
        echo -e "${RED}错误: docker-compose.yml 内容不能为空${NC}"
        pause_func
        return
    fi
    
    echo ""
    echo "=== 预览配置 ==="
    echo "$COMPOSE_CONTENT"
    echo ""
    echo -ne "确认部署? (y/N): "; read confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "已取消"
        pause_func
        return
    fi
    
    echo ""
    echo "=== 部署中 ==="
    echo "$COMPOSE_CONTENT" | pct exec "$lxc_id" -- bash -c 'cat > /tmp/docker-compose.yml'
    
    COMPOSE_CMD=$(get_compose_cmd "$lxc_id")
    if [[ -z "$COMPOSE_CMD" ]]; then
        echo -e "${RED}Docker Compose 未安装${NC}"
        pause_func
        return
    fi
    
    pct exec "$lxc_id" -- bash -c "cd /tmp && $COMPOSE_CMD -f /tmp/docker-compose.yml up -d"
    
    if [[ $? -eq 0 ]]; then
        echo ""
        echo -e "${GREEN}部署完成!${NC}"
        echo -e "查看容器: ${CYAN}pct exec $lxc_id -- docker ps${NC}"
        echo -e "查看日志: ${CYAN}pct exec $lxc_id -- $COMPOSE_CMD -f /tmp/docker-compose.yml logs${NC}"
    else
        echo -e "${RED}部署失败，请检查配置是否正确${NC}"
    fi
    
    pause_func
}

# 系统管理
system_menu() {
    while true; do
        clear
        echo -e "${BLUE}════════ 系统管理 ════════${NC}"
        echo -e "  ${GREEN}[1]${NC} 系统状态"
        echo -e "  ${GREEN}[2]${NC} 系统更新"
        echo -e "  ${GREEN}[3]${NC} 清理系统"
        echo -e "  ${GREEN}[4]${NC} 网络信息"
        echo -e "  ${GREEN}[5]${NC} 存储信息"
        echo -e "  ${GREEN}[6]${NC} 内核管理"
        echo -e "  ${GREEN}[7]${NC} 系统日志"
        echo -e "  ${GREEN}[8]${NC} 修复 Docker 源"
        echo -e "  ${GREEN}[9]${NC} 屏蔽订阅提示"
        echo -e "  ${GREEN}[0]${NC} 返回"
        echo -ne "${CYAN}选择: ${NC}"
        read c
        echo
        
        case "$c" in
            1)
                echo -e "${BLUE}=== 系统状态 ===${NC}"
                echo "主机: $(hostname) | PVE: $(pveversion | grep -oP 'pve-manager/\K[0-9.]+')"
                echo "内核: $(uname -r)"
                echo "CPU: $(nproc) 核 | 内存: $(free -h | awk 'NR==2{print $3"/"$2}')"
                echo "磁盘: $(df -h / | awk 'NR==2{print $3"/"$2"("$5")"}')"
                echo "运行中: VM $(qm list 2>/dev/null | grep running | wc -l) | LXC $(pct list 2>/dev/null | grep running | wc -l)"
                pause_func
                ;;
            2)
                echo "更新系统..."
                apt update && apt upgrade -y
                pause_func
                ;;
            3)
                clear
                echo -e "${BLUE}═══ 系统清理 ═══${NC}"
                echo -e "${YELLOW}清理项目:${NC}"
                echo -e "  ${GREEN}[1]${NC} 清理 apt 缓存"
                echo -e "  ${GREEN}[2]${NC} 清理旧内核"
                echo -e "  ${GREEN}[3]${NC} 清理临时文件"
                echo -e "  ${GREEN}[4]${NC} 完整清理 (全部执行)"
                echo -e "  ${GREEN}[0]${NC} 返回"
                echo -ne "${CYAN}选择: ${NC}"
                read choice
                echo
                
                case "$choice" in
                    1)
                        echo -e "${YELLOW}清理 apt 缓存...${NC}"
                        apt clean && apt autoclean
                        echo -e "${GREEN}apt 缓存已清理${NC}"
                        ;;
                    2)
                        echo -e "${YELLOW}清理旧内核...${NC}"
                        apt autoremove -y --purge 'pve-kernel-*' 'linux-image-*' 2>/dev/null
                        update-grub 2>/dev/null
                        echo -e "${GREEN}旧内核已清理${NC}"
                        ;;
                    3)
                        echo -e "${YELLOW}清理临时文件...${NC}"
                        rm -rf /tmp/* 2>/dev/null
                        echo -e "${GREEN}临时文件已清理${NC}"
                        ;;
                    4)
                        echo -e "${YELLOW}执行完整清理...${NC}"
                        apt clean && apt autoclean
                        apt autoremove -y
                        rm -rf /tmp/* 2>/dev/null
                        echo -e "${GREEN}系统清理完成${NC}"
                        ;;
                    0)
                        ;;
                    *)
                        echo -e "${RED}无效选择${NC}"
                        ;;
                esac
                pause_func
                ;;
            4)
                echo -e "${BLUE}=== 网络信息 ===${NC}"
                echo -e "${YELLOW}网络接口:${NC}"
                ip -br addr
                echo -e "${YELLOW}网桥:${NC}"
                brctl show 2>/dev/null || bridge link show
                echo -e "${YELLOW}路由:${NC}"
                ip route
                echo -e "${YELLOW}DNS:${NC}"
                cat /etc/resolv.conf
                pause_func
                ;;
            5)
                echo -e "${BLUE}=== 存储信息 ===${NC}"
                pvesm status
                echo ""
                echo -e "${YELLOW}存储使用详情:${NC}"
                df -h | grep -E "(Filesystem|/dev/)"
                pause_func
                ;;
            6)
                kernel_management
                ;;
            7)
                echo -e "${BLUE}=== 系统日志 ===${NC}"
                echo -e "${YELLOW}[1]${NC} 系统日志 (syslog)"
                echo -e "${YELLOW}[2]${NC} PVE 日志"
                echo -e "${YELLOW}[3]${NC} 内核日志 (dmesg)"
                echo -ne "选择: "; read log_type
                case "$log_type" in
                    1) tail -100 /var/log/syslog ;;
                    2) tail -100 /var/log/pve/tasks/index ;;
                    3) dmesg | tail -100 ;;
                esac
                pause_func
                ;;
            8)
                fix_docker_source
                ;;
            9)
               屏蔽_subscription_notice
                ;;
            0) break ;;
        esac
    done
}

# 屏蔽订阅提示
屏蔽_subscription_notice() {
    local js_file="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
    local backup_file="$js_file.bak"
    
    while true; do
        clear
        echo -e "${BLUE}═══ 屏蔽订阅提示 ═══${NC}"
        echo ""
        
        if [[ -f "$backup_file" ]]; then
            echo -e "${GREEN}当前状态: 已屏蔽${NC}"
        else
            echo -e "${YELLOW}当前状态: 未屏蔽${NC}"
        fi
        echo ""
        echo -e "${CYAN}[1]${NC} 屏蔽订阅提示"
        echo -e "${CYAN}[2]${NC} 恢复订阅提示"
        echo -e "${CYAN}[0]${NC} 返回"
        echo -ne "${CYAN}选择: ${NC}"
        read choice
        echo
        
        case "$choice" in
            1)
                if [[ -f "$backup_file" ]]; then
                    echo -e "${YELLOW}订阅提示已经被屏蔽${NC}"
                else
                    echo -e "${YELLOW}正在屏蔽订阅提示...${NC}"
                    if [[ ! -f "$js_file" ]]; then
                        echo -e "${RED}错误: 文件不存在 $js_file${NC}"
                        pause_func
                        continue
                    fi
                    cp "$js_file" "$backup_file"
                    
                    if grep -q "res.data.status.toLowerCase() !== 'active'" "$js_file"; then
                        sed -i "s/res.data.status.toLowerCase() !== 'active'/res.data.status.toLowerCase() === 'active'/g" "$js_file"
                        systemctl restart pveproxy.service
                        echo -e "${GREEN}已屏蔽订阅提示（策略A）${NC}"
                        echo -e "${YELLOW}请刷新浏览器或重新登录 PVE Web${NC}"
                    elif grep -q "Ext.Msg.show({" "$js_file"; then
                        perl -i -0777 -pe "s/(Ext\.Msg\.show\(\{\s+title: gettext\('No valid sub)/void\(\{ \/\/\1/g" "$js_file"
                        systemctl restart pveproxy.service
                        echo -e "${GREEN}已屏蔽订阅提示（策略B）${NC}"
                        echo -e "${YELLOW}请刷新浏览器或重新登录 PVE Web${NC}"
                    else
                        echo -e "${RED}未找到订阅检查代码，PVE 版本可能已更新${NC}"
                        rm -f "$backup_file"
                    fi
                fi
                pause_func
                ;;
            2)
                if [[ -f "$backup_file" ]]; then
                    echo -e "${YELLOW}正在恢复订阅提示...${NC}"
                    mv "$backup_file" "$js_file"
                    systemctl restart pveproxy.service
                    echo -e "${GREEN}已恢复订阅提示${NC}"
                else
                    echo -e "${YELLOW}订阅提示未被屏蔽（无备份文件）${NC}"
                fi
                pause_func
                ;;
            0)
                return ;;
            *)
                echo -e "${RED}无效选择${NC}"
                ;;
        esac
    done
}

# 内核管理
kernel_management() {
    while true; do
        clear
        echo -e "${BLUE}════════ 内核管理 ════════${NC}"
        echo -e "${YELLOW}当前内核:${NC} $(uname -r)"
        echo ""
        echo -e "${YELLOW}已安装内核:${NC}"
        dpkg -l 2>/dev/null | grep -E "pve-kernel|proxmox-kernel" | awk '{printf "  %s (%s)\n", $2, $3}' || echo "  无"
        echo ""
        echo -e "${GREEN}[1]${NC} 查看可用内核"
        echo -e "${GREEN}[2]${NC} 安装新内核"
        echo -e "${GREEN}[3]${NC} 设置默认启动内核"
        echo -e "${GREEN}[4]${NC} 清理旧内核"
        echo -e "${GREEN}[0]${NC} 返回"
        echo -ne "${CYAN}选择: ${NC}"
        read k
        echo
        
        case "$k" in
            1)
                echo -e "${YELLOW}正在获取可用内核列表...${NC}"
                local kernel_url="https://mirrors.tuna.tsinghua.edu.cn/proxmox/debian/pve/dists/trixie/pve-no-subscription/binary-amd64/Packages"
                local kernels=$(curl -s "$kernel_url" 2>/dev/null | grep -E '^Package: (pve-kernel|proxmox-kernel)' | awk '{print $2}' | sort -V | tail -10)
                if [[ -n "$kernels" ]]; then
                    echo -e "${CYAN}可用内核 (最近10个):${NC}"
                    echo "$kernels" | while read line; do echo -e "  ${GREEN}•${NC} $line"; done
                else
                    echo -e "${RED}获取失败，请检查网络${NC}"
                fi
                ;;
            2)
                read -p "请输入内核版本 (如 6.8.8-2-pve): " kernel_ver
                if [[ -n "$kernel_ver" ]]; then
                    if [[ ! "$kernel_ver" =~ ^proxmox-kernel ]]; then
                        kernel_ver="proxmox-kernel-$kernel_ver"
                    fi
                    echo -e "${YELLOW}正在安装 $kernel_ver...${NC}"
                    apt update
                    if apt install -y "$kernel_ver"; then
                        echo -e "${GREEN}安装成功${NC}"
                        update-grub
                        echo -e "${YELLOW}建议重启系统应用新内核${NC}"
                    else
                        echo -e "${RED}安装失败${NC}"
                    fi
                fi
                ;;
            3)
                read -p "请输入默认内核版本 (如 6.8.8-2-pve): " kernel_ver
                if [[ -n "$kernel_ver" ]]; then
                    if grub-set-default "Advanced options for Proxmox VE>Proxmox VE, with Linux $kernel_ver" 2>/dev/null; then
                        echo -e "${GREEN}设置成功${NC}"
                        update-grub
                    else
                        echo -e "${RED}设置失败，请检查内核版本${NC}"
                    fi
                fi
                ;;
            4)
                echo -e "${YELLOW}清理旧内核 (保留当前内核)...${NC}"
                apt autoremove -y --purge 'pve-kernel-*' 'proxmox-kernel-*' 2>/dev/null
                update-grub
                echo -e "${GREEN}清理完成${NC}"
                ;;
            0) return ;;
            *) ;;
        esac
        pause_func
    done
}

fix_docker_source() {
    clear
    echo -e "${BLUE}═══ 修复 Docker 源 ═══${NC}"
    echo -e "${YELLOW}此功能用于修复 Docker CE 源错误${NC}"
    echo -e "${YELLOW}常见问题: 阿里云 Docker 源不支持 Debian 13 (Trixie)${NC}"
    echo ""
    echo -e "${YELLOW}当前 Docker 源配置:${NC}"
    ls -la /etc/apt/sources.list.d/ | grep -i docker 2>/dev/null || echo "无 Docker 源配置"
    echo ""
    echo -e "${CYAN}[1]${NC} 移除 Docker CE 源 (使用系统自带 docker.io)"
    echo -e "${CYAN}[2]${NC} Docker 官方源 (国外)"
    echo -e "${CYAN}[3]${NC} 中科大 Docker 源 (推荐国内)"
    echo -e "${CYAN}[4]${NC} 阿里云 Docker 源"
    echo -e "${CYAN}[5]${NC} 清华 Docker 源"
    echo -e "${CYAN}[0]${NC} 返回"
    echo -ne "${CYAN}选择: ${NC}"
    read fix_choice
    echo
    
    case "$fix_choice" in
        1)
            echo -e "${YELLOW}移除 Docker CE 源...${NC}"
            rm -f /etc/apt/sources.list.d/docker*.list 2>/dev/null
            rm -f /etc/apt/sources.list.d/*.docker* 2>/dev/null
            rm -f /etc/apt/keyrings/docker.gpg 2>/dev/null
            echo -e "${GREEN}已移除 Docker CE 源${NC}"
            echo -e "${GREEN}现在可以使用系统自带的 docker.io${NC}"
            apt update
            pause_func
            ;;
        2)
            echo -e "${YELLOW}添加 Docker 官方源...${NC}"
            apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
            mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian trixie stable" > /etc/apt/sources.list.d/docker.list
            echo -e "${GREEN}Docker 官方源添加完成${NC}"
            apt update
            pause_func
            ;;
        3)
            echo -e "${YELLOW}添加中科大 Docker 源...${NC}"
            apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
            mkdir -p /etc/apt/keyrings
            curl -fsSL https://mirrors.ustc.edu.cn/docker-ce/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.ustc.edu.cn/docker-ce/linux/debian trixie stable" > /etc/apt/sources.list.d/docker.list
            echo -e "${GREEN}中科大 Docker 源添加完成${NC}"
            apt update
            pause_func
            ;;
        4)
            echo -e "${YELLOW}添加阿里云 Docker 源...${NC}"
            apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
            mkdir -p /etc/apt/keyrings
            curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/debian trixie stable" > /etc/apt/sources.list.d/docker.list
            echo -e "${GREEN}阿里云 Docker 源添加完成${NC}"
            apt update
            pause_func
            ;;
        5)
            echo -e "${YELLOW}添加清华 Docker 源...${NC}"
            apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
            mkdir -p /etc/apt/keyrings
            curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian trixie stable" > /etc/apt/sources.list.d/docker.list
            echo -e "${GREEN}清华 Docker 源添加完成${NC}"
            apt update
            pause_func
            ;;
        *)
            return ;;
    esac
}

# 换源
change_source() {
    block_non_pve9 "更换软件源" || return 1
    
    if ! ping -c 1 mirrors.tuna.tsinghua.edu.cn &> /dev/null 2>&1; then
        echo -e "${RED}网络连接失败，请检查网络${NC}"
        pause_func
        return 1
    fi
    
    while true; do
        clear
        echo -e "${BLUE}════════ 换源工具 ════════${NC}"
        echo -e "  ${GREEN}[1]${NC} 中科大源 (推荐)"
        echo -e "  ${GREEN}[2]${NC} 清华源"
        echo -e "  ${GREEN}[3]${NC} 阿里云源"
        echo -e "  ${GREEN}[4]${NC} 华为云源"
        echo -e "  ${GREEN}[0]${NC} 返回"
        echo -ne "${CYAN}选择: ${NC}"
        read c
        echo
        
        case "$c" in
            1) 
                DEBIAN_MIRROR="https://mirrors.ustc.edu.cn/debian"
                PVE_MIRROR="https://mirrors.ustc.edu.cn/proxmox/debian/pve"
                CT_MIRROR="https://mirrors.ustc.edu.cn/proxmox"
                ;;
            2) 
                DEBIAN_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/debian"
                PVE_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/proxmox/debian/pve"
                CT_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/proxmox"
                ;;
            3) 
                DEBIAN_MIRROR="https://mirrors.aliyun.com/debian"
                PVE_MIRROR="https://mirrors.aliyun.com/proxmox/debian/pve"
                CT_MIRROR="https://mirrors.aliyun.com/proxmox"
                ;;
            4) 
                DEBIAN_MIRROR="https://mirrors.huaweicloud.com/debian"
                PVE_MIRROR="https://mirrors.huaweicloud.com/proxmox/debian/pve"
                CT_MIRROR="https://mirrors.huaweicloud.com/proxmox"
                ;;
            0) break ;;
            *) continue ;;
        esac
        
        echo -e "${YELLOW}安全更新源选择:${NC}"
        echo -e "  [1] 使用镜像站安全源 (速度快)"
        echo -e "  [2] 使用官方安全源 (更新及时)"
        read -p "请选择 [1-2] (默认: 1): " sec_choice
        sec_choice=${sec_choice:-1}
        
        if [[ "$sec_choice" == "2" ]]; then
            SECURITY_MIRROR="https://security.debian.org/debian-security"
        else
            SECURITY_MIRROR="${DEBIAN_MIRROR/debian/debian-security}"
        fi
        
        echo -e "${YELLOW}确认换源? (y/N)${NC}"
        read confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && continue
        
        echo -e "${YELLOW}正在换源，请稍候...${NC}"
        
        backup_file "/etc/apt/sources.list.d/debian.sources"
        [[ -f "/etc/apt/sources.list.d/pve-enterprise.sources" ]] && backup_file "/etc/apt/sources.list.d/pve-enterprise.sources"
        
        cat > /etc/apt/sources.list.d/debian.sources << EOF
Types: deb
URIs: $DEBIAN_MIRROR
Suites: trixie trixie-updates trixie-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: $SECURITY_MIRROR
Suites: trixie-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
        
        if [[ -f "/etc/apt/sources.list.d/pve-enterprise.sources" ]]; then
            sed -i 's/^Types:/#Types:/g' /etc/apt/sources.list.d/pve-enterprise.sources
            sed -i 's/^URIs:/#URIs:/g' /etc/apt/sources.list.d/pve-enterprise.sources
        fi
        
        cat > /etc/apt/sources.list.d/pve-no-subscription.sources << EOF
Types: deb
URIs: $PVE_MIRROR
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
        
        if [[ -f "/usr/share/perl5/PVE/APLInfo.pm" ]]; then
            backup_file "/usr/share/perl5/PVE/APLInfo.pm"
            sed -i "s|https://mirrors.ustc.edu.cn/proxmox|http://download.proxmox.com|g" /usr/share/perl5/PVE/APLInfo.pm
            sed -i "s|https://mirrors.tuna.tsinghua.edu.cn/proxmox|http://download.proxmox.com|g" /usr/share/perl5/PVE/APLInfo.pm
            sed -i "s|https://mirrors.aliyun.com/proxmox|http://download.proxmox.com|g" /usr/share/perl5/PVE/APLInfo.pm
            sed -i "s|https://mirrors.huaweicloud.com/proxmox|http://download.proxmox.com|g" /usr/share/perl5/PVE/APLInfo.pm
            sed -i "s|http://download.proxmox.com|$CT_MIRROR|g" /usr/share/perl5/PVE/APLInfo.pm
        fi
        
        echo -e "${GREEN}换源完成${NC}"
        echo -e "${YELLOW}已更换: Debian源 / PVE源 / CT模板源${NC}"
        apt update
        pause_func
    done
}

# 主循环
main() {
    echo -e "${GREEN}PVE Toolkit $VERSION 加载完成${NC}"
    echo -e "${GREEN}PVE 版本检查通过${NC}"
    sleep 1
    
    while true; do
        show_menu
        echo -ne "${CYAN}选择 [0-3]: ${NC}"
        read choice
        echo
        
        case "$choice" in
            1) system_menu ;;
            2) lxc_menu ;;
            3) change_source ;;
            0) echo "再见"; exit 0 ;;
        esac
    done
}

main "$@"