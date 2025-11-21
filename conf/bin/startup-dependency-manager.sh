#!/bin/bash
# Simple dependency manager using supervisorctl
# All environment variables are managed by supervisor configuration

echo "=== Glitchtip AIO Dependency Manager ==="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to wait for service to be running
wait_for_service() {
    local service_name=$1
    local timeout=$2
    local attempt=0

    echo -e "${YELLOW}Waiting for $service_name to be ready...${NC}"

    while [ $attempt -lt $timeout ]; do
        local status=$(supervisorctl status "$service_name" 2>/dev/null | awk '{print $2}')

        case $status in
            "RUNNING")
                echo -e "${GREEN}✓ $service_name is running${NC}"
                return 0
                ;;
            "FATAL"|"EXITED")
                local exit_code=$(supervisorctl status "$service_name" 2>/dev/null | awk '{print $4}')
                echo -e "${RED}✗ $service_name failed (exit code: $exit_code)${NC}"
                return 1
                ;;
            "STOPPED"|"STARTING")
                # Still starting up
                ;;
            *)
                echo -e "${YELLOW}Attempt $((attempt + 1))/$timeout: $service_name status: $status${NC}"
                ;;
        esac

        sleep 1
        attempt=$((attempt + 1))
    done

    echo -e "${RED}✗ $service_name failed to start within timeout${NC}"
    return 1
}

# Function to wait for database to be fully ready
wait_for_database() {
    local max_attempts=60
    local attempt=0

    echo -e "${YELLOW}Waiting for database to be ready...${NC}"

    # First wait for postgres service
    if ! wait_for_service "postgres" $max_attempts; then
        return 1
    fi

    # Then wait for actual database connectivity
    while [ $attempt -lt $max_attempts ]; do
        if su - postgres -c "pg_isready -q" 2>/dev/null; then
            echo -e "${GREEN}✓ Database is accepting connections${NC}"
            return 0
        fi
        echo -e "${YELLOW}Attempt $((attempt + 1))/$max_attempts: Database not ready...${NC}"
        sleep 2
        attempt=$((attempt + 1))
    done

    echo -e "${RED}✗ Database failed to become ready${NC}"
    return 1
}

# Main startup sequence
main() {
    echo -e "${GREEN}Starting dependency-managed service sequence...${NC}"

    # Step 1: Wait for PostgreSQL to be ready
    if ! wait_for_database; then
        echo -e "${RED}Fatal: PostgreSQL failed to start${NC}"
        exit 1
    fi

    # Step 2: Always run migrations after database is ready (regardless of Redis mode)
    echo -e "${YELLOW}Running database migrations...${NC}"
    supervisorctl start migrate

    # Wait for migrations to complete
    local migrate_timeout=120
    local attempt=0
    while [ $attempt -lt $migrate_timeout ]; do
        local status=$(supervisorctl status migrate 2>/dev/null | awk '{print $2}')
        if [ "$status" = "EXITED" ]; then
            echo -e "${GREEN}✓ Migrations completed${NC}"
            break
        elif [ "$status" = "FATAL" ]; then
            echo -e "${RED}✗ Migrations failed${NC}"
            exit 1
        fi
        echo -e "${YELLOW}Migration in progress... ($((attempt + 1))/$migrate_timeout)${NC}"
        sleep 2
        attempt=$((attempt + 1))
    done

    if [ $attempt -ge $migrate_timeout ]; then
        echo -e "${RED}✗ Migrations timed out after $migrate_timeout seconds${NC}"
        exit 1
    fi

    # Step 3: Wait for Redis (if enabled)
    if [ "${DISABLE_REDIS:-false}" != "true" ]; then
        if ! wait_for_service "redis" 30; then
            echo -e "${RED}Fatal: Redis failed to start${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}✓ Redis disabled (PostgreSQL-only mode)${NC}"
    fi

    # Step 4: Start Celery
    echo -e "${YELLOW}Starting Celery worker...${NC}"
    supervisorctl start celery

    if ! wait_for_service "celery" 60; then
        echo -e "${RED}Fatal: Celery failed to start${NC}"
        exit 1
    fi

    # Step 5: Start Web service
    echo -e "${YELLOW}Starting Web service...${NC}"
    supervisorctl start web

    if ! wait_for_service "web" 60; then
        echo -e "${RED}Fatal: Web service failed to start${NC}"
        exit 1
    fi

    # All services started successfully
    echo -e "${GREEN}🎉 All services started successfully!${NC}"
    echo -e "${GREEN}Final service status:${NC}"
    supervisorctl status

    # Test health endpoint
    sleep 5
    if curl -f http://localhost:${PORT:-8000}/_health/ > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Health check passed${NC}"
    else
        echo -e "${YELLOW}⚠ Health check failed, but services are running${NC}"
    fi
}

# Execute main function
main "$@"