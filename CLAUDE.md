# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Glitchtip All-in-One (AIO) deployment project that provides a single-container deployment solution for Glitchtip, an open-source error tracking and performance monitoring platform. The project uses Docker with Supervisor to manage multiple services (PostgreSQL, Redis, Django web application, and Celery worker) within a single container.

## Architecture

The project uses a single-container architecture with Supervisor managing multiple services:

- **PostgreSQL**: Primary database (port 5432)
- **Redis**: Caching and message broker (port 6379) 
- **Django Web Application**: Glitchtip main application (port 8000)
- **Celery Worker**: Background task processing
- **Supervisor**: Process management system

## Common Commands

### Development and Deployment

```bash
# Just command runner (recommended)
just deploy                    # Default deployment on port 8000
just deploy-port 8080          # Deploy on custom port
just deploy-persist            # Deploy with data persistence
just start/stop/restart        # Container lifecycle management
just status                    # Check container status
just logs                      # View logs (with subcommands for specific services)

# Build and rebuild
just rebuild                   # Rebuild Docker image
just clean                     # Clean up container and image

# Database operations
just backup                    # Backup database
just restore                   # Restore database
just migrate                   # Run Django migrations
just psql                      # Enter PostgreSQL shell
just redis                     # Enter Redis CLI

# Container interaction
just shell                     # Enter container shell
just django <command>          # Run Django management commands
```

### Environment Variables

Key environment variables for configuration:

```bash
# Application configuration
SECRET_KEY=your-secret-key
PORT=8000
GLITCHTIP_DOMAIN=http://localhost:8000
DEBUG=false

# Database and Redis
DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres
REDIS_URL=redis://localhost:6379/0
CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/0

# Email configuration
DEFAULT_FROM_EMAIL=glitchtip@localhost
EMAIL_URL=consolemail://

# Deployment options
PERSIST_DATA=false             # Enable data persistence
EXPOSE_WEB_PORT=true           # Expose web port
EXPOSE_DB_PORT=false           # Expose database port
EXPOSE_REDIS_PORT=false        # Expose Redis port
```

## Service Architecture

### Container Structure
- **Base Image**: `glitchtip/glitchtip:v5.1`
- **Process Manager**: Supervisor with individual service configurations
- **Data Storage**: Configurable persistence via Docker volumes
- **Health Checks**: Built-in health check endpoint at `/_health/`

### Service Dependencies
Services start in this order via Supervisor priority:
1. PostgreSQL (priority 100)
2. Redis (priority 200) 
3. Django migrations (priority 300)
4. Celery worker (priority 400)
5. Django web application (priority 500)

### Data Persistence
When `PERSIST_DATA=true`, the following directories are mounted:
- `/data/postgres/data` - PostgreSQL data
- `/data/redis/data` - Redis data
- `/backups` - Database backups
- `/logs` - Service logs
- `/uploads` - File uploads

## Build System

### Docker Image
- **Base**: Official `glitchtip/glitchtip:v5.1` image
- **Additional Packages**: PostgreSQL, Redis, Supervisor, net utilities
- **Package Sources**: Aliyun mirrors for faster Chinese access
- **Init System**: Custom entrypoint script with environment variable handling

### Just Commands
The project uses Just (https://just.systems) as a command runner:
- Configuration variables in `justfile`
- Environment variable support with `env_var_or_default()`
- Helper functions for deployment and management

## Configuration Files

### Key Files
- `Dockerfile` - Single-container image definition
- `justfile` - Command runner configuration
- `.dockerignore` - Docker build exclusions
- `.env.example` - Environment variable template
- `README.md` - Comprehensive documentation (in Chinese)

### Service Scripts (embedded in Dockerfile)
- `/code/bin/start-postgres.sh` - PostgreSQL initialization and startup
- `/code/bin/start-redis.sh` - Redis configuration and startup
- `/code/bin/run-migrate.sh` - Django migration runner
- `/code/bin/run-celery.sh` - Celery worker startup
- `/code/bin/run-web.sh` - Django web application startup
- `/usr/local/bin/health-check` - Service health verification

## Development Workflow

### Local Development
```bash
# Start development environment
just deploy

# View logs for specific service
just logs-app          # Django application
just logs-celery       # Celery worker
just logs-pgsql        # PostgreSQL
just logs-redis        # Redis

# Access services
just shell             # Container shell
just psql              # PostgreSQL shell
just redis             # Redis CLI
```

### Production Deployment
```bash
# Deploy with persistence
PERSIST_DATA=true just deploy-persist

# Backup and restore
just backup
just restore

# Update deployment
just rebuild
just deploy-persist
```

## Important Notes

### Security
- Default credentials are `postgres:postgres` for PostgreSQL
- Generate unique `SECRET_KEY` for production deployments
- Consider using HTTPS and proper authentication in production

### Performance
- Services run within a single container to reduce network overhead
- Supervisor ensures proper service startup order and restart policies
- Health checks monitor all critical services

### Maintenance
- Regular backups recommended via `just backup`
- Monitor logs with `just logs-*` commands
- Use `just status` to check service health
- Database migrations via `just migrate`