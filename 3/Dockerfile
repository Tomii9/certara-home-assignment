# The upstream artifact (rest_<version>.zip) ships only prebuilt Go binaries,
# no source. Stage 1 downloads the zip, verifies its checksum and selects the
# linux binary matching the target CPU architecture (amd64 / arm64). Stage 2 is
# a minimal distroless image running as non-root.

ARG APP_VERSION=1.0

FROM alpine:3.20 AS fetch
ARG APP_VERSION
ARG APP_ZIP_URL=https://github.com/DawiX/rest-hw-dwnld/raw/refs/heads/main/rest_${APP_VERSION}.zip
ARG APP_ZIP_SHA256=8747ca75c4deea2d4a14c3d217e69b7d430a43bedd734d7eb65b7f3f15564deb
# Provided automatically by BuildKit (amd64, arm64, ...). With the legacy
# builder it is empty and the architecture is detected via uname below.
ARG TARGETARCH

RUN apk add --no-cache curl unzip
WORKDIR /src
RUN set -eu; \
    curl -fsSL -o rest.zip "${APP_ZIP_URL}"; \
    if [ -n "${APP_ZIP_SHA256}" ]; then \
      echo "${APP_ZIP_SHA256}  rest.zip" | sha256sum -c -; \
    fi; \
    unzip -q rest.zip; \
    arch="${TARGETARCH:-}"; \
    if [ -z "${arch}" ]; then \
      case "$(uname -m)" in \
        x86_64) arch=amd64 ;; \
        aarch64|arm64) arch=arm64 ;; \
        *) arch="$(uname -m)" ;; \
      esac; \
    fi; \
    bin="rest_${APP_VERSION}_linux_${arch}"; \
    if [ ! -f "${bin}" ]; then \
      echo "No linux binary for architecture '${arch}' in zip:"; ls -1; exit 1; \
    fi; \
    install -m 0755 "${bin}" /rest

FROM gcr.io/distroless/static-debian12:nonroot
ARG APP_VERSION
LABEL org.opencontainers.image.title="hello-rest" \
      org.opencontainers.image.description="Simple Go REST service exposing /hello-world" \
      org.opencontainers.image.version="${APP_VERSION}"

COPY --from=fetch /rest /app/rest
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/app/rest"]
