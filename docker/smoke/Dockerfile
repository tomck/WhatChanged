FROM python:3.12-alpine
RUN pip install --no-cache-dir pymysql
COPY smoke.py /usr/local/bin/smoke.py
CMD ["python", "/usr/local/bin/smoke.py"]
