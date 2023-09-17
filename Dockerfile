FROM php:8-fpm

# vite dev
EXPOSE 5173
# vite preview
EXPOSE 4173
# http
EXPOSE 80
# https
EXPOSE 443
# laravel serve
EXPOSE 8000

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

RUN apt-get update && apt-get upgrade -y

# Required libraries for MongoDB from "echo $PHPIZE_DEPS"
# autoconf dpkg-dev file g++ gcc libc-dev make pkg-config re2c
# 
# Required libraries for MongoDB from https://mongoc.org/libmongoc/current/installing.html
# libmongoc-dev libbson-dev cmake libssl-dev libsasl2-dev
# 
# libssl-dev is required for enable libmongoc SSL
RUN apt-get install -y libssl-dev \ 
  && pecl install mongodb \
  && echo "extension=mongodb.so" >> `php --ini | grep "Loaded Configuration" | sed -e "s|.*:\s*||"`

RUN apt-get install -y nodejs npm

# Required libraries by Composer
RUN apt-get install -y zip unzip
COPY --from=composer /usr/bin/composer /usr/bin/composer

RUN apt-get install -y git \
  && git config --global --add safe.directory "*"

WORKDIR /usr/src/app
