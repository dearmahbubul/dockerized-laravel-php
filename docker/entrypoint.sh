#!/bin/sh
# =============================================================================
# App container bootstrap
#  1. Materialise the baked Laravel skeleton when artisan is missing
#  2. Ensure .env exists (from docker/.env.docker)
#  3. Patch config/database.php to add the 'vector' connection
#  4. Ensure APP_KEY
#  5. Wait for the primary DB + the vector DB
#  6. Run migrations in the background, then start PHP-FPM
# =============================================================================
set -e

cd /var/www

# -----------------------------------
# 1. Laravel skeleton
# -----------------------------------
if [ ! -f artisan ]; then
    echo "Laravel not found. Materialising baked skeleton (/opt/laravel)..."
    # -n: never overwrite existing repo files (.gitignore, docker-compose.yml, ...)
    cp -an /opt/laravel/. .
fi

# -----------------------------------
# 2. .env
# -----------------------------------
if [ ! -s .env ]; then
    cp docker/.env.docker .env
fi

# -----------------------------------
# 3. Patch config/database.php with the vector connection
# -----------------------------------
if [ -f /opt/stubs/database.php ] && [ ! -f config/database.php.bak ]; then
    echo "Patching config/database.php (adding vector connection)..."
    cp config/database.php config/database.php.bak
    cp /opt/stubs/database.php config/database.php
fi

# -----------------------------------
# 4. Vendor
# -----------------------------------
if [ ! -f vendor/autoload.php ]; then
    echo "Installing dependencies..."
    composer install --no-interaction --prefer-dist --optimize-autoloader
fi

# -----------------------------------
# Permissions
# -----------------------------------
chown -R www-data:www-data storage bootstrap/cache 2>/dev/null || true
chmod -R 775 storage bootstrap/cache 2>/dev/null || true

# -----------------------------------
# APP_KEY
# -----------------------------------
if ! grep -q "^APP_KEY=base64" .env; then
    echo "Generating app key..."
    php artisan key:generate --force
fi

# -----------------------------------
# 5. Wait for databases
# -----------------------------------
DB_DRIVER=$(grep '^DB_CONNECTION=' .env | head -n1 | cut -d= -f2)
DB_HOST=$(grep '^DB_HOST=' .env | head -n1 | cut -d= -f2 | sed 's/=.*//')
DB_PORT=$(grep '^DB_PORT=' .env | head -n1 | cut -d= -f2)
DB_DATABASE=$(grep '^DB_DATABASE=' .env | head -n1 | cut -d= -f2)
DB_USERNAME=$(grep '^DB_USERNAME=' .env | head -n1 | cut -d= -f2)
DB_PASSWORD=$(grep '^DB_PASSWORD=' .env | head -n1 | cut -d= -f2)

# default to mysql if empty
if [ -z "$DB_DRIVER" ]; then DB_DRIVER=mysql; fi

echo "Waiting for primary DB ($DB_DRIVER)..."
until DB_DRIVER="$DB_DRIVER" DB_HOST="$DB_HOST" DB_PORT="$DB_PORT" DB_DATABASE="$DB_DATABASE" DB_USERNAME="$DB_USERNAME" DB_PASSWORD="$DB_PASSWORD" php -r '
    try { new PDO(getenv("DB_DRIVER").":host=".getenv("DB_HOST").";port=".getenv("DB_PORT").";dbname=".getenv("DB_DATABASE"), getenv("DB_USERNAME"), getenv("DB_PASSWORD")); }
    catch (Exception $e) { exit(1); }
'; do
    sleep 2
done

echo "Waiting for vector DB (pgsql)..."
until php -r '
    try { new PDO("pgsql:host=postgres;port=5432;dbname=vector", "laravel", "secret"); }
    catch (Exception $e) { exit(1); }
'; do
    sleep 2
done

# -----------------------------------
# 6. Migrations (background) + PHP-FPM
# -----------------------------------
(
    echo "Running migrations ($DB_DRIVER)..."
    php artisan migrate --force || true
    echo "Running vector migrations..."
    php artisan migrate --database=vector --force || true
    echo "Clearing config cache..."
    php artisan config:clear || true
) &

echo "Starting PHP-FPM..."
exec php-fpm -F
