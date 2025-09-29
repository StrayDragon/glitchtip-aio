#!/bin/bash

# 设置默认环境变量
export SECRET_KEY="${SECRET_KEY:-$(openssl rand -hex 32)}"
export PORT="${PORT:-8004}"
export GLITCHTIP_DOMAIN="${GLITCHTIP_DOMAIN:-http://localhost:8004}"
export DEFAULT_FROM_EMAIL="${DEFAULT_FROM_EMAIL:-glitchtip@localhost}"
export DEBUG="${DEBUG:-false}"
export DB_PASSWORD="${DB_PASSWORD:-$(openssl rand -hex 16)}"
export DATABASE_URL="${DATABASE_URL:-postgres://postgres:${DB_PASSWORD}@localhost:5432/postgres}"
export REDIS_URL="${REDIS_URL:-redis://localhost:6379/0}"
export CELERY_BROKER_URL="${CELERY_BROKER_URL:-redis://localhost:6379/0}"
export CELERY_RESULT_BACKEND="${CELERY_RESULT_BACKEND:-redis://localhost:6379/0}"
export REDIS_PASSWORD="${REDIS_PASSWORD:-}"
export EMAIL_URL="${EMAIL_URL:-}"

# Django 安全配置 - 设置默认可信域名
export ALLOWED_HOSTS="${ALLOWED_HOSTS:-localhost,127.0.0.1}"
export CSRF_TRUSTED_ORIGINS="${CSRF_TRUSTED_ORIGINS:-${GLITCHTIP_DOMAIN}}"

# 用户和组织管理配置 - 支持环境变量覆盖
export ENABLE_USER_REGISTRATION="${ENABLE_USER_REGISTRATION:-false}"
export ENABLE_ORGANIZATION_CREATION="${ENABLE_ORGANIZATION_CREATION:-false}"

# 数据库连接池配置 - 禁用连接池以避免连接问题
export DATABASE_POOL="false"

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
ENV_EOF

echo "=== Glitchtip AIO Container Starting ==="
echo "Configuration:"
echo "   Domain: ${GLITCHTIP_DOMAIN}"
echo "   Port: ${PORT}"
echo "   Debug: ${DEBUG}"
echo "   Database: PostgreSQL 17"
echo "   Cache: Redis"
echo "   Supervisor: Enhanced Configuration"
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

# 设置进程限制
ulimit -n 65536
ulimit -u 32768

echo "Starting enhanced Supervisor with process monitoring..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf