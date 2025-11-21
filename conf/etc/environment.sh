#!/bin/bash
# Environment variables aligned with official compose.yml

# Core database configuration - aligned with compose.yml
export DATABASE_URL="${DATABASE_URL:-postgres://postgres:postgres@localhost:5432/postgres}"

# PostgreSQL-only mode: set DISABLE_REDIS=true to use PostgreSQL for cache/sessions
# Based on GlitchTip 5.2 changelog: set VALKEY_URL to empty string to use PostgreSQL
if [ "${DISABLE_REDIS:-false}" = "true" ]; then
    export VALKEY_URL=""
    export REDIS_URL=""
    export CELERY_BROKER_URL="sqla+postgresql://postgres:postgres@localhost:5432/postgres"
    export CELERY_RESULT_BACKEND="db+postgresql://postgres:postgres@localhost:5432/postgres"
    echo "PostgreSQL-only mode enabled - Using PostgreSQL as cache, celery, and sessions backend"
else
    # Use Redis instead of Valkey for AIO (compose.yml uses valkey service)
    export VALKEY_URL="${VALKEY_URL:-redis://localhost:6379/0}"
    export REDIS_URL="${REDIS_URL:-redis://localhost:6379/0}"
    export CELERY_BROKER_URL="${CELERY_BROKER_URL:-redis://localhost:6379/0}"
    export CELERY_RESULT_BACKEND="${CELERY_RESULT_BACKEND:-redis://localhost:6379/0}"
fi

# Environment variables from official compose.yml
export SECRET_KEY="${SECRET_KEY:-change_me}"
export ENABLE_ORGANIZATION_CREATION="${ENABLE_ORGANIZATION_CREATION:-true}"
export ENABLE_TEST_API="${ENABLE_TEST_API:-true}"
export DEBUG="${DEBUG:-false}"  # Production default, different from compose.yml DEBUG: "true"
export EMAIL_BACKEND="${EMAIL_BACKEND:-django.core.mail.backends.console.EmailBackend}"
export ENABLE_OBSERVABILITY_API="${ENABLE_OBSERVABILITY_API:-true}"

# Celery configuration from compose.yml
export CELERY_WORKER_CONCURRENCY="${CELERY_WORKER_CONCURRENCY:-4}"
export CELERY_WORKER_PREFETCH_MULTIPLIER="${CELERY_WORKER_PREFETCH_MULTIPLIER:-25}"
export CELERY_WORKER_POOL="${CELERY_WORKER_POOL:-threads}"
export CELERY_SKIP_CHECKS="${CELERY_SKIP_CHECKS:-true}"