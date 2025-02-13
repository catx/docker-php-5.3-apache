FROM debian:jessie

RUN sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list

# persistent / runtime deps
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      librecode0 \
      libmysqlclient-dev \
      libsqlite3-0 \
      libfreetype6 \
      libfreetype6-dev \
      libjpeg62-turbo \
      libjpeg62-turbo-dev \
      libxml2 \
    && apt-get clean \
    && rm -r /var/lib/apt/lists/*

# phpize deps
RUN apt-get update && apt-get install -y --no-install-recommends \
      autoconf \
      file \
      g++ \
      gcc \
      libc-dev \
      make \
      pkg-config \
      re2c \
    && apt-get clean \
    && rm -r /var/lib/apt/lists/*

##<apache2>##
RUN apt-get update && apt-get install -y apache2-bin apache2-dev apache2.2-common --no-install-recommends && rm -rf /var/lib/apt/lists/*

RUN rm -rf /var/www/html && mkdir -p /var/lock/apache2 /var/run/apache2 /var/log/apache2 /var/www/html && chown -R www-data:www-data /var/lock/apache2 /var/run/apache2 /var/log/apache2 /var/www/html

# Apache + PHP requires preforking Apache for best results
RUN a2dismod mpm_event && a2enmod mpm_prefork

RUN mv /etc/apache2/apache2.conf /etc/apache2/apache2.conf.dist
COPY apache2.conf /etc/apache2/apache2.conf
##</apache2>##

ENV PHP_INI_DIR /etc/php5/apache2
RUN mkdir -p $PHP_INI_DIR/conf.d

# compile openssl, otherwise --with-openssl won't work
COPY openssl-1.0.2u.tar.gz /tmp/openssl.tar.gz
RUN CFLAGS="-fPIC" \
      && cd /tmp \
      && mkdir openssl \
      && tar -xzf openssl.tar.gz -C openssl --strip-components=1 \
      && cd /tmp/openssl \
      && ./config -fPIC && make && make install \
      && rm -rf /tmp/*

ENV PHP_VERSION 5.3.29

# php 5.3 needs older autoconf
# --enable-mysqlnd is included below because it's harder to compile after the fact the extensions are (since it's a plugin for several extensions, not an extension in itself)
RUN buildDeps=" \
                apache2-dev \
                autoconf2.13 \
                libcurl4-openssl-dev \
                libreadline6-dev \
                librecode-dev \
                libsqlite3-dev \
                libssl-dev \
                libxml2-dev \
                libpng-dev \
                libjpeg62-turbo-dev \
                libfreetype6-dev \
                xz-utils \
      " \
      && set -x \
      && apt-get update && apt-get install -y $buildDeps --no-install-recommends && rm -rf /var/lib/apt/lists/* \
      && curl -SL "http://php.net/get/php-$PHP_VERSION.tar.xz/from/this/mirror" -o php.tar.xz \
      && mkdir -p /usr/src/php \
      && mkdir /usr/include/freetype2/freetype \
      && ln -s /usr/include/freetype2/freetype.h /usr/include/freetype2/freetype/freetype.h \
      && tar -xof php.tar.xz -C /usr/src/php --strip-components=1 \
      && rm php.tar.xz* \
      && cd /usr/src/php \
      && ./configure --disable-cgi \
            $(command -v apxs2 > /dev/null 2>&1 && echo '--with-apxs2=/usr/bin/apxs2' || true) \
            --with-config-file-path="$PHP_INI_DIR" \
            --with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
            --enable-ftp \
            --enable-mbstring \
            --enable-zip \
            --enable-mysqlnd \
            --with-mysql \
            --with-mysqli \
            --with-pdo-mysql \
            --with-curl \
            --with-openssl=/usr/local/ssl \
            --enable-soap \
            --with-freetype-dir=/usr/include/freetype2 \
            --with-jpeg-dir=/usr/lib \
            --with-png \
            --with-gd \
            --with-readline \
            --with-recode \
            --with-zlib \
      && make -j"$(nproc)" \
      && make install \
      && { find /usr/local/bin /usr/local/sbin -type f -executable -exec strip --strip-all '{}' + || true; } \
      && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false -o APT::AutoRemove::SuggestsImportant=false $buildDeps \
      && make clean

RUN echo "default_charset = " > $PHP_INI_DIR/php.ini \
    && echo "date.timezone = Asia/Shanghai" >> $PHP_INI_DIR/php.ini

COPY docker-php-* /usr/local/bin/
COPY apache2-foreground /usr/local/bin/

WORKDIR /var/www/html

EXPOSE 80
CMD ["apache2-foreground"]
