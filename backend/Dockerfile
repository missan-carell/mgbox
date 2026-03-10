FROM python:3.10-slim
WORKDIR /app

# 复制整个项目（包括根目录的脚本和 backend 目录）
COPY requirements.txt .
COPY *.py .
COPY static ./static

RUN pip install --no-cache-dir -r requirements.txt

# 暴露端口
EXPOSE 5000

# 使用 gunicorn 启动
CMD ["gunicorn", "-w", "4", "-b", "0.0.0.0:5000", "app:app"]
# CMD ["gunicorn", "-b", "0.0.0.0:5000", "--reload", "--log-level", "debug", "app:app"]'
