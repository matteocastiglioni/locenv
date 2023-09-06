FROM php:8-cli-alpine

WORKDIR /usr/src/app

# RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

RUN apk update && apk upgrade

COPY --from=composer /usr/bin/composer /usr/bin/composer

RUN apk add nodejs npm

RUN apk add git \
  && git config --global --add safe.directory "*"
