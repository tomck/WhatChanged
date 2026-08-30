FROM python:3.12-alpine
RUN apk add --no-cache su-exec && pip install --no-cache-dir pymysql
COPY watcher.py /usr/local/bin/watcher.py
COPY test_watcher.py /usr/local/bin/test_watcher.py
COPY entrypoint.sh /usr/local/bin/watcher-entrypoint
ENTRYPOINT ["/usr/local/bin/watcher-entrypoint"]
