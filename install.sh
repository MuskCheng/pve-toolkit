#!/bin/bash
#
# PVE Toolkit 一键安装脚本
# 使用: bash -c "$(curl -sL https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/install.sh)"

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}PVE Toolkit 安装向导${NC}"
echo ""

# 检查 root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 需要 root 权限${NC}"
    echo -e "${YELLOW}请使用 su - root 切换后再执行${NC}"
    exit 1
fi

# 检查 PVE
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

echo -e "${GREEN}✓ PVE 版本检查通过${NC}"
echo ""

# 下载脚本
echo -e "${YELLOW}正在下载 PVE Toolkit...${NC}"
SCRIPT_URL="https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/pve-tool.sh"

if curl -sL "$SCRIPT_URL" -o /tmp/pve-tool.sh; then
    echo -e "${GREEN}✓ 下载完成${NC}"
else
    echo -e "${RED}✗ 下载失败，请检查网络连接${NC}"
    exit 1
fi

# 添加执行权限
chmod +x /tmp/pve-tool.sh

echo ""
echo -e "${GREEN}安装完成！${NC}"
echo ""
echo -e "${YELLOW}正在启动 PVE Toolkit...${NC}"
echo ""

# 运行脚本
exec bash /tmp/pve-tool.sh
