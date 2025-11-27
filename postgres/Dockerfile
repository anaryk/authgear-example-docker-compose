FROM postgres:16-trixie

ENV PARTMAN_VERSION=5.0.1
ENV PGAUDIT_VERSION=16.0

RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends --no-install-suggests \
    ca-certificates \
    unzip \
    build-essential \
    wget \
    postgresql-server-dev-16 \
    libkrb5-dev; \
  rm -rf /var/lib/apt/lists/*

RUN set -eux; \
  wget https://github.com/pgpartman/pg_partman/archive/v${PARTMAN_VERSION}.zip \
    -O pg_partman-${PARTMAN_VERSION}.zip; \
  unzip pg_partman-${PARTMAN_VERSION}.zip; \
  cd pg_partman-${PARTMAN_VERSION}; \
  make NO_BGW=1 install

RUN set -eux; \
  wget https://github.com/pgaudit/pgaudit/archive/${PGAUDIT_VERSION}.zip \
    -O pgaudit-${PGAUDIT_VERSION}.zip; \
  unzip pgaudit-${PGAUDIT_VERSION}.zip; \
  cd pgaudit-${PGAUDIT_VERSION}; \
  make install USE_PGXS=1
