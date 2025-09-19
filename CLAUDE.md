# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Glitchtip AIO is a single-container deployment solution for Glitchtip (open-source error tracking platform). This project bundles PostgreSQL, Redis, Django web app, and Celery worker in one Docker container managed by Supervisor.

**Note**: This is a deployment orchestration project, not a traditional codebase. There's no source code to develop or test - the focus is on container deployment and management.

## Architecture

Single-container with Supervisor managing services in priority order:
1. **PostgreSQL** (port 5432) - Primary database
2. **Redis** (port 6379) - Caching/message broker  
3. **Django Web App** (port 8000) - Glitchtip main application
4. **Celery Worker** - Background task processing
5. **Supervisor** - Process management system

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

# Database (default: postgres:postgres)
DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres
REDIS_URL=redis://localhost:6379/0
```

**Data Persistence** (when `PERSIST_DATA=true`):
- `/data/postgres/data` - PostgreSQL data
- `/data/redis/data` - Redis data  
- `/backups` - Database backups
- `/logs` - Service logs
- `/uploads` - File uploads

## Technical Details

### Container Structure
- **Base Image**: `glitchtip/glitchtip:v5.1` with PostgreSQL 17, Redis 7.x
- **Package Sources**: Aliyun mirrors for Chinese access optimization
- **Health Check**: Available at `/_health/` endpoint
- **Service Scripts**: Embedded in Dockerfile for each service

### Build System
- **Dockerfile**: Single-container image with all services
- **Just Commands**: Comprehensive task automation in `justfile`
- **No Traditional Build**: This is a deployment project, not a codebase

### Key Files
- `Dockerfile` - Container image definition
- `justfile` - Command runner configuration (11,542 lines)
- `.env.example` - Environment variable template
- `README.md` - Comprehensive documentation (Chinese)

**No Testing/Linting**: This project has no traditional test suite or linting commands. Quality assurance comes from Docker health checks and service monitoring.

## Working with This Project

### Common Workflows

**Quick Start**:
```bash
just deploy                    # Start on port 8000
just logs-app                  # Monitor application
just status                    # Check health
```

**Production Deployment**:
```bash
PERSIST_DATA=true just deploy-persist  # Persistent data
just backup                          # Backup database
just rebuild && just deploy-persist   # Update deployment
```

**Troubleshooting**:
```bash
just logs-[service]          # View specific service logs
just shell                   # Access container shell
just status                  # Check all service status
```

### Security Notes
- Default PostgreSQL credentials: `postgres:postgres`
- Generate unique `SECRET_KEY` for production
- Use HTTPS in production deployments

### Architecture Benefits
- **Simplified Deployment**: Single container vs multi-container setups
- **Optimized for China**: Aliyun mirrors for faster access
- **Comprehensive Management**: All operations via Just commands
- **Production Ready**: Health checks, persistence, backup/restore