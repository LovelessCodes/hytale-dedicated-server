FROM eclipse-temurin:25-jdk

WORKDIR /app

RUN apt-get update && apt-get install -y curl unzip dos2unix python3 && rm -rf /var/lib/apt/lists/*

# Download and extract to /tmp to keep /app clean
RUN curl -L https://downloader.hytale.com/hytale-downloader.zip -o /tmp/downloader.zip \
    && mkdir /tmp/extract \
    && unzip /tmp/downloader.zip -d /tmp/extract \
    && BINARY_PATH=$(find /tmp/extract -name "hytale-downloader-linux-amd64") \
    && mv "$BINARY_PATH" /usr/local/bin/hytale-downloader \
    && chmod +x /usr/local/bin/hytale-downloader \
    && rm -rf /tmp/downloader.zip /tmp/extract

COPY entrypoint.sh /entrypoint.sh
RUN dos2unix /entrypoint.sh && chmod +x /entrypoint.sh

EXPOSE 5520/udp
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]