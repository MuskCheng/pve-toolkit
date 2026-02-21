#!/bin/bash
#
# 备份管理模块
#

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 列出所有备份
backup_list() {
    echo -e "${BLUE}=== 备份列表 ===${NC}"
    if [[ -d "$BACKUP_DIR" ]]; then
        ls -lh "$BACKUP_DIR"/*.vma.zst 2>/dev/null || echo -e "${YELLOW}无 VM 备份${NC}"
        ls -lh "$BACKUP_DIR"/*.tar.zst 2>/dev/null || echo -e "${YELLOW}无 LXC 备份${NC}"
    else
        echo -e "${RED}备份目录不存在: $BACKUP_DIR${NC}"
    fi
}

# 创建备份
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

# 清理旧备份
backup_cleanup() {
    echo -e "${BLUE}清理 ${BACKUP_RETENTION_DAYS} 天前的备份...${NC}"
    find "$BACKUP_DIR" -name "*.vma.zst" -mtime +${BACKUP_RETENTION_DAYS} -delete
    find "$BACKUP_DIR" -name "*.tar.zst" -mtime +${BACKUP_RETENTION_DAYS} -delete
    echo -e "${GREEN}清理完成${NC}"
}

# 判断备份文件类型并恢复
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
    
    echo -e "${YELLOW}警告: 这将覆盖现有的 VM/LXC $vmid${NC}"
    read -p "确认继续? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        if [[ "$restore_cmd" == "qmrestore" ]]; then
            qmrestore "$backup_file" "$vmid" --storage local
        else
            pctrestore "$vmid" "$backup_file" --storage local
        fi
    fi
}

# 显示备份帮助
backup_help() {
    echo -e "${BLUE}备份管理命令:${NC}"
    echo "  --list              列出所有备份"
    echo "  --create <ID>       创建备份"
    echo "  --cleanup           清理旧备份"
    echo "  --restore <file> <ID> 恢复备份"
}

# 备份模块入口
backup_main() {
    case "${1:-}" in
        --list|-l)
            backup_list
            ;;
        --create|-c)
            backup_create "$2" "$3"
            ;;
        --cleanup)
            backup_cleanup
            ;;
        --restore|-r)
            backup_restore "$2" "$3"
            ;;
        --help|-h)
            backup_help
            ;;
        *)
            echo -e "${RED}错误: 未知备份命令${NC}"
            backup_help
            return 1
            ;;
    esac
}

# 备份模块交互式菜单
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
            1)
                backup_list
                ;;
            2)
                echo -ne "请输入 VM/LXC ID: "
                read -r vmid
                echo -ne "备份模式 (snapshot/suspend/stop) [snapshot]: "
                read -r mode
                backup_create "$vmid" "${mode:-snapshot}"
                ;;
            3)
                backup_cleanup
                ;;
            4)
                backup_list
                echo -ne "请输入备份文件路径: "
                read -r backup_file
                echo -ne "请输入目标 VM ID: "
                read -r vmid
                backup_restore "$backup_file" "$vmid"
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
