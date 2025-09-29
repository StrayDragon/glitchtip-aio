#!/bin/bash
set -e

echo "Starting PostgreSQL..."

# 初始化数据库（如果需要）
if [ ! -f "/data/postgres/PG_VERSION" ]; then
    echo "Initializing PostgreSQL database..."
    # 初始化数据库时设置密码
    echo "${DB_PASSWORD}" > /tmp/postgres_pw
    /usr/lib/postgresql/17/bin/initdb -D /data/postgres --auth-host=scram-sha-256 --auth-local=scram-sha-256 --pwfile=/tmp/postgres_pw
    rm -f /tmp/postgres_pw

    # 确保访问权限配置正确 - 只允许本地访问
    cat >> /data/postgres/pg_hba.conf << PGEOF
host all all 127.0.0.1/32 scram-sha-256
host all all ::1/128 scram-sha-256
local all all scram-sha-256
PGEOF

    # 基本配置已在initdb时设置，这里添加优化配置
    cat >> /data/postgres/postgresql.conf << PGEOF
# Performance optimizations for container environment
listen_addresses = 'localhost'
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