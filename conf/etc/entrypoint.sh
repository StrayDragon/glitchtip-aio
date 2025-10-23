#!/bin/bash

# 设置默认环境变量 - 与官方 docker-compose 保持一致
export SECRET_KEY="${SECRET_KEY:-$(openssl rand -hex 32)}"
export PORT="${PORT:-8000}"  # 默认 8000，但允许环境变量覆盖
export GLITCHTIP_DOMAIN="${GLITCHTIP_DOMAIN:-http://localhost:8000}"
export DEFAULT_FROM_EMAIL="${DEFAULT_FROM_EMAIL:-glitchtip@localhost}"
export DEBUG="${DEBUG:-false}"
export DB_PASSWORD="${DB_PASSWORD:-$(openssl rand -hex 16)}"
export DATABASE_URL="${DATABASE_URL:-postgres://postgres:${DB_PASSWORD}@localhost:5432/postgres}"
export REDIS_URL="${REDIS_URL:-redis://localhost:6379/0}"
export CELERY_BROKER_URL="${CELERY_BROKER_URL:-redis://localhost:6379/0}"
export CELERY_RESULT_BACKEND="${CELERY_RESULT_BACKEND:-redis://localhost:6379/0}"
export REDIS_PASSWORD="${REDIS_PASSWORD:-}"
export EMAIL_URL="${EMAIL_URL:-}"

# Django 安全配置 - 智能设置允许的主机
if [ -n "$ALLOWED_HOSTS" ]; then
    echo "使用用户指定的 ALLOWED_HOSTS: $ALLOWED_HOSTS"
else
    # 从 GLITCHTIP_DOMAIN 提取主机名
    DOMAIN_HOST=$(echo "$GLITCHTIP_DOMAIN" | sed 's|https\?://||' | sed 's|:[0-9]*||' | sed 's|/.*||')
    if [ "$DOMAIN_HOST" != "localhost" ] && [ "$DOMAIN_HOST" != "127.0.0.1" ]; then
        export ALLOWED_HOSTS="localhost,127.0.0.1,$DOMAIN_HOST"
        echo "自动推导 ALLOWED_HOSTS: $ALLOWED_HOSTS"
    else
        export ALLOWED_HOSTS="localhost,127.0.0.1"
        echo "使用默认 ALLOWED_HOSTS: $ALLOWED_HOSTS"
    fi
fi

# 设置 CSRF 可信来源
export CSRF_TRUSTED_ORIGINS="${CSRF_TRUSTED_ORIGINS:-${GLITCHTIP_DOMAIN}}"

# 用户和组织管理配置 - 支持环境变量覆盖
export ENABLE_USER_REGISTRATION="${ENABLE_USER_REGISTRATION:-false}"
export ENABLE_ORGANIZATION_CREATION="${ENABLE_ORGANIZATION_CREATION:-false}"

# 数据库连接池配置 - 禁用连接池以避免连接问题
export DATABASE_POOL="false"

# 数据库主机配置 - 确保使用 localhost 而不是 postgres
export DB_HOST="localhost"

# 创建 .env 文件
cat > /code/.env << ENV_EOF
SECRET_KEY=${SECRET_KEY}
PORT=${PORT}
GLITCHTIP_DOMAIN=${GLITCHTIP_DOMAIN}
DEFAULT_FROM_EMAIL=${DEFAULT_FROM_EMAIL}
DEBUG=${DEBUG}
DATABASE_URL=${DATABASE_URL}
REDIS_URL=${REDIS_URL}
CELERY_BROKER_URL=${CELERY_BROKER_URL}
CELERY_RESULT_BACKEND=${CELERY_RESULT_BACKEND}
DB_PASSWORD=${DB_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}
EMAIL_URL=${EMAIL_URL}
ENABLE_USER_REGISTRATION=${ENABLE_USER_REGISTRATION}
ENABLE_ORGANIZATION_CREATION=${ENABLE_ORGANIZATION_CREATION}
DJANGO_SETTINGS_MODULE=glitchtip.settings
PYTHONPATH=/code

# Django 安全配置
ALLOWED_HOSTS=${ALLOWED_HOSTS}
CSRF_TRUSTED_ORIGINS=${CSRF_TRUSTED_ORIGINS}

# 用户和组织管理配置
ENABLE_USER_REGISTRATION=${ENABLE_USER_REGISTRATION}
ENABLE_ORGANIZATION_CREATION=${ENABLE_ORGANIZATION_CREATION}

# 数据库连接配置
DB_HOST=${DB_HOST}
ENV_EOF

echo "=== Glitchtip AIO Container Starting ==="
echo "Configuration:"
echo "   Domain: ${GLITCHTIP_DOMAIN}"
echo "   Port: ${PORT}"
echo "   Debug: ${DEBUG}"
echo "   Database: PostgreSQL 17 (Host: ${DB_HOST})"
echo "   Cache: Redis"
echo "   Supervisor: Enhanced Configuration"
echo "   Connection Pool: ${DATABASE_POOL}"
echo "========================================"

# 创建必要的目录和文件
mkdir -p /var/log/supervisor /var/run/redis /var/run/postgresql /var/log/redis
touch /var/log/supervisor/supervisord.log

# 设置权限和用户
chmod +x /code/bin/*.sh
chmod +x /usr/local/bin/*

# 设置目录权限
chown -R postgres:postgres /data/postgres
chown -R redis:redis /data/redis /var/run/redis /var/log/redis
chown -R glitchtip:glitchtip /code
chown -R root:root /var/log/supervisor

# 初始化数据库密码（如果数据库已初始化）
if [ -f "/data/postgres/PG_VERSION" ]; then
    echo "Setting PostgreSQL password..."
    su - postgres -c "psql -c \"ALTER USER postgres WITH PASSWORD '${DB_PASSWORD}';\"" 2>/dev/null || true
fi

# 确保必要的目录权限
chmod -R 755 /var/log/supervisor
chmod -R 755 /code

# 设置默认环境变量（避免supervisor报错）
export FEISHU_GROUP_DEVOPS_ROBOT_WEBHOOK_URL="${FEISHU_GROUP_DEVOPS_ROBOT_WEBHOOK_URL:-}"

# 设置进程限制
ulimit -n 65536
ulimit -u 32768

echo "Starting enhanced Supervisor with process monitoring..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
