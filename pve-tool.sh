#!/bin/bash
#
# PVE Toolkit - Proxmox VE 管理工具集
# 版本: V0.29
# 使用: curl -sL https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/pve-tool.sh -o /tmp/pve.sh && bash /tmp/pve.sh

VERSION="V0.29"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# 暂停函数
pause_func() {
    echo -ne "${YELLOW}按任意键继续...${NC} "
    read -n 1 -s
    echo
}

# 检查 root
[[ $EUID -ne 0 ]] && { echo -e "${RED}需要 root 权限${NC}"; exit 1; }

# 检查 PVE
command -v pveversion &>/dev/null && pveversion | grep -q "pve-manager/9" || { echo -e "${RED}需要 PVE 9.0+${NC}"; exit 1; }

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
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "  ${GREEN}[1]${NC} 备份管理"
    echo -e "  ${GREEN}[2]${NC} 系统监控"
    echo -e "  ${GREEN}[3]${NC} LXC 管理"
    echo -e "  ${GREEN}[4]${NC} 系统管理"
    echo -e "  ${GREEN}[5]${NC} 换源工具"
    echo -e "  ${GREEN}[0]${NC} 退出"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
}

# 备份管理
backup_menu() {
    while true; do
        clear
        echo -e "${BLUE}════════ 备份管理 ════════${NC}"
        echo -e "  ${GREEN}[1]${NC} 列出备份"
        echo -e "  ${GREEN}[2]${NC} 创建备份"
        echo -e "  ${GREEN}[3]${NC} 清理备份"
        echo -e "  ${GREEN}[0]${NC} 返回"
        echo -ne "${CYAN}选择: ${NC}"
        read -n 1 c
        echo
        
        case "$c" in
            1)
                echo -e "${BLUE}=== 备份列表 ===${NC}"
                ls -lh "$BACKUP_DIR"/*.vma.zst 2>/dev/null || echo "无 VM 备份"
                ls -lh "$BACKUP_DIR"/*.tar.zst 2>/dev/null || echo "无 LXC 备份"
                pause_func
                ;;
            2)
                echo -ne "VM ID: "; read id
                [[ -n "$id" ]] && vzdump "$id" --mode snapshot --compress zstd --storage local
                pause_func
                ;;
            3)
                echo "清理 7 天前备份..."
                find "$BACKUP_DIR" -name "*.vma.zst" -mtime +7 -delete 2>/dev/null
                find "$BACKUP_DIR" -name "*.tar.zst" -mtime +7 -delete 2>/dev/null
                echo "完成"
                pause_func
                ;;
            0) break ;;
        esac
    done
}

# 系统监控
monitor_menu() {
    while true; do
        clear
        echo -e "${BLUE}════════ 系统监控 ════════${NC}"
        echo -e "  ${GREEN}[1]${NC} 系统状态"
        echo -e "  ${GREEN}[2]${NC} VM 列表"
        echo -e "  ${GREEN}[3]${NC} LXC 列表"
        echo -e "  ${GREEN}[0]${NC} 返回"
        echo -ne "${CYAN}选择: ${NC}"
        read -n 1 c
        echo
        
        case "$c" in
            1)
                echo -e "${BLUE}=== 系统状态 ===${NC}"
                echo "主机: $(hostname) | PVE: $(pveversion | grep -oP 'pve-manager/\K[0-9.]+')"
                echo "内核: $(uname -r)"
                echo "CPU: $(nproc) 核 | 内存: $(free -h | awk 'NR==2{print $3"/"$2}')"
                echo "磁盘: $(df -h / | awk 'NR==2{print $3"/"$2"("$5")"}')"
                echo "VM: $(qm list 2>/dev/null | grep running | wc -l) | LXC: $(pct list 2>/dev/null | grep running | wc -l)"
                pause_func
                ;;
            2) qm list; pause_func ;;
            3) pct list; pause_func ;;
            0) break ;;
        esac
    done
}

# LXC 管理
lxc_menu() {
    while true; do
        clear
        echo -e "${BLUE}════════ LXC 管理 ════════${NC}"
        echo -e "  ${GREEN}[1]${NC} 列表"
        echo -e "  ${GREEN}[2]${NC} 创建容器"
        echo -e "  ${GREEN}[3]${NC} 启动"
        echo -e "  ${GREEN}[4]${NC} 停止"
        echo -e "  ${GREEN}[5]${NC} 安装 Docker"
        echo -e "  ${GREEN}[0]${NC} 返回"
        echo -ne "${CYAN}选择: ${NC}"
        read -n 1 c
        echo
        
        case "$c" in
            1) pct list; pause_func ;;
            2)
                echo -ne "ID: "; read id; echo -ne "主机名: "; read hn
                [[ -n "$id" && -n "$hn" ]] && pct create "$id" local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst \
                    --hostname "$hn" --memory $LXC_MEM --cores $LXC_CORES --rootfs local:$LXC_DISK \
                    --net0 "name=eth0,bridge=vmbr0,ip=dhcp" --unprivileged 0 --start 1
                pause_func
                ;;
            3) echo -ne "ID: "; read id; [[ -n "$id" ]] && pct start "$id"; pause_func ;;
            4) echo -ne "ID: "; read id; [[ -n "$id" ]] && pct stop "$id"; pause_func ;;
            5)
                echo -ne "ID: "; read id
                [[ -n "$id" ]] && pct exec "$id" -- bash -c 'apt update && apt install -y docker.io && systemctl enable docker && systemctl start docker'
                pause_func
                ;;
            0) break ;;
        esac
    done
}

# 系统管理
system_menu() {
    while true; do
        clear
        echo -e "${BLUE}════════ 系统管理 ════════${NC}"
        echo -e "  ${GREEN}[1]${NC} 系统信息"
        echo -e "  ${GREEN}[2]${NC} 更新系统"
        echo -e "  ${GREEN}[3]${NC} 清理系统"
        echo -e "  ${GREEN}[0]${NC} 返回"
        echo -ne "${CYAN}选择: ${NC}"
        read -n 1 c
        echo
        
        case "$c" in
            1)
                echo -e "${BLUE}=== 系统信息 ===${NC}"
                pveversion -v
                echo "主机: $(hostname) | IP: $(hostname -I | awk '{print $1}')"
                pause_func
                ;;
            2)
                echo "更新系统..."
                apt update && apt upgrade -y
                pause_func
                ;;
            3)
                apt autoremove -y && apt autoclean
                echo "完成"
                pause_func
                ;;
            0) break ;;
        esac
    done
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
        read -n 1 c
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
        read -n 1 confirm
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
    sleep 1
    
    while true; do
        show_menu
        echo -ne "${CYAN}选择 [0-5]: ${NC}"
        read -n 1 choice
        echo
        
        case "$choice" in
            1) backup_menu ;;
            2) monitor_menu ;;
            3) lxc_menu ;;
            4) system_menu ;;
            5) change_source ;;
            0) echo "再见"; exit 0 ;;
        esac
    done
}

main "$@"
