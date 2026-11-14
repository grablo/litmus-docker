# Litmus NVR — Docker

Run [Litmus NVR](https://litmusnvr.com) as a Docker container: AI search and alerts for the IP cameras you already have.

## Quick start

```bash
git clone https://github.com/grablo/litmus-docker.git
cd litmus-docker
docker compose up -d
```

Open `http://<this-host>:8128/` for the local screen. On first start the setup code is printed in `docker logs litmus`. You can also add the device at [app.litmusnvr.com](https://app.litmusnvr.com) to use it from anywhere.

Pin a version:

```bash
cp .env.example .env      # set LITMUS_VERSION
docker compose up -d
```

Update by pulling a newer image (the container does not update itself):

```bash
docker compose pull && docker compose up -d
```

On Home Assistant OS or Supervised, use the [add-on](https://github.com/grablo/litmus-hass-addons) instead.

## Persistent data

| Volume | Path | Purpose |
|---|---|---|
| `litmus-id` | `/data` | Device identity. Keep it so this stays the same device |
| `litmus-config` | `/etc/litmus` | Settings, including encrypted values |
| `litmus-data` | `/var/litmus` | Recordings, history, downloaded files |
| `litmus-log` | `/var/log/litmus` | Logs |
| `litmus-models` | `/usr/share/litmus` | AI and speech models, face data |
| `litmus-secure` | `/var/lib/.syscache-litmus` | Keys for the encrypted settings |
| `litmus-zigbee` | `/usr/lib/litmus/zigbee` | Zigbee runtime and paired devices |

## Hardware

The container uses `network_mode: host` and needs outbound internet for remote access. Network cameras need no extra setup. For physical devices, uncomment the lines in `docker-compose.yml`; none of them needs `privileged`.

| Feature | Add to `docker-compose.yml` |
|---|---|
| Audio | `devices: /dev/snd` and `LITMUS_START_PULSE=1`, or mount the host PulseAudio socket |
| USB camera | `devices: /dev/video0`, `/dev/media0` and `volumes: /run/udev:/run/udev:ro` |
| USB serial | `devices: /dev/ttyUSB0` |
| Zigbee dongle | `devices: /dev/ttyACM0` |

Device passthrough needs a real Linux host. Docker Desktop on Windows and macOS runs in a VM and cannot pass USB devices through.

## Image

Images are published to `ghcr.io/grablo/litmus-nvr` for `linux/amd64` and `linux/arm64`. Each image is built from the official release `.deb`. To build it yourself:

```bash
docker build --build-arg LITMUS_VERSION=2.4.0 -t ghcr.io/grablo/litmus-nvr:2.4.0 .
```

## Home Assistant discovery

Home Assistant finds Litmus by itself (Settings › Devices & services › Discovered) once Home Assistant is turned on in Litmus
(Settings › Integrations). The container runs its own avahi-daemon for this — host networking is required (the default in
`docker-compose.yml`).

- If the host already runs avahi-daemon, mount its socket instead (the two commented volume lines in `docker-compose.yml`).
  Two mDNS responders on one host make discovery unreliable.
- `LITMUS_AVAHI=0` turns advertising off; add Litmus in Home Assistant by its address (shown in Litmus › Settings › Integrations).

## Logs

```bash
docker logs -f litmus
```

Set `LITMUS_LOG_STDOUT=0` to stop mirroring the log file to the container output.

## Health check

The image's health check calls the local server at `http://127.0.0.1:8128/api/v1/health`. It shows whether Litmus NVR is responding, not whether the host has internet access. If you turn off the local server or change its port in `local_server.json`, set `healthcheck: disable: true` in `docker-compose.yml`.

## License

This repository contains only packaging. Litmus NVR itself is proprietary software of Grablo Inc.
