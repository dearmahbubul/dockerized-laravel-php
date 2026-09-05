#!/bin/bash
set -e

# Ensure both databases exist on this PostgreSQL instance:
#   - laravel  (primary app DB when DB_CONNECTION=pgsql)
#   - vector   (always used for embeddings)
# Runs once during first init by the official postgres entrypoint.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    SELECT 'CREATE DATABASE laravel'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'laravel')\gexec

    SELECT 'CREATE DATABASE vector'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'vector')\gexec
EOSQL

# pgvector is baked into the image; create it on the vector DB so embeddings
# work immediately (migrations would do this too via ensureVectorExtensionExists).
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "vector" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS vector;
EOSQL

echo "initdb: ensured 'laravel' and 'vector' databases exist."