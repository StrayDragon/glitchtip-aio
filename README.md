# Glitchtip AIO - 单容器部署方案

基于 `glitchtip/glitchtip:v5.1` 的单容器部署方案，集成了 PostgreSQL、Redis 和 Glitchtip 服务，支持一键部署。

## 快速开始

### 一键部署

```bash
# 即用即销毁模式（数据存储在容器内部）
./deploy.sh

# 数据持久化模式（数据存储在宿主机）
PERSIST_DATA=true ./deploy.sh

# 自定义端口部署
./deploy.sh 8080

# 自定义端口和域名
./deploy.sh 8080 http://yourdomain.com

# 完整自定义（数据持久化模式）
PERSIST_DATA=true ./deploy.sh 8080 http://yourdomain.com /custom/data/path
```

### 服务管理

```bash
# 启动服务
./manage.sh start

# 停止服务
./manage.sh stop

# 重启服务
./manage.sh restart

# 查看日志
./manage.sh logs

# 查看状态
./manage.sh status

# 备份数据库
./manage.sh backup

# 恢复数据库
./manage.sh restore

# 运行数据库迁移
./manage.sh migrate

# 进入容器
./manage.sh shell

# 进入数据库
./manage.sh psql

# 进入 Redis
./manage.sh redis

# 显示系统信息
./manage.sh info
```

## 优化特性

### 性能优化
- **基础镜像**: 使用官方 `glitchtip/glitchtip:v5.1`，避免重复构建
- **镜像源**: 阿里云 APT 源 + Python pip 源，国内访问速度快
- **进程管理**: Supervisor 精确控制各服务启动顺序

### 稳定性优化
- **健康检查**: 内置完整的服务健康检查机制
- **自动重启**: 容器异常退出时自动重启
- **错误处理**: 完善的错误处理和重试机制

### 易用性优化
- **一键部署**: 自动处理所有依赖和配置
- **智能检测**: 自动检测端口占用、网络连接等
- **详细日志**: 清晰的进度提示和错误信息

## 包含的服务

| 服务 | 版本 | 端口 | 说明 |
|------|------|------|------|
| PostgreSQL | 17 | 5432 | 主数据库 |
| Redis | 7.x | 6379 | 缓存和消息队列 |
| Django | 4.x+ | 8000 | Glitchtip 主应用 |
| Celery | 5.x+ | - | 后台任务处理 |
| Supervisor | 4.x+ | - | 进程管理器 |

## 配置选项

### 环境变量

```bash
# 应用配置
SECRET_KEY=your-secret-key
PORT=8000
GLITCHTIP_DOMAIN=http://localhost:8000
DEBUG=false

# 数据库配置
DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres

# Redis 配置
REDIS_URL=redis://localhost:6379/0
CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/0

# 邮件配置
DEFAULT_FROM_EMAIL=glitchtip@localhost
EMAIL_URL=consolemail://
```

### 镜像源配置

```bash
# APT 源（阿里云）
deb https://mirrors.aliyun.com/debian/ bookworm main
deb https://mirrors.aliyun.com/debian/ bookworm-updates main

# Python pip 源（阿里云）
https://mirrors.aliyun.com/pypi/simple/
```

## 访问地址

- **Web 应用**: http://localhost:8000
- **健康检查**: http://localhost:8000/_health/
- **API 文档**: http://localhost:8000/api/
- **管理后台**: http://localhost:8000/admin/

### 数据库连接

```bash
# PostgreSQL
Host: localhost
Port: 5432
Database: postgres
Username: postgres
Password: postgres

# Redis
Host: localhost
Port: 6379
```

## 监控和日志

### 实时监控

```bash
# 查看容器状态
./manage.sh status

# 查看资源使用
docker stats glitchtip-aio

# 查看进程状态
docker exec glitchtip-aio supervisorctl status
```

### 日志管理

```bash
# 查看所有日志
./manage.sh logs

# 查看特定服务日志
docker logs glitchtip-aio | grep postgres
docker logs glitchtip-aio | grep redis
docker logs glitchtip-aio | grep web

# 查看最近的错误
docker logs --tail 100 glitchtip-aio | grep ERROR
```

## 开发和维护

### 数据库操作

```bash
# 进入数据库
./manage.sh psql

# 备份数据库
./manage.sh backup

# 恢复数据库
./manage.sh restore

# 手动备份
docker exec glitchtip-aio pg_dump -U postgres > backup.sql

# 手动恢复
docker exec -i glitchtip-aio psql -U postgres < backup.sql
```

### Redis 操作

```bash
# 进入 Redis CLI
./manage.sh redis

# 查看键值
docker exec glitchtip-aio redis-cli KEYS "*"

# 清空缓存
docker exec glitchtip-aio redis-cli FLUSHALL

# 查看信息
docker exec glitchtip-aio redis-cli INFO
```

### 容器管理

```bash
# 进入容器 shell
./manage.sh shell

# 重新构建镜像
./manage.sh rebuild

# 更新到最新版本
./manage.sh update

# 清理容器和镜像
./manage.sh clean
```

## 性能优化建议

### 系统配置

```bash
# 增加文件描述符限制
ulimit -n 65536

# 优化内核参数
echo 'net.core.somaxconn = 65535' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_max_syn_backlog = 65535' >> /etc/sysctl.conf
sysctl -p
```

### Docker 配置

```bash
# 限制内存使用
docker run -m 2g --memory-swap 3g ...

# 限制 CPU 使用
docker run --cpus=2.0 ...

# 添加健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3
```

## 版本更新

### 更新到最新版本

```bash
# 自动更新
./manage.sh update

# 手动更新
docker pull glitchtip/glitchtip:v5.1
./manage.sh rebuild
```

### 版本回滚

```bash
# 查看可用版本
docker images glitchtip/glitchtip

# 使用特定版本
docker run ... glitchtip/glitchtip:v5.0
```

## 数据持久化

### 自动数据持久化

默认情况下，所有部署都会自动创建数据目录并进行卷挂载：

```bash
# 部署时自动创建的数据结构
data/
├── postgres/data/    # PostgreSQL 数据
├── redis/data/       # Redis 数据
├── backups/          # 备份文件
├── logs/             # 日志文件
└── uploads/          # 上传文件
```

### 数据库迁移管理

```bash
# 运行数据库迁移
./manage.sh migrate

# 查看迁移状态
docker exec glitchtip-aio python manage.py showmigrations

# 创建迁移文件
docker exec -it glitchtip-aio python manage.py makemigrations

# 回滚迁移
docker exec glitchtip-aio python manage.py migrate <app_name> <migration_name>
```

### 备份和恢复

```bash
# 创建备份
./manage.sh backup

# 恢复备份
./manage.sh restore

# 手动备份
docker exec glitchtip-aio pg_dump -U postgres | gzip > backup-$(date +%Y%m%d).sql.gz

# 手动恢复
gunzip -c backup-20231201.sql.gz | docker exec -i glitchtip-aio psql -U postgres
```

### 系统信息查看

```bash
# 查看详细的系统信息
./manage.sh info

# 查看容器资源使用
docker stats glitchtip-aio

# 查看进程状态
docker exec glitchtip-aio supervisorctl status
```

## 注意事项

### 安全性

1. **生产环境**: 修改默认密码和密钥
2. **HTTPS**: 配置 SSL 证书
3. **防火墙**: 限制端口访问
4. **备份**: 定期备份数据

### 数据持久化

1. **数据库**: 使用卷挂载持久化数据
2. **文件上传**: 配置外部存储
3. **日志**: 配置日志轮转

### 监控告警

1. **健康检查**: 监控服务状态
2. **资源使用**: 监控 CPU、内存、磁盘
3. **错误日志**: 设置错误告警

## 故障排除

### 常见问题

1. **端口冲突**
   ```bash
   # 检查端口占用
   netstat -tulpn | grep :8000
   # 使用其他端口
   ./deploy.sh 8080
   ```

2. **镜像拉取失败**
   ```bash
   # 配置 Docker 镜像加速
   sudo mkdir -p /etc/docker
   sudo tee /etc/docker/daemon.json <<-'EOF'
   {
     "registry-mirrors": ["https://mirrors.aliyun.com"]
   }
   EOF
   sudo systemctl restart docker
   ```

3. **内存不足**
   ```bash
   # 检查内存使用
   free -h
   # 增加交换空间
   sudo fallocate -l 2G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

4. **服务启动缓慢**
   ```bash
   # 查看启动日志
   docker logs glitchtip-aio
   # 检查资源使用
   docker stats glitchtip-aio
   ```

### 调试技巧

```bash
# 查看容器内部进程
docker top glitchtip-aio

# 查看容器配置
docker inspect glitchtip-aio

# 进入调试模式
docker exec -it glitchtip-aio bash

# 查看网络连接
docker exec glitchtip-aio netstat -tulpn
```

## 性能对比

| 指标 | 原版 Compose | 优化版单容器 |
|------|-------------|-------------|
| 启动时间 | 2-3 分钟 | 1-2 分钟 |
| 镜像大小 | ~2GB | ~1.5GB |
| 内存使用 | ~1GB | ~800MB |
| 部署复杂度 | 高 | 低 |
| 网络开销 | 多容器通信 | 单容器内部 |
| 维护难度 | 中等 | 简单 |

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

本项目遵循与原 Glitchtip 项目相同的许可证。

---

**提示**: 
- 首次部署请使用 `./deploy.sh`，日常管理使用 `./manage.sh`
- 默认为即用即销毁模式，数据存储在容器内部
- 设置 `PERSIST_DATA=true` 启用数据持久化模式
- 数据持久化模式适合生产环境和需要长期使用的场景
