# Example Dockerfile - Simple Glitchtip AIO container
# This is a simplified version that uses the base image with minimal configuration
#
# DATA PERSISTENCE AND VOLUME MOUNTING:
#
# Base image uses /data directory structure:
#   /data/postgres    - PostgreSQL database files (PG_VERSION, PG_DATA, etc.)
#   /data/redis       - Redis data files (dump.rdb, etc.)
#   /data/backups     - Database backup files
#   /data/logs        - Application logs
#   /data/uploads     - File uploads
#
# USAGE EXAMPLES:
#
# 1. Self-contained (data lost when container removed):
#    docker build -t glitchtip-aio-example .
#    docker run -d -p 8000:8000 --name glitchtip-aio-example glitchtip-aio-example
#
# 2. With persistent data (recommended for production):
#    docker run -d -p 8000:8000 --name glitchtip-aio-example \
#           -v /host/path/postgres:/data/postgres \
#           -v /host/path/redis:/data/redis \
#           -v /host/path/backups:/data/backups \
#           -v /host/path/logs:/data/logs \
#           -v /host/path/uploads:/data/uploads \
#           glitchtip-aio-example
#
# 3. Single volume mount (mounts entire /data structure):
#    docker run -d -p 8000:8000 --name glitchtip-aio-example \
#           -v /host/path/glitchtip-data:/data \
#           glitchtip-aio-example
#
# IMPORTANT NOTES:
# - Base image automatically creates /data directories if they don't exist
# - Base image sets proper permissions: postgres:postgres for /data/postgres, redis:redis for /data/redis
# - For production, always use volume mounts to prevent data loss
# - PostgreSQL data requires proper permissions on host directories
# - First run will initialize PostgreSQL database in /data/postgres
# - Redis will save data to /data/redis/dump.rdb
# - Health check available at: curl http://localhost:8000/_health/
#
# ENVIRONMENT VARIABLES:
# - SECRET_KEY: Generate unique key for production (security risk if default used)
# - PORT: Web application port (default: 8000)
# - GLITCHTIP_DOMAIN: External URL for your Glitchtip instance
# - DEBUG: Set to false for production
# - DATABASE_URL: Override PostgreSQL connection (default: postgres://postgres:postgres@localhost:5432/postgres)
# - REDIS_URL: Override Redis connection (default: redis://localhost:6379/0)
#
# PORTS:
# - 8000: Web application (exposed)
# - 5432: PostgreSQL (internal only, not exposed)
# - 6379: Redis (internal only, not exposed)

FROM glitchtip-aio:latest

# Environment variables - CHANGE SECRET_KEY FOR PRODUCTION!
# TODO: NEED CONFIG 'GLITCHTIP_DOMAIN' and SECRET_KEY use ``
#       more see: https://glitchtip.com/documentation/install#configuration
ENV SECRET_KEY="dev-secret-key-change-in-production" \
    PORT=8000 \
    GLITCHTIP_DOMAIN="http://localhost:8000" \ 
    DEBUG=false

# Health check - monitors all services (PostgreSQL, Redis, Django, Celery)
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD /usr/local/bin/health-check

# Expose web port only (database and redis are internal)
EXPOSE 8000

# Work directory - base image handles all service initialization
WORKDIR /code

# Use base image entrypoint and command
# Base entrypoint handles: directory creation, permission setting, service startup
# Services managed by supervisor: postgres, redis, migrate, celery, web
ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
