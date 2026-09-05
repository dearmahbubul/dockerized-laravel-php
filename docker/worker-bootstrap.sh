#!/bin/sh
# =============================================================================
# Worker container bootstrap (horizon / scheduler services)
# -----------------------------------------------------------------------------
# The `app` container's entrypoint bootstraps the bind-mounted skeleton. Worker
# containers share the same image but bypass that entrypoint (they don't run
# PHP-FPM). On a FIRST boot of a fresh clone the skeleton doesn't exist yet, so
# this script mirrors entrypoint.sh steps 1 + 3 before exec-ing the worker
# command:
#
#   1. Materialise the baked skeleton (/opt/laravel) when artisan is missing
#   2. composer install when vendor/ is missing  (safety net)
#   3. Exec the service command (php artisan horizon / schedule:work)
#
# Idempotent and race-safe: both `app` and workers may copy /opt/laravel at
# first boot; `cp -a` over identical content is harmless.
# =============================================================================
set -e

cd /var/www

# -----------------------------------
# 1. Materialise the baked Laravel skeleton on a fresh clone
# -----------------------------------
if [ ! -f artisan ]; then
    if [ -d /opt/laravel ]; then
        echo "Worker: materialising baked skeleton (/opt/laravel)..."
        cp -a /opt/laravel/. /var/www/
    else
        echo "ERROR: no artisan and no baked skeleton (/opt/laravel). Cannot run worker."
        exit 1
    fi
fi

# -----------------------------------
# 2. Ensure composer vendor/ exists
# -----------------------------------
# Normally baked into the image; kept as a safety net for host-side edits.
if [ ! -f vendor/autoload.php ]; then
    echo "Worker: installing dependencies..."
    composer install --no-interaction --prefer-dist --optimize-autoloader
fi

# -----------------------------------
# 3. Hand off to the service command
# -----------------------------------
exec "$@"