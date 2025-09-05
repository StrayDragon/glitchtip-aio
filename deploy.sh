#!/bin/bash

# Glitchtip AIO 一键部署脚本
# 使用方法: ./deploy.sh [端口] [域名]

set -e

# 默认配置
DEFAULT_PORT=8000
DEFAULT_DOMAIN="http://localhost:${DEFAULT_PORT}"

# 参数处理
PORT=${1:-$DEFAULT_PORT}
DOMAIN=${2:-$DEFAULT_DOMAIN}

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# 检查 Docker 是否已安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    print_success "Docker 已安装"
}

# 检查 Docker 是否运行
check_docker_running() {
    if ! docker info &> /dev/null; then
        print_error "Docker 服务未运行，请启动 Docker 服务"
        exit 1
    fi
    print_success "Docker 服务正在运行"
}

# 停止并删除现有容器
cleanup_existing() {
    if docker ps -a --format 'table {{.Names}}' | grep -q "glitchtip-aio"; then
        print_warning "发现现有的 Glitchtip AIO 容器，正在停止和删除..."
        docker stop glitchtip-aio 2>/dev/null || true
        docker rm glitchtip-aio 2>/dev/null || true
        print_success "现有容器已清理"
    fi
}

# 构建 Docker 镜像
build_image() {
    print_info "开始构建 Glitchtip AIO 镜像..."
    
    # 检查是否存在 Dockerfile
    if [ ! -f "Dockerfile" ]; then
        print_error "Dockerfile 不存在，请确保在正确的目录中运行此脚本"
        exit 1
    fi
    
    # 构建镜像
    if docker build -t glitchtip-aio .; then
        print_success "镜像构建成功"
    else
        print_error "镜像构建失败"
        exit 1
    fi
}

# 运行容器
run_container() {
    print_info "启动 Glitchtip AIO 容器..."
    
    # 生成随机密钥
    SECRET_KEY=$(openssl rand -hex 32)
    
    # 运行容器
    docker run -d \
        --name glitchtip-aio \
        -p "${PORT}:8000" \
        -p "5432:5432" \
        -p "6379:6379" \
        -e "SECRET_KEY=${SECRET_KEY}" \
        -e "PORT=${PORT}" \
        -e "GLITCHTIP_DOMAIN=${DOMAIN}" \
        -e "DEFAULT_FROM_EMAIL=glitchtip@${DOMAIN#http://}" \
        -e "DEBUG=false" \
        --restart unless-stopped \
        glitchtip-aio
    
    if [ $? -eq 0 ]; then
        print_success "容器启动成功"
    else
        print_error "容器启动失败"
        exit 1
    fi
}

# 等待服务启动
wait_for_services() {
    print_info "等待服务启动..."
    
    # 等待 30 秒让服务启动
    for i in {1..30}; do
        if curl -f "http://localhost:${PORT}/_health/" &>/dev/null; then
            print_success "所有服务已启动并运行正常"
            return 0
        fi
        echo -n "."
        sleep 1
    done
    
    echo
    print_warning "服务启动时间较长，请检查容器日志"
    return 1
}

# 显示访问信息
show_access_info() {
    echo
    echo "=========================================="
    echo -e "${GREEN}🎉 Glitchtip AIO 部署完成！${NC}"
    echo "=========================================="
    echo
    echo "🌐 访问地址:"
    echo "   Web 应用: ${DOMAIN}:${PORT}"
    echo "   健康检查: ${DOMAIN}:${PORT}/_health/"
    echo
    echo "🔌 端口映射:"
    echo "   Web 服务: ${PORT} -> 8000"
    echo "   PostgreSQL: 5432 -> 5432"
    echo "   Redis: 6379 -> 6379"
    echo
    echo "📊 数据库连接:"
    echo "   Host: localhost"
    echo "   Port: 5432"
    echo "   Database: postgres"
    echo "   Username: postgres"
    echo "   Password: postgres"
    echo
    echo "🗄️  Redis 连接:"
    echo "   Host: localhost"
    echo "   Port: 6379"
    echo
    echo "🔧 管理命令:"
    echo "   查看日志: docker logs -f glitchtip-aio"
    echo "   进入容器: docker exec -it glitchtip-aio bash"
    echo "   停止服务: docker stop glitchtip-aio"
    echo "   重启服务: docker restart glitchtip-aio"
    echo "   删除容器: docker rm -f glitchtip-aio"
    echo
    echo "⚠️  重要提醒:"
    echo "   1. 生产环境请修改默认密码"
    echo "   2. 建议配置 HTTPS"
    echo "   3. 定期备份数据"
    echo "=========================================="
}

# 主函数
main() {
    echo "🚀 Glitchtip AIO 一键部署脚本"
    echo "================================="
    echo "配置信息:"
    echo "  端口: ${PORT}"
    echo "  域名: ${DOMAIN}"
    echo "================================="
    echo
    
    # 执行部署步骤
    check_docker
    check_docker_running
    cleanup_existing
    build_image
    run_container
    wait_for_services
    show_access_info
}

# 捕获中断信号
trap 'print_error "部署被中断"; exit 1' INT TERM

# 运行主函数
main "$@"