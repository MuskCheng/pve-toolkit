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
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }

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

echo -e "${GREEN}╔═══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      PVE Toolkit 安装器             ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"
echo ""

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    log_err "此脚本需要 root 权限"
    echo "请使用: su - root -c 'curl -sL $SCRIPT_URL | bash'"
    exit 1
fi

log_info "开始安装 PVE Toolkit..."

# 检查并安装依赖
for cmd in curl; do
    if ! command -v $cmd &>/dev/null; then
        log_err "需要安装 $cmd"
        exit 1
    fi
done

# 检查并自动安装 git
if ! command -v git &>/dev/null; then
    log_warn "未检测到 git，正在安装..."
    apt-get update -qq 2>/dev/null || true
    apt-get install -y -qq git 2>/dev/null || apt-get install -y git || log_err "git 安装失败，请手动安装: apt-get install -y git"
    if command -v git &>/dev/null; then
        log_ok "git 安装完成"
    fi
else
    log_ok "git 已安装"
fi

REPO_URL="https://github.com/$GH_USER/pve-toolkit.git"

# 如果已存在，则更新
if [[ -d "$INSTALL_DIR" ]]; then
    log_warn "检测到已安装，正在更新..."
    cd "$INSTALL_DIR"
    if git remote -v | grep -q origin; then
        log_info "正在拉取最新代码..."
        if git pull origin master 2>/dev/null; then
            log_ok "更新完成"
        else
            log_warn "更新失败，将重新安装"
            cd /
            rm -rf "$INSTALL_DIR"
        fi
    else
        rm -rf "$INSTALL_DIR"
    fi
fi

if [[ ! -d "$INSTALL_DIR" ]]; then
    log_info "正在克隆仓库: $REPO_URL"
    git clone "$REPO_URL" "$INSTALL_DIR" --depth 1
    log_ok "下载完成"
    cd "$INSTALL_DIR"
fi

# 设置权限
log_info "设置脚本权限..."
chmod +x pve-tool.sh
chmod +x modules/*.sh
chmod +x install.sh
log_ok "权限设置完成"

# 创建软链接
log_info "创建命令快捷方式..."
ln -sf "$INSTALL_DIR/pve-tool.sh" /usr/local/bin/pve-tool 2>/dev/null || true
log_ok "快捷方式创建完成"

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      ✅ 安装完成!                     ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}使用方法:${NC}"
echo "  pve-tool              # 运行工具"
echo "  pve-tool backup      # 命令行模式"
echo ""
echo -e "${BLUE}或直接运行:${NC}"
echo "  $INSTALL_DIR/pve-tool.sh"
echo ""
echo -e "${BLUE}更新命令:${NC}"
echo "  curl -sL $SCRIPT_URL | bash"
echo ""
