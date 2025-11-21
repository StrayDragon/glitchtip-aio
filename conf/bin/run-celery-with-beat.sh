#!/bin/bash
# Celery Worker + Beat 启动脚本 - 官方 compose.yml 中的 bin/run-celery-with-beat.sh
echo "Starting Celery worker with Beat scheduler..."

cd /code

# Load environment variables
source /code/etc/environment.sh

# 等待依赖服务启动
until nc -z localhost 5432; do
    echo "Waiting for PostgreSQL to be ready..."
    sleep 2
done

# Only wait for Redis if not disabled
if [ "${DISABLE_REDIS:-false}" != "true" ]; then
    until nc -z localhost 6379; do
        echo "Waiting for Redis/Valkey to be ready..."
        sleep 2
    done
fi

export DJANGO_SETTINGS_MODULE=glitchtip.settings
export PYTHONPATH=/code

# Celery 性能配置
export CELERY_WORKER_CONCURRENCY="${CELERY_WORKER_CONCURRENCY:-4}"
export CELERY_WORKER_PREFETCH_MULTIPLIER="${CELERY_WORKER_PREFETCH_MULTIPLIER:-25}"
export CELERY_WORKER_POOL="${CELERY_WORKER_POOL:-threads}"
export CELERY_SKIP_CHECKS="${CELERY_SKIP_CHECKS:-true}"
export CELERY_LOG_LEVEL="${CELERY_LOG_LEVEL:-info}"

# 设置优化参数
export C_FORCE_ROOT=true
export PYTHONOPTIMIZE=1

echo "Environment Configuration:"
echo "   Database: ${DATABASE_URL}"
echo "   Broker: ${CELERY_BROKER_URL}"
echo "   Result Backend: ${CELERY_RESULT_BACKEND}"
echo "   Concurrency: ${CELERY_WORKER_CONCURRENCY}"
echo "   Pool: ${CELERY_WORKER_POOL}"

# 启动 Celery worker with beat (官方配置 + 性能参数)
# 使用最简化的配置确保启动成功
exec celery -A glitchtip worker -B --loglevel=info