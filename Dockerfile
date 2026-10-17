# syntax=docker/dockerfile:1

ARG PHP_VERSION="8.4-alpine"
ARG NODE_VERSION="22-alpine"
ARG COMPOSER_VERSION="2"

FROM php:${PHP_VERSION} AS php

# Install PHP extensions
# RUN docker-php-ext-install pdo_mysql mbstring

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

FROM node:${NODE_VERSION} AS node

RUN apk add --no-cache git

FROM composer:${COMPOSER_VERSION} AS composer
