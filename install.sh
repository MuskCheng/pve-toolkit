#!/bin/bash
#
# PVE Toolkit 一键安装脚本
# 使用: bash -c "$(curl -sL https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/install.sh)"

set -e

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
NC=$'\033[0m'

# 创建 post-merge hook 自动清理旧文件
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)/.git/hooks"
HOOK_FILE="$HOOK_DIR/post-merge"
if [[ ! -f "$HOOK_FILE" ]]; then
    mkdir -p "$HOOK_DIR"
    cat > "$HOOK_FILE" << 'HOOK_EOF'
#!/bin/bash
git checkout -q -- .
rm -f *.bak *.old *.tmp 2>/dev/null
HOOK_EOF
    chmod +x "$HOOK_FILE"
fi

echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  PVE Toolkit 安装向导${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""

# ========== 1. Root 权限检查 ==========
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}✗ 错误: 需要 root 权限${NC}"
    echo -e "${YELLOW}  请使用 su - root 或 sudo 执行${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Root 权限检查通过${NC}"

# ========== 2. PVE 环境检测 ==========
if ! command -v pveversion &>/dev/null; then
    echo -e "${RED}✗ 错误: 非 PVE 环境${NC}"
    echo -e "${YELLOW}  本工具仅支持 Proxmox VE 系统${NC}"
    exit 1
fi
echo -e "${GREEN}✓ PVE 环境检测通过${NC}"

# ========== 3. 依赖包检查 ==========
check_packages() {
    local packages=("curl")
    local missing=()
    
    for pkg in "${packages[@]}"; do
        if ! command -v "$pkg" &> /dev/null; then
            missing+=("$pkg")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${YELLOW}! 缺少依赖包: ${missing[*]}${NC}"
        echo -e "${YELLOW}  正在安装...${NC}"
        apt update -qq && apt install -y -qq "${missing[@]}" 2>/dev/null
        echo -e "${GREEN}✓ 依赖包安装完成${NC}"
    else
        echo -e "${GREEN}✓ 依赖包检查通过${NC}"
    fi
}
check_packages

# ========== 4. PVE 版本检测 ==========
PVE_VERSION=$(pveversion | grep -oP 'pve-manager/\K[0-9.]+' | head -1)
PVE_MAJOR=$(echo "$PVE_VERSION" | cut -d. -f1)
PVE_MINOR=$(echo "$PVE_VERSION" | cut -d. -f2)

echo -e "${CYAN}  当前 PVE 版本: $PVE_VERSION${NC}"
echo ""

if [[ "$PVE_MAJOR" != "9" ]]; then
    echo -e "${RED}════════════════════════════════════════${NC}"
    echo -e "${RED}  警告: 当前为 PVE $PVE_MAJOR.x (推荐 PVE 9.x)${NC}"
    echo -e "${RED}  换源等操作可能导致软件源错配或系统异常${NC}"
    echo -e "${RED}════════════════════════════════════════${NC}"
    echo ""
    read -p "  确认继续? 输入 'yes': " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo -e "${YELLOW}  已取消安装${NC}"
        exit 0
    fi
fi

if [[ -z "$PVE_VERSION" ]]; then
    echo -e "${RED}✗ 无法获取 PVE 版本${NC}"
    exit 1
fi

echo -e "${GREEN}✓ PVE 版本检测通过${NC}"
echo ""

# ========== 5. 选择下载源 ==========
echo -e "${CYAN}请选择下载源:${NC}"
echo -e "  ${GREEN}[1]${NC} 官方源 - 国外服务器推荐"
echo -e "  ${GREEN}[2]${NC} 加速源 - 国内服务器推荐"
read -p "选择 [2]: " source_choice
source_choice=${source_choice:-2}

case "$source_choice" in
    1) 
        SCRIPT_URL="https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/pve-tool.sh"
        echo -e "${YELLOW}使用官方源下载...${NC}"
        ;;
    *) 
        SCRIPT_URL="https://cdn.jsdelivr.net/gh/MuskCheng/pve-toolkit@master/pve-tool.sh"
        echo -e "${YELLOW}使用加速源下载...${NC}"
        ;;
esac

# ========== 6. 下载脚本 ==========
echo ""
if curl -sL "$SCRIPT_URL" -o /tmp/pve-tool.sh; then
    echo -e "${GREEN}✓ 下载完成${NC}"
else
    echo -e "${RED}✗ 下载失败，尝试备用源...${NC}"
    SCRIPT_URL="https://raw.githubusercontent.com/MuskCheng/pve-toolkit/master/pve-tool.sh"
    if curl -sL "$SCRIPT_URL" -o /tmp/pve-tool.sh; then
        echo -e "${GREEN}✓ 备用源下载成功${NC}"
    else
        echo -e "${RED}✗ 所有下载方式均失败${NC}"
        exit 1
    fi
fi

chmod +x /tmp/pve-tool.sh

echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  安装完成，正在启动...${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""

export PVE_MAJOR_VERSION="$PVE_MAJOR"
export PVE_FULL_VERSION="$PVE_VERSION"
exec bash /tmp/pve-tool.sh "$@"
