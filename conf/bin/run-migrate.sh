#!/bin/bash
set -e  # Exit on any error

echo "Running Django migrations..."
cd /code

# Set database environment variables
export DB_PASSWORD="${DB_PASSWORD:-postgres}"
export DATABASE_URL="postgres://postgres:${DB_PASSWORD}@localhost:5432/postgres"

# Wait for PostgreSQL to be ready
until nc -z localhost 5432; do
    echo "Waiting for database port to be ready..."
    sleep 2
done

# Wait for PostgreSQL to be fully initialized and accepting connections
echo "Waiting for database to be fully initialized..."
until PGPASSWORD="${DB_PASSWORD}" psql -U postgres -d postgres -c "SELECT 1;" > /dev/null 2>&1; do
    echo "Waiting for database to accept connections..."
    sleep 2
done

echo "Database is ready, waiting additional time for full initialization..."
sleep 10

echo "Running Django migrations..."
python manage.py migrate --noinput
echo "Migrations completed successfully"