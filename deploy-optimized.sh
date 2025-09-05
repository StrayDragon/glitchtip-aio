#!/bin/bash

# Glitchtip AIO 优化版部署脚本
# 基于 glitchtip/glitchtip:v5.1 + 阿里源 + 北京地区镜像源

set -e

# 默认配置
DEFAULT_PORT=8000
DEFAULT_DOMAIN="http://localhost:${DEFAULT_PORT}"
IMAGE_NAME="glitchtip-aio-optimized"
CONTAINER_NAME="glitchtip-aio"

# 参数处理
PORT=${1:-$DEFAULT_PORT}
DOMAIN=${2:-$DEFAULT_DOMAIN}

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                 🚀 Glitchtip AIO 部署脚本                      ║"
    echo "║          基于 glitchtip/glitchtip:v5.1 优化版                 ║"
    echo "║                阿里源 + 北京地区镜像源                         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# 检查 Docker 是否已安装
check_docker() {
    print_step "检查 Docker 环境..."
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker 未安装，请先安装 Docker"
        echo "安装命令："
        echo "  Ubuntu/Debian: curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh"
        echo "  CentOS/RHEL: yum install -y docker-ce docker-ce-cli containerd.io"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        print_error "Docker 服务未运行，请启动 Docker 服务"
        echo "启动命令："
        echo "  systemctl start docker"
        echo "  service docker start"
        exit 1
    fi
    
    print_success "✅ Docker 环境检查通过"
    echo "   Docker 版本: $(docker --version)"
}

# 检查网络连接
check_network() {
    print_step "检查网络连接..."
    
    # 检查 Docker Hub 连接
    if docker pull hello-world &>/dev/null; then
        print_success "✅ Docker Hub 连接正常"
    else
        print_warning "⚠️  Docker Hub 连接可能有问题，但继续尝试..."
    fi
}

# 停止并删除现有容器
cleanup_existing() {
    print_step "清理现有容器..."
    
    if docker ps -a --format 'table {{.Names}}' | grep -q "${CONTAINER_NAME}"; then
        print_warning "发现现有的 ${CONTAINER_NAME} 容器，正在停止和删除..."
        docker stop ${CONTAINER_NAME} 2>/dev/null || true
        docker rm ${CONTAINER_NAME} 2>/dev/null || true
        print_success "✅ 现有容器已清理"
    else
        print_info "ℹ️  没有发现现有容器"
    fi
}

# 检查端口占用
check_port() {
    print_step "检查端口占用..."
    
    if netstat -tulpn 2>/dev/null | grep -q ":${PORT}"; then
        print_warning "⚠️  端口 ${PORT} 已被占用"
        echo "   占用情况："
        netstat -tulpn 2>/dev/null | grep ":${PORT}" || echo "   无法获取详细信息"
        read -p "   是否继续？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "操作已取消"
            exit 0
        fi
    else
        print_success "✅ 端口 ${PORT} 可用"
    fi
}

# 构建 Docker 镜像
build_image() {
    print_step "构建 Glitchtip AIO 镜像..."
    
    # 检查是否存在 Dockerfile
    if [ ! -f "Dockerfile.optimized" ]; then
        print_error "Dockerfile.optimized 不存在，请确保在正确的目录中运行此脚本"
        exit 1
    fi
    
    print_info "📦 开始构建镜像（这可能需要几分钟）..."
    
    # 构建镜像，显示进度
    if docker build -f Dockerfile.optimized -t ${IMAGE_NAME} . --progress=plain; then
        print_success "✅ 镜像构建成功"
        echo "   镜像名称: ${IMAGE_NAME}"
        echo "   镜像大小: $(docker images ${IMAGE_NAME} --format "table {{.Size}}" | tail -n 1)"
    else
        print_error "❌ 镜像构建失败"
        echo "   请检查网络连接或 Dockerfile.optimized 文件"
        exit 1
    fi
}

# 运行容器
run_container() {
    print_step "启动 Glitchtip AIO 容器..."
    
    # 生成随机密钥
    SECRET_KEY=$(openssl rand -hex 32)
    
    print_info "🚀 启动容器..."
    
    # 运行容器
    if docker run -d \
        --name ${CONTAINER_NAME} \
        -p "${PORT}:8000" \
        -p "5432:5432" \
        -p "6379:6379" \
        -e "SECRET_KEY=${SECRET_KEY}" \
        -e "PORT=${PORT}" \
        -e "GLITCHTIP_DOMAIN=${DOMAIN}" \
        -e "DEFAULT_FROM_EMAIL=glitchtip@${DOMAIN#http://}" \
        -e "DEBUG=false" \
        --restart unless-stopped \
        ${IMAGE_NAME}; then
        
        print_success "✅ 容器启动成功"
        echo "   容器名称: ${CONTAINER_NAME}"
    else
        print_error "❌ 容器启动失败"
        exit 1
    fi
}

# 等待服务启动
wait_for_services() {
    print_step "等待服务启动..."
    
    echo "   📊 等待服务启动中（最多 2 分钟）..."
    
    # 等待 120 秒让服务启动
    for i in {1..120}; do
        if curl -f "http://localhost:${PORT}/_health/" &>/dev/null; then
            print_success "✅ 所有服务已启动并运行正常"
            return 0
        fi
        
        # 显示进度
        if [ $((i % 10)) -eq 0 ]; then
            echo -n "   "
        fi
        echo -n "."
        
        # 每 30 秒显示一次日志
        if [ $((i % 30)) -eq 0 ]; then
            echo ""
            print_info "📋 当前容器状态："
            docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        fi
        
        sleep 1
    done
    
    echo ""
    print_warning "⚠️  服务启动时间较长，请检查容器日志"
    echo "   查看日志命令: docker logs -f ${CONTAINER_NAME}"
    return 1
}

# 验证服务
verify_services() {
    print_step "验证服务状态..."
    
    echo "   🔍 正在验证各个服务..."
    
    # 检查容器状态
    CONTAINER_STATUS=$(docker ps --filter "name=${CONTAINER_NAME}" --format "{{.Status}}")
    if [[ $CONTAINER_STATUS == *"Up"* ]]; then
        print_success "✅ 容器运行正常"
        echo "   状态: $CONTAINER_STATUS"
    else
        print_error "❌ 容器状态异常"
        return 1
    fi
    
    # 检查健康状态
    HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' ${CONTAINER_NAME})
    if [ "$HEALTH_STATUS" = "healthy" ]; then
        print_success "✅ 容器健康状态良好"
    else
        print_warning "⚠️  容器健康状态: $HEALTH_STATUS"
    fi
    
    # 检查端口访问
    if curl -f "http://localhost:${PORT}/_health/" &>/dev/null; then
        print_success "✅ Web 服务可访问"
    else
        print_warning "⚠️  Web 服务暂时无法访问"
    fi
    
    # 检查数据库连接
    if docker exec ${CONTAINER_NAME} nc -z localhost 5432 &>/dev/null; then
        print_success "✅ PostgreSQL 服务运行正常"
    else
        print_warning "⚠️  PostgreSQL 服务可能有问题"
    fi
    
    # 检查 Redis 连接
    if docker exec ${CONTAINER_NAME} nc -z localhost 6379 &>/dev/null; then
        print_success "✅ Redis 服务运行正常"
    else
        print_warning "⚠️  Redis 服务可能有问题"
    fi
}

# 显示访问信息
show_access_info() {
    echo ""
    echo "🎉 ${GREEN}部署完成！Glitchtip AIO 已成功启动${NC}"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo ""
    echo "🌐 ${CYAN}访问地址:${NC}"
    echo "   📱 Web 应用: ${DOMAIN}:${PORT}"
    echo "   ❤️  健康检查: ${DOMAIN}:${PORT}/_health/"
    echo ""
    echo "🔌 ${CYAN}端口映射:${NC}"
    echo "   🌍 Web 服务: ${PORT} → 8000"
    echo "   🗄️  PostgreSQL: 5432 → 5432"
    echo "   🔴 Redis: 6379 → 6379"
    echo ""
    echo "📊 ${CYAN}数据库连接:${NC}"
    echo "   🏠 Host: localhost"
    echo "   🔌 Port: 5432"
    echo "   🗄️  Database: postgres"
    echo "   👤 Username: postgres"
    echo "   🔐 Password: postgres"
    echo ""
    echo "🔴 ${CYAN}Redis 连接:${NC}"
    echo "   🏠 Host: localhost"
    echo "   🔌 Port: 6379"
    echo ""
    echo "🔧 ${CYAN}管理命令:${NC}"
    echo "   📋 查看状态: ./manage.sh status"
    echo "   📜 查看日志: docker logs -f ${CONTAINER_NAME}"
    echo "   🐚 进入容器: docker exec -it ${CONTAINER_NAME} bash"
    echo "   ⏹️  停止服务: docker stop ${CONTAINER_NAME}"
    echo "   🔄 重启服务: docker restart ${CONTAINER_NAME}"
    echo "   🗑️  删除容器: docker rm -f ${CONTAINER_NAME}"
    echo ""
    echo "⚠️  ${YELLOW}重要提醒:${NC}"
    echo "   🔐 生产环境请修改默认数据库密码"
    echo "   🔒 建议配置 HTTPS 证书"
    echo "   💾 定期备份数据库数据"
    echo "   📊 监控服务器资源使用情况"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
}

# 显示快速开始指南
show_quick_start() {
    echo ""
    echo "🚀 ${CYAN}快速开始指南${NC}"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo ""
    echo "🎯 ${GREEN}常用命令:${NC}"
    echo "   ./manage.sh start    # 启动服务"
    echo "   ./manage.sh stop     # 停止服务"
    echo "   ./manage.sh restart  # 重启服务"
    echo "   ./manage.sh logs     # 查看日志"
    echo "   ./manage.sh status   # 查看状态"
    echo ""
    echo "📊 ${GREEN}数据库操作:${NC}"
    echo "   docker exec -it ${CONTAINER_NAME} psql -U postgres"
    echo "   docker exec ${CONTAINER_NAME} pg_dump -U postgres > backup.sql"
    echo "   docker exec -i ${CONTAINER_NAME} psql -U postgres < backup.sql"
    echo ""
    echo "🔴 ${GREEN}Redis 操作:${NC}"
    echo "   docker exec -it ${CONTAINER_NAME} redis-cli"
    echo "   docker exec ${CONTAINER_NAME} redis-cli FLUSHALL"
    echo ""
    echo "📝 ${GREEN}故障排除:${NC}"
    echo "   如果服务无法访问，请检查："
    echo "   1. 防火墙设置: sudo ufw status"
    echo "   2. 端口占用: netstat -tulpn | grep :${PORT}"
    echo "   3. 容器日志: docker logs ${CONTAINER_NAME}"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
}

# 主函数
main() {
    print_banner
    
    echo "📋 ${CYAN}部署配置:${NC}"
    echo "   🌐 域名: ${DOMAIN}"
    echo "   🔌 端口: ${PORT}"
    echo "   🏷️  镜像: ${IMAGE_NAME}"
    echo "   📦 容器: ${CONTAINER_NAME}"
    echo ""
    
    # 执行部署步骤
    check_docker
    check_network
    check_port
    cleanup_existing
    build_image
    run_container
    wait_for_services
    verify_services
    show_access_info
    show_quick_start
}

# 捕获中断信号
trap 'print_error "部署被中断"; exit 1' INT TERM

# 运行主函数
main "$@"