#!/bin/bash

# Load environment variables from our configuration
source /code/etc/environment.sh

# Set additional environment variables
export PORT="${PORT:-8000}"
export GLITCHTIP_DOMAIN="${GLITCHTIP_DOMAIN:-http://localhost:8000}"
export DEFAULT_FROM_EMAIL="${DEFAULT_FROM_EMAIL:-glitchtip@localhost}"
export DB_PASSWORD="${DB_PASSWORD:-postgres}"
export REDIS_PASSWORD="${REDIS_PASSWORD:-}"

# 其他配置
export EMAIL_URL="${EMAIL_URL:-}"
export SITE_URL="${GLITCHTIP_DOMAIN}"

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
DB_PASSWORD=${DB_PASSWORD}

# Valkey/Redis 配置
VALKEY_URL=${VALKEY_URL}
REDIS_URL=${REDIS_URL}
CELERY_BROKER_URL=${CELERY_BROKER_URL}
CELERY_RESULT_BACKEND=${CELERY_RESULT_BACKEND}
REDIS_PASSWORD=${REDIS_PASSWORD}

# Celery 性能配置
CELERY_WORKER_CONCURRENCY=${CELERY_WORKER_CONCURRENCY}
CELERY_WORKER_PREFETCH_MULTIPLIER=${CELERY_WORKER_PREFETCH_MULTIPLIER}
CELERY_WORKER_POOL=${CELERY_WORKER_POOL}
CELERY_SKIP_CHECKS=${CELERY_SKIP_CHECKS}

# Django 功能配置
ENABLE_ORGANIZATION_CREATION=${ENABLE_ORGANIZATION_CREATION}
ENABLE_TEST_API=${ENABLE_TEST_API}
ENABLE_OBSERVABILITY_API=${ENABLE_OBSERVABILITY_API}
ENABLE_USER_REGISTRATION=${ENABLE_USER_REGISTRATION}
EMAIL_BACKEND=${EMAIL_BACKEND}
EMAIL_URL=${EMAIL_URL}
SITE_URL=${SITE_URL}

# Django 基础配置
DJANGO_SETTINGS_MODULE=glitchtip.settings
PYTHONPATH=/code

# Django 安全配置
ALLOWED_HOSTS=${ALLOWED_HOSTS}
CSRF_TRUSTED_ORIGINS=${CSRF_TRUSTED_ORIGINS}

# 数据库连接配置
DB_HOST=${DB_HOST}

# 飞书webhook配置
FEISHU_GROUP_DEVOPS_ROBOT_WEBHOOK_URL=${FEISHU_GROUP_DEVOPS_ROBOT_WEBHOOK_URL}
ENV_EOF

# 创建agent日志目录和文件
mkdir -p /var/log/agent
touch /var/log/agent/scheduled-restart.log
chmod 644 /var/log/agent/scheduled-restart.log

# Determine cache backend
if [ "${DISABLE_REDIS:-false}" = "true" ]; then
    CACHE_BACKEND="PostgreSQL"
else
    CACHE_BACKEND="Redis"
fi

echo "=== Glitchtip AIO Container Starting ==="
echo "Configuration:"
echo "   Domain: ${GLITCHTIP_DOMAIN}"
echo "   Port: ${PORT}"
echo "   Debug: ${DEBUG}"
echo "   Database: PostgreSQL 17 (Host: localhost)"
echo "   Cache: ${CACHE_BACKEND}"
echo "   Supervisor: Enhanced Configuration"
echo "   Connection Pool: false"
echo "========================================"

# 创建必要的目录和文件
mkdir -p /var/log/supervisor /var/run/redis /var/run/postgresql /var/log/redis
touch /var/log/supervisor/supervisord.log

# 创建agent日志目录和文件
mkdir -p /var/log/agent
touch /var/log/agent/scheduled-restart.log
chmod 644 /var/log/agent/scheduled-restart.log

# 启动cron服务 (系统crontab已包含环境变量配置)
echo "Starting cron service with system crontab..."
service cron start

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

# 动态生成 supervisor 配置以支持 PostgreSQL-only 模式
if [ "${DISABLE_REDIS:-false}" = "true" ]; then
    echo "PostgreSQL-only mode: Disabling Redis service in supervisor..."

    # 创建临时的 supervisor 配置，移除 Redis 服务
    cat > /tmp/supervisord.conf << 'EOF'
[supervisord]
nodaemon=true
user=root
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid
minfds=1024
minprocs=200
childlogdir=/var/log/supervisor
logfile_maxbytes=50MB
logfile_backups=10
loglevel=info
rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[unix_http_server]
file=/var/run/supervisor.sock
chmod=0700

[supervisorctl]
serverurl=unix:///var/run/supervisor.sock

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[program:postgres]
command=/code/bin/start-postgres.sh
user=postgres
autostart=true
autorestart=true
exitcodes=0,2
startsecs=30
stopwaitsecs=20
startretries=3
stopasgroup=true
killasgroup=true
stdout_logfile=/var/log/supervisor/postgres.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
stderr_logfile=/var/log/supervisor/postgres.err.log
stderr_logfile_maxbytes=10MB
stderr_logfile_backups=5
priority=100
environment=PGDATA="/data/postgres"

[program:migrate]
command=/code/bin/run-migrate.sh
user=glitchtip
autostart=false
autorestart=false
startsecs=5
stopwaitsecs=20
startretries=3
stdout_logfile=/var/log/supervisor/migrate.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
stderr_logfile=/var/log/supervisor/migrate.err.log
stderr_logfile_maxbytes=10MB
stderr_logfile_backups=5
priority=200
environment=PYTHONPATH="/code",DJANGO_SETTINGS_MODULE="glitchtip.settings"
exitcodes=0
autorestart=unexpected
stopsignal=INT

[program:celery]
command=/code/bin/run-celery-with-beat.sh
user=glitchtip
autostart=false
autorestart=unexpected
exitcodes=0,2,143
startsecs=15
stopwaitsecs=20
startretries=3
stopasgroup=true
killasgroup=true
stdout_logfile=/var/log/supervisor/celery.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
stderr_logfile=/var/log/supervisor/celery.err.log
stderr_logfile_maxbytes=10MB
stderr_logfile_backups=5
priority=300
environment=PYTHONPATH="/code",DJANGO_SETTINGS_MODULE="glitchtip.settings"

[program:web]
command=/code/bin/run-web.sh
user=glitchtip
autostart=false
autorestart=unexpected
exitcodes=0,2,143
startsecs=30
stopwaitsecs=30
startretries=5
stopasgroup=true
killasgroup=true
stdout_logfile=/var/log/supervisor/web.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
stderr_logfile=/var/log/supervisor/web.err.log
stderr_logfile_maxbytes=10MB
stderr_logfile_backups=5
priority=400
environment=PYTHONPATH="/code",DJANGO_SETTINGS_MODULE="glitchtip.settings"

[program:startup_manager]
command=/code/bin/startup-dependency-manager.sh
user=root
autostart=true
autorestart=false
startsecs=5
stopwaitsecs=20
startretries=1
stdout_logfile=/var/log/supervisor/startup_manager.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
stderr_logfile=/var/log/supervisor/startup_manager.err.log
stderr_logfile_maxbytes=10MB
stderr_logfile_backups=5
priority=50
environment=PYTHONPATH="/code",DJANGO_SETTINGS_MODULE="glitchtip.settings"

[eventlistener:process_monitor]
command=/usr/local/bin/process_monitor
events=PROCESS_STATE_FATAL,PROCESS_STATE_EXITED,PROCESS_STATE_RUNNING
user=root
stdout_logfile=/var/log/supervisor/process_monitor.log
stderr_logfile=/var/log/supervisor/process_monitor.err.log
priority=600
buffer_size=50
autostart=true
autorestart=true
startsecs=5
stopwaitsecs=5
EOF

    echo "Starting enhanced Supervisor with PostgreSQL-only configuration..."
    exec /usr/bin/supervisord -c /tmp/supervisord.conf
else
    echo "Starting enhanced Supervisor with standard configuration..."
    exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
fi
