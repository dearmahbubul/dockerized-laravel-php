# =============================================================================
# Dockerise — PHP application image (Laravel 13 + Horizon)
# -----------------------------------------------------------------------------
# This image runs the Laravel app via PHP-FPM (served by the nginx container)
# and also powers the "horizon" service, which manages Redis queue workers.
#
# Build:  docker compose build
# Run:    docker compose up -d
# =============================================================================

FROM php:8.4-fpm

# -----------------------------------------------------------------------------
# System packages + core PHP extensions
# -----------------------------------------------------------------------------
# - unzip / git / curl / zip : composer & general tooling
# - libzip-dev               : compiled support for the zip extension
# - default-mysql-client     : mysqldump/mysql CLI for manual DB inspection
# - libfreetype / libjpeg / libpng : GD image library dependencies.
#       GD is REQUIRED by picqer/php-barcode-generator (BarcodeService renders
#       PNG barcodes on the admin print-barcode page). Without it that page 500s.
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y \
    unzip git curl libzip-dev zip default-mysql-client \
    libfreetype6-dev libjpeg62-turbo-dev libpng-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install pdo pdo_mysql zip gd

# -----------------------------------------------------------------------------
# pcntl + posix — HARD REQUIREMENTS for Laravel Horizon
# -----------------------------------------------------------------------------
# Horizon's master supervisor uses PCNTL signals to start/stop/restart its
# queue workers and relies on POSIX process APIs. These extensions are only
# available on Linux, which is fine: Horizon runs exclusively inside this
# container (the Windows dev host cannot load them).
#
# sockets — used by the Pest browser-testing plugin (tests/Browser).
# -----------------------------------------------------------------------------
RUN docker-php-ext-install pcntl posix sockets

# -----------------------------------------------------------------------------
# Redis extension (phpredis)
# -----------------------------------------------------------------------------
# Used for cache / sessions / queues as configured in .env.docker
# (CACHE_STORE=redis, SESSION_DRIVER=redis, QUEUE_CONNECTION=redis).
# -----------------------------------------------------------------------------
RUN pecl install redis && docker-php-ext-enable redis

# -----------------------------------------------------------------------------
# Xdebug (disabled by default)
# -----------------------------------------------------------------------------
# Installed for local debugging; xdebug.mode=off keeps it dormant unless you
# flip the mode in a custom ini or docker-compose.override.yml.
# -----------------------------------------------------------------------------
RUN pecl install xdebug \
    && docker-php-ext-enable xdebug \
    && echo "xdebug.mode=off" > /usr/local/etc/php/conf.d/xdebug.ini

# -----------------------------------------------------------------------------
# Composer (pulled from the official image so we always get a working binary)
# -----------------------------------------------------------------------------
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /var/www

# -----------------------------------------------------------------------------
# Composer dependencies — baked into the image WHEN the checkout contains a
# composer manifest (i.e. the Laravel app is committed). For an infra-only
# clone there is no composer.json, so nothing is installed here and the
# entrypoint bootstraps the Laravel skeleton (and its vendor/) on first start.
#
# The wildcard COPY is required: a literal `COPY composer.json composer.lock`
# would fail the build when those files are absent from a fresh clone.
#
# --no-scripts: postAutoloadDump references app/Helpers which doesn't exist
#   at this layer. Scripts run later after the full code copy.
# --optimize-autoloader: generates a classmap for fast file resolution.
#   The classmap indexes vendor/ only — app classes use PSR-4 at runtime.
# -----------------------------------------------------------------------------
COPY composer.json* composer.lock* ./
RUN if [ -f composer.json ]; then \
        if [ -f composer.lock ]; then \
            composer install --no-scripts --no-interaction --prefer-dist --optimize-autoloader; \
        else \
            composer update --no-scripts --no-interaction --prefer-dist --optimize-autoloader; \
        fi && composer clear-cache; \
    else \
        echo "No composer.json in build context — dependencies will be installed by the entrypoint on first boot."; \
    fi

# -----------------------------------------------------------------------------
# Baked Laravel skeleton — materialised HERE at image build time so first boot
# never has to download/extract 100+ packages through the (Windows) host bind
# mount (that path caused multi-minute boots and nginx 504s). The entrypoint
# copies /opt/laravel into /var/www on the first boot of an app-less clone.
#
# Unconditional on purpose: the conditional-if-composer.json variant silently
# flips when the build context contains a materialised skeleton (composer.json
# present), producing inconsistent images.
# -----------------------------------------------------------------------------
RUN composer create-project laravel/laravel /opt/laravel --no-interaction --prefer-dist \
    && rm -f /opt/laravel/.env /opt/laravel/database/database.sqlite

# -----------------------------------------------------------------------------
# Application code — layered AFTER composer so code edits don't invalidate
# the (slow) dependency install. The anonymous volume for /var/www/vendor
# ensures the image-baked vendor/ stays in place.
# -----------------------------------------------------------------------------
COPY . .

# -----------------------------------------------------------------------------
# Entrypoint: bootstraps .env / permissions / migrations on first run,
# then hands off to CMD. See docker-entrypoint.sh for the full bootstrap flow.
# NOTE: vendor/ is already installed — the entrypoint no longer needs to run
# `composer install` (it was skipped when vendor/ existed anyway).
# -----------------------------------------------------------------------------
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && sed -i 's/\r$//' /usr/local/bin/entrypoint.sh

ENTRYPOINT ["entrypoint.sh"]

# Default process: PHP-FPM in foreground (the nginx container talks to it on
# port 9000). The horizon service overrides CMD to run "php artisan horizon".
CMD ["php-fpm", "-F"]
