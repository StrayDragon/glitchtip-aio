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

### Essential Commands

```bash
# Deployment
just deploy                    # Deploy on port 8000
just deploy-port 8080          # Deploy on custom port
just deploy-persist            # Deploy with data persistence

# Container management
just start/stop/restart        # Container lifecycle
just status                    # Check service health
just logs                      # View all logs
just logs-app/celery/pgsql/redis # View specific service logs

# Database operations
just backup/restore            # Backup/restore database
just migrate                   # Run Django migrations
just psql/redis                # Enter database shell

# Container interaction
just shell                     # Enter container shell
just django <command>          # Run Django commands
just rebuild                   # Rebuild Docker image
just clean                     # Clean containers and images
```

### Key Environment Variables

```bash
# Core configuration
SECRET_KEY=your-secret-key     # Generate unique key for production
PORT=8000                      # Web application port
GLITCHTIP_DOMAIN=http://localhost:8000
DEBUG=false

# Data persistence
PERSIST_DATA=false             # Enable persistent volumes
EXPOSE_WEB_PORT=true           # Expose web port to host
EXPOSE_DB_PORT=false          # Expose database port to host
EXPOSE_REDIS_PORT=false       # Expose Redis port to host

# Database (default: postgres:postgres)
DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres
REDIS_URL=redis://localhost:6379/0
CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/0

# Email configuration
DEFAULT_FROM_EMAIL=glitchtip@localhost
EMAIL_URL=consolemail://
```

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
- **Health Check**: Available at `/_health/` endpoint
- **Service Scripts**: Embedded in Dockerfile for each service

### Service Management
Services are managed by Supervisor in priority order:
- `start-postgres.sh` - PostgreSQL initialization and startup
- `start-redis.sh` - Redis configuration and startup
- `start-web.sh` - Django web application
- `start-celery.sh` - Celery background worker

### Build System
- **Dockerfile**: Single-container image with all services
- **Just Commands**: Comprehensive task automation in `justfile`
- **No Traditional Build**: This is a deployment project, not a codebase

### Key Files
- `Dockerfile` - Container image definition with embedded service scripts
- `justfile` - Command runner configuration with comprehensive task automation
- `.env.example` - Environment variable template
- `README.md` - Comprehensive documentation (Chinese)
- `.gitmodules` - Git submodule configuration for source code

**No Testing/Linting**: This project has no traditional test suite or linting commands. Quality assurance comes from Docker health checks and service monitoring.

## Development Workflows

### Quick Start
```bash
just deploy                    # Start on port 8000
just logs-app                  # Monitor application
just status                    # Check health
```

### Production Deployment
```bash
PERSIST_DATA=true just deploy-persist  # Persistent data
just backup                          # Backup database
just rebuild && just deploy-persist   # Update deployment
```

### Development and Debugging
```bash
just shell                   # Access container shell
just django <command>        # Run Django commands
just logs-supervisor         # View supervisor logs
just logs-errors             # View error logs only
```

### Database Operations
```bash
just psql                    # Enter PostgreSQL shell
just redis                   # Enter Redis CLI
just backup                  # Create database backup
just restore                 # Restore from backup
just migrate                 # Run Django migrations
```

### Service Monitoring
```bash
just status                  # Check all service status
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
- Default PostgreSQL credentials: `postgres:postgres` (change for production)
- Generate unique `SECRET_KEY` for production deployments
- Use HTTPS and SSL certificates in production
- Configure firewall rules to limit port access
- Enable database authentication in production

### Production Optimizations
- Enable data persistence: `PERSIST_DATA=true`
- Configure resource limits: `docker run -m 2g --cpus=2.0`
- Set up monitoring and alerting
- Configure log rotation and backup schedules
- Use reverse proxy (Nginx/Apache) for SSL termination

## Architecture Benefits

- **Simplified Deployment**: Single container vs multi-container setups
- **Optimized for China**: Aliyun mirrors for faster access
- **Comprehensive Management**: All operations via Just commands
- **Production Ready**: Health checks, persistence, backup/restore
- **Resource Efficient**: Shared container resources reduce overhead
- **Reliable**: Supervisor ensures proper service startup order and auto-restart