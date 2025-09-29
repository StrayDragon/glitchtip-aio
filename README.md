# Glitchtip AIO - All-in-One 容器化部署

Glitchtip AIO 是一个单容器部署解决方案，将 Glitchtip（开源错误跟踪平台）与其所有依赖项（PostgreSQL、Redis、Django、Celery）打包在一个 Docker 容器中。

## 🚀 快速开始

### 1. 配置管理

```bash
# 初始化配置文件
./manage-config.sh init

# 设置生产环境配置
./manage-config.sh prod

# 设置开发环境配置
./manage-config.sh dev

# 显示当前配置
./manage-config.sh show

# 测试配置文件
./manage-config.sh test
```

### 2. 快速部署

```bash
# 部署开发环境
./quick-deploy.sh dev

# 部署生产环境
./quick-deploy.sh prod

# 使用自定义配置部署
./quick-deploy.sh custom
```

### 3. 使用 Just 命令

```bash
# 基础部署
just deploy

# 自定义端口部署
just deploy-port 9000

# 自定义域名部署
just deploy-custom 8000 https://mydomain.com

# 生产环境部署
just deploy-prod https://mydomain.com
```

## 📋 环境变量配置

### 关键配置项

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `DEFAULT_DOMAIN` | `http://localhost:8004` | 访问域名 |
| `ALLOWED_HOSTS` | `localhost,127.0.0.1` | 允许的主机名 |
| `CSRF_TRUSTED_ORIGINS` | `$DEFAULT_DOMAIN` | CSRF 可信来源 |
| `ENABLE_USER_REGISTRATION` | `false` | 是否允许用户注册 |
| `ENABLE_ORGANIZATION_CREATION` | `false` | 是否允许组织创建 |
| `DEBUG` | `false` | 调试模式 |
| `SECRET_KEY` | 自动生成 | Django 密钥 |
| `DB_PASSWORD` | 自动生成 | 数据库密码 |
| `PERSIST_DATA` | `false` | 数据持久化 |

### 完整配置示例

```bash
# .env 文件示例
DEFAULT_DOMAIN=https://mydomain.com
ALLOWED_HOSTS=localhost,127.0.0.1,mydomain.com
CSRF_TRUSTED_ORIGINS=https://mydomain.com
ENABLE_USER_REGISTRATION=false
ENABLE_ORGANIZATION_CREATION=false
DEBUG=false
SECRET_KEY=your-secret-key-here
DB_PASSWORD=your-database-password
PERSIST_DATA=true
```

## 🛡️ 安全特性

### 已实现的安全措施

- ✅ **数据库安全**: PostgreSQL 只允许本地访问
- ✅ **端口安全**: 只暴露 Web 服务端口
- ✅ **认证安全**: SCRAM-SHA-256 强认证
- ✅ **CSRF 保护**: 可信来源配置
- ✅ **主机验证**: ALLOWED_HOSTS 配置
- ✅ **用户管理**: 可禁用注册和组织创建
- ✅ **进程隔离**: 专用用户运行服务

### 安全最佳实践

1. **生产环境配置**
   ```bash
   ENABLE_USER_REGISTRATION=false
   ENABLE_ORGANIZATION_CREATION=false
   DEBUG=false
   ```

2. **网络安全**
   ```bash
   EXPOSE_DB_PORT=false
   EXPOSE_REDIS_PORT=false
   ```

3. **强密码配置**
   ```bash
   DB_PASSWORD=$(openssl rand -hex 32)
   SECRET_KEY=$(openssl rand -hex 32)
   ```

## 🔧 管理脚本

### 配置管理脚本 (`manage-config.sh`)

```bash
./manage-config.sh init      # 初始化配置
./manage-config.sh prod      # 生产环境配置
./manage-config.sh dev       # 开发环境配置
./manage-config.sh show      # 显示当前配置
./manage-config.sh test      # 测试配置
./manage-config.sh clean     # 清理文件
```

### 快速部署脚本 (`quick-deploy.sh`)

```bash
./quick-deploy.sh dev        # 开发环境部署
./quick-deploy.sh prod       # 生产环境部署
./quick-deploy.sh custom     # 自定义配置部署
```

### Just 命令

```bash
# 部署命令
just deploy                    # 默认部署
just deploy-port 8080          # 自定义端口
just deploy-custom 9000 https://mydomain.com  # 自定义域名

# 容器管理
just start/stop/restart        # 容器生命周期
just status                    # 检查状态
just logs                      # 查看日志

# 数据库操作
just backup/restore            # 备份/恢复
just migrate                   # 运行迁移
just psql/redis                # 进入数据库

# 用户管理
just user-create email         # 创建用户
just user-list                 # 列出用户
just user-superuser email      # 设置超级用户
```

## 📊 服务状态

### 健康检查

容器包含健康检查，可以通过以下方式检查：

```bash
# 检查容器状态
docker ps | grep glitchtip-aio

# 查看健康状态
docker inspect glitchtip-aio | grep Health

# 访问健康检查端点
curl http://localhost:8004/_health/
```

### 服务进程

容器内的服务包括：
- **PostgreSQL**: 数据库服务
- **Redis**: 缓存和消息队列
- **Gunicorn**: Web 应用服务器
- **Celery**: 后台任务处理器
- **Supervisor**: 进程管理器

## 🔌 SDK 集成

### SDK 配置

```javascript
// JavaScript SDK
Sentry.init({
  dsn: 'https://your-key@your-domain.com/1',
});
```

```python
# Python SDK
import sentry_sdk
sentry_sdk.init(
    dsn="https://your-key@your-domain.com/1",
)
```

### 重要说明

SDK 集成**不受** `ALLOWED_HOSTS` 和 `CSRF_TRUSTED_ORIGINS` 限制，可以安全使用。

## 🐛 故障排除

### 常见问题

1. **Origin 检查失败**
   ```bash
   # 检查 ALLOWED_HOSTS 和 CSRF_TRUSTED_ORIGINS 配置
   ./manage-config.sh show
   ```

2. **数据库连接问题**
   ```bash
   # 检查数据库服务状态
   just logs-pgsql
   ```

3. **容器启动失败**
   ```bash
   # 查看详细日志
   docker logs glitchtip-aio
   ```

### 测试脚本

```bash
# 运行集成测试
./test-sdk-integration.sh

# 测试配置文件
./manage-config.sh test
```

## 📁 项目文件结构

```
glitchtip-aio/
├── .env                    # 环境配置文件（运行时生成）
├── .env.example           # 配置模板
├── .env.production        # 生产环境配置示例
├── .env.development       # 开发环境配置示例
├── Dockerfile             # 容器定义
├── justfile              # Just 命令配置
├── manage-config.sh       # 配置管理脚本
├── quick-deploy.sh       # 快速部署脚本
├── test-sdk-integration.sh # SDK 集成测试脚本
├── conf/
│   ├── bin/              # 服务脚本
│   ├── supervisor/       # Supervisor 配置
│   └── etc/              # 配置文件
├── data/                 # 数据目录（可选）
└── README.md             # 项目文档
```

## 📚 相关文档

- [Glitchtip 官方文档](https://glitchtip.com/documentation/)
- [Docker 安全最佳实践](https://docs.docker.com/engine/security/)
- [Django 部署清单](https://docs.djangoproject.com/en/stable/howto/deployment/checklist/)

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

本项目遵循 MIT 许可证。