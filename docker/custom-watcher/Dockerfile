FROM python:3.12-alpine
RUN pip install --no-cache-dir pymysql
COPY watcher.py /usr/local/bin/watcher.py
CMD ["python", "/usr/local/bin/watcher.py"]
