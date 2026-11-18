#!/bin/sh
# Container liveness: the local server answers right now (see the HEALTHCHECK note in the Dockerfile).
# Reads the same settings the device does (litmus-controller LocalServer.cpp readConfig, QA D-135):
#   /etc/litmus/local_server.json  {"enabled": false}  -> the local server is off on purpose: healthy
#                                  {"port": 8129}      -> ask that port instead of 8128
#   GRABLO_LOCAL_SERVER (any value) overrides "enabled": "0" = off, anything else = on.
# Before this, the check only knew GRABLO_LOCAL_SERVER and always asked 8128, so a device with the
# local screen turned off or moved stayed "unhealthy" forever (an orchestrator could keep restarting it).
cfg=/etc/litmus/local_server.json
enabled=1
port=8128
if [ -r "$cfg" ]; then
  j=$(tr -d ' \t\r\n' < "$cfg")
  case "$j" in
    *'"enabled":false'*) enabled=0 ;;
  esac
  p=$(printf '%s' "$j" | sed -n 's/.*"port":\([0-9][0-9]*\)[,}].*/\1/p')
  if [ -n "$p" ] && [ "$p" -gt 0 ] && [ "$p" -lt 65536 ]; then port=$p; fi
fi
if [ -n "${GRABLO_LOCAL_SERVER+x}" ]; then
  if [ "$GRABLO_LOCAL_SERVER" = "0" ]; then enabled=0; else enabled=1; fi
fi
[ "$enabled" = "0" ] && exit 0
curl -fsS --noproxy '*' --max-time 4 "http://127.0.0.1:${port}/api/v1/health" >/dev/null || exit 1
