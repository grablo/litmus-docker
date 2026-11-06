# ============================================================================
# Litmus NVR — runtime container image
# ----------------------------------------------------------------------------
# The Litmus binary is NOT committed to this repo. The image is built by
# downloading the official release .deb from the public CDN (downloads.litmusnvr.com)
# and extracting its files (the package install scripts are not run).
#
# Build:
#   docker build --build-arg LITMUS_VERSION=3.0.0 -t ghcr.io/litmusnvr/litmus-nvr:3.0.0 .
#   (multi-arch builds are handled by .github/workflows/build-image.yml)
#
# Base image: debian:13-slim (trixie).
#
# Was debian:11-slim (bullseye) on the theory that it had to match the
# controller's build ABI. Measured 2026-09-22 — it does not:
#
#   · the binary needs at most GLIBC_2.30 (bullseye itself ships 2.31), so any
#     newer base satisfies it — glibc is backward compatible in this direction
#   · of the 78 SONAMEs it needs, 64 are bundled in /usr/lib/litmus (141 files);
#     only 14 come from this image, and all 14 resolve on trixie
#     (the one that could have moved is libvlc.so.5 — trixie is still VLC 3.x)
#   · the 27 runtime packages below all resolve on bookworm and trixie
#
# The move was forced: Debian 11 is now oldoldstable and its security suite is
# mid-migration to the archive — the bullseye-security *index* is still served
# while its *pool* is empty, so `apt-get install` fetches a 404 and the build
# dies. Nothing we could pin around (checked deb.debian.org, security.debian.org,
# archive.debian.org and two mirrors; snapshot.debian.org works but freezes us
# in the past). trixie is current stable and matches the Raspberry Pi images we
# already ship (rpios_trixie).
#
# The controller's own builder (docker/builder in litmus-controller) stays on
# bullseye — 141 bundled libraries are matched to it there, and its output runs
# on later releases anyway. That is a different decision from this one.
# ============================================================================
FROM debian:13-slim

# Litmus version to fetch. The .deb architecture (amd64|arm64) is derived at build
# time from the image itself via `dpkg --print-architecture` — robust under buildx
# emulation and any builder that doesn't pass TARGETARCH.
ARG LITMUS_VERSION=3.0.0

# The deb adds /usr/share/litmus/product.json (edition marker read by the controller).

ENV DEBIAN_FRONTEND=noninteractive \
    LD_LIBRARY_PATH=/usr/lib/litmus

# Marker the controller reads (IsRunningInContainer) to detect a containerized
# deployment → disables in-app OTA and reports `containerized` to the web app.
ENV GRABLO_CONTAINER=1

# OCI image metadata
LABEL org.opencontainers.image.title="Litmus NVR" \
      org.opencontainers.image.description="Litmus NVR controller as a Docker container — network/IoT/AI/remote-control alongside Home Assistant." \
      org.opencontainers.image.source="https://github.com/litmusnvr/litmus-docker" \
      org.opencontainers.image.url="https://litmusnvr.com" \
      org.opencontainers.image.vendor="Litmus NVR" \
      org.opencontainers.image.version="${LITMUS_VERSION}" \
      org.opencontainers.image.licenses="LicenseRef-Proprietary"

# Runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
      vlc libvlc5 libxss1 libltdl7 libssh2-1 libcurl4 libatomic1 \
      libusb-1.0-0 libpq5 unixodbc libpulse0 libvulkan1 \
      pulseaudio pulseaudio-utils alsa-utils libharfbuzz0b libxml2 \
      libfreetype6 mosquitto ca-certificates curl \
      libxcursor1 libxinerama1 libxrandr2 libxi6 libwayland-cursor0 \
      libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 \
 && rm -rf /var/lib/apt/lists/*
# ★ libxi6 는 2026-09-22 trixie 전환에서 **명시로 옮긴 것**이다. bullseye 에서는
#   다른 패키지의 전이 의존으로 딸려와 목록에 없어도 됐는데, trixie 에서 그 체인이
#   끊겨 `libXi.so.6 => not found` 가 났다(본체와 미디어 라이브러리 둘 다).
#   배포 중인 1.29.1(bullseye) 이미지는 미해결 0 건이라 이것은 전환이 만든 회귀다.
#   전이 의존에 기대면 베이스가 바뀔 때마다 같은 일이 난다 — 필요한 것은 적어 둔다.

# Download the public release .deb and extract its files (install scripts not run)
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    curl -fsSL -o /tmp/litmus.deb "https://downloads.litmusnvr.com/releases/litmus/litmus-nvr_${LITMUS_VERSION}_${arch}.deb"; \
    dpkg-deb -x /tmp/litmus.deb /tmp/litmus-root; \
    cp -a /tmp/litmus-root/usr/bin/litmus /usr/bin/; \
    cp -a /tmp/litmus-root/usr/lib/litmus /usr/lib/; \
    cp -a /tmp/litmus-root/usr/share/litmus /usr/share/; \
    # Image-owned copy of what must follow the image, not the volume: compose mounts a volume on /usr/share/litmus
    # (models, face DB), which hides the image's local screen (www/spot), message catalogs (locales/<code>.json) and
    # edition marker (product.json) after the first run. entrypoint.sh copies these back on every start.
    mkdir -p /opt/litmus-image; \
    cp -a /tmp/litmus-root/usr/share/litmus/www /opt/litmus-image/www 2>/dev/null || true; \
    cp -a /tmp/litmus-root/usr/share/litmus/locales /opt/litmus-image/locales 2>/dev/null || true; \
    cp -a /tmp/litmus-root/usr/share/litmus/product.json /opt/litmus-image/product.json 2>/dev/null || true; \
    rm -rf /tmp/litmus.deb /tmp/litmus-root; \
    ldconfig /usr/lib/litmus

COPY entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh \
 && chmod +x /entrypoint.sh /usr/bin/litmus/litmus

WORKDIR /usr/bin/litmus

# Liveness: litmus has reached the Litmus cloud (MQTT). Basic readiness signal —
# litmus runs as PID 1 so the container exits if it dies; this also flags
# "started but never connected" (broken network/cloud).
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD grep -q "MQTT connected" /var/log/litmus/log.txt 2>/dev/null || exit 1

ENTRYPOINT ["/entrypoint.sh"]
