# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Glitchtip All-in-One (AIO) deployment project. Glitchtip is an open-source error tracking and performance monitoring platform, similar to Sentry. This repository provides a simplified deployment configuration using Docker Compose.

## Architecture

The project consists of a single Docker Compose configuration that orchestrates multiple services:

- **web**: Main Glitchtip web application (Django-based)
- **worker**: Celery worker for background tasks
- **postgres**: PostgreSQL database
- **redis**: Redis/Valkey for caching and task queue
- **migrate**: Database migration service

## Common Commands

### Development Setup

```bash
# Copy and configure the docker-compose file
cp docker-compose.example.yaml docker-compose.yaml
# Edit docker-compose.yaml with your configuration

# Start all services
docker-compose up -d

# Run database migrations
docker-compose run migrate

# View logs
docker-compose logs -f web
```

### Production Deployment

```bash
# Start production environment
docker-compose -f docker-compose.yaml up -d

# Stop services
docker-compose down

# Update to latest version
docker-compose pull
docker-compose up -d
```

### Maintenance

```bash
# Access database
docker-compose exec postgres psql -U postgres

# Access Redis
docker-compose exec redis redis-cli

# Run Django management commands
docker-compose exec web python manage.py <command>
```

## Configuration

Key environment variables that need to be configured:

- `SECRET_KEY`: Generate with `openssl rand -hex 32`
- `DATABASE_URL`: PostgreSQL connection string
- `GLITCHTIP_DOMAIN`: Your domain name
- `DEFAULT_FROM_EMAIL`: Email for notifications
- `EMAIL_URL`: SMTP configuration for emails

## Service Architecture

- **Web Service**: Runs on port 8000, handles HTTP requests
- **Worker Service**: Processes background tasks with Celery
- **PostgreSQL**: Primary data storage
- **Redis**: Caching and Celery message broker
- **Volumes**: Persistent storage for database (`pg-data`) and file uploads (`uploads`)

## Important Notes

- The web and worker services use the same Glitchtip Docker image
- Celery worker is configured to autoscale between 1-3 processes by default
- Database authentication is set to "trust" in the example - consider adding authentication for production
- All services are configured to restart automatically unless stopped