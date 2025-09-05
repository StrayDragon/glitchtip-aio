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
echo "Starting PostgreSQL..."
if [ ! -f "/data/postgres/PG_VERSION" ]; then
    echo "Initializing PostgreSQL database..."
    sudo -u postgres /usr/lib/postgresql/17/bin/initdb -D /data/postgres
    echo "host all all 0.0.0.0/0 trust" >> /data/postgres/pg_hba.conf
    echo "listen_addresses = '*'" >> /data/postgres/postgresql.conf
fi

# Initialize database if needed
sudo -u postgres /usr/lib/postgresql/17/bin/pg_ctl -D /data/postgres start

until nc -z localhost 5432; do
    echo "Waiting for PostgreSQL to start..."
    sleep 2
done

sudo -u postgres psql -c "SELECT 1 FROM pg_database WHERE datname = 'postgres'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE DATABASE postgres"

sudo -u postgres psql -c "SELECT 1 FROM pg_roles WHERE rolname = 'postgres'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE USER postgres WITH SUPERUSER PASSWORD 'postgres'"

# Stop the background server and start in foreground
sudo -u postgres /usr/lib/postgresql/17/bin/pg_ctl -D /data/postgres stop

echo "PostgreSQL starting in foreground..."
exec sudo -u postgres /usr/lib/postgresql/17/bin/postgres -D /data/postgres
EOF

COPY <<EOF /code/bin/start-redis.sh
#!/bin/bash
echo "Starting Redis..."
cat > /tmp/redis.conf << REDIS_EOF
bind 127.0.0.1
port 6379
daemonize no
pidfile /var/run/redis/redis-server.pid
logfile /var/log/redis/redis-server.log
dir /data/redis
REDIS_EOF

mkdir -p /data/redis /var/run/redis /var/log/redis
chown -R redis:redis /data/redis /var/run/redis /var/log/redis

redis-server /tmp/redis.conf
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
until nc -z localhost 6379; do
    echo "Waiting for Redis to be ready..."
    sleep 2
done

export DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres
export REDIS_URL=redis://localhost:6379/0
export CELERY_BROKER_URL=redis://localhost:6379/0
export CELERY_RESULT_BACKEND=redis://localhost:6379/0

celery -A glitchtip worker --loglevel=info --autoscale=1,3
EOF

COPY <<EOF /code/bin/run-web.sh
#!/bin/bash
echo "Starting Django web server..."
cd /code
until nc -z localhost 5432 && nc -z localhost 6379; do
    echo "Waiting for database and Redis to be ready..."
    sleep 2
done

export DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres
export REDIS_URL=redis://localhost:6379/0
export CELERY_BROKER_URL=redis://localhost:6379/0
export CELERY_RESULT_BACKEND=redis://localhost:6379/0

python manage.py collectstatic --noinput
python manage.py runserver 0.0.0.0:8000
EOF

COPY <<EOF /usr/local/bin/health-check
#!/bin/bash
echo "Running health check..."

if nc -z localhost 5432; then
    echo "PostgreSQL is running"
else
    echo "PostgreSQL is not running"
    exit 1
fi

if nc -z localhost 6379; then
    echo "Redis is running"
else
    echo "Redis is not running"
    exit 1
fi

if curl -f http://localhost:8000/_health/ > /dev/null 2>&1; then
    echo "Django application is running"
else
    echo "Django application is not responding"
    exit 1
fi

echo "All services are healthy"
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
ENV_EOF

echo "=== Glitchtip AIO Container Starting ==="
echo "Configuration:"
echo "   Domain: ${GLITCHTIP_DOMAIN}"
echo "   Port: ${PORT}"
echo "   Debug: ${DEBUG}"
echo "   Database: PostgreSQL 17"
echo "   Cache: Redis"
echo "========================================"

# 设置权限
chown -R nobody:nogroup /code
chown -R postgres:postgres /data/postgres
chown -R redis:redis /data/redis

# 启动 supervisord
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
EOF

RUN chmod +x /entrypoint.sh

EXPOSE 8000 5432 6379

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD /usr/local/bin/health-check

WORKDIR /code

ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
