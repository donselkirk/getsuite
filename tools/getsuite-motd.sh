#!/usr/bin/env bash

# Show once per login shell even if profile.d is sourced more than once.
[[ "${GETSUITE_MOTD_SHOWN:-0}" == "1" ]] && return 0
export GETSUITE_MOTD_SHOWN=1

registry="/opt/getsuite/installed.apps"
ip_address="$(hostname -I 2>/dev/null | awk '{print $1}')"
if [[ -z "$ip_address" ]]; then
  ip_address="$(ip -4 addr show scope global 2>/dev/null | awk '/inet / {sub(/\/.*/, "", $2); print $2; exit}')"
fi

printf '\n\033[1;92mGetSuite LXC Container\033[0m\n'
printf ' OS: %s\n' "$(. /etc/os-release && printf '%s %s' "$NAME" "$VERSION_ID")"
printf ' Hostname: %s\n' "$(hostname)"
printf ' IP Address: %s\n' "${ip_address:-unavailable}"
printf ' Repository: https://github.com/donselkirk/getsuite\n'
printf '\n VPN Connection:\n'
if [[ -f /opt/getsuite/gluetun.enabled ]]; then
  vpn_state="$(systemctl is-active gluetun 2>/dev/null || true)"
  provider="$(awk -F= '$1 == "VPN_SERVICE_PROVIDER" {gsub(/^"|"$/, "", $2); print $2; exit}' /opt/gluetun-data/.env 2>/dev/null)"
  vpn_ip="$(tr -d '[:space:]' </opt/gluetun-data/ip 2>/dev/null || true)"
  route_device="$(ip -4 route get 1.1.1.1 2>/dev/null | awk 'NR == 1 {for (i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}')"
  if [[ "$vpn_state" == active && "$route_device" =~ ^(tun|wg) && -n "$vpn_ip" ]]; then
    connection="connected"
  else
    connection="disconnected"
  fi
  printf '  - Status: %s (%s)\n' "$connection" "${vpn_state:-unknown}"
  printf '  - Provider: %s\n' "${provider:-unknown}"
  printf '  - VPN interface: %s\n' "${route_device:-unavailable}"
  printf '  - VPN public IP: %s\n' "${vpn_ip:-unavailable}"
else
  printf '  - Gluetun is not installed\n'
fi
printf '\n Installed Applications:\n'

installed_count=0
if [[ -r "$registry" ]]; then
  while IFS= read -r app; do
    case "$app" in
      qbittorrent) label="qBittorrent"; port="8090"; service="qbittorrent-nox" ;;
      *) continue ;;
    esac

    state="$(systemctl is-active "$service" 2>/dev/null || true)"
    [[ -n "$state" ]] || state="unknown"
    printf '  - %-7s http://%s:%s (%s)\n' "$label" "${ip_address:-localhost}" "$port" "$state"
    installed_count=$((installed_count + 1))
  done <"$registry"
fi

if ((installed_count == 0)); then
  printf '  - None; run: getsuite add\n'
fi
printf '\n'

unset registry ip_address installed_count app label port service state vpn_state provider vpn_ip route_device connection
