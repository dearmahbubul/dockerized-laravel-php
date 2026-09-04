#!/bin/sh

set -e

cd /var/www

if [ ! -f artisan ]; then
    echo "Laravel not found. Installing..."

    composer create-project laravel/laravel temp

    echo "Moving Laravel files..."

    cp -a temp/. .

    rm -rf temp

    echo "Laravel installation completed."
fi

exec "$@"