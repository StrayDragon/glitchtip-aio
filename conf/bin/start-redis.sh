#!/bin/bash
echo "Starting Redis..."

# 创建必要的目录
mkdir -p /data/redis /var/run/redis /var/log/redis

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