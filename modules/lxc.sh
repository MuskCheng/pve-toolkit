#!/bin/bash
#
# LXC 容器管理模块
#

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
WHITE='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m'

# 列出所有 LXC 容器
lxc_list() {
    echo -e "${BLUE}=== LXC 容器列表 ===${NC}"
    pct list
}

# 创建 LXC 容器
lxc_create() {
    local vmid="$1"
    local hostname="$2"
    local memory="${3:-$LXC_DEFAULT_MEMORY}"
    local cores="${4:-$LXC_DEFAULT_CORES}"
    local disk="${5:-$LXC_DEFAULT_DISK}"
    
    if [[ -z "$vmid" ]] || [[ -z "$hostname" ]]; then
        echo -e "${RED}错误: 请指定容器 ID 和主机名${NC}"
        echo "用法: $0 lxc --create <ID> <主机名> [内存] [核心数] [磁盘大小]"
        return 1
    fi
    
    : "${LXC_TEMPLATE:=local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst}"
    if ! pvesm status "$LXC_TEMPLATE" 2>/dev/null | grep -q "^local" && [[ ! -f "/var/lib/vz/template/cache/$(basename "$LXC_TEMPLATE")" ]]; then
        echo -e "${YELLOW}警告: 模板可能不存在: $LXC_TEMPLATE${NC}"
        echo "可用模板:"
        ls -la /var/lib/vz/template/cache/ 2>/dev/null || echo "  (无模板缓存)"
    fi
    
    echo -e "${GREEN}创建 LXC 容器 $vmid...${NC}"
    echo "  主机名: $hostname"
    echo "  内存: ${memory}MB"
    echo "  核心数: $cores"
    echo "  磁盘: ${disk}GB"
    
    pct create "$vmid" "$LXC_TEMPLATE" \
        --hostname "$hostname" \
        --memory "$memory" \
        --cores "$cores" \
        --rootfs "local:${disk}" \
        --net0 "name=eth0,bridge=vmbr0,ip=dhcp" \
        --unprivileged 0 \
        --features "nesting=1,keyctl=1" \
        --start 1
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}容器 $vmid 创建成功并已启动${NC}"
    else
        echo -e "${RED}容器创建失败${NC}"
        return 1
    fi
}

# 启动容器
lxc_start() {
    local vmid="$1"
    if [[ -z "$vmid" ]]; then
        echo -e "${RED}错误: 请指定容器 ID${NC}"
        return 1
    fi
    pct start "$vmid"
    echo -e "${GREEN}容器 $vmid 已启动${NC}"
}

# 停止容器
lxc_stop() {
    local vmid="$1"
    if [[ -z "$vmid" ]]; then
        echo -e "${RED}错误: 请指定容器 ID${NC}"
        return 1
    fi
    pct stop "$vmid"
    echo -e "${GREEN}容器 $vmid 已停止${NC}"
}

# 重启容器
lxc_restart() {
    local vmid="$1"
    if [[ -z "$vmid" ]]; then
        echo -e "${RED}错误: 请指定容器 ID${NC}"
        return 1
    fi
    pct restart "$vmid"
    echo -e "${GREEN}容器 $vmid 已重启${NC}"
}

# 删除容器
lxc_delete() {
    local vmid="$1"
    local force="${2:-}"
    
    if [[ -z "$vmid" ]]; then
        echo -e "${RED}错误: 请指定容器 ID${NC}"
        return 1
    fi
    
    # 检查容器是否存在
    if ! pct list | grep -q "^$vmid "; then
        echo -e "${RED}错误: 容器 $vmid 不存在${NC}"
        return 1
    fi
    
    if [[ "$force" == "-f" ]] || [[ "$force" == "--force" ]]; then
        pct stop "$vmid" 2>/dev/null
        pct destroy "$vmid"
        echo -e "${GREEN}容器 $vmid 已删除${NC}"
    else
        echo -e "${YELLOW}警告: 这将删除容器 $vmid 及其所有数据！${NC}"
        echo -ne "确认删除? (y/N): "
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            pct stop "$vmid" 2>/dev/null
            pct destroy "$vmid"
            echo -e "${GREEN}容器 $vmid 已删除${NC}"
        else
            echo -e "${YELLOW}已取消删除${NC}"
        fi
    fi
}

# 进入容器控制台
lxc_console() {
    local vmid="$1"
    if [[ -z "$vmid" ]]; then
        echo -e "${RED}错误: 请指定容器 ID${NC}"
        return 1
    fi
    pct enter "$vmid"
}

# 显示容器详情
lxc_info() {
    local vmid="$1"
    if [[ -z "$vmid" ]]; then
        echo -e "${RED}错误: 请指定容器 ID${NC}"
        return 1
    fi
    echo -e "${BLUE}=== 容器 $vmid 详情 ===${NC}"
    pct config "$vmid"
    echo ""
    echo -e "${BLUE}资源使用:${NC}"
    pct status "$vmid"
}

# 安装 Docker
lxc_install_docker() {
    local vmid="$1"
    if [[ -z "$vmid" ]]; then
        echo -e "${RED}错误: 请指定容器 ID${NC}"
        return 1
    fi
    
    echo -e "${GREEN}正在为容器 $vmid 安装 Docker...${NC}"
    
    # 使用官方 Docker 源安装
    pct exec "$vmid" -- bash -c '
        # 安装依赖
        apt update && apt install -y curl ca-certificates gnupg lsb-release
        
        # 获取 Debian 版本号
        CODENAME=$(lsb_release -cs)
        
        mkdir -p /etc/apt/keyrings
        
        # 方法1: 官方 Docker 源
        if curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null; then
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${CODENAME} stable" > /etc/apt/sources.list.d/docker.list
            if apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null; then
                DOCKER_OK=1
            fi
        fi
        
        # 方法2: 系统自带 docker.io
        if [[ "$DOCKER_OK" != "1" ]]; then
            rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
            if apt install -y docker.io 2>/dev/null; then
                DOCKER_OK=2
            fi
        fi
        
        if [[ "$DOCKER_OK" != "1" ]] && [[ "$DOCKER_OK" != "2" ]]; then
            exit 1
        fi
        
        # 启动 Docker
        systemctl enable docker 2>/dev/null || systemctl enable docker.io 2>/dev/null || true
        systemctl start docker 2>/dev/null || systemctl start docker.io 2>/dev/null || true
    '
    
    if [[ $? -eq 0 ]]; then
        # 配置默认 Docker 镜像加速
        pct exec "$vmid" -- bash -c "mkdir -p /etc/docker && echo '{\"registry-mirrors\":[\"https://docker.m.daocloud.io\",\"https://hub.rat.dev\"]}' > /etc/docker/daemon.json"
        pct exec "$vmid" -- bash -c "systemctl restart docker 2>/dev/null || systemctl restart docker.io 2>/dev/null || true"
        echo -e "${GREEN}Docker 安装完成${NC}"
        pct exec "$vmid" -- bash -c "docker --version 2>/dev/null || docker.io --version 2>/dev/null"
        
        # 询问是否切换镜像源
        echo ""
        echo -ne "${YELLOW}是否切换其他 Docker 镜像源? (y/N): ${NC}"
        read -r change_mirror
        if [[ "$change_mirror" =~ ^[Yy]$ ]]; then
            lxc_docker_mirror_menu "$vmid"
        fi
    else
        echo -e "${RED}Docker 安装失败${NC}"
        return 1
    fi
}

# 安装 Docker Compose
lxc_install_docker_compose() {
    local vmid="$1"
    if [[ -z "$vmid" ]]; then
        echo -e "${RED}错误: 请指定容器 ID${NC}"
        return 1
    fi
    
    echo -e "${GREEN}正在为容器 $vmid 安装 Docker Compose...${NC}"
    
    # 使用 pip 安装 docker-compose (更可靠)
    pct exec "$vmid" -- bash -c "apt update && apt install -y python3-pip && pip3 install docker-compose --break-system-packages"
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Docker Compose 安装完成${NC}"
        pct exec "$vmid" -- docker-compose --version
        
        # 显示使用引导
        echo ""
        echo -e "${CYAN}═══════════════════════════════════════${NC}"
        echo -e "${BOLD}      Docker Compose 使用引导${NC}"
        echo -e "${CYAN}═══════════════════════════════════════${NC}"
        echo ""
        echo -e "${YELLOW}常用命令:${NC}"
        echo "  docker-compose up -d        后台启动服务"
        echo "  docker-compose down         停止并删除容器"
        echo "  docker-compose ps           查看运行状态"
        echo "  docker-compose logs -f      查看日志"
        echo "  docker-compose restart      重启服务"
        echo ""
        echo -e "${YELLOW}示例 docker-compose.yml:${NC}"
        echo "  version: '3'"
        echo "  services:"
        echo "    nginx:"
        echo "      image: nginx:alpine"
        echo "      ports:"
        echo "        - \"80:80\""
        echo "      restart: always"
        echo ""
        echo -ne "${WHITE}是否现在创建 docker-compose.yml? (y/N): ${NC}"
        read -r create_compose
        if [[ "$create_compose" =~ ^[Yy]$ ]]; then
            lxc_create_compose_file "$vmid"
        fi
    else
        echo -e "${RED}Docker Compose 安装失败${NC}"
        return 1
    fi
}

# 创建 docker-compose.yml 文件
lxc_create_compose_file() {
    local vmid="$1"
    
    echo ""
    echo -e "${WHITE}选择模板:${NC}"
    echo "  [1] Nginx"
    echo "  [2] MySQL"
    echo "  [3] Redis"
    echo "  [4] Portainer"
    echo "  [5] 自定义"
    echo ""
    echo -ne "${WHITE}请选择 [1-5]: ${NC}"
    read -r template
    
    local compose_content=""
    local work_dir="/opt/docker-compose"
    
    case "$template" in
        1)
            compose_content="version: '3'
services:
  nginx:
    image: nginx:alpine
    container_name: nginx
    ports:
      - \"80:80\"
    restart: always"
            ;;
        2)
            compose_content="version: '3'
services:
  mysql:
    image: mysql:8.0
    container_name: mysql
    environment:
      MYSQL_ROOT_PASSWORD: root123456
    ports:
      - \"3306:3306\"
    volumes:
      - ./data:/var/lib/mysql
    restart: always"
            ;;
        3)
            compose_content="version: '3'
services:
  redis:
    image: redis:alpine
    container_name: redis
    ports:
      - \"6379:6379\"
    restart: always"
            ;;
        4)
            compose_content="version: '3'
services:
  portainer:
    image: portainer/portainer-ce
    container_name: portainer
    ports:
      - \"9000:9000\"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./data:/data
    restart: always"
            ;;
        5)
            echo -ne "${WHITE}输入工作目录 [/opt/docker-compose]: ${NC}"
            read -r work_dir
            work_dir="${work_dir:-/opt/docker-compose}"
            echo -ne "${WHITE}输入 compose 内容 (输入 END 结束):${NC}"
            echo ""
            compose_content=""
            while IFS= read -r line; do
                [[ "$line" == "END" ]] && break
                compose_content="${compose_content}${line}"$'\n'
            done
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            return 1
            ;;
    esac
    
    # 创建目录并写入文件
    pct exec "$vmid" -- bash -c "mkdir -p $work_dir && echo '$compose_content' > $work_dir/docker-compose.yml"
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}文件已创建: $work_dir/docker-compose.yml${NC}"
        echo ""
        echo -e "${YELLOW}文件内容:${NC}"
        pct exec "$vmid" -- cat "$work_dir/docker-compose.yml"
        echo ""
        echo -ne "${WHITE}是否立即启动? (y/N): ${NC}"
        read -r start_now
        if [[ "$start_now" =~ ^[Yy]$ ]]; then
            pct exec "$vmid" -- bash -c "cd $work_dir && docker-compose up -d"
            echo -e "${GREEN}服务已启动${NC}"
        fi
    else
        echo -e "${RED}文件创建失败${NC}"
        return 1
    fi
}

# Docker 镜像源选择菜单
lxc_docker_mirror_menu() {
    local vmid="$1"
    
    if [[ -z "$vmid" ]]; then
        echo -e "${RED}错误: 请指定容器 ID${NC}"
        return 1
    fi
    
    while true; do
        echo ""
        echo -e "${WHITE}═══════════════════════════════════════${NC}"
        echo -e "${BOLD}      Docker 镜像源选择${NC}"
        echo -e "${WHITE}═══════════════════════════════════════${NC}"
        echo ""
        echo -e "  ${GREEN}[1]${NC} DaoCloud (推荐)"
        echo -e "  ${GREEN}[2]${NC} 阿里云"
        echo -e "  ${GREEN}[3]${NC} 腾讯云"
        echo -e "  ${GREEN}[4]${NC} 华为云"
        echo -e "  ${GREEN}[5]${NC} 网易"
        echo -e "  ${GREEN}[6]${NC} 中科大"
        echo -e "  ${GREEN}[0]${NC} 返回上级"
        echo ""
        echo -ne "${WHITE}请选择 [0-6]: ${NC}"
        read -r choice
        
        case "$choice" in
            1)
                lxc_set_docker_mirror "$vmid" "https://docker.m.daocloud.io"
                ;;
            2)
                lxc_set_docker_mirror "$vmid" "https://registry.cn-hangzhou.aliyuncs.com"
                ;;
            3)
                lxc_set_docker_mirror "$vmid" "https://mirror.ccs.tencentyun.com"
                ;;
            4)
                lxc_set_docker_mirror "$vmid" "https://mirrors.huaweicloud.com"
                ;;
            5)
                lxc_set_docker_mirror "$vmid" "https://hub-mirror.c.163.com"
                ;;
            6)
                lxc_set_docker_mirror "$vmid" "https://docker.mirrors.ustc.edu.cn"
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

# 设置 Docker 镜像源
lxc_set_docker_mirror() {
    local vmid="$1"
    local mirror="$2"
    
    if [[ -z "$vmid" ]] || [[ -z "$mirror" ]]; then
        echo -e "${RED}错误: 参数不完整${NC}"
        return 1
    fi
    
    echo -e "${GREEN}正在为容器 $vmid 配置 Docker 镜像源...${NC}"
    
    # 创建 docker 目录并写入配置
    pct exec "$vmid" -- bash -c "mkdir -p /etc/docker && cat > /etc/docker/daemon.json << EOF
{
  \"registry-mirrors\": [\"$mirror\"]
}
EOF"
    
    # 重启 Docker 服务
    pct exec "$vmid" -- systemctl daemon-reload
    pct exec "$vmid" -- systemctl restart docker
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Docker 镜像源已配置: $mirror${NC}"
    else
        echo -e "${RED}配置失败${NC}"
        return 1
    fi
}

# Docker 容器管理菜单
lxc_docker_container_menu() {
    local vmid="$1"
    
    if [[ -z "$vmid" ]]; then
        echo -e "${RED}错误: 请指定容器 ID${NC}"
        return 1
    fi
    
    while true; do
        echo ""
        echo -e "${WHITE}═══════════════════════════════════════${NC}"
        echo -e "${BOLD}      Docker 容器管理${NC}"
        echo -e "${WHITE}═══════════════════════════════════════${NC}"
        echo ""
        echo -e "  ${GREEN}[1]${NC} 搜索 Docker 镜像"
        echo -e "  ${GREEN}[2]${NC} 拉取 Docker 镜像"
        echo -e "  ${GREEN}[3]${NC} 查看本地镜像"
        echo -e "  ${GREEN}[4]${NC} 运行 Docker 容器"
        echo -e "  ${GREEN}[5]${NC} 查看运行中的容器"
        echo -e "  ${GREEN}[6]${NC} 查看所有容器"
        echo -e "  ${GREEN}[0]${NC} 返回上级"
        echo ""
        echo -ne "${WHITE}请选择 [0-6]: ${NC}"
        read -r choice
        
        case "$choice" in
            1)
                lxc_docker_search "$vmid"
                ;;
            2)
                lxc_docker_pull "$vmid"
                ;;
            3)
                lxc_docker_images "$vmid"
                ;;
            4)
                lxc_docker_run "$vmid"
                ;;
            5)
                lxc_docker_ps "$vmid"
                ;;
            6)
                lxc_docker_ps_all "$vmid"
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

# 搜索 Docker 镜像
lxc_docker_search() {
    local vmid="$1"
    
    echo ""
    echo -e "${WHITE}═══════════════════════════════════════${NC}"
    echo -e "${BOLD}      Docker 镜像搜索${NC}"
    echo -e "${WHITE}═══════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${GREEN}[1]${NC} 热门镜像推荐"
    echo -e "  ${GREEN}[2]${NC} 模糊搜索镜像"
    echo -e "  ${GREEN}[0]${NC} 返回上级"
    echo ""
    echo -ne "${WHITE}请选择 [0-2]: ${NC}"
    read -r search_choice
    
    case "$search_choice" in
        1)
            lxc_docker_popular_images "$vmid"
            ;;
        2)
            lxc_docker_fuzzy_search "$vmid"
            ;;
        0)
            return 0
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            ;;
    esac
}

# 热门镜像推荐列表
lxc_docker_popular_images() {
    local vmid="$1"
    
    echo ""
    echo -e "${GREEN}热门镜像推荐:${NC}"
    echo ""
    echo -e "${YELLOW}【系统/基础】${NC}"
    echo "  alpine          - 轻量级 Linux (5MB)"
    echo "  debian          - Debian 系统"
    echo "  ubuntu          - Ubuntu 系统"
    echo "  centos          - CentOS 系统"
    echo ""
    echo -e "${YELLOW}【Web 服务器】${NC}"
    echo "  nginx           - Nginx 服务器"
    echo "  nginx:alpine    - Nginx 轻量版"
    echo "  apache          - Apache 服务器"
    echo "  caddy           - Caddy 服务器"
    echo ""
    echo -e "${YELLOW}【数据库】${NC}"
    echo "  mysql           - MySQL 数据库"
    echo "  mysql:8.0       - MySQL 8.0"
    echo "  mariadb         - MariaDB 数据库"
    echo "  postgres        - PostgreSQL 数据库"
    echo "  redis           - Redis 缓存"
    echo "  mongodb         - MongoDB 数据库"
    echo ""
    echo -e "${YELLOW}【面板/工具】${NC}"
    echo "  portainer/portainer-ce    - Docker 管理面板"
    echo "  whyour/qinglong           - 青龙面板"
    echo "  gdy666/lucky              - Lucky 大吉"
    echo "  hysteria/fatedier-alist - Alist 文件列表"
    echo "  xhofe/alist              - Alist 文件列表"
    echo ""
    echo -e "${YELLOW}【下载工具】${NC}"
    echo "  deluge          - Deluge 下载器"
    echo "  transmission    - Transmission 下载器"
    echo "  qbittorrent     - qBittorrent 下载器"
    echo ""
    echo -e "${YELLOW}【媒体服务】${NC}"
    echo "  jellyfin        - Jellyfin 媒体服务器"
    echo "  emby            - Emby 媒体服务器"
    echo "  plexinc/pms-docker - Plex 媒体服务器"
    echo ""
    echo -e "${YELLOW}【开发工具】${NC}"
    echo "  node            - Node.js 环境"
    echo "  python          - Python 环境"
    echo "  golang          - Go 语言环境"
    echo "  gitlab/gitlab-ce - GitLab 代码仓库"
    echo "  gitea/gitea     - Gitea 轻量 Git 服务"
    echo ""
    echo -ne "${WHITE}输入镜像名拉取 (回车跳过): ${NC}"
    read -r image
    if [[ -n "$image" ]]; then
        echo -e "${GREEN}正在拉取镜像: $image${NC}"
        pct exec "$vmid" -- docker pull "$image"
    fi
}

# 模糊搜索镜像
lxc_docker_fuzzy_search() {
    local vmid="$1"
    
    echo ""
    echo -ne "${WHITE}请输入搜索关键词: ${NC}"
    read -r keyword
    
    if [[ -z "$keyword" ]]; then
        echo -e "${RED}错误: 请输入搜索关键词${NC}"
        return 1
    fi
    
    # 预设镜像库模糊匹配
    local images=(
        "nginx:alpine" "nginx:latest" "apache" "caddy"
        "mysql:8.0" "mysql:latest" "mariadb" "postgres" "redis:alpine" "mongodb"
        "portainer/portainer-ce" "whyour/qinglong" "gdy666/lucky" "xhofe/alist"
        "jellyfin/jellyfin" "emby/embyserver" "linuxserver/plex"
        "deluge" "linuxserver/transmission" "linuxserver/qbittorrent"
        "node:20-alpine" "python:3.12-alpine" "golang:1.21-alpine"
        "gitlab/gitlab-ce" "gitea/gitea"
        "alpine" "debian:12" "ubuntu:22.04" "centos:7"
        "nextcloud" "wordpress" "gitlab/gitlab-runner"
    )
    
    echo ""
    echo -e "${GREEN}匹配结果:${NC}"
    local found=0
    for img in "${images[@]}"; do
        if [[ "$img" == *"$keyword"* ]]; then
            echo "  $img"
            found=1
        fi
    done
    
    if [[ $found -eq 0 ]]; then
        echo -e "${YELLOW}未找到匹配镜像，请使用完整镜像名${NC}"
    fi
    
    echo ""
    echo -ne "${WHITE}输入镜像名拉取 (回车跳过): ${NC}"
    read -r image
    if [[ -n "$image" ]]; then
        echo -e "${GREEN}正在拉取镜像: $image${NC}"
        pct exec "$vmid" -- docker pull "$image"
    fi
}

# 拉取 Docker 镜像
lxc_docker_pull() {
    local vmid="$1"
    
    echo ""
    echo -ne "${WHITE}请输入镜像名称 (如 nginx:alpine): ${NC}"
    read -r image
    
    if [[ -z "$image" ]]; then
        echo -e "${RED}错误: 请输入镜像名称${NC}"
        return 1
    fi
    
    echo -e "${GREEN}正在拉取镜像: $image${NC}"
    pct exec "$vmid" -- docker pull "$image"
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}镜像拉取完成${NC}"
    else
        echo -e "${RED}镜像拉取失败${NC}"
        return 1
    fi
}

# 查看本地镜像
lxc_docker_images() {
    local vmid="$1"
    
    echo ""
    echo -e "${GREEN}本地镜像列表:${NC}"
    pct exec "$vmid" -- docker images
}

# 运行 Docker 容器
lxc_docker_run() {
    local vmid="$1"
    
    echo ""
    echo -ne "${WHITE}请输入镜像名称: ${NC}"
    read -r image
    
    if [[ -z "$image" ]]; then
        echo -e "${RED}错误: 请输入镜像名称${NC}"
        return 1
    fi
    
    echo -ne "${WHITE}请输入容器名称 (可选): ${NC}"
    read -r name
    
    echo -ne "${WHITE}请输入端口映射 (如 8080:80, 留空跳过): ${NC}"
    read -r port
    
    echo -ne "${WHITE}是否后台运行? (Y/n): ${NC}"
    read -r detach
    local detach_flag="-d"
    if [[ "$detach" =~ ^[Nn]$ ]]; then
        detach_flag=""
    fi
    
    local cmd="docker run $detach_flag"
    [[ -n "$name" ]] && cmd="$cmd --name $name"
    [[ -n "$port" ]] && cmd="$cmd -p $port"
    cmd="$cmd $image"
    
    echo -e "${GREEN}执行命令: $cmd${NC}"
    pct exec "$vmid" -- bash -c "$cmd"
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}容器启动成功${NC}"
    else
        echo -e "${RED}容器启动失败${NC}"
        return 1
    fi
}

# 查看运行中的容器
lxc_docker_ps() {
    local vmid="$1"
    
    echo ""
    echo -e "${GREEN}运行中的容器:${NC}"
    pct exec "$vmid" -- docker ps
}

# 查看所有容器
lxc_docker_ps_all() {
    local vmid="$1"
    
    echo ""
    echo -e "${GREEN}所有容器:${NC}"
    pct exec "$vmid" -- docker ps -a
}

# 软件安装菜单
lxc_software_menu() {
    local vmid="$1"
    
    if [[ -z "$vmid" ]]; then
        echo -e "${RED}错误: 请指定容器 ID${NC}"
        return 1
    fi
    
    while true; do
        echo ""
        echo -e "${WHITE}═══════════════════════════════════════${NC}"
        echo -e "${BOLD}      容器 $vmid 软件安装${NC}"
        echo -e "${WHITE}═══════════════════════════════════════${NC}"
        echo ""
        echo -e "  ${GREEN}[1]${NC} 安装 Docker"
        echo -e "  ${GREEN}[2]${NC} 安装 Docker Compose"
        echo -e "  ${GREEN}[3]${NC} Docker 换源"
        echo -e "  ${GREEN}[4]${NC} Docker 容器管理"
        echo -e "  ${GREEN}[0]${NC} 返回上级"
        echo ""
        echo -ne "${WHITE}请选择 [0-4]: ${NC}"
        read -r choice
        
        case "$choice" in
            1)
                lxc_install_docker "$vmid"
                ;;
            2)
                lxc_install_docker_compose "$vmid"
                ;;
            3)
                lxc_docker_mirror_menu "$vmid"
                ;;
            4)
                lxc_docker_container_menu "$vmid"
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

# 显示 LXC 帮助
lxc_help() {
    echo -e "${BLUE}LXC 容器管理命令:${NC}"
    echo "  --list                     列出所有容器"
    echo "  --create <ID> <名称> [内存] [核心] [磁盘]"
    echo "                             创建新容器"
    echo "  --start <ID>               启动容器"
    echo "  --stop <ID>                停止容器"
    echo "  --restart <ID>             重启容器"
    echo "  --delete <ID> [-f]         删除容器 (-f 强制删除)"
    echo "  --console <ID>             进入容器控制台"
    echo "  --install-docker <ID>      安装 Docker"
    echo "  --install-compose <ID>     安装 Docker Compose"
    echo "  --info <ID>                显示容器详情"
}

# LXC 模块入口
lxc_main() {
    case "${1:-}" in
        --list|-l)
            lxc_list
            ;;
        --create|-c)
            lxc_create "$2" "$3" "$4" "$5" "$6"
            ;;
        --start)
            lxc_start "$2"
            ;;
        --stop)
            lxc_stop "$2"
            ;;
        --restart)
            lxc_restart "$2"
            ;;
        --delete|-d)
            lxc_delete "$2" "$3"
            ;;
        --console)
            lxc_console "$2"
            ;;
        --install-docker)
            lxc_install_docker "$2"
            ;;
        --install-compose)
            lxc_install_docker_compose "$2"
            ;;
        --info|-i)
            lxc_info "$2"
            ;;
        --help|-h)
            lxc_help
            ;;
        *)
            echo -e "${RED}错误: 未知 LXC 命令${NC}"
            lxc_help
            return 1
            ;;
    esac
}

# LXC 模块交互式菜单
lxc_interactive() {
    while true; do
        echo ""
        echo -e "${WHITE}═══════════════════════════════════════${NC}"
        echo -e "${BOLD}          LXC 容器管理${NC}"
        echo -e "${WHITE}═══════════════════════════════════════${NC}"
        echo ""
        echo -e "  ${GREEN}[1]${NC} 列出所有容器"
        echo -e "  ${GREEN}[2]${NC} 创建容器"
        echo -e "  ${GREEN}[3]${NC} 启动容器"
        echo -e "  ${GREEN}[4]${NC} 停止容器"
        echo -e "  ${GREEN}[5]${NC} 重启容器"
        echo -e "  ${GREEN}[6]${NC} 删除容器"
        echo -e "  ${GREEN}[7]${NC} 软件安装"
        echo -e "  ${GREEN}[8]${NC} 容器详情"
        echo -e "  ${GREEN}[0]${NC} 返回主菜单"
        echo ""
        echo -ne "${WHITE}请选择 [0-8]: ${NC}"
        read -r choice
        
        case "$choice" in
            1)
                lxc_list
                ;;
            2)
                echo -ne "请输入容器 ID: "
                read -r vmid
                echo -ne "请输入主机名: "
                read -r hostname
                echo -ne "内存 (MB) [2048]: "
                read -r memory
                echo -ne "核心数 [2]: "
                read -r cores
                echo -ne "磁盘大小 (GB) [20]: "
                read -r disk
                lxc_create "$vmid" "$hostname" "${memory:-2048}" "${cores:-2}" "${disk:-20}"
                ;;
            3)
                lxc_list
                echo -ne "请输入容器 ID: "
                read -r vmid
                lxc_start "$vmid"
                ;;
            4)
                lxc_list
                echo -ne "请输入容器 ID: "
                read -r vmid
                lxc_stop "$vmid"
                ;;
            5)
                lxc_list
                echo -ne "请输入容器 ID: "
                read -r vmid
                lxc_restart "$vmid"
                ;;
            6)
                lxc_list
                echo -ne "请输入容器 ID: "
                read -r vmid
                lxc_delete "$vmid"
                ;;
            7)
                lxc_list
                echo -ne "请输入容器 ID: "
                read -r vmid
                lxc_software_menu "$vmid"
                ;;
            8)
                lxc_list
                echo -ne "请输入容器 ID: "
                read -r vmid
                lxc_info "$vmid"
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
