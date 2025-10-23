# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Glitchtip AIO is a single-container deployment solution that packages Glitchtip (open-source error tracking platform) with all dependencies (PostgreSQL, Redis, Django, Celery) in one Docker container. This is designed for cloud environment testing using container-image deployment mode. **Not recommended for production environments**.

## Architecture

This is an all-in-one container containing:
- **Backend**: Django-based GlitchTip application with multiple apps (alerts, event_ingest, files, organizations, etc.)
- **Frontend**: Angular 20 application with Material Design components
- **Database**: PostgreSQL with partitioning support
- **Task Queue**: Celery with Redis for background tasks
- **Web Server**: Uvicorn ASGI server managed by Supervisor

### Prefer source_code for more details for build dockerfile

- **source_code/glitchtip-backend/**: Django backend application
  - `apps/`: Django apps (alerts, event_ingest, files, organizations, etc.)
  - `glitchtip/`: Core Django configuration and ASGI application
  - `bin/`: Various runtime scripts for different deployment scenarios
  - `manage.py`: Django management script

- **source_code/glitchtip-frontend/**: Angular frontend application
  - Built with Angular 20, Angular Material, and RxJS
  - Uses Storybook for component documentation
  - Supports i18n (English, French, Norwegian)

## Container Deployment

The main `Dockerfile` creates a self-contained container with:
- Supervisor managing all processes
- PostgreSQL and Redis running locally
- Health checks via `/code/bin/health-check`
- All dependencies bundled using APT packages from Aliyun mirrors

Configuration files are in `conf/` directory:
- `conf/bin/`: Runtime scripts and health checks
- `conf/supervisor/`: Process management configuration
- `conf/etc/entrypoint.sh`: Container entry point

## Important Notes

- This AIO (All-In-One) setup is specifically designed for testing in cloud environments
- The container runs multiple services (PostgreSQL, Redis, Django, Celery) in a single process
- Uses Chinese mirror sources (mirrors.aliyun.com) for faster package installation
- Database persists to `/data/postgres`, Redis data to `/data/redis`
- Web service exposed on port 8000
- Celery worker automatically restarts every 6 hours to mitigate memory leaks
