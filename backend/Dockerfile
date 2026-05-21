FROM python:3.12-slim

WORKDIR /app

# 仅先拷贝依赖清单以利用构建缓存
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

ENV PORT=8000
EXPOSE 8000

# 平台会注入 $PORT；本地默认 8000
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
