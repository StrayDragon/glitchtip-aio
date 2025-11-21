#!/bin/bash
echo "Starting Django web server..."
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
        echo "Waiting for Redis to be ready..."
        sleep 2
    done
fi

export DJANGO_SETTINGS_MODULE=glitchtip.settings

# 优化Python环境
export PYTHONOPTIMIZE=1
export PYTHONUNBUFFERED=1

# 收集静态文件
echo "Collecting static files..."
python manage.py collectstatic --noinput --clear

# 设置默认端口
CURRENT_PORT=${PORT:-8000}

echo "Port configuration: PORT=${PORT}, CURRENT_PORT=${CURRENT_PORT}"

echo "Starting Gunicorn production server"
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
