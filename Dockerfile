FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .
COPY database.py .
COPY routes/ ./routes/
COPY services/ ./services/
COPY templates/ ./templates/

ENV FLASK_APP=app.py

EXPOSE 5000

CMD ["flask", "run", "--host=0.0.0.0", "--port=5000"]
