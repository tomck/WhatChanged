FROM debian:12
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends tripwire && rm -rf /var/lib/apt/lists/*
COPY tripwire.sh /usr/local/bin/tripwire-watch
RUN chmod +x /usr/local/bin/tripwire-watch
ENTRYPOINT ["/usr/local/bin/tripwire-watch"]
