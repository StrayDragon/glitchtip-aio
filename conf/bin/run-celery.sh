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

export DATABASE_URL="${DATABASE_URL:-postgres://postgres:${DB_PASSWORD:-postgres}@localhost:5432/postgres}"
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
    --without-heartbeat