import? "my.justfile"

# 默认命令 - 显示可用命令列表
default:
    @just --list

# =============================================================================
# 配置变量
# =============================================================================

# 容器配置
export IMAGE_NAME := "glitchtip-aio"
export CONTAINER_NAME := "glitchtip-aio-test"
export DATA_DIR := "./data"
export BACKUP_DIR := DATA_DIR + "/backups"

# 网络配置
export DEFAULT_PORT := "8000"
export DEFAULT_DOMAIN := "http://localhost:8000"

# =============================================================================
# 容器生命周期管理
# =============================================================================

deploy-test:
    docker run --rm -d \
      -e SECRET_KEY="$(openssl rand -hex 32)" \
      -e GLITCHTIP_DOMAIN="http://localhost:8000" \
      -e EMAIL_URL="consolemail://" \
      -e DEFAULT_FROM_EMAIL="glitchtip@localhost" \
      -e DEBUG="true" \
      -e ENABLE_USER_REGISTRATION=false \
      -e ENABLE_ORGANIZATION_CREATION=false \
      -e DB_PASSWORD="$(openssl rand -hex 16)" \
      -e GLITCHTIP_MAX_EVENT_LIFE_DAYS=7 \
      -e GLITCHTIP_MAX_TRANSACTION_EVENT_LIFE_DAYS=7 \
      -e GLITCHTIP_MAX_FILE_LIFE_DAYS=7 \
      -e ALLOWED_HOSTS="localhost,127.0.0.1" \
      -p 8000:8000 \
      --name {{CONTAINER_NAME}} \
      glitchtip-aio:latest

# 查看完整日志
logs:
    #!/usr/bin/env bash
    echo "可用日志命令:"
    echo "  just logs*"
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

# 查看错误日志(web)
logs-web-errors:
    #!/usr/bin/env bash
    echo "=== Web错误日志 ==="
    docker exec {{CONTAINER_NAME}} tail -f /var/log/supervisor/web.err.log

# 查看错误日志
logs-celery-errors:
    #!/usr/bin/env bash
    echo "=== Celery错误日志 ==="
    docker exec {{CONTAINER_NAME}} tail -f /var/log/supervisor/celery.err.log

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
run-migrate:
    docker exec {{CONTAINER_NAME}} python manage.py migrate --noinput

# =============================================================================
# 容器交互
# =============================================================================

# 进入容器 shell
it-shell:
    docker exec -it {{CONTAINER_NAME}} bash

# 进入 PostgreSQL
it-shell-psql:
    docker exec -it {{CONTAINER_NAME}} psql -U postgres

# 进入 Redis CLI
it-shell-redis:
    docker exec -it {{CONTAINER_NAME}} redis-cli

# Django 管理命令
it-django-mange *args:
    docker exec {{CONTAINER_NAME}} python manage.py {{args}}

# =============================================================================
# 维护和清理
# =============================================================================

# 重新构建镜像
build:
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

# 打包项目代码（忽略.gitignore中的文件）
package-to-zip:
    #!/usr/bin/env bash
    set -e

    # 设置项目名称和版本
    PROJECT_NAME="glitchtip-aio"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    ZIP_FILE="${PROJECT_NAME}-${TIMESTAMP}.zip"

    echo "打包项目代码到 ${ZIP_FILE}..."

    # 创建临时目录
    TEMP_DIR=$(mktemp -d)

    # 复制项目文件（排除.git和.gitignore中的文件）
    rsync -av --progress \
        --exclude=.git \
        --exclude=node_modules \
        --exclude=*.log \
        --exclude=data \
        --exclude=*.zip \
        --exclude=.DS_Store \
        --exclude=Thumbs.db \
        ./ "${TEMP_DIR}/${PROJECT_NAME}/"

    # 创建zip文件
    cd "${TEMP_DIR}"
    zip -r "${ZIP_FILE}" "${PROJECT_NAME}/"

    # 移动zip文件到项目根目录
    mv "${ZIP_FILE}" "$(pwd)/"

    # 清理临时目录
    rm -rf "${TEMP_DIR}"

    echo "✓ 项目已打包到 ${ZIP_FILE}"
    echo "文件大小: $(du -h "${ZIP_FILE}" | cut -f1)"
    echo "包含文件: $(unzip -l "${ZIP_FILE}" | grep -c "文件")"
