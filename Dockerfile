ARG VERSION="latest"

FROM php:${VERSION} AS php

# Install PHP extensions
# RUN docker-php-ext-install pdo_mysql mbstring

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

# RUN apt-get update && apt-get upgrade -y

# # Required libraries for MongoDB from "echo $PHPIZE_DEPS"
# # autoconf dpkg-dev file g++ gcc libc-dev make pkg-config re2c
# # 
# # Required libraries for MongoDB from https://mongoc.org/libmongoc/current/installing.html
# # libmongoc-dev libbson-dev cmake libssl-dev libsasl2-dev
# # 
# # libssl-dev is required for enable libmongoc SSL
# RUN apt-get install -y libssl-dev \ 
#   && pecl install mongodb \
#   && echo "extension=mongodb.so" >> `php --ini | grep "Loaded Configuration" | sed -e "s|.*:\s*||"`

FROM node:${VERSION} AS node

FROM composer:${VERSION} AS composer

FROM alpine/git:${VERSION} AS git
RUN git config --global --add safe.directory "*"

FROM python:${VERSION} AS python
RUN apt-get update && apt-get upgrade -y
RUN apt-get install -y python3-venv python3-pip

EXPOSE 5173 4173 80 443 8000