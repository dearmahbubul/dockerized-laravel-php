#!/bin/sh
# =============================================================================
# Container bootstrap
# -----------------------------------------------------------------------------
# Runs every time an `app`-built container starts. Its job is to guarantee the
# environment is usable before handing off to PHP-FPM:
#
#   1. Ensure a Laravel skeleton exists   (fresh-volume convenience)
#   2. Ensure a .env file exists          (copied from .env.docker template)
#   3. Ensure composer vendor/ exists     (composer install)
#   4. Ensure storage is writable         (www-data needs to write logs/cache)
#   5. Ensure an APP_KEY exists           (required for encryption)
#   6. Wait until MySQL accepts connections
#   7. Run pending migrations             (background; never blocks FPM start)
#   8. Exec PHP-FPM in the foreground     (PID 1 hand-off for signal handling)
#
# NOTE: The "horizon" service in docker-compose.yml intentionally bypasses this
# script and assumes step 1–3 were completed by the `app` service.
#
# set -e : abort on any error so a broken bootstrap is visible immediately.
# =============================================================================
set -e

cd /var/www

echo "Bootstrapping Laravel..."

# -----------------------------------
# 1. Install Laravel if missing
# -----------------------------------
# Only relevant when mounting a completely empty volume. A normal checkout of
# this repository already contains artisan/, app/, etc.
if [ ! -f artisan ]; then
    if [ -d /opt/laravel ]; then
        echo "Laravel not found. Materialising baked skeleton (/opt/laravel)..."
        cp -a /opt/laravel/. /var/www/
    else
        echo "Laravel not found. Installing..."
        rm -rf temp
        composer create-project laravel/laravel temp
        echo "Moving Laravel files..."
        # Move everything including dotfiles (.env.example, .gitignore, ...).
        mv temp/* .
        mv temp/.[!.]* . 2>/dev/null || true
        rm -rf temp
    fi
fi

# -----------------------------------
# 2. Apply Docker .env only if .env is missing or empty
# -----------------------------------
# -s tests for a non-empty file. This way local changes made inside the
# container (or to a mounted .env) survive container restarts instead of being
# overwritten by the template on every boot.
if [ ! -s .env ]; then
    cp docker/.env.docker .env
fi

# -----------------------------------
# 3. Install dependencies
# -----------------------------------
# Skipped when the host bind-mount already provides vendor/ (the usual dev
# flow), which keeps container startup fast.
# NOTE: composer install is also done during docker build (Dockerfile).
# This is a safety net only — it should normally be a no-op.
if [ ! -f vendor/autoload.php ]; then
    echo "Installing dependencies..."
    composer install --no-interaction --prefer-dist --optimize-autoloader
fi

# -----------------------------------
# 4. Fix permissions
# -----------------------------------
# Laravel writes logs, compiled views and cache into storage/ and
# bootstrap/cache/. PHP-FPM workers run as www-data and need write access.
# `|| true` keeps the container booting on filesystems where chown is a no-op.
echo "Fixing permissions..."
chown -R www-data:www-data storage bootstrap/cache || true
chmod -R 775 storage bootstrap/cache || true

# -----------------------------------
# 4b. Public storage serving
# -----------------------------------
# Uploaded files live in storage/app/public (the "public" disk) and are served
# under /storage/... by NGINX directly (see nginx/default.conf -> the
# "location ^~ /storage/" block). We deliberately do NOT run
# `php artisan storage:link` here: creating symlinks inside a Windows bind
# mount is not supported by Docker Desktop, and nginx's alias achieves the
# same result without one.

# -----------------------------------
# 5. Generate app key
# -----------------------------------
# Required for session/cookie encryption. Generated once; preserved afterwards.
if ! grep -q "^APP_KEY=base64" .env; then
    echo "Generating app key..."
    php artisan key:generate --force
fi

# -----------------------------------
# 6. Wait for MySQL
# -----------------------------------
# compose already gates on mysql's healthcheck, but healthchecks only run on a
# cadence — this tight loop removes any residual race right before migrating.
until php -r "
try {
    new PDO('mysql:host=mysql;port=3306;dbname=laravel', 'laravel', 'secret');
    echo \"DB connected\" . PHP_EOL;
} catch (Exception \$e) {
    exit(1);
}
"; do
    sleep 2
done

# -----------------------------------
# 7. Run migrations (background)
# -----------------------------------
# Deliberately non-blocking: PHP-FPM starts serving immediately while
# migrations finish. Failures are logged but never prevent boot.
(
    echo "Running migrations..."
    php artisan migrate --force || true

    echo "Clearing config cache..."
    php artisan config:clear || true
) &

# -----------------------------------
# 8. Start PHP-FPM
# -----------------------------------
# exec replaces the shell with FPM as PID 1 so SIGTERM/SIGINT from
# `docker stop` reach PHP directly (fast, clean shutdown).
echo "Starting PHP-FPM..."
exec php-fpm -F
