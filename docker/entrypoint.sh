#!/bin/sh

set -e

cd /var/www

echo "Bootstrapping Laravel..."

# -----------------------------------
# 1. Install Laravel if missing
# -----------------------------------
if [ ! -f artisan ]; then
    echo "Laravel not found. Installing latest Laravel 13.x..."

    rm -rf temp

    composer create-project laravel/laravel:^13.0 temp

    echo "Moving Laravel files..."

    cp -a temp/. .

    rm -rf temp

    echo "Laravel installation completed."
fi

# -----------------------------------
# 2. Create .env if missing
# -----------------------------------
if [ ! -f .env ]; then
    echo "Creating .env..."

#    cp .env.example .env
    cp docker/.env.docker .env
fi

# -----------------------------------
# 3. Install Composer dependencies
# -----------------------------------
if [ ! -d vendor ]; then
    echo "Installing Composer dependencies..."

    composer install \
        --no-interaction \
        --prefer-dist \
        --optimize-autoloader
fi

# -----------------------------------
# 4. Generate application key
# -----------------------------------
if ! grep -q "^APP_KEY=base64:" .env; then
    echo "Generating application key..."

    php artisan key:generate --force
fi

# -----------------------------------
# 5. Wait for PostgreSQL
# -----------------------------------
echo "Waiting for PostgreSQL..."

#until php -r "
#try {
#    new PDO(
#        'pgsql:host=db;port=5432;dbname=laravel',
#        'laravel',
#        'secret'
#    );
#
#    echo 'PostgreSQL is ready.\n';
#} catch (Throwable \$e) {
#    exit(1);
#}
#"; do
#    sleep 2
#done

#until php artisan db:show >/dev/null 2>&1; do
#    sleep 2
#done

echo "Verifying PostgreSQL connection..."

php artisan db:show

echo "PostgreSQL is ready."

# -----------------------------------
# 6. Run database migrations
# -----------------------------------
echo "Running database migrations..."

php artisan migrate --force

# -----------------------------------
# 7. Start PHP-FPM
# -----------------------------------
echo "Starting PHP-FPM..."

exec php-fpm -F