#!/usr/bin/env bash
set -u

readonly timeout_seconds="${GETSUITE_VPN_READY_TIMEOUT:-90}"
deadline=$((SECONDS + timeout_seconds))

while ((SECONDS < deadline)); do
  if systemctl is-active --quiet gluetun.service \
    && [[ -c /dev/net/tun ]] \
    && ip link show tun0 2>/dev/null | grep -qE '^[0-9]+: tun0: <[^>]*UP([,>])' \
    && ip route get 1.1.1.1 2>/dev/null | grep -qE 'dev tun0([[:space:]]|$)' \
    && curl -fsS --max-time 2 http://127.0.0.1:9999/ >/dev/null 2>&1 \
    && [[ -s /gluetun/ip ]]; then
    exit 0
  fi
  sleep 2
done

echo "GetSuite: Gluetun did not become VPN-ready within ${timeout_seconds}s; refusing to start qBittorrent." >&2
exit 1
