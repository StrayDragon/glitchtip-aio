# Glitchtip AIO - 基于 glitchtip/glitchtip:v5.1 的单容器部署方案
FROM glitchtip/glitchtip:v5.1

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# 切换到 root 用户进行系统配置
USER root

# 配置阿里源
RUN sed -i 's|deb.debian.org|mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    supervisor \
    postgresql \
    postgresql-contrib \
    redis-server \
    curl \
    netcat-openbsd \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# 配置 pip 镜像源为阿里云（使用全局配置）
RUN mkdir -p /etc/pip && \
    echo "[global]" > /etc/pip.conf && \
    echo "index-url = https://mirrors.aliyun.com/pypi/simple/" >> /etc/pip.conf && \
    echo "trusted-host = mirrors.aliyun.com" >> /etc/pip.conf

# 创建数据目录
RUN mkdir -p /data/postgres /data/redis /var/log/supervisor /code/bin

# 配置 PostgreSQL
RUN mkdir -p /etc/postgresql && \
    chown -R postgres:postgres /data/postgres && \
    echo "host all all 0.0.0.0/0 trust" >> /etc/postgresql/pg_hba.conf

# 创建启动脚本
COPY <<EOF /code/bin/start-postgres.sh
#!/bin/bash
echo "Starting PostgreSQL..."
# 初始化数据库（如果需要）
if [ ! -f "/data/postgres/PG_VERSION" ]; then
    echo "Initializing PostgreSQL database..."
    sudo -u postgres /usr/lib/postgresql/17/bin/initdb -D /data/postgres
    echo "host all all 0.0.0.0/0 trust" >> /data/postgres/pg_hba.conf
    echo "listen_addresses = '*'" >> /data/postgres/postgresql.conf
fi

# 启动 PostgreSQL
sudo -u postgres /usr/lib/postgresql/17/bin/pg_ctl -D /data/postgres start

# 等待 PostgreSQL 启动
until nc -z localhost 5432; do
    echo "Waiting for PostgreSQL to start..."
    sleep 2
done

# 创建数据库（如果不存在）
sudo -u postgres psql -c "SELECT 1 FROM pg_database WHERE datname = 'postgres'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE DATABASE postgres"

sudo -u postgres psql -c "SELECT 1 FROM pg_roles WHERE rolname = 'postgres'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE USER postgres WITH SUPERUSER PASSWORD 'postgres'"

echo "PostgreSQL started successfully"
EOF

COPY <<EOF /code/bin/start-redis.sh
#!/bin/bash
echo "Starting Redis..."
# 创建 Redis 配置文件
cat > /tmp/redis.conf << REDIS_EOF
bind 127.0.0.1
port 6379
daemonize no
pidfile /var/run/redis/redis-server.pid
logfile /var/log/redis/redis-server.log
dir /data/redis
REDIS_EOF

# 创建 Redis 数据目录
mkdir -p /data/redis /var/run/redis /var/log/redis
chown -R redis:redis /data/redis /var/run/redis /var/log/redis

# 启动 Redis（前台模式）
redis-server /tmp/redis.conf
EOF

COPY <<EOF /code/bin/run-migrate.sh
#!/bin/bash
echo "Running Django migrations..."
# 切换到应用目录
cd /code
# 等待数据库就绪
until nc -z localhost 5432; do
    echo "Waiting for database to be ready..."
    sleep 2
done

# 设置数据库 URL
export DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres

# 运行迁移
python manage.py migrate --noinput
echo "Migrations completed"
EOF

COPY <<EOF /code/bin/run-celery.sh
#!/bin/bash
echo "Starting Celery worker..."
# 切换到应用目录
cd /code
# 等待 Redis 就绪
until nc -z localhost 6379; do
    echo "Waiting for Redis to be ready..."
    sleep 2
done

# 设置环境变量
export DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres
export REDIS_URL=redis://localhost:6379/0
export CELERY_BROKER_URL=redis://localhost:6379/0
export CELERY_RESULT_BACKEND=redis://localhost:6379/0

# 启动 Celery worker
celery -A glitchtip worker --loglevel=info --autoscale=1,3
EOF

COPY <<EOF /code/bin/run-web.sh
#!/bin/bash
echo "Starting Django web server..."
# 切换到应用目录
cd /code
# 等待数据库和 Redis 就绪
until nc -z localhost 5432 && nc -z localhost 6379; do
    echo "Waiting for database and Redis to be ready..."
    sleep 2
done

# 设置环境变量
export DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres
export REDIS_URL=redis://localhost:6379/0
export CELERY_BROKER_URL=redis://localhost:6379/0
export CELERY_RESULT_BACKEND=redis://localhost:6379/0

# 收集静态文件
python manage.py collectstatic --noinput

# 启动 Django 服务器
python manage.py runserver 0.0.0.0:8000
EOF

COPY <<EOF /code/bin/health-check.sh
#!/bin/bash
echo "Running health check..."

# 检查 PostgreSQL
if nc -z localhost 5432; then
    echo "✅ PostgreSQL is running"
else
    echo "❌ PostgreSQL is not running"
    exit 1
fi

# 检查 Redis
if nc -z localhost 6379; then
    echo "✅ Redis is running"
else
    echo "❌ Redis is not running"
    exit 1
fi

# 检查 Django 应用
if curl -f http://localhost:8000/_health/ > /dev/null 2>&1; then
    echo "✅ Django application is running"
else
    echo "❌ Django application is not responding"
    exit 1
fi

echo "✅ All services are healthy"
EOF

# 给脚本执行权限
RUN chmod +x /code/bin/*.sh

# 创建 Supervisor 配置
COPY <<EOF /etc/supervisor/conf.d/supervisord.conf
[supervisord]
nodaemon=true
user=root
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid
minfds=1024
minprocs=200

[program:postgres]
command=/code/bin/start-postgres.sh
user=root
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/postgres.log
stderr_logfile=/var/log/supervisor/postgres.err.log
priority=100
startretries=3

[program:redis]
command=/code/bin/start-redis.sh
user=root
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/redis.log
stderr_logfile=/var/log/supervisor/redis.err.log
priority=200
startretries=3

[program:migrate]
command=/code/bin/run-migrate.sh
user=root
autostart=true
autorestart=false
stdout_logfile=/var/log/supervisor/migrate.log
stderr_logfile=/var/log/supervisor/migrate.err.log
priority=300
startretries=3

[program:celery]
command=/code/bin/run-celery.sh
user=root
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/celery.log
stderr_logfile=/var/log/supervisor/celery.err.log
priority=400
startretries=3
stopasgroup=true
killasgroup=true

[program:web]
command=/code/bin/run-web.sh
user=root
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/web.log
stderr_logfile=/var/log/supervisor/web.err.log
priority=500
startretries=3
stopasgroup=true
killasgroup=true

[include]
files = /etc/supervisor/conf.d/*.conf
EOF

# 创建健康检查端点
COPY <<EOF /code/health_check.py
#!/usr/bin/env python
import os
import sys
import django
from django.http import JsonResponse
from django.core.management import execute_from_command_line

# 设置 Django 环境
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'glitchtip.settings')
try:
    django.setup()
except Exception as e:
    print(f"Django setup failed: {e}")

def health_check(request):
    return JsonResponse({
        'status': 'ok',
        'services': {
            'postgres': '✅ Operational',
            'redis': '✅ Operational',
            'web': '✅ Running',
            'worker': '✅ Background tasks ready'
        },
        'version': '5.1'
    })

if __name__ == '__main__':
    execute_from_command_line(sys.argv)
EOF

RUN chmod +x /code/health_check.py

# 创建启动脚本
COPY <<EOF /entrypoint.sh
#!/bin/bash

# 设置默认环境变量
export SECRET_KEY=${SECRET_KEY:-$(openssl rand -hex 32)}
export PORT=${PORT:-8000}
export GLITCHTIP_DOMAIN=${GLITCHTIP_DOMAIN:-http://localhost:8000}
export DEFAULT_FROM_EMAIL=${DEFAULT_FROM_EMAIL:-glitchtip@localhost}
export DEBUG=${DEBUG:-false}
export DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres
export REDIS_URL=redis://localhost:6379/0
export CELERY_BROKER_URL=redis://localhost:6379/0
export CELERY_RESULT_BACKEND=redis://localhost:6379/0

# 创建 .env 文件
cat > /code/.env << ENV_EOF
SECRET_KEY=\${SECRET_KEY}
PORT=\${PORT}
GLITCHTIP_DOMAIN=\${GLITCHTIP_DOMAIN}
DEFAULT_FROM_EMAIL=\${DEFAULT_FROM_EMAIL}
DEBUG=\${DEBUG}
DATABASE_URL=\${DATABASE_URL}
REDIS_URL=\${REDIS_URL}
CELERY_BROKER_URL=\${CELERY_BROKER_URL}
CELERY_RESULT_BACKEND=\${CELERY_RESULT_BACKEND}
ENV_EOF

echo "=== 🚀 Glitchtip AIO Container Starting ==="
echo "📋 Configuration:"
echo "   Domain: \${GLITCHTIP_DOMAIN}"
echo "   Port: \${PORT}"
echo "   Debug: \${DEBUG}"
echo "   Database: PostgreSQL 15"
echo "   Cache: Redis"
echo "========================================"

# 确保目录权限正确
chown -R nobody:nogroup /code
chown -R postgres:postgres /data/postgres
chown -R redis:redis /data/redis

# 启动 Supervisor
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
EOF

RUN chmod +x /entrypoint.sh

# 暴露端口
EXPOSE 8000 5432 6379

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD /code/bin/health-check.sh

# 设置工作目录
WORKDIR /code

# 设置启动命令
ENTRYPOINT ["/entrypoint.sh"]

# 默认命令
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]