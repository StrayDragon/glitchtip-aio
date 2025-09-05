#!/bin/bash

# Glitchtip AIO 优化版管理脚本
# 基于 glitchtip/glitchtip:v5.1 + 阿里源 + 北京地区镜像源

CONTAINER_NAME="glitchtip-aio"
IMAGE_NAME="glitchtip-aio-optimized"
DOCKERFILE="Dockerfile.optimized"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
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

print_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                 🛠️  Glitchtip AIO 管理脚本                     ║"
    echo "║              基于 glitchtip/glitchtip:v5.1                   ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# 显示帮助信息
show_help() {
    print_banner
    echo "📚 ${CYAN}使用方法:${NC}"
    echo "   $0 [命令]"
    echo ""
    echo "🔧 ${CYAN}可用命令:${NC}"
    echo "   start        - 启动 Glitchtip AIO 服务"
    echo "   stop         - 停止 Glitchtip AIO 服务"
    echo "   restart      - 重启 Glitchtip AIO 服务"
    echo "   logs         - 查看服务日志"
    echo "   status       - 查看服务状态"
    echo "   rebuild      - 重新构建镜像并重启服务"
    echo "   update       - 更新到最新版本并重启"
    echo "   clean        - 清理容器和镜像"
    echo "   backup       - 备份数据库"
    echo "   restore      - 恢复数据库"
    echo "   shell        - 进入容器 shell"
    echo "   psql         - 进入 PostgreSQL"
    echo "   redis        - 进入 Redis CLI"
    echo "   help         - 显示此帮助信息"
    echo ""
    echo "📖 ${CYAN}示例:${NC}"
    echo "   $0 start"
    echo "   $0 logs"
    echo "   $0 rebuild"
    echo ""
    echo "💡 ${CYAN}提示:${NC}"
    echo "   首次部署请使用: ./deploy-optimized.sh"
    echo "   日常管理使用此脚本即可"
}

# 检查容器是否存在
check_container_exists() {
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_error "容器 ${CONTAINER_NAME} 不存在"
        print_info "请先使用 ./deploy-optimized.sh 进行部署"
        return 1
    fi
    return 0
}

# 检查容器是否运行
check_container_running() {
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_warning "容器 ${CONTAINER_NAME} 未运行"
        return 1
    fi
    return 0
}

# 启动服务
start_service() {
    print_step "启动 Glitchtip AIO 服务..."
    
    if check_container_running; then
        print_warning "服务已经在运行"
        return 0
    fi
    
    if ! check_container_exists; then
        return 1
    fi
    
    print_info "🚀 启动容器..."
    if docker start ${CONTAINER_NAME}; then
        print_success "✅ 服务启动成功"
        
        # 等待服务启动
        echo "   ⏳ 等待服务启动..."
        for i in {1..60}; do
            if curl -f http://localhost:8000/_health/ &>/dev/null; then
                print_success "✅ 服务已就绪"
                break
            fi
            echo -n "."
            sleep 1
        done
        echo ""
        
        show_access_summary
    else
        print_error "❌ 服务启动失败"
        return 1
    fi
}

# 停止服务
stop_service() {
    print_step "停止 Glitchtip AIO 服务..."
    
    if ! check_container_exists; then
        return 1
    fi
    
    if ! check_container_running; then
        print_info "服务已经停止"
        return 0
    fi
    
    print_info "🛑 停止容器..."
    if docker stop ${CONTAINER_NAME}; then
        print_success "✅ 服务停止成功"
    else
        print_error "❌ 服务停止失败"
        return 1
    fi
}

# 重启服务
restart_service() {
    print_step "重启 Glitchtip AIO 服务..."
    
    if ! check_container_exists; then
        return 1
    fi
    
    print_info "🔄 重启容器..."
    if docker restart ${CONTAINER_NAME}; then
        print_success "✅ 服务重启成功"
        
        # 等待服务启动
        echo "   ⏳ 等待服务启动..."
        for i in {1..60}; do
            if curl -f http://localhost:8000/_health/ &>/dev/null; then
                print_success "✅ 服务已就绪"
                break
            fi
            echo -n "."
            sleep 1
        done
        echo ""
        
        show_access_summary
    else
        print_error "❌ 服务重启失败"
        return 1
    fi
}

# 查看日志
show_logs() {
    print_step "显示 Glitchtip AIO 服务日志..."
    print_info "📜 按 Ctrl+C 退出日志查看"
    echo ""
    
    if ! check_container_exists; then
        return 1
    fi
    
    # 显示最近的日志
    if ! check_container_running; then
        print_warning "容器未运行，显示最后 50 行日志"
        docker logs --tail 50 ${CONTAINER_NAME}
        return 0
    fi
    
    # 实时显示日志
    docker logs -f ${CONTAINER_NAME}
}

# 查看状态
show_status() {
    print_step "Glitchtip AIO 服务状态..."
    echo ""
    
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_error "❌ 容器不存在"
        echo "   请先运行 ./deploy-optimized.sh 进行部署"
        return 1
    fi
    
    # 显示容器基本信息
    echo "📦 ${CYAN}容器信息:${NC}"
    docker ps -a --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    
    # 检查运行状态
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_success "✅ 容器正在运行"
        
        # 显示健康状态
        HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' ${CONTAINER_NAME})
        echo "🏥 健康状态: $HEALTH_STATUS"
        
        # 检查服务健康状态
        echo ""
        echo "🔍 ${CYAN}服务状态:${NC}"
        if curl -f http://localhost:8000/_health/ &>/dev/null; then
            print_success "✅ Web 服务正常"
            HEALTH_RESPONSE=$(curl -s http://localhost:8000/_health/)
            echo "   $HEALTH_RESPONSE"
        else
            print_warning "⚠️  Web 服务无响应"
        fi
        
        # 检查数据库
        if docker exec ${CONTAINER_NAME} nc -z localhost 5432 &>/dev/null; then
            print_success "✅ PostgreSQL 正常"
        else
            print_warning "⚠️  PostgreSQL 异常"
        fi
        
        # 检查 Redis
        if docker exec ${CONTAINER_NAME} nc -z localhost 6379 &>/dev/null; then
            print_success "✅ Redis 正常"
        else
            print_warning "⚠️  Redis 异常"
        fi
        
        # 显示资源使用情况
        echo ""
        echo "📊 ${CYAN}资源使用:${NC}"
        docker stats --no-stream ${CONTAINER_NAME} --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
        
        # 显示进程状态
        echo ""
        echo "🔄 ${CYAN}进程状态:${NC}"
        docker exec ${CONTAINER_NAME} supervisorctl status 2>/dev/null || echo "   无法获取进程状态"
        
    else
        print_warning "⚠️  容器已停止"
    fi
    
    echo ""
    show_access_summary
}

# 重新构建镜像
rebuild_service() {
    print_step "重新构建 Glitchtip AIO 镜像..."
    
    print_warning "⚠️  这将停止当前服务并重新构建镜像"
    read -p "确定要继续吗？(y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "操作已取消"
        return 0
    fi
    
    # 停止现有容器
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_info "🛑 停止现有容器..."
        docker stop ${CONTAINER_NAME}
    fi
    
    # 删除现有容器
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_info "🗑️  删除现有容器..."
        docker rm ${CONTAINER_NAME}
    fi
    
    # 构建新镜像
    print_info "🔨 构建新镜像..."
    if docker build -f ${DOCKERFILE} -t ${IMAGE_NAME} .; then
        print_success "✅ 镜像构建成功"
        
        # 重新运行容器
        print_info "🚀 启动新容器..."
        SECRET_KEY=$(openssl rand -hex 32)
        if docker run -d \
            --name ${CONTAINER_NAME} \
            -p "8000:8000" \
            -p "5432:5432" \
            -p "6379:6379" \
            -e "SECRET_KEY=${SECRET_KEY}" \
            -e "DEBUG=false" \
            --restart unless-stopped \
            ${IMAGE_NAME}; then
            
            print_success "✅ 容器启动成功"
            
            # 等待服务启动
            echo "   ⏳ 等待服务启动..."
            for i in {1..60}; do
                if curl -f http://localhost:8000/_health/ &>/dev/null; then
                    print_success "✅ 服务已就绪"
                    break
                fi
                echo -n "."
                sleep 1
            done
            echo ""
            
            show_access_summary
        else
            print_error "❌ 容器启动失败"
            return 1
        fi
    else
        print_error "❌ 镜像构建失败"
        return 1
    fi
}

# 更新服务
update_service() {
    print_step "更新 Glitchtip AIO 到最新版本..."
    
    print_warning "⚠️  这将拉取最新的基础镜像并重新构建"
    read -p "确定要继续吗？(y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "操作已取消"
        return 0
    fi
    
    # 拉取最新基础镜像
    print_info "📥 拉取最新基础镜像..."
    docker pull glitchtip/glitchtip:v5.1
    
    # 重新构建
    rebuild_service
}

# 清理容器和镜像
clean_all() {
    print_step "清理 Glitchtip AIO 容器和镜像..."
    
    print_warning "⚠️  这将删除所有容器、镜像和数据！"
    print_warning "⚠️  此操作不可恢复！"
    read -p "确定要继续吗？(y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "操作已取消"
        return 0
    fi
    
    # 停止并删除容器
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_info "🛑 停止并删除容器..."
        docker stop ${CONTAINER_NAME} 2>/dev/null || true
        docker rm ${CONTAINER_NAME} 2>/dev/null || true
        print_success "✅ 容器已删除"
    fi
    
    # 删除镜像
    if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE_NAME}:latest$"; then
        print_info "🗑️  删除镜像..."
        docker rmi ${IMAGE_NAME}:latest 2>/dev/null || true
        print_success "✅ 镜像已删除"
    fi
    
    # 清理悬空镜像
    print_info "🧹 清理悬空镜像..."
    docker image prune -f
    
    print_success "✅ 清理完成"
}

# 备份数据库
backup_database() {
    print_step "备份数据库..."
    
    if ! check_container_running; then
        print_error "容器未运行，无法备份"
        return 1
    fi
    
    BACKUP_FILE="glitchtip-backup-$(date +%Y%m%d-%H%M%S).sql"
    
    print_info "💾 备份数据库到 ${BACKUP_FILE}..."
    
    if docker exec ${CONTAINER_NAME} pg_dump -U postgres > ${BACKUP_FILE}; then
        print_success "✅ 数据库备份成功"
        echo "   备份文件: ${BACKUP_FILE}"
        echo "   文件大小: $(ls -lh ${BACKUP_FILE} | awk '{print $5}')"
    else
        print_error "❌ 数据库备份失败"
        return 1
    fi
}

# 恢复数据库
restore_database() {
    print_step "恢复数据库..."
    
    if ! check_container_running; then
        print_error "容器未运行，无法恢复"
        return 1
    fi
    
    # 查找备份文件
    BACKUP_FILES=(*.sql)
    if [ ${#BACKUP_FILES[@]} -eq 0 ]; then
        print_error "没有找到备份文件 (.sql)"
        return 1
    fi
    
    echo "📋 找到以下备份文件:"
    select BACKUP_FILE in "${BACKUP_FILES[@]}"; do
        if [ -n "$BACKUP_FILE" ]; then
            break
        fi
    done
    
    print_warning "⚠️  恢复数据库将覆盖现有数据"
    read -p "确定要继续吗？(y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "操作已取消"
        return 0
    fi
    
    print_info "🔄 恢复数据库从 ${BACKUP_FILE}..."
    
    if docker exec -i ${CONTAINER_NAME} psql -U postgres < ${BACKUP_FILE}; then
        print_success "✅ 数据库恢复成功"
    else
        print_error "❌ 数据库恢复失败"
        return 1
    fi
}

# 进入容器 shell
enter_shell() {
    print_step "进入容器 shell..."
    
    if ! check_container_running; then
        print_error "容器未运行"
        return 1
    fi
    
    print_info "🐚 进入容器 shell..."
    docker exec -it ${CONTAINER_NAME} bash
}

# 进入 PostgreSQL
enter_postgres() {
    print_step "进入 PostgreSQL..."
    
    if ! check_container_running; then
        print_error "容器未运行"
        return 1
    fi
    
    print_info "🗄️  进入 PostgreSQL..."
    docker exec -it ${CONTAINER_NAME} psql -U postgres
}

# 进入 Redis CLI
enter_redis() {
    print_step "进入 Redis CLI..."
    
    if ! check_container_running; then
        print_error "容器未运行"
        return 1
    fi
    
    print_info "🔴 进入 Redis CLI..."
    docker exec -it ${CONTAINER_NAME} redis-cli
}

# 显示访问信息摘要
show_access_summary() {
    echo ""
    echo "🌐 ${CYAN}访问信息:${NC}"
    echo "   📱 Web 应用: http://localhost:8000"
    echo "   ❤️  健康检查: http://localhost:8000/_health/"
    echo "   🗄️  PostgreSQL: localhost:5432"
    echo "   🔴 Redis: localhost:6379"
    echo ""
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
        "rebuild")
            rebuild_service
            ;;
        "update")
            update_service
            ;;
        "clean")
            clean_all
            ;;
        "backup")
            backup_database
            ;;
        "restore")
            restore_database
            ;;
        "shell")
            enter_shell
            ;;
        "psql")
            enter_postgres
            ;;
        "redis")
            enter_redis
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