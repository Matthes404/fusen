# Fusen-Sync-Server: PocketBase mit den Collections und dem Zugang von Fusen.
#
# Bauen und starten:
#   docker compose up -d
#
# Die Daten liegen im Volume unter /pb/pb_data und überleben ein neues Image.

FROM alpine:3.22 AS fetch

ARG POCKETBASE_VERSION=0.40.3
# Wird von `docker buildx` gesetzt; beim einfachen `docker build` leer.
ARG TARGETARCH=amd64

RUN apk add --no-cache ca-certificates unzip wget

WORKDIR /download
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) pb_arch=amd64 ;; \
      arm64) pb_arch=arm64 ;; \
      arm)   pb_arch=armv7 ;; \
      *) echo "Architektur ${TARGETARCH} wird von PocketBase nicht angeboten" >&2; exit 1 ;; \
    esac; \
    wget -q -O pocketbase.zip \
      "https://github.com/pocketbase/pocketbase/releases/download/v${POCKETBASE_VERSION}/pocketbase_${POCKETBASE_VERSION}_linux_${pb_arch}.zip"; \
    unzip -q pocketbase.zip pocketbase; \
    chmod +x pocketbase

FROM alpine:3.22

RUN apk add --no-cache ca-certificates tzdata wget

COPY --from=fetch /download/pocketbase /usr/local/bin/pocketbase
COPY pb_migrations /pb/pb_migrations
COPY pb_hooks /pb/pb_hooks

WORKDIR /pb
EXPOSE 8090
VOLUME ["/pb/pb_data"]

# PocketBase antwortet auf /api/health, ohne dass man angemeldet sein muss.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8090/api/health || exit 1

CMD ["pocketbase", "serve", \
     "--http=0.0.0.0:8090", \
     "--dir=/pb/pb_data", \
     "--migrationsDir=/pb/pb_migrations", \
     "--hooksDir=/pb/pb_hooks"]
