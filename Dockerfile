# =============================================================================
# PHP application image — Laravel 13 + Horizon
# =============================================================================
# Runs the Laravel app via PHP-FPM (served by the nginx container) and also
# powers the "horizon" and "scheduler" worker services.
#
#   Build:  docker compose build
#   Run:    docker compose up -d
# =============================================================================

FROM php:8.4-fpm

# -----------------------------------------------------------------------------
# System packages + core PHP extensions
# -----------------------------------------------------------------------------
# - unzip / git / curl / zip  : composer and general tooling
# - libzip-dev                : build dependency for the zip extension
# - default-mysql-client      : mysql / mysqldump CLI for manual DB inspection
# - libfreetype / libjpeg / libpng : build deps for the GD extension
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y \
    unzip git curl libzip-dev zip default-mysql-client \
    libfreetype6-dev libjpeg62-turbo-dev libpng-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install pdo pdo_mysql zip gd

# -----------------------------------------------------------------------------
# pcntl + posix — required by Laravel Horizon
# -----------------------------------------------------------------------------
# Horizon's master supervisor uses PCNTL signals to start/stop its workers and
# relies on POSIX process APIs. Both are Linux-only, which is fine: Horizon
# runs only inside this container. sockets is used by the Pest browser tests.
# -----------------------------------------------------------------------------
RUN docker-php-ext-install pcntl posix sockets

# -----------------------------------------------------------------------------
# phpredis — cache / sessions / queues use Redis
# -----------------------------------------------------------------------------
RUN pecl install redis && docker-php-ext-enable redis

# -----------------------------------------------------------------------------
# Xdebug — installed but disabled by default
# -----------------------------------------------------------------------------
# Enable it locally via docker-compose.override.yml or a custom ini when needed.
# -----------------------------------------------------------------------------
RUN pecl install xdebug \
    && docker-php-ext-enable xdebug \
    && echo "xdebug.mode=off" > /usr/local/etc/php/conf.d/xdebug.ini

# -----------------------------------------------------------------------------
# Composer (from the official image)
# -----------------------------------------------------------------------------
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /var/www

# -----------------------------------------------------------------------------
# Composer dependencies
# -----------------------------------------------------------------------------
# Installed when the checkout has a composer manifest (i.e. the app is
# committed). For an infra-only clone there is none, so the build skips this
# and the entrypoint bootstraps the Laravel skeleton on first boot.
#
# The wildcard COPY is required: a literal `COPY composer.json composer.lock`
# would fail the build when those files don't exist in a fresh clone.
#
# --no-scripts keeps the build fast and offline-safe (postAutoloadDump scripts
# reference app code that isn't copied yet); --optimize-autoloader generates a
# classmap for fast file resolution.
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
# Baked Laravel skeleton (first-boot bootstrap for fresh clones)
# -----------------------------------------------------------------------------
# Produced at build time so a fresh clone never has to download/extract 100+
# packages through the host bind mount on first boot. The entrypoint copies
# /opt/laravel into /var/www when the clone has no app code yet.
#
# Unconditional on purpose: the conditional-if-composer.json variant silently
# flips when the build context contains a materialised skeleton.
#
# laravel/horizon is pre-installed so the fresh skeleton can run the horizon
# service out of the box. --no-scripts skips the app bootstrap at build time;
# package:discover is still run so Horizon's artisan commands are registered.
# -----------------------------------------------------------------------------
RUN composer create-project laravel/laravel /opt/laravel --no-interaction --prefer-dist \
    && cd /opt/laravel && composer require laravel/horizon:^5.48 --no-interaction --prefer-dist --no-scripts \
    && php artisan package:discover --ansi \
    && rm -f /opt/laravel/.env /opt/laravel/database/database.sqlite

# -----------------------------------------------------------------------------
# App code — copied AFTER the deps
# -----------------------------------------------------------------------------
# Code edits don't invalidate the slow dependency layers. At runtime an
# anonymous /var/www/vendor volume preserves the image-baked vendor/ (see
# docker-compose.yml).
# -----------------------------------------------------------------------------
COPY . .

# -----------------------------------------------------------------------------
# Entrypoints (source: docker/)
# -----------------------------------------------------------------------------
# entrypoint.sh       — app bootstrap (.env, permissions, migrations), then php-fpm
# worker-bootstrap.sh — shared bootstrap for the horizon / scheduler services
#
# sed strips CRLF so the scripts keep working after edits made on Windows.
# -----------------------------------------------------------------------------
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && sed -i 's/\r$//' /usr/local/bin/entrypoint.sh

COPY docker/worker-bootstrap.sh /usr/local/bin/worker-bootstrap.sh
RUN chmod +x /usr/local/bin/worker-bootstrap.sh \
    && sed -i 's/\r$//' /usr/local/bin/worker-bootstrap.sh

ENTRYPOINT ["entrypoint.sh"]

# Default process: PHP-FPM in the foreground (nginx talks to it on port 9000).
# The horizon / scheduler services override CMD with their own artisan commands.
CMD ["php-fpm", "-F"]