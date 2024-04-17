FROM postgis/postgis:16-3.4-alpine

ENV PG_PARTMAN_VERSION v5.1.0
ENV PG_CRON_VERSION 1.6.2
# RUN apt-get update \
#   && apt-get install make \
#   && apt-get install -y wget \
#   && rm -rf /var/lib/apt/lists/*

# Install pg_partman
RUN set -ex \
    \
    # Get some basic deps required to download the extensions and name them fetch-deps so we can delete them later
    && apk add --no-cache --virtual .fetch-deps \
        ca-certificates \
        openssl \
        build-base \
        tar \
    \
    # Download pg_partman
    && wget -O pg_partman.tar.gz "https://github.com/pgpartman/pg_partman/archive/$PG_PARTMAN_VERSION.tar.gz" \
    # Create a folder to put the src files in 
    && mkdir -p /usr/src/pg_partman \
    # Extract the src files
    && tar \
        --extract \
        --file pg_partman.tar.gz \
        --directory /usr/src/pg_partman \
        --strip-components 1 \
    # Delete src file tar
    && rm pg_partman.tar.gz \
    \
    # Get the depends required to build pg_jobmon and name this set of depends build-deps so we can delete them later
    && apk add --no-cache --virtual .build-deps \
        ca-certificates \
        openssl \
        build-base \
        tar \
        autoconf \
        automake \
        g++ \
        clang15 \
        llvm15 \
        libtool \
        libxml2-dev \
        make \
        perl \
    # Move to src file folder
    && cd /usr/src/pg_partman \
    # Build the extension
    && make \
    # Install the extension
    && make install \
    # Delete the src files for pg_partman
    && rm -rf /usr/src/pg_partman \
    \
    && wget -O /pg_cron.tgz "https://github.com/citusdata/pg_cron/archive/v$PG_CRON_VERSION.tar.gz" \
    # && tar xvzf /pg_cron.tgz \
    # && cd pg_cron-$PG_CRON_VERSION \
    # && sed -i.bak -e 's/-Werror//g' Makefile \
    # && sed -i.bak -e 's/-Wno-implicit-fallthrough//g' Makefile \
    # Create a folder to put the src files in 
    && mkdir -p /usr/src/pg_cron \
    # Extract the src files
    && tar \
        --extract \
        --file /pg_cron.tgz \
        --directory /usr/src/pg_cron \
        --strip-components 1 \
    # Delete src file tar
    && rm /pg_cron.tgz \
    # Move to src file folder
    && cd /usr/src/pg_cron \
    && make \
    && make install \
    && rm -rf /usr/src/pg_cron \
    \
    # Delete the dependancies for downloading and building the extensions, we no longer need them
    && apk del .fetch-deps .build-deps

COPY 001-setup_pgcron.sh /docker-entrypoint-initdb.d/
COPY skygres-ddl.sql /docker-entrypoint-initdb.d/