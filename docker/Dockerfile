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
RUN apt-get update && apt-get install -y --no-install-recommends nodejs && rm -rf /var/lib/apt/lists/*
# FreePBX's UCP dependency installer invokes npm while provisioning modules.
RUN apt-get update && apt-get install -y --no-install-recommends npm && rm -rf /var/lib/apt/lists/*
# FreePBX resolves PM2 from Asterisk's private Node prefix, not the global one.
RUN mkdir -p /var/lib/asterisk/.node && \
    npm install --prefix /var/lib/asterisk/.node pm2 && \
    chown -R asterisk:asterisk /var/lib/asterisk/.node
RUN apt-get update && apt-get install -y --no-install-recommends cron && rm -rf /var/lib/apt/lists/*
# FreePBX verifies signed framework modules during its first-run installer.
RUN apt-get update && apt-get install -y --no-install-recommends gpg && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://mirror.freepbx.org/modules/packages/freepbx/freepbx-17.0-latest.tgz -o freepbx.tgz && \
    tar -xzf freepbx.tgz
COPY entrypoint.sh /usr/local/bin/freepbx-lab
RUN chmod +x /usr/local/bin/freepbx-lab
EXPOSE 80
ENTRYPOINT ["/usr/local/bin/freepbx-lab"]
