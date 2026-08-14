FROM debian:12
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    apache2 autoconf automake build-essential ca-certificates curl git libedit-dev \
    libjansson-dev libsqlite3-dev libssl-dev libxml2-dev mariadb-client pkg-config \
    php php-cli php-curl php-gd php-intl php-mbstring php-mysql php-xml php-zip \
    sox uuid-dev && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /usr/src
RUN curl -fsSL https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-21-current.tar.gz -o asterisk.tgz && \
    tar -xzf asterisk.tgz && cd asterisk-21*/ && \
    ./configure --with-jansson-bundled && make -j2 && make install && make samples && \
    groupadd --system asterisk && useradd --system --gid asterisk --home-dir /var/lib/asterisk asterisk
RUN curl -fsSL https://mirror.freepbx.org/modules/packages/freepbx/freepbx-17.0-latest.tgz -o freepbx.tgz && \
    tar -xzf freepbx.tgz && mv freepbx /usr/src/freepbx
COPY entrypoint.sh /usr/local/bin/freepbx-lab
RUN chmod +x /usr/local/bin/freepbx-lab
EXPOSE 80
ENTRYPOINT ["/usr/local/bin/freepbx-lab"]
