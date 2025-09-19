FROM glitchtip/glitchtip:v5.1

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

USER root

RUN sed -i 's|deb.debian.org|mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources
RUN apt-get update && apt-get install -y \
    supervisor \
    postgresql \
    postgresql-contrib \
    redis-server \
    curl \
    netcat-openbsd \
    sudo \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/pip && \
    echo "[global]" > /etc/pip.conf && \
    echo "index-url = https://mirrors.aliyun.com/pypi/simple/" >> /etc/pip.conf && \
    echo "trusted-host = mirrors.aliyun.com" >> /etc/pip.conf

RUN mkdir -p /data/postgres /data/redis /var/log/supervisor /code/bin

RUN mkdir -p /etc/postgresql && \
    chown -R postgres:postgres /data/postgres && \
    echo "host all all 0.0.0.0/0 trust" >> /etc/postgresql/pg_hba.conf

COPY <<EOF /code/bin/start-postgres.sh
#!/bin/bash
set -e

echo "Starting PostgreSQL..."

# 初始化数据库（如果需要）
if [ ! -f "/data/postgres/PG_VERSION" ]; then
    echo "Initializing PostgreSQL database..."
    /usr/lib/postgresql/17/bin/initdb -D /data/postgres --auth-host=trust --auth-local=trust
    
    # 确保访问权限配置正确（向后兼容）
    cat >> /data/postgres/pg_hba.conf << PGEOF
host all all 0.0.0.0/0 trust
local all all trust
PGEOF
    
    # 基本配置已在initdb时设置，这里添加优化配置
    cat >> /data/postgres/postgresql.conf << PGEOF
# Performance optimizations for container environment
listen_addresses = '*'
max_connections = 100
shared_buffers = 128MB
effective_cache_size = 4GB
maintenance_work_mem = 64MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
work_mem = 4MB
min_wal_size = 1GB
max_wal_size = 4GB

# Logging configuration
log_min_duration_statement = 1000
log_checkpoints = on
log_connections = on
log_disconnections = on
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
PGEOF
fi

# 简单的锁文件清理（如果存在且进程未运行）
if [ -f "/data/postgres/postmaster.pid" ]; then
    PID=$(head -n 1 /data/postgres/postmaster.pid 2>/dev/null || echo "")
    if [ -n "$PID" ] && ! kill -0 "$PID" 2>/dev/null; then
        echo "Cleaning up stale PostgreSQL lock file..."
        rm -f /data/postgres/postmaster.pid
    fi
fi

# 启动PostgreSQL（前台运行，符合Docker最佳实践）
echo "Starting PostgreSQL in foreground..."
exec /usr/lib/postgresql/17/bin/postgres -D /data/postgres
EOF

COPY <<EOF /code/bin/start-redis.sh
#!/bin/bash
echo "Starting Redis..."

# 创建必要的目录
mkdir -p /data/redis /var/run/redis /var/log/redis
chown -R redis:redis /data/redis /var/run/redis /var/log/redis

# 生成Redis配置
cat > /tmp/redis.conf << REDIS_EOF
bind 127.0.0.1
port 6379
daemonize no
pidfile /var/run/redis/redis-server.pid
logfile /var/log/redis/redis-server.log
dir /data/redis
maxmemory 512mb
maxmemory-policy allkeys-lru
timeout 300
tcp-keepalive 60
loglevel notice
databases 16
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
REDIS_EOF

echo "Redis configuration created"
exec redis-server /tmp/redis.conf
EOF

COPY <<EOF /code/bin/run-migrate.sh
#!/bin/bash
echo "Running Django migrations..."
cd /code
until nc -z localhost 5432; do
    echo "Waiting for database to be ready..."
    sleep 2
done

export DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres
python manage.py migrate --noinput
echo "Migrations completed"
EOF

COPY <<EOF /code/bin/run-celery.sh
#!/bin/bash
echo "Starting Celery worker..."
cd /code

# 等待依赖服务启动
until nc -z localhost 5432; do
    echo "Waiting for PostgreSQL to be ready..."
    sleep 2
done

until nc -z localhost 6379; do
    echo "Waiting for Redis to be ready..."
    sleep 2
done

export DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres
export REDIS_URL=redis://localhost:6379/0
export CELERY_BROKER_URL=redis://localhost:6379/0
export CELERY_RESULT_BACKEND=redis://localhost:6379/0
export CELERY_LOG_LEVEL=info

# 设置优化参数
export C_FORCE_ROOT=true
export PYTHONOPTIMIZE=1

echo "Starting Celery worker with autoscaling..."
exec celery -A glitchtip worker \
    --loglevel=info \
    --autoscale=2,4 \
    --max-tasks-per-child=100 \
    --time-limit=300 \
    --soft-time-limit=280 \
    --without-gossip \
    --without-mingle \
    --without-heartbeat \
    --worker-pool-restarts=1
EOF

COPY <<EOF /code/bin/run-web.sh
#!/bin/bash
echo "Starting Django web server..."
cd /code

# 等待依赖服务启动
until nc -z localhost 5432; do
    echo "Waiting for PostgreSQL to be ready..."
    sleep 2
done

until nc -z localhost 6379; do
    echo "Waiting for Redis to be ready..."
    sleep 2
done

export DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres
export REDIS_URL=redis://localhost:6379/0
export CELERY_BROKER_URL=redis://localhost:6379/0
export CELERY_RESULT_BACKEND=redis://localhost:6379/0
export DJANGO_SETTINGS_MODULE=glitchtip.settings

# 优化Python环境
export PYTHONOPTIMIZE=1
export PYTHONUNBUFFERED=1

# 收集静态文件
echo "Collecting static files..."
python manage.py collectstatic --noinput --clear

# 优化Django设置
export DEBUG=false
export ALLOWED_HOSTS='*'

echo "Starting Django development server..."
exec python manage.py runserver 0.0.0.0:8000 \
    --settings=glitchtip.settings \
    --verbosity=1
EOF

COPY <<EOF /usr/local/bin/health-check
#!/bin/bash
echo "Running comprehensive health check..."

# 检查PostgreSQL
if nc -z localhost 5432; then
    echo "✓ PostgreSQL is running"
    
    # 检查PostgreSQL连接
    if timeout 5 psql -U postgres -d postgres -c "SELECT 1;" > /dev/null 2>&1; then
        echo "✓ PostgreSQL connection is working"
    else
        echo "✗ PostgreSQL connection failed"
        exit 1
    fi
else
    echo "✗ PostgreSQL is not running"
    exit 1
fi

# 检查Redis
if nc -z localhost 6379; then
    echo "✓ Redis is running"
    
    # 检查Redis连接
    if timeout 5 redis-cli ping > /dev/null 2>&1; then
        echo "✓ Redis connection is working"
    else
        echo "✗ Redis connection failed"
        exit 1
    fi
else
    echo "✗ Redis is not running"
    exit 1
fi

# 检查Django应用
if curl -f http://localhost:8000/_health/ > /dev/null 2>&1; then
    echo "✓ Django application is running"
    
    # 检查Django应用响应时间
    response_time=$(curl -o /dev/null -s -w '%{time_total}' http://localhost:8000/_health/)
    echo "✓ Django application response time: ${response_time}s"
    
    # 检查响应时间是否过长
    if [ "$(echo "$response_time > 5.0" | awk '{print ($1 > 5.0) ? 1 : 0}')" = "1" ]; then
        echo "⚠ Django application response time is slow"
    fi
else
    echo "✗ Django application is not responding"
    exit 1
fi

# 检查Celery工作进程
if pgrep -f "celery.*worker" > /dev/null; then
    echo "✓ Celery worker is running"
else
    echo "✗ Celery worker is not running"
    exit 1
fi

# 检查系统资源
memory_usage=$(free | grep Mem | awk '{printf "%.2f", $3/$2 * 100.0}')
echo "✓ Memory usage: ${memory_usage}%"

disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
echo "✓ Disk usage: ${disk_usage}%"

if [ "$disk_usage" -gt 90 ]; then
    echo "⚠ Disk usage is high"
fi

echo "✓ All services are healthy"
EOF

COPY <<EOF /usr/local/bin/process_monitor
#!/usr/bin/env python3
import sys
import subprocess
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def handle_event(event_data):
    try:
        logger.info(f"Received event: {event_data}")
        
        if 'PROCESS_STATE_FATAL' in event_data or 'PROCESS_STATE_EXITED' in event_data:
            logger.warning("Process monitoring event received")
            
    except Exception as e:
        logger.error(f"Error handling event: {e}")

def main():
    logger.info("Process monitor started")
    
    for line in sys.stdin:
        if line.strip():
            handle_event(line.strip())
    
    logger.info("Process monitor stopped")

if __name__ == '__main__':
    main()
EOF


RUN chmod +x /usr/local/bin/* /code/bin/*.sh

COPY <<EOF /etc/supervisor/conf.d/supervisord.conf
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

[program:postgres]
command=/code/bin/start-postgres.sh
user=postgres
autostart=true
autorestart=true
exitcodes=0,2
startsecs=10
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

[program:redis]
command=/code/bin/start-redis.sh
user=redis
autostart=true
autorestart=unexpected
exitcodes=0,2
startsecs=5
stopwaitsecs=10
startretries=3
stopasgroup=true
killasgroup=true
stdout_logfile=/var/log/supervisor/redis.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
stderr_logfile=/var/log/supervisor/redis.err.log
stderr_logfile_maxbytes=10MB
stderr_logfile_backups=5
priority=200
environment=REDIS_HOME="/data/redis"

[program:migrate]
command=/code/bin/run-migrate.sh
user=root
autostart=true
autorestart=false
startsecs=120
stopwaitsecs=20
startretries=1
stdout_logfile=/var/log/supervisor/migrate.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
stderr_logfile=/var/log/supervisor/migrate.err.log
stderr_logfile_maxbytes=10MB
stderr_logfile_backups=5
priority=300
environment=PYTHONPATH="/code",DJANGO_SETTINGS_MODULE="glitchtip.settings"
exitcodes=0,1
autorestart=false

[program:celery]
command=/code/bin/run-celery.sh
user=root
autostart=true
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
priority=400
environment=PYTHONPATH="/code",CELERY_LOG_LEVEL="INFO"

[program:web]
command=/code/bin/run-web.sh
user=root
autostart=true
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
priority=500
environment=PYTHONPATH="/code",DJANGO_SETTINGS_MODULE="glitchtip.settings",PYTHONOPTIMIZE="1",PYTHONUNBUFFERED="1"

[include]
files = /etc/supervisor/conf.d/*.conf

[eventlistener:process_monitor]
command=/usr/local/bin/process_monitor
events=PROCESS_STATE_FATAL,PROCESS_STATE_EXITED
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

RUN cat > /entrypoint.sh << 'EOF'
#!/bin/bash

# 设置默认环境变量
export SECRET_KEY="${SECRET_KEY:-$(openssl rand -hex 32)}"
export PORT="${PORT:-8000}"
export GLITCHTIP_DOMAIN="${GLITCHTIP_DOMAIN:-http://localhost:8000}"
export DEFAULT_FROM_EMAIL="${DEFAULT_FROM_EMAIL:-glitchtip@localhost}"
export DEBUG="${DEBUG:-false}"
export DATABASE_URL="${DATABASE_URL:-postgres://postgres:postgres@localhost:5432/postgres}"
export REDIS_URL="${REDIS_URL:-redis://localhost:6379/0}"
export CELERY_BROKER_URL="${CELERY_BROKER_URL:-redis://localhost:6379/0}"
export CELERY_RESULT_BACKEND="${CELERY_RESULT_BACKEND:-redis://localhost:6379/0}"
export DB_PASSWORD="${DB_PASSWORD:-postgres}"
export REDIS_PASSWORD="${REDIS_PASSWORD:-}"
export EMAIL_URL="${EMAIL_URL:-}"

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
DJANGO_SETTINGS_MODULE=glitchtip.settings
PYTHONPATH=/code
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

# 设置权限和用户
chmod +x /code/bin/*.sh
chmod +x /usr/local/bin/*

# 设置目录权限
chown -R postgres:postgres /data/postgres
chown -R redis:redis /data/redis
chown -R root:root /code
chown -R root:root /var/log/supervisor

# 创建必要的目录和文件
mkdir -p /var/run/redis /var/run/postgresql
touch /var/log/supervisor/supervisord.log

# 设置进程限制
ulimit -n 65536
ulimit -u 32768

echo "Starting enhanced Supervisor with process monitoring..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
EOF

RUN chmod +x /entrypoint.sh

EXPOSE 8000 5432 6379

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD /usr/local/bin/health-check

WORKDIR /code

ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
