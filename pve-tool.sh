#!/bin/bash
#
# PVE Toolkit - Proxmox VE 管理工具集
# 使用: curl -sL https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/pve-tool.sh -o /tmp/pve.sh && bash /tmp/pve.sh

# 读取本地版本
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
    VERSION=$(cat "$SCRIPT_DIR/VERSION")
else
    VERSION="V0.8.0"
fi

# 查询 GitHub 最新版本（支持国内镜像加速）
get_latest_version() {
    local latest
    local api_urls=(
        "https://ghproxy.net/https://api.github.com/repos/MuskCheng/pve-toolkit/releases/latest"
        "https://mirror.ghproxy.com/https://api.github.com/repos/MuskCheng/pve-toolkit/releases/latest"
        "https://api.github.com/repos/MuskCheng/pve-toolkit/releases/latest"
    )
    
    for url in "${api_urls[@]}"; do
        latest=$(curl -sSL --connect-timeout 5 "$url" 2>/dev/null | grep -oP '"tag_name":\s*"\K[^"]+' || echo "")
        if [[ -n "$latest" ]]; then
            echo "$latest"
            return
        fi
    done
    echo ""
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
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
WHITE=$'\033[1;37m'
BOLD=$'\033[1m'
NC=$'\033[0m'

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
    
    # 版本比较并显示提示
    local current_ver=${VERSION#V}
    local latest_ver=${LATEST_VERSION#V}
    if [[ "$LATEST_VERSION" != "$VERSION" ]] && [[ "$latest_ver" > "$current_ver" ]] 2>/dev/null; then
        echo -e "${RED}⚠️  有新版本可用！当前: ${VERSION} → 最新: ${LATEST_VERSION}${NC}"
        echo -e "${YELLOW}   运行 git pull 或重新下载脚本以更新${NC}"
    else
        echo -e "${CYAN}当前版本: ${VERSION} (已是最新)${NC}"
    fi
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

# 显示容器列表（增强版）
show_lxc_list() {
    clear
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                          LXC 容器列表${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════${NC}"
    printf " %-5s %-20s %-6s %-6s %-15s\n" "VMID" "名称" "状态" "特权容器" "IP地址"
    echo -e "${BLUE}────────────────────────────────────────────────────────${NC}"
    
    local containers=$(pct list 2>/dev/null | tail -n +2)
    if [[ -z "$containers" ]]; then
        echo -e "${YELLOW}  无容器${NC}"
        echo -e "${BLUE}══════════════════════════════════════════════════════════════════════${NC}"
        return
    fi
    
    while IFS= read -r line; do
        local vmid=$(echo "$line" | awk '{print $1}')
        local status=$(echo "$line" | awk '{print $2}')
        local name=$(echo "$line" | awk '{print $NF}')
        
        local unprivileged=$(pct config "$vmid" 2>/dev/null | grep "^unprivileged:" | awk '{print $2}')
        
        local ip_addr="-"
        if [[ "$status" == "running" ]]; then
            local raw_ip=$(pct exec "$vmid" -- ip -4 addr show 2>/dev/null | grep -v '127\.' | grep -oP 'inet \K[0-9.]+' | head -1)
            if [[ -n "$raw_ip" && "$raw_ip" =~ ^([0-9.]+)/[0-9]+$ ]]; then
                ip_addr="${BASH_REMATCH[1]}"
            elif [[ -n "$raw_ip" && "$raw_ip" =~ ^[0-9.]+$ ]]; then
                ip_addr="$raw_ip"
            else
                ip_addr="-"
            fi
        fi
        
        local status_text status_color
        case "$status" in
            running) status_text="运行"; status_color="${GREEN}" ;;
            stopped) status_text="停止"; status_color="${RED}" ;;
            *) status_text="$status"; status_color="${YELLOW}" ;;
        esac
        
        local priv_text priv_color
        if [[ "$unprivileged" == "1" ]]; then
            priv_text="否"
            priv_color="${GREEN}"
        else
            priv_text="是"
            priv_color="${RED}"
        fi
        
        printf "${WHITE}%-5s${NC} ${WHITE}%-20s${NC} ${status_color}%-6s${NC} ${priv_color}%-6s${NC} ${WHITE}%-15s${NC}\n" \
            "$vmid" "$name" "$status_text" "$priv_text" "$ip_addr"
    done <<< "$containers"
    
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════${NC}"
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
        echo -e "  ${GREEN}[0]${NC} 返回"
        echo -ne "${CYAN}选择: ${NC}"
        read c
        echo
        
        case "$c" in
            1) show_lxc_list; pause_func ;;
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
        echo -e "${YELLOW}安装 Docker (使用国内镜像源)...${NC}"
        
        echo -e "${YELLOW}配置 Docker CE 镜像源...${NC}"
        echo -e "${YELLOW}安装必要工具 (gnupg, curl)...${NC}"
        pct exec "$lxc_id" -- bash -lc 'apt update && apt install -y gnupg curl' 2>&1 || true
        
        if pct exec "$lxc_id" -- bash -lc 'mkdir -p /etc/apt/keyrings' 2>&1 && \
           pct exec "$lxc_id" -- bash -lc 'curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/debian/gpg 2>/dev/null | gpg --dearmor -o /etc/apt/keyrings/docker.gpg' 2>&1 && \
           pct exec "$lxc_id" -- bash -lc 'echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/debian trixie stable" > /etc/apt/sources.list.d/docker.list' 2>&1; then
            echo -e "${GREEN}镜像源配置成功，正在更新软件包缓存...${NC}"
            pct exec "$lxc_id" -- bash -lc 'apt-get update -o Acquire::Languages=none -o Acquire::Translation=none' 2>&1 || true
            
            echo -e "${GREEN}开始安装 Docker...${NC}"
            if pct exec "$lxc_id" -- bash -lc 'apt install -y --no-install-recommends docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin' 2>&1; then
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
            echo -e "${RED}Docker CE 安装失败，尝试安装 docker.io...${NC}"
            if pct exec "$lxc_id" -- bash -lc 'apt install -y --no-install-recommends docker.io' 2>&1; then
                pct exec "$lxc_id" -- bash -lc 'systemctl enable docker 2>/dev/null || true'
                pct exec "$lxc_id" -- bash -lc 'systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true'
                
                if pct exec "$lxc_id" -- bash -lc 'command -v docker &>/dev/null' 2>/dev/null || \
                   pct exec "$lxc_id" -- test -x /usr/bin/docker 2>/dev/null; then
                    echo -e "${GREEN}Docker (docker.io) 安装完成${NC}"
                    pct exec "$lxc_id" -- docker --version 2>/dev/null || true
                    DOCKER_AVAILABLE=1
                fi
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
        CURL_INSTALL_LOG=$(pct exec "$lxc_id" -- bash -lc 'apt install -y --no-install-recommends curl wget 2>&1' || true)
        
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
                if pct exec "$lxc_id" -- pip3 install -i https://pypi.tuna.tsinghua.edu.cn/simple docker-compose --break-system-packages 2>&1; then
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
                "https://mirrors.aliyun.com/docker-compose/${COMPOSE_VERSION}/docker-compose-Linux-x86_64"
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
                    if pct exec "$lxc_id" -- pip3 install -i https://pypi.tuna.tsinghua.edu.cn/simple docker-compose --break-system-packages 2>&1; then
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

# 安装 DPanel 面板
install_dpanel() {
    clear
    echo -e "${BLUE}════════ DPanel 面板安装 ════════${NC}"
    echo -e "${YELLOW}DPanel - Docker 可视化管理面板${NC}"
    echo ""
    
    pct list
    echo ""
    echo -ne "选择 LXC 容器 ID: "; read lxc_id
    
    if [[ -z "$lxc_id" ]]; then
        echo -e "${RED}错误: 请输入容器 ID${NC}"
        pause_func
        return
    fi
    
    # 检查容器是否存在
    if ! pct status "$lxc_id" &>/dev/null; then
        echo -e "${RED}错误: 容器 $lxc_id 不存在${NC}"
        pause_func
        return
    fi
    
    # 检查容器是否运行
    if ! pct status "$lxc_id" | grep -q "running"; then
        echo -e "${YELLOW}容器未运行，正在启动...${NC}"
        pct start "$lxc_id"
        sleep 3
    fi
    
    # 检查 Docker 环境
    echo ""
    echo -e "${YELLOW}检查 Docker 环境...${NC}"
    if ! pct exec "$lxc_id" -- bash -lc 'command -v docker &>/dev/null' 2>/dev/null && \
       ! pct exec "$lxc_id" -- test -x /usr/bin/docker 2>/dev/null; then
        echo ""
        echo -e "${RED}错误: 容器中未安装 Docker${NC}"
        echo -e "${YELLOW}请先使用「安装 Docker」功能安装 Docker 环境${NC}"
        pause_func
        return
    fi
    
    echo -e "${GREEN}Docker 环境已就绪${NC}"
    
    echo ""
    echo -e "${YELLOW}════════ 步骤 1/2: 配置镜像加速 ════════${NC}"
    
    # 配置 Docker 镜像加速
    local REGISTRY_MIRRORS="https://docker.1ms.run"
    echo -e "${CYAN}使用镜像源: ${GREEN}$REGISTRY_MIRRORS${NC}"
    
    pct exec "$lxc_id" -- bash -c "mkdir -p /etc/docker"
    pct exec "$lxc_id" -- bash -c "cat > /etc/docker/daemon.json << 'EOF'
{
  \"registry-mirrors\": [\"$REGISTRY_MIRRORS\"]
}
EOF"
    
    # 重启 Docker 服务使配置生效
    echo -e "${YELLOW}重启 Docker 服务...${NC}"
    pct exec "$lxc_id" -- bash -c 'systemctl daemon-reload && systemctl restart docker' 2>/dev/null || \
    pct exec "$lxc_id" -- bash -c 'service docker restart' 2>/dev/null || true
    
    sleep 2
    
    echo ""
    echo -e "${YELLOW}════════ 步骤 2/2: 安装 DPanel ════════${NC}"
    
    # 获取容器 IP 用于显示
    local container_ip=$(pct exec "$lxc_id" -- ip -4 addr show 2>/dev/null | grep -v '127\.' | grep -oP 'inet \K[0-9.]+' | head -1)
    
    echo ""
    echo -e "${YELLOW}选择 DPanel 版本:${NC}"
    echo -e "  ${GREEN}[1]${NC} Lite 版 (推荐，端口 8807)"
    echo -e "  ${GREEN}[2]${NC} 标准版 (需要 80/443 端口)"
    echo -ne "${CYAN}选择 [1]: ${NC}"
    read dpanel_ver
    dpanel_ver=${dpanel_ver:-1}
    
    echo ""
    
    case "$dpanel_ver" in
        1)
            echo -e "${YELLOW}正在安装 DPanel Lite 版...${NC}"
            pct exec "$lxc_id" -- docker run -d \
                --name dpanel \
                --restart=always \
                -p 8807:8080 \
                -e APP_NAME=dpanel \
                -v /var/run/docker.sock:/var/run/docker.sock \
                -v dpanel:/dpanel \
                dpanel/dpanel:lite
            ;;
        2)
            echo -e "${YELLOW}正在安装 DPanel 标准版...${NC}"
            pct exec "$lxc_id" -- docker run -d \
                --name dpanel \
                --restart=always \
                -p 80:80 -p 443:443 -p 8807:8080 \
                -e APP_NAME=dpanel \
                -v /var/run/docker.sock:/var/run/docker.sock \
                -v dpanel:/dpanel \
                dpanel/dpanel:latest
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            pause_func
            return
            ;;
    esac
    
    if [[ $? -eq 0 ]]; then
        echo ""
        echo -e "${GREEN}════════ 安装完成 ════════${NC}"
        echo ""
        echo -e "${GREEN}访问地址:${NC}"
        if [[ -n "$container_ip" ]]; then
            echo -e "  ${CYAN}http://${container_ip}:8807${NC}"
        else
            echo -e "  ${CYAN}http://<容器IP>:8807${NC}"
        fi
        echo ""
        echo -e "${YELLOW}默认账号: admin / admin${NC}"
        echo -e "${YELLOW}首次登录请修改密码${NC}"
    else
        echo -e "${RED}安装失败${NC}"
    fi
    
    pause_func
}

# 安装 Lucky 大吉
install_lucky() {
    clear
    echo -e "${BLUE}════════ Lucky 大吉安装 ════════${NC}"
    echo -e "${YELLOW}Lucky - IPv4/IPv6 端口转发/反向代理/动态域名/DDNS/证书管理${NC}"
    echo ""
    
    pct list
    echo ""
    echo -ne "选择 LXC 容器 ID: "; read lxc_id
    
    if [[ -z "$lxc_id" ]]; then
        echo -e "${RED}错误: 请输入容器 ID${NC}"
        pause_func
        return
    fi
    
    # 检查容器是否存在
    if ! pct status "$lxc_id" &>/dev/null; then
        echo -e "${RED}错误: 容器 $lxc_id 不存在${NC}"
        pause_func
        return
    fi
    
    # 检查容器是否运行
    if ! pct status "$lxc_id" | grep -q "running"; then
        echo -e "${YELLOW}容器未运行，正在启动...${NC}"
        pct start "$lxc_id"
        sleep 3
    fi
    
    # 检查 Docker 环境
    echo ""
    echo -e "${YELLOW}检查 Docker 环境...${NC}"
    if ! pct exec "$lxc_id" -- bash -lc 'command -v docker &>/dev/null' 2>/dev/null && \
       ! pct exec "$lxc_id" -- test -x /usr/bin/docker 2>/dev/null; then
        echo ""
        echo -e "${RED}错误: 容器中未安装 Docker${NC}"
        echo -e "${YELLOW}请先使用「安装 Docker」功能安装 Docker 环境${NC}"
        pause_func
        return
    fi
    
    echo -e "${GREEN}Docker 环境已就绪${NC}"
    
    # 获取容器 IP 用于显示
    local container_ip=$(pct exec "$lxc_id" -- ip -4 addr show 2>/dev/null | grep -v '127\.' | grep -oP 'inet \K[0-9.]+' | head -1)
    
    echo ""
    echo -e "${YELLOW}════════ 配置 Lucky ════════${NC}"
    
    # 默认配置
    local lucky_port="16601"
    local lucky_conf_dir="/opt/lucky/conf"
    
    echo -e "${YELLOW}选择网络模式:${NC}"
    echo -e "  ${GREEN}[1]${NC} Host 模式 (推荐，支持 IPv4/IPv6)"
    echo -e "      端口可在 Lucky 后台设置页面修改"
    echo -e "  ${GREEN}[2]${NC} Bridge 模式 (仅 IPv4，可能出现端口无法访问)"
    echo -ne "${CYAN}选择 [1]: ${NC}"
    read net_mode
    net_mode=${net_mode:-1}
    
    # Bridge 模式需要端口映射
    if [[ "$net_mode" == "2" ]]; then
        echo -ne "管理端口 [${lucky_port}]: "; read input_port
        lucky_port=${input_port:-$lucky_port}
    fi
    
    echo -ne "配置目录 [${lucky_conf_dir}]: "; read input_conf
    lucky_conf_dir=${input_conf:-$lucky_conf_dir}
    
    echo ""
    echo -e "${YELLOW}正在安装 Lucky...${NC}"
    
    # 检查是否已存在 lucky 容器
    if pct exec "$lxc_id" -- docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^lucky$'; then
        echo -e "${YELLOW}检测到已存在 lucky 容器，正在移除...${NC}"
        pct exec "$lxc_id" -- docker rm -f lucky 2>/dev/null
    fi
    
    # 创建配置目录
    pct exec "$lxc_id" -- mkdir -p "$lucky_conf_dir"
    
    case "$net_mode" in
        1)
            pct exec "$lxc_id" -- docker run -d \
                --name lucky \
                --restart=always \
                --net=host \
                -v "${lucky_conf_dir}:/goodluck" \
                gdy666/lucky:v2
            ;;
        2)
            pct exec "$lxc_id" -- docker run -d \
                --name lucky \
                --restart=always \
                -p "${lucky_port}:16601" \
                -v "${lucky_conf_dir}:/goodluck" \
                gdy666/lucky:v2
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            pause_func
            return
            ;;
    esac
    
    if [[ $? -eq 0 ]]; then
        echo ""
        echo -e "${GREEN}════════ 安装完成 ════════${NC}"
        echo ""
        echo -e "${GREEN}访问地址:${NC}"
        local display_port="16601"
        if [[ "$net_mode" == "2" ]]; then
            display_port="$lucky_port"
        fi
        if [[ -n "$container_ip" ]]; then
            echo -e "  ${CYAN}http://${container_ip}:${display_port}${NC}"
        else
            echo -e "  ${CYAN}http://<容器IP>:${display_port}${NC}"
        fi
        echo ""
        echo -e "${YELLOW}默认账号: 666${NC}"
        echo -e "${YELLOW}默认密码: 666${NC}"
        echo ""
        echo -e "${RED}⚠️  重要提示:${NC}"
        echo -e "${RED}   1. 外网访问权限在首次启动后 10 分钟内有效，请尽快登录设置${NC}"
        echo -e "${RED}   2. 未设置安全入口或未修改默认密码将无法使用所有功能${NC}"
        echo -e "${RED}   3. 安全入口设置后需通过 http://IP:端口/安全入口 访问${NC}"
        echo ""
        echo -e "${CYAN}配置目录: ${lucky_conf_dir}${NC}"
        echo -e "${CYAN}容器内路径: /goodluck${NC}"
        if [[ "$net_mode" == "1" ]]; then
            echo -e "${CYAN}网络模式: Host (端口可在 Lucky 后台修改)${NC}"
        else
            echo -e "${CYAN}网络模式: Bridge (端口映射 ${lucky_port}:16601)${NC}"
        fi
    else
        echo -e "${RED}安装失败${NC}"
    fi
    
    pause_func
}

install_openclaw() {
    clear
    echo -e "${BLUE}════════ OpenClaw 安装 ════════${NC}"
    echo -e "${YELLOW}OpenClaw - 个人 AI 助手，支持多种消息平台${NC}"
    echo ""
    
    pct list
    echo ""
    echo -ne "选择 LXC 容器 ID: "; read lxc_id
    
    if [[ -z "$lxc_id" ]]; then
        echo -e "${RED}错误: 请输入容器 ID${NC}"
        pause_func
        return
    fi
    
    # 检查容器是否存在
    if ! pct status "$lxc_id" &>/dev/null; then
        echo -e "${RED}错误: 容器 $lxc_id 不存在${NC}"
        pause_func
        return
    fi
    
    # 检查容器是否运行
    if ! pct status "$lxc_id" | grep -q "running"; then
        echo -e "${YELLOW}容器未运行，正在启动...${NC}"
        pct start "$lxc_id"
        sleep 3
    fi
    
    # 检查 Docker 环境
    echo ""
    echo -e "${YELLOW}检查 Docker 环境...${NC}"
    if ! pct exec "$lxc_id" -- bash -lc 'command -v docker &>/dev/null' 2>/dev/null && \
       ! pct exec "$lxc_id" -- test -x /usr/bin/docker 2>/dev/null; then
        echo ""
        echo -e "${RED}错误: 容器中未安装 Docker${NC}"
        echo -e "${YELLOW}请先使用「安装 Docker」功能安装 Docker 环境${NC}"
        pause_func
        return
    fi
    
    echo -e "${GREEN}Docker 环境已就绪${NC}"
    
    # 获取容器 IP 用于显示
    local container_ip=$(pct exec "$lxc_id" -- ip -4 addr show 2>/dev/null | grep -v '127\.' | grep -oP 'inet \K[0-9.]+' | head -1)
    
    echo ""
    echo -e "${YELLOW}════════ 配置 OpenClaw ════════${NC}"
    
    # 默认配置
    local openclaw_port="18789"
    local openclaw_bridge_port="18790"
    local openclaw_config_dir="/opt/openclaw/config"
    local openclaw_workspace_dir="/opt/openclaw/workspace"
    
    echo -ne "网关端口 [${openclaw_port}]: "; read input_port
    openclaw_port=${input_port:-$openclaw_port}
    
    echo -ne "桥接端口 [${openclaw_bridge_port}]: "; read input_bridge_port
    openclaw_bridge_port=${input_bridge_port:-$openclaw_bridge_port}
    
    echo -ne "配置目录 [${openclaw_config_dir}]: "; read input_config
    openclaw_config_dir=${input_config:-$openclaw_config_dir}
    
    echo -ne "工作目录 [${openclaw_workspace_dir}]: "; read input_workspace
    openclaw_workspace_dir=${input_workspace:-$openclaw_workspace_dir}
    
    echo ""
    echo -e "${YELLOW}正在安装 OpenClaw...${NC}"
    
    # 创建目录
    pct exec "$lxc_id" -- mkdir -p "$openclaw_config_dir" "$openclaw_workspace_dir"
    
    # 检查是否已存在 openclaw 容器
    if pct exec "$lxc_id" -- docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^openclaw-gateway$'; then
        echo -e "${YELLOW}检测到已存在 OpenClaw 容器，正在移除...${NC}"
        pct exec "$lxc_id" -- docker rm -f openclaw-gateway openclaw-cli 2>/dev/null
    fi
    
    # 获取 Docker Compose 命令
    local compose_cmd=$(get_compose_cmd "$lxc_id")
    if [[ -z "$compose_cmd" ]]; then
        echo -e "${RED}错误: Docker Compose 未安装${NC}"
        pause_func
        return
    fi
    
    # 创建 docker-compose.yml 文件
    local compose_file="/tmp/openclaw-docker-compose.yml"
    pct exec "$lxc_id" -- bash -c "cat > $compose_file" << EOF
services:
  openclaw-gateway:
    image: ghcr.io/openclaw/openclaw:latest
    environment:
      HOME: /home/node
      TERM: xterm-256color
      OPENCLAW_GATEWAY_TOKEN: \${OPENCLAW_GATEWAY_TOKEN:-}
      OPENCLAW_ALLOW_INSECURE_PRIVATE_WS: \${OPENCLAW_ALLOW_INSECURE_PRIVATE_WS:-}
      CLAUDE_AI_SESSION_KEY: \${CLAUDE_AI_SESSION_KEY:-}
      CLAUDE_WEB_SESSION_KEY: \${CLAUDE_WEB_SESSION_KEY:-}
      CLAUDE_WEB_COOKIE: \${CLAUDE_WEB_COOKIE:-}
      TZ: \${OPENCLAW_TZ:-UTC}
    volumes:
      - ${openclaw_config_dir}:/home/node/.openclaw
      - ${openclaw_workspace_dir}:/home/node/.openclaw/workspace
    ports:
      - "${openclaw_port}:18789"
      - "${openclaw_bridge_port}:18790"
    init: true
    restart: unless-stopped
    command:
      [
        "node",
        "dist/index.js",
        "gateway",
        "--bind",
        "lan",
        "--port",
        "18789",
      ]
    healthcheck:
      test:
        [
          "CMD",
          "node",
          "-e",
          "fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))",
        ]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 20s

  openclaw-cli:
    image: ghcr.io/openclaw/openclaw:latest
    network_mode: "service:openclaw-gateway"
    cap_drop:
      - NET_RAW
      - NET_ADMIN
    security_opt:
      - no-new-privileges:true
    environment:
      HOME: /home/node
      TERM: xterm-256color
      OPENCLAW_GATEWAY_TOKEN: \${OPENCLAW_GATEWAY_TOKEN:-}
      OPENCLAW_ALLOW_INSECURE_PRIVATE_WS: \${OPENCLAW_ALLOW_INSECURE_PRIVATE_WS:-}
      BROWSER: echo
      CLAUDE_AI_SESSION_KEY: \${CLAUDE_AI_SESSION_KEY:-}
      CLAUDE_WEB_SESSION_KEY: \${CLAUDE_WEB_SESSION_KEY:-}
      CLAUDE_WEB_COOKIE: \${CLAUDE_WEB_COOKIE:-}
      TZ: \${OPENCLAW_TZ:-UTC}
    volumes:
      - ${openclaw_config_dir}:/home/node/.openclaw
      - ${openclaw_workspace_dir}:/home/node/.openclaw/workspace
    stdin_open: true
    tty: true
    init: true
    entrypoint: ["node", "dist/index.js"]
    depends_on:
      - openclaw-gateway
EOF
    
    # 创建 .env 文件
    pct exec "$lxc_id" -- bash -c "cat > /tmp/openclaw.env" << EOF
OPENCLAW_GATEWAY_TOKEN=
OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=
CLAUDE_AI_SESSION_KEY=
CLAUDE_WEB_SESSION_KEY=
CLAUDE_WEB_COOKIE=
OPENCLAW_TZ=UTC
EOF
    
    # 启动服务
    echo ""
    echo -e "${YELLOW}启动 OpenClaw 服务...${NC}"
    if pct exec "$lxc_id" -- bash -lc "cd /tmp && $compose_cmd --env-file /tmp/openclaw.env -f $compose_file up -d" 2>&1; then
        echo ""
        echo -e "${GREEN}════════ 安装完成 ════════${NC}"
        echo ""
        echo -e "${GREEN}访问地址:${NC}"
        if [[ -n "$container_ip" ]]; then
            echo -e "  ${CYAN}http://${container_ip}:${openclaw_port}${NC}"
        else
            echo -e "  ${CYAN}http://<容器IP>:${openclaw_port}${NC}"
        fi
        echo ""
        echo -e "${YELLOW}配置目录: ${openclaw_config_dir}${NC}"
        echo -e "${YELLOW}工作目录: ${openclaw_workspace_dir}${NC}"
        echo ""
        echo -e "${CYAN}容器内配置路径: /home/node/.openclaw${NC}"
        echo -e "${CYAN}容器内工作路径: /home/node/.openclaw/workspace${NC}"
        echo ""
        echo -e "${RED}重要提示:${NC}"
        echo -e "${RED}  1. 首次访问需要完成 OpenClaw 引导设置${NC}"
        echo -e "${RED}  2. 请设置 OPENCLAW_GATEWAY_TOKEN 以确保安全访问${NC}"
        echo -e "${RED}  3. 可通过 docker compose logs 查看日志${NC}"
    else
        echo -e "${RED}安装失败${NC}"
    fi
    
    pause_func
}

# Docker 管理
docker_menu() {
    while true; do
        clear
        echo -e "${BLUE}════════ Docker 管理 ════════${NC}"
        echo -e "  ${GREEN}[1]${NC} 安装 Docker (含 Docker Compose)"
        echo -e "  ${GREEN}[2]${NC} 安装 DPanel 面板"
        echo -e "  ${GREEN}[3]${NC} 安装 Lucky 大吉"
        echo -e "  ${GREEN}[4]${NC} 安装 OpenClaw"
        echo -e "  ${GREEN}[5]${NC} Docker 换源"
        echo -e "  ${GREEN}[6]${NC} Docker 容器管理"
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
                install_dpanel
                ;;
            3)
                install_lucky
                ;;
            4)
                install_openclaw
                ;;
            5)
                docker_change_registry
                ;;
            6)
                docker_container_menu
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
        pct exec "$lxc_id" -- docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}' 2>/dev/null || echo "无法获取容器列表"
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
        # 获取容器使用的镜像
        local container_image=$(pct exec "$lxc_id" -- docker inspect "$container_name" --format='{{.Config.Image}}' 2>/dev/null || echo "")
        
        echo -e "${RED}警告: 将删除容器 $container_name${NC}"
        if [[ -n "$container_image" ]]; then
            echo -e "${YELLOW}容器使用的镜像: $container_image${NC}"
        fi
        echo -ne "确认删除容器? (y/N): "; read confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            if pct exec "$lxc_id" -- docker rm -f "$container_name" 2>/dev/null; then
                echo -e "${GREEN}容器 $container_name 已删除${NC}"
                
                # 询问是否删除镜像
                if [[ -n "$container_image" ]]; then
                    echo -ne "${CYAN}是否同时删除镜像 $container_image? (y/N): ${NC}"; read rm_image
                    if [[ "$rm_image" == "y" || "$rm_image" == "Y" ]]; then
                        if pct exec "$lxc_id" -- docker rmi "$container_image" 2>/dev/null; then
                            echo -e "${GREEN}镜像 $container_image 已删除${NC}"
                        else
                            echo -e "${YELLOW}镜像删除失败（可能被其他容器使用）${NC}"
                        fi
                    fi
                fi
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
    echo -e "  ${GREEN}[1]${NC} 毫秒镜像 (推荐)"
    echo -e "  ${GREEN}[2]${NC} 轩辕镜像免费版"
    echo -e "  ${GREEN}[3]${NC} 耗子面板"
    echo -e "  ${GREEN}[4]${NC} 中科大镜像"
    echo -e "  ${GREEN}[5]${NC} 阿里云镜像"
    echo -e "  ${GREEN}[6]${NC} 自定义镜像源"
    echo -e "  ${GREEN}[0]${NC} 取消"
    echo -ne "${CYAN}选择: ${NC}"
    read registry_choice
    echo
    
    REGISTRY_MIRRORS=""
    case "$registry_choice" in
        1)
            REGISTRY_MIRRORS="https://docker.1ms.run"
            echo -e "${GREEN}已选择: 毫秒镜像${NC}"
            ;;
        2)
            REGISTRY_MIRRORS="https://docker.xuanyuan.me"
            echo -e "${GREEN}已选择: 轩辕镜像免费版${NC}"
            ;;
        3)
            REGISTRY_MIRRORS="https://hub.rat.dev"
            echo -e "${GREEN}已选择: 耗子面板${NC}"
            ;;
        4)
            REGISTRY_MIRRORS="https://docker.mirrors.ustc.edu.cn"
            echo -e "${GREEN}已选择: 中科大镜像${NC}"
            ;;
        5)
            REGISTRY_MIRRORS="https://docker.mirrors.aliyun.com"
            echo -e "${GREEN}已选择: 阿里云镜像${NC}"
            ;;
        6)
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
    echo -e "${YELLOW}测试拉取镜像 (alpine)...${NC}"
    if pct exec "$lxc_id" -- docker pull alpine:latest 2>&1 | tail -3; then
        echo ""
        echo -e "${GREEN}Docker 镜像源配置成功！${NC}"
        echo -e "${YELLOW}清理测试镜像...${NC}"
        pct exec "$lxc_id" -- docker rmi alpine:latest 2>/dev/null || true
        pct exec "$lxc_id" -- docker image prune -f 2>/dev/null || true
        echo -e "${GREEN}测试数据已清理${NC}"
    else
        echo -e "${YELLOW}测试拉取失败，请检查网络或尝试其他镜像源${NC}"
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
               block_subscription_notice
                ;;
            0) break ;;
        esac
    done
}

# 屏蔽订阅提示
block_subscription_notice() {
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
                    
                    local modified=false
                    
                    # 策略A: 匹配 res.data.status 模式 (PVE 8.x/9.x 通用)
                    if grep -q "res\.data\.status\.toLowerCase() !== 'active'" "$js_file" 2>/dev/null; then
                        sed -i "s/res\.data\.status\.toLowerCase() !== 'active'/res.data.status.toLowerCase() === 'active'/g" "$js_file"
                        modified=true
                        echo -e "${GREEN}策略A生效: 修改了判断逻辑${NC}"
                    fi
                    
                    # 策略B: 匹配 !== 'active' 通用模式
                    if ! $modified && grep -q "!== 'active'" "$js_file" 2>/dev/null; then
                        sed -i "s/!== 'active'/=== 'active'/g" "$js_file"
                        modified=true
                        echo -e "${GREEN}策略B生效: 修改了判断逻辑${NC}"
                    fi
                    
                    # 策略C: 使用 Perl 多行匹配 Ext.Msg.show (兜底)
                    if ! $modified; then
                        if perl -i -0777 -pe 's/(Ext\.Msg\.show\(\{[\s\S]*?title: gettext\('"'"'No valid sub)/void({ \/\/\1/g' "$js_file" 2>/dev/null; then
                            if ! grep -q "Ext.Msg.show({.*No valid sub" "$js_file" 2>/dev/null; then
                                modified=true
                                echo -e "${GREEN}策略C生效: 屏蔽了弹窗函数${NC}"
                            fi
                        fi
                    fi
                    
                    if $modified; then
                        systemctl restart pveproxy.service
                        echo -e "${GREEN}已屏蔽订阅提示${NC}"
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
                local kernel_url="https://mirrors.aliyun.com/proxmox/debian/pve/dists/trixie/pve-no-subscription/binary-amd64/Packages"
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
    echo -e "${CYAN}[3]${NC} 清华 Docker 源 (推荐国内)"
    echo -e "${CYAN}[4]${NC} 阿里云 Docker 源"
    echo -e "${CYAN}[5]${NC} 中科大 Docker 源"
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
            echo -e "${YELLOW}添加清华 Docker 源...${NC}"
            apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
            mkdir -p /etc/apt/keyrings
            curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/debian trixie stable" > /etc/apt/sources.list.d/docker.list
            echo -e "${GREEN}清华 Docker 源添加完成${NC}"
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
            echo -e "${YELLOW}添加中科大 Docker 源...${NC}"
            apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
            mkdir -p /etc/apt/keyrings
            curl -fsSL https://mirrors.ustc.edu.cn/docker-ce/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.ustc.edu.cn/docker-ce/linux/debian trixie stable" > /etc/apt/sources.list.d/docker.list
            echo -e "${GREEN}中科大 Docker 源添加完成${NC}"
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
    
    DEBIAN_CODENAME=$(grep -oP 'VERSION_CODENAME=\K\w+' /etc/os-release 2>/dev/null || echo "trixie")
    PVE_VERSION=$(pveversion 2>/dev/null | grep -oP 'pve-manager\/\K[0-9]+' || echo "9")
    
    echo -e "${CYAN}检测到系统: Debian $DEBIAN_CODENAME, PVE $PVE_VERSION${NC}"
    
    while true; do
        clear
        echo -e "${BLUE}════════ 换源工具 ════════${NC}"
        echo -e "  ${GREEN}[1]${NC} 中科大源 (推荐)"
        echo -e "  ${GREEN}[2]${NC} 清华源"
        echo -e "  ${GREEN}[3]${NC} 阿里云源"
        echo -e "  ${GREEN}[4]${NC} 华为云源"
        echo -e "  ${GREEN}[5]${NC} 南京大学源"
        echo -e "  ${GREEN}[6]${NC} 腾讯云源"
        echo -e "  ${GREEN}[7]${NC} Ceph源配置"
        echo -e "  ${GREEN}[0]${NC} 返回"
        echo -ne "${CYAN}选择: ${NC}"
        read c
        echo
        
        TEST_MIRROR=""
        case "$c" in
            1) 
                DEBIAN_MIRROR="https://mirrors.ustc.edu.cn/debian"
                PVE_MIRROR="https://mirrors.ustc.edu.cn/proxmox/debian/pve"
                CT_MIRROR="https://mirrors.ustc.edu.cn/proxmox"
                CEPH_MIRROR="https://mirrors.ustc.edu.cn/proxmox/debian/ceph"
                TEST_MIRROR="mirrors.ustc.edu.cn"
                ;;
            2) 
                DEBIAN_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/debian"
                PVE_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/proxmox/debian/pve"
                CT_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/proxmox"
                CEPH_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/proxmox/debian/ceph"
                TEST_MIRROR="mirrors.tuna.tsinghua.edu.cn"
                ;;
            3) 
                echo -e "${YELLOW}注意: 阿里云仅支持 Debian 系统源，不支持 PVE 源${NC}"
                echo -e "${YELLOW}将使用阿里云 Debian 源，PVE 源保持默认${NC}"
                DEBIAN_MIRROR="https://mirrors.aliyun.com/debian"
                PVE_MIRROR=""
                CT_MIRROR=""
                CEPH_MIRROR=""
                TEST_MIRROR="mirrors.aliyun.com"
                ;;
            4) 
                DEBIAN_MIRROR="https://mirrors.huaweicloud.com/debian"
                PVE_MIRROR="https://mirrors.huaweicloud.com/proxmox/debian/pve"
                CT_MIRROR="https://mirrors.huaweicloud.com/proxmox"
                CEPH_MIRROR="https://mirrors.huaweicloud.com/proxmox/debian/ceph"
                TEST_MIRROR="mirrors.huaweicloud.com"
                ;;
            5) 
                DEBIAN_MIRROR="https://mirror.nju.edu.cn/debian"
                PVE_MIRROR="https://mirror.nju.edu.cn/proxmox/debian/pve"
                CT_MIRROR="https://mirror.nju.edu.cn/proxmox"
                CEPH_MIRROR="https://mirror.nju.edu.cn/proxmox/debian/ceph"
                TEST_MIRROR="mirror.nju.edu.cn"
                ;;
            6) 
                DEBIAN_MIRROR="https://mirrors.cloud.tencent.com/debian"
                PVE_MIRROR="https://mirrors.cloud.tencent.com/proxmox/debian/pve"
                CT_MIRROR="https://mirrors.cloud.tencent.com/proxmox"
                CEPH_MIRROR="https://mirrors.cloud.tencent.com/proxmox/debian/ceph"
                TEST_MIRROR="mirrors.cloud.tencent.com"
                ;;
            7)
                change_ceph_source
                continue
                ;;
            0) break ;;
            *) continue ;;
        esac
        
        if ! ping -c 1 "$TEST_MIRROR" &> /dev/null 2>&1; then
            echo -e "${RED}网络连接失败，无法访问 $TEST_MIRROR${NC}"
            pause_func
            continue
        fi
        
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
Suites: $DEBIAN_CODENAME ${DEBIAN_CODENAME}-updates ${DEBIAN_CODENAME}-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: $SECURITY_MIRROR
Suites: ${DEBIAN_CODENAME}-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
        
        if [[ -f "/etc/apt/sources.list.d/pve-enterprise.sources" ]]; then
            backup_file "/etc/apt/sources.list.d/pve-enterprise.sources"
            sed -i 's/^Types:/#Types:/g' /etc/apt/sources.list.d/pve-enterprise.sources
            sed -i 's/^URIs:/#URIs:/g' /etc/apt/sources.list.d/pve-enterprise.sources
        fi
        
        if [[ -f "/etc/apt/sources.list.d/pve-enterprise.list" ]]; then
            backup_file "/etc/apt/sources.list.d/pve-enterprise.list"
            echo "# Disabled by PVE Toolkit" > /etc/apt/sources.list.d/pve-enterprise.list
        fi
        
        if [[ -n "$PVE_MIRROR" ]]; then
            cat > /etc/apt/sources.list.d/pve-no-subscription.sources << EOF
Types: deb
URIs: $PVE_MIRROR
Suites: $DEBIAN_CODENAME
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
        fi
        
        if [[ -f "/usr/share/perl5/PVE/APLInfo.pm" ]]; then
            backup_file "/usr/share/perl5/PVE/APLInfo.pm"
            sed -i "s|https://mirrors.aliyun.com/proxmox|http://download.proxmox.com|g" /usr/share/perl5/PVE/APLInfo.pm
            sed -i "s|https://mirrors.ustc.edu.cn/proxmox|http://download.proxmox.com|g" /usr/share/perl5/PVE/APLInfo.pm
            sed -i "s|https://mirrors.tuna.tsinghua.edu.cn/proxmox|http://download.proxmox.com|g" /usr/share/perl5/PVE/APLInfo.pm
            sed -i "s|https://mirrors.huaweicloud.com/proxmox|http://download.proxmox.com|g" /usr/share/perl5/PVE/APLInfo.pm
            sed -i "s|https://mirror.nju.edu.cn/proxmox|http://download.proxmox.com|g" /usr/share/perl5/PVE/APLInfo.pm
            sed -i "s|https://mirrors.cloud.tencent.com/proxmox|http://download.proxmox.com|g" /usr/share/perl5/PVE/APLInfo.pm
            if [[ -n "$CT_MIRROR" ]]; then
                sed -i "s|http://download.proxmox.com|$CT_MIRROR|g" /usr/share/perl5/PVE/APLInfo.pm
            fi
        fi
        
        echo -e "${GREEN}换源完成${NC}"
        if [[ -n "$PVE_MIRROR" && -n "$CT_MIRROR" ]]; then
            echo -e "${YELLOW}已更换: Debian源 / PVE源 / CT模板源${NC}"
        elif [[ -n "$PVE_MIRROR" ]]; then
            echo -e "${YELLOW}已更换: Debian源 / PVE源${NC}"
        else
            echo -e "${YELLOW}已更换: Debian源 (PVE源保持默认)${NC}"
        fi
        apt update
        pause_func
    done
}

change_ceph_source() {
    if ! command -v ceph &>/dev/null; then
        echo -e "${YELLOW}未检测到 Ceph 安装，跳过 Ceph 源配置${NC}"
        pause_func
        return 0
    fi
    
    CEPH_CODENAME=$(ceph -v 2>/dev/null | grep -oP 'ceph \K[a-z]+' || echo "")
    if [[ -z "$CEPH_CODENAME" ]]; then
        CEPH_CODENAME="quincy"
    fi
    
    DEBIAN_CODENAME=$(grep -oP 'VERSION_CODENAME=\K\w+' /etc/os-release 2>/dev/null || echo "trixie")
    
    while true; do
        clear
        echo -e "${BLUE}════════ Ceph 源配置 ════════${NC}"
        echo -e "检测到 Ceph 版本: ${GREEN}$CEPH_CODENAME${NC}"
        echo ""
        echo -e "  ${GREEN}[1]${NC} 中科大 Ceph 源"
        echo -e "  ${GREEN}[2]${NC} 清华 Ceph 源"
        echo -e "  ${GREEN}[3]${NC} 华为云 Ceph 源"
        echo -e "  ${GREEN}[4]${NC} 南京大学 Ceph 源"
        echo -e "  ${GREEN}[5]${NC} 腾讯云 Ceph 源"
        echo -e "  ${GREEN}[6]${NC} 移除 Ceph 源 (使用默认)"
        echo -e "  ${GREEN}[0]${NC} 返回"
        echo -ne "${CYAN}选择: ${NC}"
        read c
        echo
        
        case "$c" in
            1)
                CEPH_MIRROR="https://mirrors.ustc.edu.cn/proxmox/debian/ceph"
                TEST_MIRROR="mirrors.ustc.edu.cn"
                ;;
            2)
                CEPH_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/proxmox/debian/ceph"
                TEST_MIRROR="mirrors.tuna.tsinghua.edu.cn"
                ;;
            3)
                CEPH_MIRROR="https://mirrors.huaweicloud.com/proxmox/debian/ceph"
                TEST_MIRROR="mirrors.huaweicloud.com"
                ;;
            4)
                CEPH_MIRROR="https://mirror.nju.edu.cn/proxmox/debian/ceph"
                TEST_MIRROR="mirror.nju.edu.cn"
                ;;
            5)
                CEPH_MIRROR="https://mirrors.cloud.tencent.com/proxmox/debian/ceph"
                TEST_MIRROR="mirrors.cloud.tencent.com"
                ;;
            6)
                if [[ -f "/etc/apt/sources.list.d/ceph.sources" ]]; then
                    backup_file "/etc/apt/sources.list.d/ceph.sources"
                    rm -f /etc/apt/sources.list.d/ceph.sources
                    echo -e "${GREEN}Ceph 源已移除${NC}"
                    apt update
                    pause_func
                    return 0
                else
                    echo -e "${YELLOW}Ceph 源文件不存在${NC}"
                    pause_func
                    return 0
                fi
                ;;
            0)
                return 0
                ;;
            *)
                continue
                ;;
        esac
        
        if ! ping -c 1 "$TEST_MIRROR" &> /dev/null 2>&1; then
            echo -e "${RED}网络连接失败，无法访问 $TEST_MIRROR${NC}"
            pause_func
            continue
        fi
        
        echo -e "${YELLOW}确认配置 Ceph 源? (y/N)${NC}"
        read confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && continue
        
        if [[ -f "/etc/apt/sources.list.d/ceph.sources" ]]; then
            backup_file "/etc/apt/sources.list.d/ceph.sources"
        fi
        
        cat > /etc/apt/sources.list.d/ceph.sources << EOF
Types: deb
URIs: $CEPH_MIRROR/$CEPH_CODENAME
Suites: $DEBIAN_CODENAME
Components: no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
        
        echo -e "${GREEN}Ceph 源配置完成${NC}"
        apt update
        pause_func
        return 0
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
