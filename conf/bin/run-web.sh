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

export DATABASE_URL="${DATABASE_URL:-postgres://postgres:${DB_PASSWORD:-postgres}@localhost:5432/postgres}"
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

echo "Starting Gunicorn production server..."
exec gunicorn glitchtip.wsgi:application \
    --bind 0.0.0.0:8000 \
    --workers 2 \
    --threads 4 \
    --timeout 120 \
    --keep-alive 5 \
    --max-requests 1000 \
    --max-requests-jitter 100 \
    --access-logfile - \
    --error-logfile - \
    --log-level info \
    --capture-output
