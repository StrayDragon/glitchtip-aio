#!/bin/bash
# 定时重启脚本 - 每周一临晨3:01执行
# 智能判断是否需要重启web和celery服务

set -euo pipefail

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SCHEDULED-RESTART: $*" | tee -a /var/log/supervisor/scheduled-restart.log
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SCHEDULED-RESTART ERROR: $*" | tee -a /var/log/supervisor/scheduled-restart.log >&2
}

# 检查PostgreSQL连接
check_postgresql() {
    log "检查PostgreSQL连接..."

    # 设置数据库连接参数
    export PGPASSWORD="${DB_PASSWORD:-postgres}"

    # 检查PostgreSQL连接和基本查询
    if timeout 10 psql -h localhost -U postgres -d postgres -c "SELECT 1;" >/dev/null 2>&1; then
        log "✓ PostgreSQL连接正常"
        return 0
    else
        error "✗ PostgreSQL连接失败"
        return 1
    fi
}

# 检查Redis连接
check_redis() {
    log "检查Redis连接..."

    if timeout 10 redis-cli -h localhost ping 2>/dev/null | grep -q "PONG"; then
        log "✓ Redis连接正常"
        return 0
    else
        error "✗ Redis连接失败"
        return 1
    fi
}

# 检查Django应用健康状态
check_django_health() {
    log "检查Django应用健康状态..."

    # 检查Django健康端点
    if timeout 10 curl -s -f http://localhost:8000/_health/ >/dev/null 2>&1; then
        log "✓ Django应用健康检查通过"
        return 0
    else
        error "✗ Django应用健康检查失败"
        return 1
    fi
}

# 检查Celery工作进程
check_celery_workers() {
    log "检查Celery工作进程状态..."

    # 检查Celery进程是否在运行
    if pgrep -f "celery.*worker" > /dev/null 2>&1; then
        local worker_pids=$(pgrep -f "celery.*worker" | wc -l)
        log "✓ Celery worker进程运行中 (${worker_pids} 个进程)"

        # 尝试连接检查，如果失败不影响总体判断
        if timeout 10 celery -A glitchtip inspect active --broker=redis://localhost:6379/0 2>/dev/null | grep -q "OK\|empty" 2>/dev/null; then
            local active_count=$(celery -A glitchtip inspect active --broker=redis://localhost:6379/0 2>/dev/null | grep -c "OK\|empty" 2>/dev/null || echo "1")
            log "✓ Celery worker响应正常 (${active_count} 个活跃)"
        else
            log "⚠ Celery worker连接检查超时，但进程运行正常"
        fi
        return 0
    else
        error "✗ Celery worker进程未运行"
        return 1
    fi
}

# 检查系统资源
check_system_resources() {
    log "检查系统资源使用情况..."

    # 检查内存使用率
    local mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}' || echo "0")
    if [ "$mem_usage" -gt 90 ]; then
        log "⚠ 内存使用率过高: ${mem_usage}%"
    fi

    # 检查磁盘使用率
    local disk_usage=$(df / | awk 'NR==2{print $5}' | sed 's/%//' || echo "0")
    if [ "$disk_usage" -gt 85 ]; then
        log "⚠ 磁盘使用率过高: ${disk_usage}%"
    fi

    log "✓ 系统资源检查完成 - 内存: ${mem_usage}%, 磁盘: ${disk_usage}%"
    return 0
}

# 重启服务函数
restart_service() {
    local service_name="$1"
    log "重启服务: ${service_name}..."

    if supervisorctl restart "${service_name}"; then
        log "✓ 服务 ${service_name} 重启成功"
        return 0
    else
        error "✗ 服务 ${service_name} 重启失败"
        return 1
    fi
}

# 等待服务启动完成
wait_for_service() {
    local service_name="$1"
    local max_wait="${2:-30}"
    local wait_count=0

    log "等待服务 ${service_name} 启动..."

    while [ $wait_count -lt $max_wait ]; do
        if supervisorctl status "${service_name}" | grep -q "RUNNING"; then
            log "✓ 服务 ${service_name} 已启动"
            return 0
        fi

        sleep 2
        wait_count=$((wait_count + 2))
    done

    error "✗ 服务 ${service_name} 启动超时"
    return 1
}

# 主执行逻辑
main() {
    log "=== 开始定时重启检查 $(date) ==="

    # 切换到工作目录
    cd /code

    # 设置环境变量
    export DATABASE_URL="${DATABASE_URL:-postgres://postgres:${DB_PASSWORD:-postgres}@localhost:5432/postgres}"
    export REDIS_URL="redis://localhost:6379/0"
    export CELERY_BROKER_URL="redis://localhost:6379/0"
    export CELERY_RESULT_BACKEND="redis://localhost:6379/0"
    export DJANGO_SETTINGS_MODULE="glitchtip.settings"

    # 健康检查标志
    local restart_needed=false
    local health_issues=()

    # 1. 检查基础服务健康状态
    log "开始健康检查..."

    if ! check_postgresql; then
        health_issues+=("PostgreSQL连接异常")
    fi

    if ! check_redis; then
        health_issues+=("Redis连接异常")
    fi

    # 如果基础服务有问题，不重启应用层服务
    if [ ${#health_issues[@]} -gt 0 ]; then
        error "检测到基础服务问题，跳过应用服务重启: ${health_issues[*]}"
        return 1
    fi

    # 2. 检查应用层服务健康状态
    local app_issues=()

    if ! check_django_health; then
        app_issues+=("Django应用健康检查失败")
    fi

    if ! check_celery_workers; then
        app_issues+=("Celery工作进程异常")
    fi

    # 3. 检查系统资源
    check_system_resources

    # 4. 智能判断是否需要重启
    if [ ${#app_issues[@]} -gt 0 ]; then
        restart_needed=true
        log "检测到应用服务问题，将执行重启: ${app_issues[*]}"
    else
        log "所有服务健康检查通过，执行预防性重启(每周例行维护)"
        restart_needed=true
    fi

    # 5. 执行重启操作
    if [ "$restart_needed" = true ]; then
        log "开始执行服务重启..."

        # 重启web服务
        restart_service "web"
        sleep 5
        wait_for_service "web" 60

        # 等待web服务完全启动后再重启celery
        sleep 10

        # 重启celery服务
        restart_service "celery"
        sleep 5
        wait_for_service "celery" 60

        # 最终验证
        log "执行重启后健康检查..."

        sleep 10

        if check_django_health && check_celery_workers; then
            log "✓ 所有服务重启后运行正常"
        else
            error "✗ 重启后仍有服务异常，请检查日志"
            return 1
        fi
    fi

    log "=== 定时重启检查完成 $(date) ==="
    return 0
}

# 执行主函数
main "$@" 2>&1 | tee -a /var/log/supervisor/scheduled-restart.log