# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Glitchtip AIO is a single-container deployment solution for Glitchtip (open-source error tracking platform). This project bundles PostgreSQL, Redis, Django web app, and Celery worker in one Docker container managed by Supervisor.

**Note**: This is a deployment orchestration project, not a traditional codebase. There's no source code to develop or test - the focus is on container deployment and management. The actual Glitchtip source code is managed as git submodules in `source_code/`.

## Architecture

Single-container with Supervisor managing services in priority order:
1. **PostgreSQL 17** (port 5432) - Primary database
2. **Redis 7.x** (port 6379) - Caching/message broker
3. **Django Web App** (port 8000) - Glitchtip main application
4. **Celery Worker** - Background task processing
5. **Supervisor 4.x+** - Process management system

## Common Commands

**This project uses Just (https://just.systems) as the command runner.**

The justfile imports additional command modules:
- `my.justfile` → `et.justfile` (ET-specific deployment commands)

### Essential Commands

```bash
# Deployment
just deploy-test               # Deploy container for testing
just et-deploy-test            # ET-specific test deployment with custom domain
just build                     # Rebuild Docker image
just clean                     # Clean containers and images
just et-push                   # Build and push to ET registry (overwrites latest)

# Container monitoring
just logs                      # View container logs
just logs-supervisor           # View supervisor logs
just logs-app                  # View application logs
just logs-celery               # View Celery logs
just logs-pgsql                # View PostgreSQL logs
just logs-redis                # View Redis logs
just logs-migrate              # View migration logs
just logs-web-errors           # View web error logs only
just logs-celery-errors        # View Celery error logs only

# Database operations
just backup                    # Backup database
just restore                   # Restore database (interactive)
just run-migrate               # Run Django migrations

# Container interaction
just it-shell                  # Enter container shell
just it-shell-psql             # Enter PostgreSQL shell
just it-shell-redis            # Enter Redis CLI
just it-django-mange <command> # Run Django commands

# Scheduled restart management
just run-scheduled-restart     # Manually execute scheduled restart script (testing)
just logs-scheduled-restart    # View scheduled restart logs
just logs-scheduled-restart-errors # View scheduled restart error logs

# Project management
just package-to-zip            # Package project to ZIP (excludes .gitignore files)
```

### Key Environment Variables

Based on `.env.example`:

```bash
# Container configuration
CONTAINER_NAME=glitchtip-aio
IMAGE_NAME=glitchtip-aio
DATA_DIR=./data
DEFAULT_PORT=8000
DEFAULT_DOMAIN=http://localhost:8000

# Django security configuration
ALLOWED_HOSTS=localhost,127.0.0.1
CSRF_TRUSTED_ORIGINS=http://localhost:8000
SECRET_KEY=                    # Generate unique key for production
DEBUG=false
ENABLE_USER_REGISTRATION=false
ENABLE_ORGANIZATION_CREATION=false
DEFAULT_FROM_EMAIL=glitchtip@localhost

# Data persistence
PERSIST_DATA=false             # Enable persistent volumes
EXPOSE_WEB_PORT=true           # Expose web port to host
EXPOSE_DB_PORT=false          # Expose database port to host
EXPOSE_REDIS_PORT=false       # Expose Redis port to host

# Security
DB_PASSWORD=                  # Database password (generate for production)
REDIS_PASSWORD=              # Redis password (optional)
DATABASE_POOL=false          # Connection pooling

# Email configuration
EMAIL_URL=consolemail://

# Performance
MAX_UPLOAD_SIZE=10485760      # 10MB

# Notification (Optional)
FEISHU_GROUP_DEVOPS_ROBOT_WEBHOOK_URL=  # Feishu webhook for restart notifications
```

### ET-Specific Configuration

For ET deployments, additional environment variables are used:
- **Domain**: `GLITCHTIP_DOMAIN=https://testglitchtip.easytransfer.cn`
- **Extended Retention**:
  - `GLITCHTIP_MAX_EVENT_LIFE_DAYS=90` (vs 7 days in test)
  - `GLITCHTIP_MAX_TRANSACTION_EVENT_LIFE_DAYS=180`
  - `GLITCHTIP_MAX_FILE_LIFE_DAYS=180`
- **Host Validation**: `ALLOWED_HOSTS="testglitchtip.easytransfer.cn,.svc.cluster.local,.localhost,127.0.0.1,[::1]"`
- **Registry**: `etservice-registry.cn-beijing.cr.aliyuncs.com/base/glitchtip-base:latest`

**Data Persistence** (when `PERSIST_DATA=true`):
- `/data/postgres/data` - PostgreSQL data
- `/data/redis/data` - Redis data
- `/data/backups` - Database backups
- `/data/logs` - Service logs
- `/data/uploads` - File uploads

## Technical Details

### Container Structure
- **Base Image**: `glitchtip/glitchtip:v5.1` with PostgreSQL 17, Redis 7.x
- **Package Sources**: Aliyun mirrors for Chinese access optimization
- **Health Check**: Available at `/_health/` endpoint with 30s intervals, 10s timeout
- **Security**: PostgreSQL restricted to localhost only, SCRAM-SHA-256 authentication
- **User Management**: Dedicated `glitchtip` user with proper permissions

### Service Management
Services are managed by Supervisor in priority order with dedicated log files:
- PostgreSQL - Database service (localhost only)
- Redis - Caching and message broker
- Gunicorn - Web application server
- Celery - Background task processor
- Scheduled Restart - Automatic daily maintenance (3:01 AM)
- Supervisor - Process management system

### Scheduled Restart Features
- **Schedule**: Every day at 3:01 AM (cron: `1 3 * * *`)
- **Implementation**: Python-based with comprehensive health monitoring
- **Health Checks**: PostgreSQL, Redis, Django application, Celery workers
- **Smart Logic**: Only restarts web/celery if base services are healthy
- **Enhanced Monitoring**: Process PID tracking, restart timing, system resource usage
- **Notifications**: Feishu webhook integration for restart reports (optional)
- **Logging**: Comprehensive logs in `/var/log/supervisor/scheduled-restart.log`
- **Detailed Information**: Memory/CPU/disk usage, network connections, load averages

### Build System
- **Dockerfile**: Single-container image with embedded service scripts from `conf/`
- **Just Commands**: Comprehensive task automation with detailed logging
- **Environment Configuration**: `.env` file based on `.env.example`
- **Docker Build Context**: `.dockerignore` excludes source code, data, logs, and development files
- **No Traditional Build**: This is a deployment project, not a codebase

### Key Files
- `Dockerfile` - Container image definition with embedded service scripts
- `justfile` - Command runner configuration with comprehensive task automation
- `.env.example` - Detailed environment variable template with security configurations
- `README.md` - Comprehensive documentation in Chinese with deployment guides
- `LICENSE` - MIT license
- `conf/` - Service configuration scripts (managed as git submodules)

**No Testing/Linting**: This project has no traditional test suite or linting commands. Quality assurance comes from Docker health checks and service monitoring.

## Development Workflows

### Quick Start
```bash
just deploy-test             # Deploy container for testing
just logs-app                # Monitor application
docker ps | grep glitchtip    # Check container status
```

### Production Deployment
1. **Prepare environment**:
   ```bash
   cp .env.example .env
   # Edit .env with production settings
   PERSIST_DATA=true
   EXPOSE_DB_PORT=false
   EXPOSE_REDIS_PORT=false
   SECRET_KEY=$(openssl rand -hex 32)
   DB_PASSWORD=$(openssl rand -hex 32)
   ```

2. **Deploy and manage**:
   ```bash
   just build                 # Rebuild with production settings
   docker run -d --env-file .env ...  # Deploy container
   just backup               # Backup database regularly
   ```

### Development and Debugging
```bash
just it-shell                # Access container shell
just it-django-mange <cmd>   # Run Django commands
just logs-supervisor         # View supervisor logs
just logs-errors             # View error logs only
```

### Database Operations
```bash
just it-shell-psql           # Enter PostgreSQL shell
just it-shell-redis          # Enter Redis CLI
just backup                  # Create database backup
just restore                 # Restore from backup
just run-migrate             # Run Django migrations
```

### Service Monitoring
```bash
docker ps | grep glitchtip    # Check container status
docker inspect <container> | grep Health  # Check health status
curl http://localhost:8000/_health/  # Test health endpoint
just logs-app                # Monitor Django application
just logs-celery             # Monitor Celery worker
just logs-pgsql              # Monitor PostgreSQL
just logs-redis              # Monitor Redis
```

## Source Code Structure

The actual Glitchtip source code is managed as git submodules:
- `source_code/glitchtip` - Main Glitchtip repository
- `source_code/glitchtip-backend` - Django backend (GitLab)
- `source_code/glitchtip-frontend` - Angular frontend (GitLab)

These are reference-only for deployment purposes - modifications should be made in the upstream repositories.

## Security and Production Notes

### Security Configuration
- **Database Security**: PostgreSQL restricted to localhost only with SCRAM-SHA-256 authentication
- **Password Management**: Generate strong `DB_PASSWORD` and `SECRET_KEY` for production
- **Port Security**: Only expose web port (8000) externally, keep DB/Redis internal
- **Host Validation**: Configure `ALLOWED_HOSTS` and `CSRF_TRUSTED_ORIGINS` properly
- **User Controls**: Disable `ENABLE_USER_REGISTRATION` and `ENABLE_ORGANIZATION_CREATION` in production
- **HTTPS**: Use SSL certificates and reverse proxy for production deployments

### Production Optimizations
- **Data Persistence**: Enable `PERSIST_DATA=true` for data survival across container restarts
- **Resource Limits**: Configure `docker run -m 2g --cpus=2.0` for resource constraints
- **Backup Strategy**: Implement regular backups using `just backup` with cron scheduling
- **Monitoring**: Set up health check monitoring and alerting
- **Log Management**: Configure log rotation and centralized logging
- **Reverse Proxy**: Use Nginx/Apache for SSL termination and load balancing
- **Network Security**: Implement firewall rules and private networks

## Architecture Benefits

- **Simplified Deployment**: Single container vs multi-container setups
- **Optimized for China**: Aliyun mirrors for faster access
- **Comprehensive Management**: All operations via Just commands
- **Production Ready**: Health checks, persistence, backup/restore
- **Resource Efficient**: Shared container resources reduce overhead
- **Reliable**: Supervisor ensures proper service startup order and auto-restart
