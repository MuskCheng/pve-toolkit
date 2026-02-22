#!/bin/bash
#
# PVE Toolkit - Proxmox VE 管理工具集
# 使用: curl -sL https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/pve-tool.sh -o /tmp/pve.sh && bash /tmp/pve.sh

# 读取本地版本
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
    VERSION=$(cat "$SCRIPT_DIR/VERSION")
else
    VERSION="V0.5.11"
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
BOLD='\033[1m'
NC='\033[0m'
DEBUG=''

get_compose_cmd() {
    local lxc_id=$1
    if pct exec "$lxc_id" -- bash -lc 'command -v docker-compose &>/dev/null' 2>/dev/null || \
       pct exec "$lxc_id" -- test -x /usr/local/bin/docker-compose 2>/dev/null; then
        echo "docker-compose"
    elif pct exec "$lxc_id" -- bash -lc 'docker compose version &>/dev/null' 2>/dev/null; then
        echo "docker compose"
    else
        echo ""
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
    echo -e "${YELLOW}本工具仅支持 Proxmox VE 9.0+${NC}"
    exit 1
fi

PVE_VER=$(pveversion | grep -oP 'pve-manager/\K[0-9.]+' | cut -d. -f1)
if [[ -z "$PVE_VER" || "$PVE_VER" -lt 9 ]]; then
    echo -e "${RED}抱歉，不支持此版本${NC}"
    echo -e "${YELLOW}当前版本: $(pveversion | grep -oP 'pve-manager/\K[0-9.]+')"
    echo -e "${YELLOW}本工具仅支持 Proxmox VE 9.0 或更高版本${NC}"
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
    echo -e "  ${GREEN}[1]${NC} LXC 容器管理"
    echo -e "  ${GREEN}[2]${NC} 系统管理"
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
                if [[ -n "$id" && -n "$hn" ]]; then
                    pct create "$id" local:vztmpl/"$template" \
                        --hostname "$hn" --memory "$mem" --cores "$cores" --rootfs local:"$disk" \
                        --net0 "name=eth0,bridge=vmbr0,ip=dhcp" --unprivileged 0 --features nesting=1,keyctl=1 --start 1
                    
                    if [[ $? -eq 0 ]]; then
                        echo ""
                        echo -e "${GREEN}容器创建成功!${NC}"
                        echo ""
                        echo -ne "是否立即预装 Docker 环境? (y/N): "; read install_docker
                        if [[ "$install_docker" == "y" || "$install_docker" == "Y" ]]; then
                            echo ""
                            echo -e "${YELLOW}正在安装 Docker 环境...${NC}"
                            if check_and_install_docker "$id"; then
                                echo -e "${GREEN}Docker 环境安装完成!${NC}"
                            else
                                echo -e "${RED}Docker 环境安装失败，请稍后手动安装${NC}"
                            fi
                        fi
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
                    [[ "$confirm" == "y" || "$confirm" == "Y" ]] && pct stop "$id" 2>/dev/null; pct destroy "$id"
                fi
                pause_func
                ;;
            4) lxc_operate_menu ;;
            5) docker_menu ;;
            0) break ;;
        esac
    done
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
            0) break ;;
        esac
    done
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
    
    if pct exec "$lxc_id" -- bash -lc 'command -v docker-compose &>/dev/null' 2>/dev/null || \
       pct exec "$lxc_id" -- test -x /usr/local/bin/docker-compose 2>/dev/null; then
        COMPOSE_CMD="docker-compose"
        echo -e "${GREEN}Docker Compose 已安装 (docker-compose)${NC}"
        pct exec "$lxc_id" -- docker-compose --version 2>/dev/null || pct exec "$lxc_id" -- /usr/local/bin/docker-compose --version 2>/dev/null || true
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
                    if pct exec "$lxc_id" -- bash -lc 'command -v docker-compose &>/dev/null' 2>/dev/null; then
                        echo -e "${GREEN}Docker Compose (pip) 安装完成${NC}"
                        COMPOSE_CMD="docker-compose"
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
            )
            
            for url in "${COMPOSE_URLS[@]}"; do
                echo -e "${CYAN}尝试: $url${NC}"
                DOWNLOAD_SUCCESS=0
                DOWNLOAD_LOG=""
                
                if [[ $HAS_CURL -eq 1 ]]; then
                    DOWNLOAD_LOG=$(pct exec "$lxc_id" -- bash -lc "curl -L --connect-timeout 10 --max-time 60 -fSL '$url' -o /usr/local/bin/docker-compose 2>&1" || true)
                    if pct exec "$lxc_id" -- bash -lc 'test -s /usr/local/bin/docker-compose' 2>/dev/null; then
                        DOWNLOAD_SUCCESS=1
                    fi
                fi
                
                if [[ $DOWNLOAD_SUCCESS -eq 0 && $HAS_WGET -eq 1 ]]; then
                    DOWNLOAD_LOG=$(pct exec "$lxc_id" -- bash -lc "wget --timeout=60 -O /usr/local/bin/docker-compose '$url' 2>&1" || true)
                    if pct exec "$lxc_id" -- bash -lc 'test -s /usr/local/bin/docker-compose' 2>/dev/null; then
                        DOWNLOAD_SUCCESS=1
                    fi
                fi
                
                if [[ $DOWNLOAD_SUCCESS -eq 1 ]]; then
                    pct exec "$lxc_id" -- bash -lc 'chmod +x /usr/local/bin/docker-compose' 2>&1
                    VERIFY_OUTPUT=$(pct exec "$lxc_id" -- bash -lc '/usr/local/bin/docker-compose --version 2>&1' || true)
                    if [[ -n "$VERIFY_OUTPUT" ]]; then
                        echo -e "${GREEN}Docker Compose (二进制) 安装完成: $VERIFY_OUTPUT${NC}"
                        COMPOSE_CMD="docker-compose"
                        COMPOSE_INSTALL_SUCCESS=1
                        break
                    fi
                fi
                echo -e "${RED}下载失败: ${DOWNLOAD_LOG:0:100}...${NC}"
            done
            
            if [[ $COMPOSE_INSTALL_SUCCESS -eq 0 ]]; then
                echo -e "${RED}所有下载方式均失败，尝试 pip 安装...${NC}"
                if pct exec "$lxc_id" -- bash -lc 'command -v pip3 &>/dev/null' 2>/dev/null || \
                   pct exec "$lxc_id" -- test -x /usr/bin/pip3 2>/dev/null; then
                    if pct exec "$lxc_id" -- pip3 install docker-compose --break-system-packages 2>&1; then
                        if pct exec "$lxc_id" -- bash -lc 'command -v docker-compose &>/dev/null' 2>/dev/null; then
                            echo -e "${GREEN}Docker Compose (pip) 安装完成${NC}"
                            COMPOSE_CMD="docker-compose"
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
            0) break ;;
        esac
    done
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
    
    pct exec "$lxc_id" -- bash -c "cd /tmp && $COMPOSE_CMD -f /tmp/docker-compose.yml up -d"
    
    echo ""
    echo -e "${GREEN}部署完成!${NC}"
    echo -e "查看容器状态: ${CYAN}pct exec $lxc_id -- docker ps${NC}"
    echo -e "查看日志: ${CYAN}pct exec $lxc_id -- docker logs $service_name${NC}"
    
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
    
    pct exec "$lxc_id" -- bash -c "cd /tmp && $COMPOSE_CMD -f /tmp/docker-compose.yml up -d"
    
    echo ""
    echo -e "${GREEN}部署完成!${NC}"
    echo -e "查看容器: ${CYAN}pct exec $lxc_id -- docker ps${NC}"
    
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
                echo -e "${BLUE}=== 内核管理 ===${NC}"
                echo -e "${YELLOW}当前内核:${NC} $(uname -r)"
                echo -e "${YELLOW}已安装内核:${NC}"
                dpkg -l | grep -E "pve-kernel|linux-image" | awk '{print $2, $3}'
                echo ""
                echo -e "${YELLOW}[1]${NC} 清理旧内核"
                echo -e "${YELLOW}[0]${NC} 返回"
                echo -ne "选择: "; read k
                if [[ "$k" == "1" ]]; then
                    echo "清理旧内核..."
                    apt autoremove -y --purge 'pve-kernel-*' 'linux-image-*'
                    update-grub
                    echo -e "${GREEN}完成${NC}"
                fi
                pause_func
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
            0) break ;;
        esac
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
    while true; do
        clear
        echo -e "${BLUE}════════ 换源工具 ════════${NC}"
        echo -e "  ${GREEN}[1]${NC} 中科大源"
        echo -e "  ${GREEN}[2]${NC} 清华源"
        echo -e "  ${GREEN}[3]${NC} 阿里云源"
        echo -e "  ${GREEN}[4]${NC} 华为云源"
        echo -e "  ${GREEN}[0]${NC} 返回"
        echo -ne "${CYAN}选择: ${NC}"
        read c
        echo
        
        case "$c" in
            1) MIRROR="mirrors.ustc.edu.cn" ;;
            2) MIRROR="mirrors.tuna.tsinghua.edu.cn" ;;
            3) MIRROR="mirrors.aliyun.com" ;;
            4) MIRROR="mirrors.huaweicloud.com" ;;
            0) break ;;
            *) continue ;;
        esac
        
        echo -e "${YELLOW}确认换源? (y/N)${NC}"
        read confirm
        echo
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && continue
        
        # 备份
        cp /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null
        
        # 换源
        cat > /etc/apt/sources.list << EOF
deb https://$MIRROR/debian trixie main contrib non-free non-free-firmware
deb https://$MIRROR/debian trixie-updates main contrib non-free non-free-firmware
deb https://$MIRROR/debian-security trixie-security main contrib non-free non-free-firmware
EOF
        
        # 换 PVE 源
        echo "deb https://$MIRROR/proxmox/debian/pve trixie pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list
        
        # 禁用企业源
        sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list 2>/dev/null
        
        echo -e "${GREEN}换源完成${NC}"
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
            1) lxc_menu ;;
            2) system_menu ;;
            3) change_source ;;
            0) echo "再见"; exit 0 ;;
        esac
    done
}

main "$@"