# syntax=docker/dockerfile:1

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
ARG GIT_EMAIL
ARG GIT_USERNAME
RUN git config --global user.email "$GIT_EMAIL"
RUN git config --global user.name "$GIT_USERNAME"
RUN git config --global --add safe.directory "*"

FROM python:${VERSION} AS python
ARG LOCAL_BIN_PATH
RUN mkdir -p "$LOCAL_BIN_PATH" && ln -s /usr/local/bin/python "$LOCAL_BIN_PATH/python"

COPY ./python-venv-setup.sh /usr/local/bin/python-venv-setup
RUN chmod +x /usr/local/bin/python-venv-setup

RUN apt-get update && apt-get upgrade -y
RUN apt-get install -y python3-venv python3-pip

EXPOSE 80 8080 443 8000 5173 4173 8501
