# Glitchtip AIO - 单容器部署方案

这是一个将 Glitchtip 所有服务打包到单个 Docker 容器中的解决方案，实现一键部署，无需 Docker Compose。

## 🚀 快速开始

### 一键部署

```bash
# 默认配置部署（端口 8000）
./deploy.sh

# 自定义端口部署
./deploy.sh 8080

# 自定义端口和域名
./deploy.sh 8080 http://yourdomain.com
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

# 清理容器和镜像
./manage.sh clean
```

## 📋 包含的服务

- **PostgreSQL 17** - 主数据库 (端口 5432)
- **Redis/Valkey** - 缓存和消息队列 (端口 6379)
- **Django Web 应用** - Glitchtip 主应用 (端口 8000)
- **Celery Worker** - 后台任务处理
- **Supervisor** - 进程管理器

## 🔧 配置选项

### 环境变量

- `SECRET_KEY` - Django 密钥 (自动生成)
- `PORT` - Web 服务端口 (默认: 8000)
- `GLITCHTIP_DOMAIN` - 访问域名 (默认: http://localhost:8000)
- `DEFAULT_FROM_EMAIL` - 发件人邮箱
- `DEBUG` - 调试模式 (默认: false)

### 数据持久化

- PostgreSQL 数据存储在容器内 `/data/postgres`
- 文件上传存储在容器内 `/data/uploads`
- **注意**: 单容器方案数据持久化有限，生产环境建议使用外部数据库

## 🌐 访问地址

- **Web 应用**: http://localhost:8000
- **健康检查**: http://localhost:8000/_health/
- **数据库**: localhost:5432 (用户: postgres, 密码: postgres)
- **Redis**: localhost:6379

## 🔍 健康检查

容器包含健康检查功能，每 30 秒检查一次服务状态：

```bash
# 手动检查
curl http://localhost:8000/_health/
```

## 📊 监控和日志

```bash
# 查看容器日志
docker logs -f glitchtip-aio

# 查看特定服务日志
docker logs glitchtip-aio | grep -E "(postgres|redis|web|celery)"

# 进入容器
docker exec -it glitchtip-aio bash

# 查看进程状态
docker exec glitchtip-aio supervisorctl status
```

## 🛠️ 开发和维护

### 重新构建镜像

```bash
# 修改 Dockerfile 后重新构建
docker build -t glitchtip-aio .

# 重启容器
docker restart glitchtip-aio
```

### 数据库操作

```bash
# 进入数据库
docker exec -it glitchtip-aio psql -U postgres

# 备份数据库
docker exec glitchtip-aio pg_dump -U postgres > backup.sql

# 恢复数据库
docker exec -i glitchtip-aio psql -U postgres < backup.sql
```

### Redis 操作

```bash
# 进入 Redis CLI
docker exec -it glitchtip-aio redis-cli

# 清空缓存
docker exec glitchtip-aio redis-cli FLUSHALL
```

## ⚠️ 注意事项

1. **生产环境**：请修改默认数据库密码
2. **数据备份**：定期备份重要数据
3. **资源限制**：根据服务器资源调整配置
4. **HTTPS**：生产环境建议配置 HTTPS
5. **安全性**：默认配置适合测试，生产环境需要加固

## 🔄 与 Docker Compose 方案对比

| 特性 | 单容器方案 | Docker Compose 方案 |
|------|-----------|-------------------|
| 部署复杂度 | ⭐ 简单 | ⭐⭐ 中等 |
| 资源使用 | ⭐⭐ 较高 | ⭐⭐⭐ 较优 |
| 扩展性 | ⭐ 有限 | ⭐⭐⭐ 良好 |
| 数据持久化 | ⭐⭐ 中等 | ⭐⭐⭐ 优秀 |
| 维护难度 | ⭐ 简单 | ⭐⭐ 中等 |
| 适合场景 | 快速测试、开发环境 | 生产环境、大规模部署 |

## 🐛 故障排除

### 常见问题

1. **端口冲突**
   ```bash
   # 检查端口占用
   netstat -tulpn | grep :8000
   # 使用其他端口
   ./deploy.sh 8080
   ```

2. **容器启动失败**
   ```bash
   # 查看详细错误
   docker logs glitchtip-aio
   # 检查 Docker 状态
   docker info
   ```

3. **服务无法访问**
   ```bash
   # 检查容器状态
   docker ps
   # 检查防火墙
   sudo ufw status
   ```

4. **内存不足**
   ```bash
   # 检查资源使用
   docker stats glitchtip-aio
   # 增加内存限制
   docker run -m 2g ...
   ```

## 📝 更新日志

- v1.0.0 - 初始版本，支持一键部署
- 包含完整的 Glitchtip 服务栈
- 集成进程管理和健康检查

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

本项目遵循与原 Glitchtip 项目相同的许可证。
