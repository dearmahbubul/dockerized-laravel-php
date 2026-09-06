#!/bin/sh
# =============================================================================
# Worker container bootstrap (horizon / scheduler)
# Processes jobs; bypasses the app entrypoint (doesn't run PHP-FPM). On first
# boot of a fresh clone it materialises the baked skeleton, then execs the
# service command.
# =============================================================================
set -e

cd /var/www

# -----------------------------------
# 1. Laravel skeleton (first boot only)
# -----------------------------------
if [ ! -f artisan ]; then
    echo "Worker: materialising baked skeleton (/opt/laravel)..."
    cp -a /opt/laravel/. .
fi

# -----------------------------------
# 2. .env
# -----------------------------------
if [ ! -s .env ]; then
    cp /docker/.env.docker .env
fi

# -----------------------------------
# 3. Patch config/database.php with the vector connection
# -----------------------------------
if [ -f /opt/stubs/database.php ] && [ ! -f config/database.php.bak ]; then
    echo "Worker: patching config/database.php (adding vector connection)..."
    cp config/database.php config/database.php.bak
    cp /opt/stubs/database.php config/database.php
fi

# -----------------------------------
# 4. Vendor
# -----------------------------------
if [ ! -f vendor/autoload.php ]; then
    echo "Worker: installing dependencies..."
    composer install --no-interaction --prefer-dist --optimize-autoloader
fi

exec "$@"