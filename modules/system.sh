#!/bin/bash
#
# 系统更新和镜像源管理模块
#

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
WHITE='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m'

# 显示当前镜像源配置
system_show_sources() {
    echo -e "${BLUE}=== APT 镜像源配置 ===${NC}"
    echo ""
    echo -e "${GREEN}Debian 源:${NC}"
    cat /etc/apt/sources.list 2>/dev/null | grep -v "^#" | grep -v "^$"
    echo ""
    echo -e "${GREEN}PVE 源:${NC}"
    cat /etc/apt/sources.list.d/pve*.list 2>/dev/null | grep -v "^#" | grep -v "^$"
}

# 获取 Debian 版本代号
get_debian_codename() {
    grep -oP 'VERSION="[^"]+"\s*\([^)]+\)' /etc/os-release 2>/dev/null | grep -oP '\(\K[^)]+' || \
    grep -oP '^PRETTY_NAME=[^(]+\([^)]+\)' /etc/os-release | grep -oP '\([^)]+' | tr -d '()' || \
    echo "bookworm"
}

# 切换镜像源通用函数
system_set_mirror() {
    local mirror_name="$1"
    local mirror_url="$2"
    local codename=$(get_debian_codename)
    
    echo -e "${YELLOW}切换到 ${mirror_name} 镜像源...${NC}"
    
    # 备份原配置
    cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%Y%m%d%H%M%S)
    
    # 写入新配置
    cat > /etc/apt/sources.list << EOF
# ${mirror_name}镜像源
deb ${mirror_url}/debian/ ${codename} main contrib non-free non-free-firmware
deb ${mirror_url}/debian/ ${codename}-updates main contrib non-free non-free-firmware
deb ${mirror_url}/debian-security/ ${codename}-security main contrib non-free non-free-firmware
EOF
    
    echo -e "${GREEN}镜像源已切换到 ${mirror_name}${NC}"
}

# 镜像源选择菜单
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
            1)
                system_set_mirror "中科大" "https://mirrors.ustc.edu.cn"
                ;;
            2)
                system_set_mirror "清华大学" "https://mirrors.tuna.tsinghua.edu.cn"
                ;;
            3)
                system_set_mirror "阿里云" "https://mirrors.aliyun.com"
                ;;
            4)
                system_set_mirror "华为云" "https://mirrors.huaweicloud.com"
                ;;
            5)
                system_set_mirror "腾讯云" "https://mirrors.cloud.tencent.com"
                ;;
            6)
                system_set_mirror "网易" "https://mirrors.163.com"
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                ;;
        esac
        
        echo ""
        echo -ne "${YELLOW}按回车键继续...${NC}"
        read -r
    done
}

# 禁用 PVE 企业源
system_disable_enterprise() {
    echo -e "${YELLOW}禁用 PVE 企业源...${NC}"
    
    if [[ -f /etc/apt/sources.list.d/pve-enterprise.list ]]; then
        sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list
        echo -e "${GREEN}已禁用 pve-enterprise.list${NC}"
    else
        echo -e "${GREEN}pve-enterprise.list 不存在或已禁用${NC}"
    fi
}

# 配置 PVE 社区源
system_set_pve_community() {
    echo -e "${YELLOW}配置 PVE 社区源 (中科大)...${NC}"
    
    cat > /etc/apt/sources.list.d/pve-no-subscription.list << EOF
# PVE 社区源 (中科大镜像)
deb https://mirrors.ustc.edu.cn/proxmox/debian/pve bookworm pve-no-subscription
EOF
    
    echo -e "${GREEN}PVE 社区源已配置${NC}"
}

# 更新系统
system_update() {
    echo -e "${BLUE}=== 系统更新 ===${NC}"
    
    echo -e "${GREEN}更新软件包列表...${NC}"
    apt update
    
    echo ""
    echo -e "${GREEN}可升级的软件包:${NC}"
    apt list --upgradable 2>/dev/null | head -20
    
    echo ""
    echo -ne "${WHITE}是否执行升级? (y/N): ${NC}"
    read -r confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}执行系统升级...${NC}"
        apt dist-upgrade -y
        echo -e "${GREEN}升级完成${NC}"
    fi
}

# 清理系统
system_cleanup() {
    echo -e "${BLUE}=== 系统清理 ===${NC}"
    
    echo -e "${GREEN}清理不需要的软件包...${NC}"
    apt autoremove -y
    apt autoclean
    
    echo -e "${GREEN}清理 APT 缓存...${NC}"
    apt clean
    
    echo -e "${GREEN}清理日志文件...${NC}"
    journalctl --vacuum-time="7days"
    
    echo -e "${GREEN}清理完成${NC}"
}

# 显示系统信息
system_info() {
    echo -e "${BLUE}=== PVE 系统信息 ===${NC}"
    echo ""
    echo -e "${GREEN}版本信息:${NC}"
    pveversion -v
    echo ""
    echo -e "${GREEN}主机信息:${NC}"
    echo "  主机名: $(hostname)"
    echo "  IP 地址: $(hostname -I | awk '{print $1}')"
    echo "  内核版本: $(uname -r)"
    echo "  系统运行时间: $(uptime -p)"
    echo ""
    echo -e "${GREEN}存储信息:${NC}"
    pvesm status
}

# 显示系统帮助
system_help() {
    echo -e "${BLUE}系统管理命令:${NC}"
    echo "  --sources              显示当前镜像源配置"
    echo "  --mirror               镜像源选择菜单"
    echo "  --disable-enterprise   禁用 PVE 企业源"
    echo "  --pve-community        配置 PVE 社区源"
    echo "  --update               更新系统"
    echo "  --cleanup              清理系统"
    echo "  --info                 显示系统信息"
}

# 系统模块入口
system_main() {
    case "${1:-}" in
        --sources)
            system_show_sources
            ;;
        --mirror)
            system_mirror_menu
            ;;
        --disable-enterprise)
            system_disable_enterprise
            ;;
        --pve-community)
            system_set_pve_community
            ;;
        --update|-u)
            system_update
            ;;
        --cleanup|-c)
            system_cleanup
            ;;
        --info|-i)
            system_info
            ;;
        --help|-h)
            system_help
            ;;
        *)
            echo -e "${RED}错误: 未知系统命令${NC}"
            system_help
            return 1
            ;;
    esac
}

# 系统模块交互式菜单
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
            1)
                system_info
                ;;
            2)
                system_show_sources
                ;;
            3)
                system_mirror_menu
                ;;
            4)
                system_disable_enterprise
                ;;
            5)
                system_set_pve_community
                ;;
            6)
                system_update
                ;;
            7)
                system_cleanup
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                ;;
        esac
        
        echo ""
        echo -ne "${YELLOW}按回车键继续...${NC}"
        read -r
    done
}