# docker build -t spryker/dockertestphp71 -f Dockerfile .

FROM php:7.2-fpm

# Install tini (init handler)
ADD https://github.com/krallin/tini/releases/download/v0.9.0/tini /tini
RUN chmod +x /tini

# For running APT in non-interactive mode
ENV DEBIAN_FRONTEND noninteractive

# Define build requirements, which can be removed after setup from the container
ENV PHPIZE_DEPS \
  autoconf            \
  build-essential     \
  file                \
  g++                 \
  gcc                 \
  libbz2-dev          \
  libc-client-dev     \
  libc-dev            \
  libcurl4-gnutls-dev \
  libedit-dev         \
  libfreetype6-dev    \
  libgmp-dev          \
  libicu-dev          \
  libjpeg62-turbo-dev \
  libkrb5-dev         \
  libmcrypt-dev       \
  libpng-dev          \
  libpq-dev           \
  libsqlite3-dev      \
  libssh2-1-dev       \
  libxml2-dev         \
  libxslt1-dev        \
  make                \
  pkg-config          \
  re2c

# Set Debian sources
RUN \
  apt-get update && apt-get install -q -y --no-install-recommends wget gnupg apt-transport-https && \
##  echo "deb http://deb.debian.org/debian/ stretch main non-free contrib\n" > /etc/apt/sources.list.d/debian.list && \
##  echo "deb-src http://deb.debian.org/debian/ stretch main non-free contrib\n" >> /etc/apt/sources.list.d/debian.list && \
  echo "deb https://deb.nodesource.com/node_8.x stretch main" > /etc/apt/sources.list.d/node.list &&  \
      wget --quiet -O - https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add -

#Fixing the postgresql-client installation issue
RUN mkdir -p /usr/share/man/man7/ && touch /usr/share/man/man7/ABORT.7.gz.dpkg-tmp && \
    mkdir -p /usr/share/man/man1/ && touch /usr/share/man/man1/psql.1.gz

# Install Debian packages
RUN \
  apt-get -qy update && apt-get install -q -y --no-install-recommends $PHPIZE_DEPS \
    apt-utils           \
    ca-certificates     \
    curl                \
    debconf             \
    debconf-utils       \
#    gettext-base        \
    git                 \
    git-core            \
    graphviz            \
    libedit2            \
#    libmysqlclient18    \
    libpq5              \
    libsqlite3-0        \
#    libssh2-php         \
    mc                  \
    netcat              \
    nginx               \
    nginx-extras        \
    nodejs              \
    patch               \
    postgresql-client   \
    psmisc              \
    python-dev          \
    python-setuptools   \
    redis-tools         \
    rsync               \
    ssmtp               \
    sudo                \
    supervisor          \
    unzip               \
    vim                 \
    wget                \
    zip                 \
    openssh-server      \

  && mkdir /var/run/sshd \
  && useradd -m -s /bin/bash -d /data jenkins               \
  && echo "jenkins:bigsecretpass" | chpasswd                \
  #Add user to group www-data and to sudoers file
  && usermod -a -G www-data jenkins                         \
  && echo 'jenkins ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers  \

# Install PHP extensions
  && docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/ \
  && docker-php-ext-configure pgsql -with-pgsql=/usr/local/pgsql \
  && docker-php-ext-install -j$(nproc) \
        bcmath      \
        bz2         \
        gd          \
        gmp         \
        iconv       \
        intl        \
        mbstring    \
        mysqli      \
        pdo         \
        pdo_mysql   \
        pdo_pgsql   \
        pgsql       \
        readline    \
        soap        \
        xmlrpc      \
        xsl         \
        zip         \

# Install PHP redis extension
  && pecl install -o -f redis \
  && rm -rf /tmp/pear \
  && echo "extension=redis.so" > $PHP_INI_DIR/conf.d/docker-php-ext-redis.ini \

# Install jinja2 cli
  && easy_install j2cli \

# Install composerrm -rf /var/lib/apt/lists/
  && curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/bin --filename=composer \

# Remove build requirements for php modules
  && apt-get -qy autoremove \
  && apt-get -qy purge $PHPIZE_DEPS \
  && rm -rf /var/lib/apt/lists/*

# Nginx configuration
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/conf.d/* /etc/nginx/conf.d/
COPY nginx/fastcgi_params /etc/nginx/fastcgi_params

# PHP-FPM configuration
RUN rm -f /usr/local/etc/php-fpm.d/*
COPY php/php-fpm.conf /usr/local/etc/php-fpm.conf
COPY php/pool.d/*.conf /usr/local/etc/php-fpm.d/
RUN echo "memory_limit = 512M" >> /usr/local/etc/php/php.ini

# supervisord configuration
COPY supervisord.conf /etc/supervisor/supervisord.conf

# Prepare application
ARG GITHUB_TOKEN
#RUN if [ -z $GITHUB_TOKEN ]; then echo ERROR: Must provide argument: GITHUB_TOKEN; exit 1; fi

RUN install -d -o www-data -g www-data -m 0755 /data /var/www
#COPY . /data
##ADD . /data
RUN mkdir -p /data/data/DE/logs
RUN mkdir -p /versions
RUN chown -R www-data:www-data /data
WORKDIR /data
COPY entrypoint.sh /entrypoint.sh
COPY config_local.php /config_local.php
COPY store.php /store.php
COPY dockersuite.yml /dockersuite.yml
COPY setup_suite.sh /setup_suite.sh
RUN chmod +x /setup_suite.sh
#Create the file flag which show that the shop has not been installed yet
RUN touch /data/initialize

#The workaround for Azure 4 min timeout
RUN mkdir -p /etc/nginx/waiting
COPY nginx/waiting/waiting_vhost.conf /etc/nginx/waiting/waiting_vhost.conf
COPY nginx/waiting/nginx_waiting.conf /etc/nginx/nginx_waiting.conf
#RUN chown -R www-data:www-data /etc/nginx

##RUN if [ ! -d vendor ]; then ./build; fi

#RUN composer config --global github-protocols https \
#    && composer config -g github-oauth.github.com $GITHUB_TOKEN \
#    && composer install --no-progress --no-suggest --no-scripts --prefer-dist --no-dev --optimize-autoloader

# Run app with entrypoints
ENTRYPOINT ["/tini", "--", "/entrypoint.sh"]

EXPOSE 8080 8081 22

#STOPSIGNAL SIGQUIT
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf", "--nodaemon"]
