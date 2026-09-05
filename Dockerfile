FROM php:8.4-fpm

# System packages + PHP extensions
RUN apt-get update && apt-get install -y \
    unzip git curl libzip-dev zip \
    default-mysql-client \
    postgresql-client libpq-dev \
    libfreetype6-dev libjpeg62-turbo-dev libpng-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install pdo pdo_mysql pdo_pgsql zip gd

# pcntl + posix — required by Horizon
RUN docker-php-ext-install pcntl posix sockets

# phpredis
RUN pecl install redis && docker-php-ext-enable redis

# Xdebug (disabled by default)
RUN pecl install xdebug \
    && docker-php-ext-enable xdebug \
    && echo "xdebug.mode=off" > /usr/local/etc/php/conf.d/xdebug.ini

# Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /var/www

# ---------------------------------------------------------------------------
# Bake a full Laravel skeleton at /opt/laravel so first-boot is instant.
# No composer.json / lock / app code comes from the build context.
# ---------------------------------------------------------------------------
RUN composer create-project laravel/laravel /opt/laravel --no-interaction --prefer-dist \
    && cd /opt/laravel \
    && composer require laravel/horizon:^5.48 laravel/ai:^0.11 --no-interaction --prefer-dist --no-scripts \
    && php artisan package:discover --ansi \
    && rm -f /opt/laravel/.env /opt/laravel/database/database.sqlite

# ---------------------------------------------------------------------------
# Entrypoints
# ---------------------------------------------------------------------------
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh && sed -i 's/\r$//' /usr/local/bin/entrypoint.sh

COPY docker/worker-bootstrap.sh /usr/local/bin/worker-bootstrap.sh
RUN chmod +x /usr/local/bin/worker-bootstrap.sh && sed -i 's/\r$//' /usr/local/bin/worker-bootstrap.sh

# Stubs (copied over after create-project to patch config)
COPY docker/stubs /opt/stubs

ENTRYPOINT ["entrypoint.sh"]
CMD ["php-fpm", "-F"]
