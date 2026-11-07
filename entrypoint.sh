#!/bin/bash
# ============================================================================
# Litmus container entrypoint
#   Does only what the container needs at startup, then runs litmus as PID 1.
# ============================================================================
set -e

DATA_DIR="${LITMUS_DATA_DIR:-/data}"

# 1) Device identity persistence
#    Keep the device identity stable across container recreation so it stays the
#    same paired device. Without it, the device must be re-paired.
if [ -s "${DATA_DIR}/machine-id" ]; then
    cp "${DATA_DIR}/machine-id" /etc/machine-id
elif [ ! -s /etc/machine-id ]; then
    cat /proc/sys/kernel/random/uuid | tr -d '-' > /etc/machine-id
    if [ -d "${DATA_DIR}" ] || mkdir -p "${DATA_DIR}" 2>/dev/null; then
        cp /etc/machine-id "${DATA_DIR}/machine-id" 2>/dev/null || true
    fi
fi
echo "[entrypoint] device identity ready"

# 2) Library cache
ldconfig /usr/lib/litmus 2>/dev/null || true

# 2b) Files that belong to the image, not to the /usr/share/litmus volume (models, face DB stay in the volume):
#     the local screen (www/spot, port 8128), the default sounds (sounds), the message catalogs (locales/<code>.json — read by the controller,
#     src/litmus-common/LocaleCatalog.h) and the edition marker (product.json — Litmus NVR image only).
#     Refresh them from the image on every start so an image update reaches existing volumes.
SHARE=/usr/share/litmus
if [ -d /opt/litmus-image ]; then
    mkdir -p "$SHARE"
    rm -rf "$SHARE/www"
    [ -d /opt/litmus-image/www ] && cp -a /opt/litmus-image/www "$SHARE/www"
    rm -rf "$SHARE/sounds"
    [ -d /opt/litmus-image/sounds ] && cp -a /opt/litmus-image/sounds "$SHARE/sounds"
    rm -rf "$SHARE/locales"
    [ -d /opt/litmus-image/locales ] && cp -a /opt/litmus-image/locales "$SHARE/locales"
    if [ -f /opt/litmus-image/product.json ]; then
        cp -f /opt/litmus-image/product.json "$SHARE/product.json"
    else
        rm -f "$SHARE/product.json"
    fi
fi

# 3) Audio
#    By default an external PulseAudio (host socket mount, or HA audio:true) is used.
#    Set LITMUS_START_PULSE=1 (with /dev/snd) to start PulseAudio inside the container.
if [ "${LITMUS_START_PULSE}" = "1" ] && command -v pulseaudio >/dev/null 2>&1; then
    echo "[entrypoint] starting in-container PulseAudio (system mode)..."
    pulseaudio --system --disallow-exit --disallow-module-loading=0 --daemonize=yes --realtime 2>/dev/null || \
        echo "[entrypoint] WARN: failed to start pulseaudio — audio disabled"
fi
[ -n "${PULSE_SERVER}" ] && echo "[entrypoint] PULSE_SERVER=${PULSE_SERVER}"

# 4) Remove stale single-instance lock.
#    litmus records its PID in /run/litmus.pid. In a container it runs as PID 1,
#    and /run persists across restarts, so a leftover lock (PID 1 is "always alive")
#    makes the next start abort with "another instance is already running".
#    Only one litmus ever runs in this container, so any lock present here is stale.
rm -f /run/litmus.pid

# 5) Mirror litmus's file log to the container stdout so `docker logs` works.
#    (litmus logs to /var/log/litmus/log.txt by default.) tail -F retries until
#    the file appears and follows rotation. Opt out with LITMUS_LOG_STDOUT=0.
if [ "${LITMUS_LOG_STDOUT:-1}" = "1" ]; then
    tail -n0 -F /var/log/litmus/log.txt 2>/dev/null &
fi

# 6) Run litmus as PID 1.
echo "[entrypoint] exec litmus ..."
exec /usr/bin/litmus/litmus
