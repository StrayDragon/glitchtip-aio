# Glitchtip AIO - Just 命令配置文件
# https://just.systems/man/zh/

# =============================================================================
# 默认命令
# =============================================================================

# 默认命令 - 显示可用命令列表
default:
    @just --list

# =============================================================================
# 配置变量
# =============================================================================

# 容器配置
export CONTAINER_NAME := "glitchtip-aio"
export IMAGE_NAME := "glitchtip-aio"
export DATA_DIR := "./data"
export BACKUP_DIR := DATA_DIR + "/backups"

# 网络配置
export DEFAULT_PORT := "8000"
export DEFAULT_DOMAIN := "http://localhost:8000"

# 环境变量（可通过命令行覆盖）
export PERSIST_DATA := env_var_or_default("PERSIST_DATA", "false")
export EXPOSE_WEB_PORT := env_var_or_default("EXPOSE_WEB_PORT", "true")
export EXPOSE_DB_PORT := env_var_or_default("EXPOSE_DB_PORT", "false")
export EXPOSE_REDIS_PORT := env_var_or_default("EXPOSE_REDIS_PORT", "false")

# =============================================================================
# 核心部署命令
# =============================================================================

# 默认部署
deploy:
    #!/usr/bin/env bash
    set -e
    just _deploy "{{DEFAULT_PORT}}" "{{DEFAULT_DOMAIN}}" "{{DATA_DIR}}"

# 自定义端口部署
deploy-port port:
    #!/usr/bin/env bash
    set -e
    just _deploy "{{port}}" "{{DEFAULT_DOMAIN}}" "{{DATA_DIR}}"

# 自定义域名和端口部署
deploy-custom port domain="http://0.0.0.0":
    #!/usr/bin/env bash
    set -e
    just _deploy "{{port}}" "{{domain}}" "{{DATA_DIR}}"

# 持久化部署
deploy-persist:
    #!/usr/bin/env bash
    set -e
    PERSIST_DATA=true just _deploy "{{DEFAULT_PORT}}" "{{DEFAULT_DOMAIN}}" "{{DATA_DIR}}"

# =============================================================================
# 容器生命周期管理
# =============================================================================

# 启动服务
start:
    docker start {{CONTAINER_NAME}} && echo "服务已启动"

# 停止服务
stop:
    docker stop {{CONTAINER_NAME}} && echo "服务已停止"

# 重启服务
restart:
    docker restart {{CONTAINER_NAME}} && echo "服务已重启"

# 查看完整日志
logs:
    #!/usr/bin/env bash
    echo "可用日志命令:"
    echo "  just logs           # 查看容器完整日志"
    echo "  just logs-supervisor # 查看supervisor主日志"
    echo "  just logs-app       # 查看应用日志"
    echo "  just logs-celery    # 查看Celery日志"
    echo "  just logs-pgsql     # 查看PostgreSQL日志"
    echo "  just logs-redis     # 查看Redis日志"
    echo "  just logs-migrate   # 查看迁移日志"
    echo "  just logs-errors    # 查看错误日志"
    echo ""
    echo "正在查看容器完整日志..."
    docker logs -f {{CONTAINER_NAME}}

# 查看supervisor主日志
logs-supervisor:
    docker exec {{CONTAINER_NAME}} tail -f /var/log/supervisor/supervisord.log

# 查看应用日志
logs-app:
    docker exec {{CONTAINER_NAME}} tail -f /var/log/supervisor/web.log

# 查看Celery日志
logs-celery:
    docker exec {{CONTAINER_NAME}} tail -f /var/log/supervisor/celery.log

# 查看PostgreSQL日志
logs-pgsql:
    docker exec {{CONTAINER_NAME}} tail -f /var/log/supervisor/postgres.log

# 查看Redis日志
logs-redis:
    docker exec {{CONTAINER_NAME}} tail -f /var/log/supervisor/redis.log

# 查看迁移日志
logs-migrate:
    docker exec {{CONTAINER_NAME}} tail -f /var/log/supervisor/migrate.log

# 查看错误日志
logs-errors:
    #!/usr/bin/env bash
    echo "=== Web错误日志 ==="
    docker exec {{CONTAINER_NAME}} tail -f /var/log/supervisor/web.err.log
    echo ""
    echo "=== Celery错误日志 ==="
    docker exec {{CONTAINER_NAME}} tail -f /var/log/supervisor/celery.err.log

# 查看状态
status:
    #!/usr/bin/env bash
    CONTAINER_NAME="{{CONTAINER_NAME}}"
    echo "容器状态:"
    docker ps -a --filter "name=$CONTAINER_NAME"
    echo ""
    if docker ps | grep -q "$CONTAINER_NAME"; then
        echo "健康检查:"
        # 获取实际映射的端口
        MAPPED_PORT=$(docker port "$CONTAINER_NAME" 8000 | cut -d: -f2 | head -1)
        if [ -z "$MAPPED_PORT" ]; then
            echo "✗ 无法获取映射端口"
        elif curl -f http://localhost:$MAPPED_PORT/_health/ >/dev/null 2>&1; then
            echo "✓ 应用运行正常 (端口: $MAPPED_PORT)"
        else
            echo "✗ 应用无响应 (端口: $MAPPED_PORT)"
        fi
    fi

# =============================================================================
# 数据库管理
# =============================================================================

# 备份数据库
backup:
    #!/usr/bin/env bash
    mkdir -p {{BACKUP_DIR}}
    BACKUP_FILE="{{BACKUP_DIR}}/glitchtip-backup-$(date +%Y%m%d-%H%M%S).sql.gz"
    docker exec {{CONTAINER_NAME}} pg_dump -U postgres | gzip > "$BACKUP_FILE"
    echo "数据库已备份到: $BACKUP_FILE"

# 恢复数据库
restore:
    #!/usr/bin/env bash
    echo "可用备份文件:"
    ls -la {{BACKUP_DIR}}/*.sql.gz
    read -p "请输入要恢复的备份文件路径: " backup_file
    gunzip -c "$backup_file" | docker exec -i {{CONTAINER_NAME}} psql -U postgres
    echo "数据库已恢复"

# 运行数据库迁移
migrate:
    docker exec {{CONTAINER_NAME}} python manage.py migrate --noinput

# =============================================================================
# 容器交互
# =============================================================================

# 进入容器 shell
shell:
    docker exec -it {{CONTAINER_NAME}} bash

# 进入 PostgreSQL
psql:
    docker exec -it {{CONTAINER_NAME}} psql -U postgres

# 进入 Redis CLI
redis:
    docker exec -it {{CONTAINER_NAME}} redis-cli

# Django 管理命令
django *args:
    docker exec {{CONTAINER_NAME}} python manage.py {{args}}

# =============================================================================
# 维护和清理
# =============================================================================

# 重新构建镜像
rebuild:
    #!/usr/bin/env bash
    docker stop {{CONTAINER_NAME}} 2>/dev/null || true
    docker rm {{CONTAINER_NAME}} 2>/dev/null || true
    docker build -t {{IMAGE_NAME}} .
    echo "镜像已重新构建"

# 清理容器和镜像
clean:
    #!/usr/bin/env bash
    docker stop {{CONTAINER_NAME}} 2>/dev/null || true
    docker rm {{CONTAINER_NAME}} 2>/dev/null || true
    docker rmi {{IMAGE_NAME}} 2>/dev/null || true
    echo "容器和镜像已清理"

# 显示系统信息
info:
    #!/usr/bin/env bash
    CONTAINER_NAME="{{CONTAINER_NAME}}"
    DATA_DIR="{{DATA_DIR}}"
    echo "系统信息:"
    echo "  Docker 版本: $(docker --version | cut -d' ' -f3 | cut -d',' -f1)"
    echo "  容器状态: $(docker ps -a --filter "name=$CONTAINER_NAME" | head -n 2 | tail -n 1 | awk '{print $7}' 2>/dev/null || echo "不存在")"
    if [ -d "$DATA_DIR" ]; then
        echo "  数据目录大小: $(du -sh "$DATA_DIR" 2>/dev/null | cut -f1)"
    fi

# =============================================================================
# 内部函数
# =============================================================================

# 内部部署函数
_deploy port domain data_path:
    #!/usr/bin/env bash
    set -e
    
    echo "Glitchtip AIO 部署"
    echo "端口: {{port}}, 域名: {{domain}}"
    echo "数据持久化: {{PERSIST_DATA}}"
    
    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        echo "错误: Docker 未安装"
        exit 1
    fi
    
    # 创建数据目录
    if [ "{{PERSIST_DATA}}" = "true" ]; then
        mkdir -p "{{data_path}}"/{postgres,data,redis,data,backups,logs,uploads}
        echo "数据目录已创建"
    fi
    
    # 清理现有容器
    docker stop {{CONTAINER_NAME}} 2>/dev/null || true
    docker rm {{CONTAINER_NAME}} 2>/dev/null || true
    
    # 构建镜像
    echo "构建镜像..."
    docker build -t {{IMAGE_NAME}} .
    
    # 生成配置
    SECRET_KEY=$(openssl rand -hex 32)
    
    # 构建运行命令
    DOCKER_CMD="docker run -d \
        --name {{CONTAINER_NAME}} \
        -e SECRET_KEY=$SECRET_KEY \
        -e PORT={{port}} \
        -e GLITCHTIP_DOMAIN={{domain}} \
        -e DEBUG=false \
        -e PERSIST_DATA={{PERSIST_DATA}}"
    
    # 添加端口映射
    if [ "{{EXPOSE_WEB_PORT}}" = "true" ]; then
        DOCKER_CMD="$DOCKER_CMD -p {{port}}:8000"
    fi
    if [ "{{EXPOSE_DB_PORT}}" = "true" ]; then
        DOCKER_CMD="$DOCKER_CMD -p 5432:5432"
    fi
    if [ "{{EXPOSE_REDIS_PORT}}" = "true" ]; then
        DOCKER_CMD="$DOCKER_CMD -p 6379:6379"
    fi
    
    # 添加数据卷
    if [ "{{PERSIST_DATA}}" = "true" ]; then
        DOCKER_CMD="$DOCKER_CMD \
            -v {{data_path}}/postgres/data:/var/lib/postgresql \
            -v {{data_path}}/redis/data:/var/lib/redis \
            -v {{data_path}}/backups:/backups \
            -v {{data_path}}/logs:/var/log \
            -v {{data_path}}/uploads:/code/uploads"
    fi
    
    DOCKER_CMD="$DOCKER_CMD \
        --restart unless-stopped \
        {{IMAGE_NAME}}"
    
    # 启动容器
    echo "启动容器..."
    eval $DOCKER_CMD
    
    # 等待服务启动
    echo "等待服务启动..."
    for i in {1..60}; do
        if curl -f http://localhost:{{port}}/_health/ &>/dev/null; then
            echo "服务已启动!"
            echo "访问地址: {{domain}}:{{port}}"
            break
        fi
        sleep 1
    done

# =============================================================================
# 帮助信息
# =============================================================================

# 显示帮助
help:
    #!/usr/bin/env bash
    echo "Glitchtip AIO - Just 命令管理"
    echo "================================"
    echo ""
    echo "部署命令:"
    echo "  just deploy              # 默认部署"
    echo "  just deploy-port 8080    # 自定义端口"
    echo "  just deploy-custom 9000 [domain] # 自定义域名和端口部署 (默认域名: 0.0.0.0)"
    echo "  just deploy-persist      # 持久化部署"
    echo ""
    echo "容器管理:"
    echo "  just start/stop/restart  # 启动/停止/重启"
    echo "  just logs               # 查看完整日志"
    echo "  just status             # 查看状态"
    echo "  just shell              # 进入容器"
    echo ""
    echo "日志查看:"
    echo "  just logs               # 显示所有日志选项"
    echo "  just logs-supervisor    # Supervisor主日志"
    echo "  just logs-app           # 应用日志"
    echo "  just logs-celery        # Celery日志"
    echo "  just logs-pgsql         # PostgreSQL日志"
    echo "  just logs-redis         # Redis日志"
    echo "  just logs-migrate       # 迁移日志"
    echo "  just logs-errors        # 错误日志"
    echo ""
    echo "数据库管理:"
    echo "  just backup/restore     # 备份/恢复"
    echo "  just migrate            # 运行迁移"
    echo "  just psql/redis         # 进入数据库"
    echo ""
    echo "维护命令:"
    echo "  just rebuild            # 重新构建"
    echo "  just clean              # 清理"
    echo "  just info               # 系统信息"
    echo ""
    echo "环境变量:"
    echo "  PERSIST_DATA=true/false"
    echo "  EXPOSE_WEB_PORT=true/false"
    echo "  EXPOSE_DB_PORT=true/false"
    echo "  EXPOSE_REDIS_PORT=true/false"