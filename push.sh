#!/bin/bash
#
# PVE Toolkit - 一键推送脚本

set -e

# 检查 git 是否初始化
if [[ ! -d .git ]]; then
    echo "错误: 当前目录不是 git 仓库"
    echo "请先运行: git init"
    exit 1
fi

# 获取 GitHub 用户名
GH_USER="${1:-MuskCheng}"

# 替换 README 中的占位符
if [[ -f README.md ]]; then
    sed -i "s/yourusername/$GH_USER/g" README.md
    sed -i "s/你的用户名/$GH_USER/g" README.md
fi

# 获取提交信息
MSG="${2:-Update}"

# 添加所有更改
git add -A

# 检查是否有更改
if git diff --staged --quiet; then
    echo "没有需要提交的更改"
    exit 0
fi

# 显示更改摘要
echo "更改的文件:"
git diff --cached --name-only | sed 's/^/  /'

# 提交
echo ""
echo "提交信息: $MSG"
git commit -m "$MSG"

# 推送到远程
echo "推送到 GitHub..."
git push

echo ""
echo "✅ 推送完成!"
echo ""
echo "用户安装命令:"
echo "  curl -sL https://raw.githubusercontent.com/$GH_USER/pve-toolkit/main/install.sh | bash"
