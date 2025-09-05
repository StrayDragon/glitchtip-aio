#!/bin/bash

# Glitchtip AIO 管理脚本
# 使用方法: ./manage.sh [start|stop|restart|logs|status|clean]

CONTAINER_NAME="glitchtip-aio"
IMAGE_NAME="glitchtip-aio"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# 显示帮助信息
show_help() {
    echo "Glitchtip AIO 管理脚本"
    echo "使用方法: $0 [命令]"
    echo ""
    echo "可用命令:"
    echo "  start    - 启动 Glitchtip AIO 服务"
    echo "  stop     - 停止 Glitchtip AIO 服务"
    echo "  restart  - 重启 Glitchtip AIO 服务"
    echo "  logs     - 查看服务日志"
    echo "  status   - 查看服务状态"
    echo "  clean    - 清理容器和镜像"
    echo "  help     - 显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 start"
    echo "  $0 logs"
}

# 检查容器是否存在
check_container_exists() {
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_error "容器 ${CONTAINER_NAME} 不存在"
        return 1
    fi
    return 0
}

# 启动服务
start_service() {
    print_info "启动 Glitchtip AIO 服务..."
    
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_warning "服务已经在运行"
        return 0
    fi
    
    if check_container_exists; then
        docker start ${CONTAINER_NAME}
    else
        print_error "容器不存在，请先使用 ./deploy.sh 部署"
        return 1
    fi
    
    if [ $? -eq 0 ]; then
        print_success "服务启动成功"
        print_info "访问地址: http://localhost:8000"
    else
        print_error "服务启动失败"
        return 1
    fi
}

# 停止服务
stop_service() {
    print_info "停止 Glitchtip AIO 服务..."
    
    if ! check_container_exists; then
        return 1
    fi
    
    docker stop ${CONTAINER_NAME}
    
    if [ $? -eq 0 ]; then
        print_success "服务停止成功"
    else
        print_error "服务停止失败"
        return 1
    fi
}

# 重启服务
restart_service() {
    print_info "重启 Glitchtip AIO 服务..."
    
    if ! check_container_exists; then
        return 1
    fi
    
    docker restart ${CONTAINER_NAME}
    
    if [ $? -eq 0 ]; then
        print_success "服务重启成功"
        print_info "访问地址: http://localhost:8000"
    else
        print_error "服务重启失败"
        return 1
    fi
}

# 查看日志
show_logs() {
    print_info "显示 Glitchtip AIO 服务日志..."
    print_info "按 Ctrl+C 退出日志查看"
    
    if ! check_container_exists; then
        return 1
    fi
    
    docker logs -f ${CONTAINER_NAME}
}

# 查看状态
show_status() {
    print_info "Glitchtip AIO 服务状态:"
    echo "================================"
    
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_error "容器不存在"
        echo "请先运行 ./deploy.sh 进行部署"
        return 1
    fi
    
    # 显示容器状态
    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep ${CONTAINER_NAME}
    
    # 检查服务健康状态
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo ""
        print_info "健康检查:"
        if curl -f http://localhost:8000/_health/ &>/dev/null; then
            print_success "✅ 所有服务运行正常"
        else
            print_warning "⚠️  服务正在启动中，请稍候"
        fi
        
        echo ""
        print_info "资源使用情况:"
        docker stats --no-stream ${CONTAINER_NAME} --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
    fi
    
    echo ""
    print_info "访问信息:"
    echo "  Web 应用: http://localhost:8000"
    echo "  健康检查: http://localhost:8000/_health/"
    echo "  数据库: localhost:5432"
    echo "  Redis: localhost:6379"
}

# 清理容器和镜像
clean_all() {
    print_warning "这将删除所有容器和镜像，数据将丢失！"
    read -p "确定要继续吗？(y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "操作已取消"
        return 0
    fi
    
    print_info "清理 Glitchtip AIO 容器和镜像..."
    
    # 停止并删除容器
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker stop ${CONTAINER_NAME} 2>/dev/null || true
        docker rm ${CONTAINER_NAME} 2>/dev/null || true
        print_success "容器已删除"
    fi
    
    # 删除镜像
    if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE_NAME}:latest$"; then
        docker rmi ${IMAGE_NAME}:latest 2>/dev/null || true
        print_success "镜像已删除"
    fi
    
    print_success "清理完成"
}

# 主函数
main() {
    case "${1:-}" in
        "start")
            start_service
            ;;
        "stop")
            stop_service
            ;;
        "restart")
            restart_service
            ;;
        "logs")
            show_logs
            ;;
        "status")
            show_status
            ;;
        "clean")
            clean_all
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        "")
            print_error "请指定命令"
            echo "使用 '$0 help' 查看帮助"
            exit 1
            ;;
        *)
            print_error "未知命令: $1"
            echo "使用 '$0 help' 查看帮助"
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"