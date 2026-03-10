FROM python:3.10-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
# RUN playwright install chromium
COPY inspector.py .
CMD ["python", "inspector.py"]