#!/bin/bash
#
# PVE Toolkit 一键安装脚本
# 使用方法: curl -sL https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/install.sh | bash

set -e

INSTALL_DIR="/opt/pve-toolkit"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 从脚本 URL 提取用户名
extract_user() {
    local url="$1"
    echo "$url" | sed -n 's|.*github.com/\([^/]*\)/.*|\1|p'
}

SCRIPT_URL="${SCRIPT_URL:-https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/install.sh}"
GH_USER=$(extract_user "$SCRIPT_URL")

# 如果提供了参数，使用参数作为用户名
if [[ -n "$1" ]] && [[ "$1" != "-"* ]]; then
    GH_USER="$1"
    SCRIPT_URL="https://raw.githubusercontent.com/$GH_USER/pve-toolkit/master/install.sh"
fi

echo -e "${GREEN}PVE Toolkit 安装器${NC}"
echo "========================"

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 此脚本需要 root 权限${NC}"
    echo "请使用: sudo bash -c '\$(curl -sL $SCRIPT_URL)'"
    exit 1
fi

# 检查并安装依赖
for cmd in curl; do
    if ! command -v $cmd &>/dev/null; then
        echo -e "${RED}错误: 需要安装 $cmd${NC}"
        exit 1
    fi
done

# 检查并自动安装 git
if ! command -v git &>/dev/null; then
    echo -e "${YELLOW}正在安装 git...${NC}"
    apt-get update && apt-get install -y git
fi

REPO_URL="https://github.com/$GH_USER/pve-toolkit.git"

# 如果已存在，则更新
if [[ -d "$INSTALL_DIR" ]]; then
    echo -e "${YELLOW}检测到已安装，正在更新...${NC}"
    cd "$INSTALL_DIR"
    if git remote -v | grep -q origin; then
        git pull origin master 2>/dev/null || echo "更新失败，将重新安装"
    else
        rm -rf "$INSTALL_DIR"
    fi
fi

if [[ ! -d "$INSTALL_DIR" ]]; then
    echo -e "${YELLOW}正在下载 PVE Toolkit...${NC}"
    git clone "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi

# 设置权限
chmod +x pve-tool.sh
chmod +x modules/*.sh

# 创建软链接
ln -sf "$INSTALL_DIR/pve-tool.sh" /usr/local/bin/pve-tool 2>/dev/null || true

echo ""
echo -e "${GREEN}✅ 安装完成!${NC}"
echo ""
echo "使用方法:"
echo "  pve-tool              # 运行工具"
echo "  pve-tool backup      # 命令行模式"
echo ""
echo "或直接运行:"
echo "  $INSTALL_DIR/pve-tool.sh"
echo ""
echo "更新命令:"
echo "  curl -sL $SCRIPT_URL | bash"
