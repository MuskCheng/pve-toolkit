# PVE Toolkit 开发注意事项

## 版本管理
- 每次修改必须同步更新 VERSION 文件和 pve-tool.sh 中的备用版本号
- CHANGELOG.md 需要添加更新记录

## 常见功能修复

### 1. Docker 容器端口显示
- 文件：pve-tool.sh
- 位置：docker_container_menu 函数中
- 问题：{{.Ports}} 在双引号中被解析
- 修复：使用单引号 + {{range .Ports}}{{.PublicPort}} {{end}}

### 2. 屏蔽订阅提示功能
- 参考：https://github.com/Mapleawaa/PVE-Tools-9
- 文件：proxmoxlib.js
- 位置：/usr/share/javascript/proxmox-widget-toolkit/
- 策略A：sed -i "s/res.data.status.toLowerCase() !== 'active'/res.data.status.toLowerCase() === 'active'/g"
- 策略B（perl多行）：perl -i -0777 -pe "s/(Ext\.Msg\.show\(\{\s+title: gettext\('No valid sub)/void\(\{ \/\/\1/g"

## 主菜单结构
[1] 系统管理
[2] LXC 容器管理
[3] 换源工具
