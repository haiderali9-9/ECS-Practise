FROM php:8.2-fpm-alpine

# Environment 
ARG ENVIRONMENT
ENV ENVIRONMENT=${ENVIRONMENT}

# Set working directory
WORKDIR /var/www/html

# Install system dependencies + PHP extensions
RUN apk add --no-cache \
    nodejs npm \
    nginx supervisor \
    libpng-dev libjpeg-turbo-dev libwebp-dev freetype-dev icu-dev \
    && docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg \
        --with-webp \
    && docker-php-ext-install -j$(nproc) \
        calendar \
        gd \
        intl

# Install Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Copy and activate production php.ini and custom php.ini
RUN cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini
COPY ./etc/${ENVIRONMENT}/custom-php-setting.ini /usr/local/etc/php/conf.d/custom-php-setting.ini

# Copy and activate custom fpm config
COPY ./etc/${ENVIRONMENT}/custom-fpm-setting.conf /usr/local/etc/php-fpm.d/www.conf

# Copy custom nginx configuration
COPY ./etc/${ENVIRONMENT}/nginx.conf /etc/nginx/nginx.conf

# Copy Supervisor configuration file
COPY ./etc/${ENVIRONMENT}/supervisor.conf /etc/supervisor/conf.d/supervisor.conf

# Copy application code
COPY . .

# Install PHP dependencies
RUN composer install --no-interaction --prefer-dist --optimize-autoloader

# Cache Laravel config/routes/views
RUN php artisan config:clear && \
    php artisan optimize

# Set correct permissions
RUN chown -R www-data:www-data /var/www/html && \
    chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache

# Install and build Node.js assets
RUN npm install && npm run build && rm -rf node_modules

# Expose port
EXPOSE 80

# Start supervisord
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisor.conf"]