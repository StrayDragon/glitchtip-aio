#!/bin/bash
echo "Running Django migrations..."
cd /code
until nc -z localhost 5432; do
    echo "Waiting for database to be ready..."
    sleep 2
done

export DATABASE_URL="${DATABASE_URL:-postgres://postgres:${DB_PASSWORD:-postgres}@localhost:5432/postgres}"
python manage.py migrate --noinput
echo "Migrations completed"