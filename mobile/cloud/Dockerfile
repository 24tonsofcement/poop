FROM python:3.10-slim
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg libsndfile1 && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir torch==2.5.1 torchaudio==2.5.1 demucs==4.0.1 numpy==1.26.4 scipy==1.13.1 Pillow==11.1.0
WORKDIR /app
COPY importer /app/importer
COPY mobile/native/python /app/mobile/native/python
COPY mobile/cloud/server.py /app/mobile/cloud/server.py
RUN useradd --create-home worker && mkdir -p /home/worker/.cache && chown -R worker:worker /home/worker
USER worker
EXPOSE 8080
CMD ["python", "mobile/cloud/server.py"]
