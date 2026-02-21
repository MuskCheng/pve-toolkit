#!/bin/bash
#
# 系统监控模块
#

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 获取系统状态
monitor_status() {
    echo -e "${BLUE}=== PVE 系统状态 ===${NC}"
    echo ""
    
    # 主机名和版本
    echo -e "${GREEN}主机信息:${NC}"
    echo "  主机名: $(hostname)"
    echo "  PVE 版本: $(pveversion)"
    echo "  内核版本: $(uname -r)"
    echo ""
    
    # CPU 使用率
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
    
    # 内存使用
    echo -e "${GREEN}内存:${NC}"
    free -h | awk 'NR==2{printf "  已用: %s / %s (%.1f%%)\n", $3, $2, $3*100/$2}'
    echo ""
    
    # 磁盘使用
    echo -e "${GREEN}磁盘:${NC}"
    df -h | grep -E "^/dev/" | awk '{printf "  %s: %s / %s (%s)\n", $1, $3, $2, $5}'
    echo ""
    
    # 运行中的 VM/LXC
    echo -e "${GREEN}虚拟机/容器:${NC}"
    echo "  运行中 VM: $(qm list | grep running | wc -l)"
    echo "  运行中 LXC: $(pct list | grep running | wc -l)"
}

# 监控 VM 状态
monitor_vm() {
    echo -e "${BLUE}=== 虚拟机状态 ===${NC}"
    qm list
}

# 监控 LXC 状态
monitor_lxc() {
    echo -e "${BLUE}=== LXC 容器状态 ===${NC}"
    pct list
}

# 监控资源使用
monitor_resources() {
    echo -e "${BLUE}=== 资源使用详情 ===${NC}"
    echo ""
    
    # 检查 CPU 阈值
    local cpu_usage
    if command -v mpstat &>/dev/null; then
        cpu_usage=$(mpstat 1 1 | awk 'END {print int(100 - $NF)}')
    else
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | cut -d'.' -f1 || echo "0")
    fi
    if [[ "$cpu_usage" =~ ^[0-9]+$ ]] && [[ "$cpu_usage" -gt "$ALERT_THRESHOLD_CPU" ]]; then
        echo -e "${RED}⚠ CPU 使用率超过阈值: ${cpu_usage}% > ${ALERT_THRESHOLD_CPU}%${NC}"
    else
        echo -e "${GREEN}✓ CPU 使用率正常: ${cpu_usage}%${NC}"
    fi
    
    # 检查内存阈值
    local mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [[ "$mem_usage" -gt "$ALERT_THRESHOLD_MEM" ]]; then
        echo -e "${RED}⚠ 内存使用率超过阈值: ${mem_usage}% > ${ALERT_THRESHOLD_MEM}%${NC}"
    else
        echo -e "${GREEN}✓ 内存使用率正常: ${mem_usage}%${NC}"
    fi
    
    # 检查磁盘阈值
    local disk_usage=$(df / | awk 'NR==2{print $5}' | tr -d '%')
    if [[ "$disk_usage" -gt "$ALERT_THRESHOLD_DISK" ]]; then
        echo -e "${RED}⚠ 磁盘使用率超过阈值: ${disk_usage}% > ${ALERT_THRESHOLD_DISK}%${NC}"
    else
        echo -e "${GREEN}✓ 磁盘使用率正常: ${disk_usage}%${NC}"
    fi
}

# 监控网络
monitor_network() {
    echo -e "${BLUE}=== 网络状态 ===${NC}"
    echo ""
    ip -brief addr
    echo ""
    echo -e "${GREEN}网络流量:${NC}"
    cat /proc/net/dev | grep -E "vmbr|eth|enp" | awk '{printf "  %s: 接收 %s / 发送 %s\n", $1, $2, $10}'
}

# 监控日志
monitor_logs() {
    local lines="${1:-50}"
    echo -e "${BLUE}=== 最近 $lines 条系统日志 ===${NC}"
    journalctl -n "$lines" --no-pager
}

# 显示监控帮助
monitor_help() {
    echo -e "${BLUE}监控命令:${NC}"
    echo "  --status       显示系统状态概览"
    echo "  --vm           显示虚拟机状态"
    echo "  --lxc          显示 LXC 容器状态"
    echo "  --resources    检查资源使用阈值"
    echo "  --network      显示网络状态"
    echo "  --logs [N]     显示最近 N 条日志 (默认 50)"
}

# 监控模块入口
monitor_main() {
    case "${1:-}" in
        --status|-s)
            monitor_status
            ;;
        --vm)
            monitor_vm
            ;;
        --lxc)
            monitor_lxc
            ;;
        --resources|-r)
            monitor_resources
            ;;
        --network|-n)
            monitor_network
            ;;
        --logs|-l)
            monitor_logs "$2"
            ;;
        --help|-h)
            monitor_help
            ;;
        *)
            echo -e "${RED}错误: 未知监控命令${NC}"
            monitor_help
            return 1
            ;;
    esac
}

# 监控模块交互式菜单
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
            1)
                monitor_status
                ;;
            2)
                monitor_vm
                ;;
            3)
                monitor_lxc
                ;;
            4)
                monitor_resources
                ;;
            5)
                monitor_network
                ;;
            6)
                echo -ne "显示日志条数 [50]: "
                read -r lines
                monitor_logs "${lines:-50}"
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
