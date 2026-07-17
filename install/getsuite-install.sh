#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Don Selkirk
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://wiki.servarr.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Keep an GetSuite-owned fallback for passwordless console access. The shared
# Community Scripts customize() helper normally performs this configuration,
# but configuring both getty paths here prevents regressions when the helper
# implementation or the Proxmox console path changes.
configure_getsuite_console_autologin() {
  [[ -z "${PASSWORD:-}" ]] || return 0

  msg_info "Configuring Console Auto-Login"
  passwd -d root &>/dev/null || true

  if systemctl cat container-getty@.service &>/dev/null \
    || [[ -f /usr/lib/systemd/system/container-getty@.service ]] \
    || [[ -f /lib/systemd/system/container-getty@.service ]]; then
    install -d -m 0755 /etc/systemd/system/container-getty@1.service.d
    cat >/etc/systemd/system/container-getty@1.service.d/override.conf <<'EOF_GETTY'
[Service]
ImportCredential=
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --noissue --keep-baud tty%I 115200,38400,9600 - $TERM
EOF_GETTY
  fi

  if systemctl cat console-getty.service &>/dev/null \
    || [[ -f /usr/lib/systemd/system/console-getty.service ]] \
    || [[ -f /lib/systemd/system/console-getty.service ]]; then
    install -d -m 0755 /etc/systemd/system/console-getty.service.d
    cat >/etc/systemd/system/console-getty.service.d/override.conf <<'EOF_CONSOLE'
[Service]
ImportCredential=
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --noissue --keep-baud 115200,38400,9600 - $TERM
EOF_CONSOLE
    systemctl enable console-getty.service &>/dev/null || true
  fi

  systemctl daemon-reload
  systemctl unmask container-getty@1.service console-getty.service &>/dev/null || true
  systemctl enable container-getty@1.service console-getty.service &>/dev/null || true
  systemctl reset-failed container-getty@1.service console-getty.service &>/dev/null || true
  systemctl restart container-getty@1.service &>/dev/null || true
  systemctl restart console-getty.service &>/dev/null || true
  msg_ok "Configured Console Auto-Login"
}

configure_getsuite_motd() {
  msg_info "Configuring GetSuite Login Banner"

  # Community Scripts deliberately provides both a static PAM MOTD and a
  # dynamic profile banner. GetSuite uses only the dynamic banner so it can
  # include the current application registry without displaying twice.
  : >/etc/motd
  if [[ -d /etc/update-motd.d ]]; then
    chmod -x /etc/update-motd.d/* 2>/dev/null || true
  fi

  cat >/etc/profile.d/00_lxc-details.sh <<'EOF_MOTD'
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
EOF_MOTD
  chmod 0755 /etc/profile.d/00_lxc-details.sh

  msg_ok "Configured GetSuite Login Banner"
}

msg_info "Installing GetSuite Manager Dependencies"
$STD apt install -y python3 whiptail
msg_ok "Installed GetSuite Manager Dependencies"

msg_info "Creating GetSuite Manager"
install -d -m 0755 /opt/getsuite/lib
install -d -m 0755 /opt/getsuite
printf '%s\n' "$FUNCTIONS_FILE_PATH" >/opt/getsuite/lib/community-functions.sh
chmod 0644 /opt/getsuite/lib/community-functions.sh
curl -fsSL "${COMMUNITY_SCRIPTS_URL}/misc/tools.func" \
  -o /opt/getsuite/lib/community-tools.sh
chmod 0644 /opt/getsuite/lib/community-tools.sh
touch /opt/getsuite/installed.apps
chmod 0644 /opt/getsuite/installed.apps

cat > /usr/local/bin/getsuite <<'EOF_MANAGER'
#!/usr/bin/env bash
set -Eeuo pipefail

export APP="GetSuite"
export NSAPP="getsuite"
VERBOSE="${VERBOSE:-no}"
STD="${STD:-}"

readonly BASE_DIR="${GETSUITE_BASE_DIR:-/opt/getsuite}"
readonly REGISTRY="${GETSUITE_REGISTRY:-${BASE_DIR}/installed.apps}"
readonly FUNCTIONS_LIBRARY="${GETSUITE_FUNCTIONS_LIBRARY:-${BASE_DIR}/lib/community-functions.sh}"
readonly TOOLS_LIBRARY="${GETSUITE_TOOLS_LIBRARY:-${BASE_DIR}/lib/community-tools.sh}"
readonly LOCK_FILE="${GETSUITE_LOCK_FILE:-/run/lock/getsuite.lock}"
readonly UPDATE_URL_FILE="${BASE_DIR}/update.url"
readonly VERSION_FILE="${BASE_DIR}/version"
readonly DEFAULT_UPDATE_BASE_URL="https://github.com/donselkirk/getsuite/releases/latest/download"
readonly MANAGER_PATH="${GETSUITE_MANAGER_PATH:-/usr/local/bin/getsuite}"
readonly MOTD_PATH="${GETSUITE_MOTD_PATH:-/etc/profile.d/00_lxc-details.sh}"
readonly REPAIR_PATH="${GETSUITE_REPAIR_PATH:-/usr/local/sbin/getsuite-fix-console-autologin}"
readonly APP_INSTALL_ROOT="${GETSUITE_APP_INSTALL_ROOT:-/opt}"
readonly SYSTEMD_UNIT_DIR="${GETSUITE_SYSTEMD_UNIT_DIR:-/etc/systemd/system}"
readonly RELEASE_MARKER_ROOT="${GETSUITE_RELEASE_MARKER_ROOT:-$HOME}"
readonly -a SUPPORTED_APPS=(qbittorrent)

declare -A APP_LABEL=(
  [qbittorrent]="qBittorrent"
)

declare -A APP_DESCRIPTION=(
  [qbittorrent]="BitTorrent client (port 8090)"
)

declare -A APP_PORT=(
  [qbittorrent]="8090"
)

declare -A APP_SERVICE=(
  [qbittorrent]="qbittorrent-nox"
)

declare -A APP_DATA_DIR=(
  [qbittorrent]="${GETSUITE_QBITTORRENT_CONFIG_DIR:-/root/.config/qBittorrent}"
)

declare -A APP_INSTALL_DIR=(
  [qbittorrent]="${APP_INSTALL_ROOT}/qbittorrent"
)

[[ $EUID -eq 0 || "${GETSUITE_ALLOW_NON_ROOT:-0}" == "1" ]] || {
  echo "Run getsuite as root." >&2
  exit 1
}

[[ -r "$FUNCTIONS_LIBRARY" ]] || {
  echo "Missing Community Scripts function library: ${FUNCTIONS_LIBRARY}" >&2
  exit 1
}

[[ -r "$TOOLS_LIBRARY" ]] || {
  echo "Missing Community Scripts tools library: ${TOOLS_LIBRARY}" >&2
  exit 1
}

# Persist the Community Scripts helper bundle used by the source installers.
# This lets future `getsuite add` and `getsuite update` operations reuse
# fetch_and_deploy_gh_release,
# check_for_gh_release, setup_uv, arch_resolve, and the standard UI functions.
source "$FUNCTIONS_LIBRARY"
source "$TOOLS_LIBRARY"
declare -F fetch_and_deploy_gh_release >/dev/null || {
  echo "Community Scripts tools library is incomplete: ${TOOLS_LIBRARY}" >&2
  exit 1
}
color

install -d -m 0755 "$BASE_DIR" "$(dirname "$LOCK_FILE")"
touch "$REGISTRY"

normalize_app() {
  printf '%s' "${1,,}" | tr -cd 'a-z0-9_-'
}

is_supported() {
  local requested app
  requested="$(normalize_app "$1")"
  for app in "${SUPPORTED_APPS[@]}"; do
    [[ "$app" == "$requested" ]] && return 0
  done
  return 1
}

conflicting_app() {
  return 0
}

is_installed() {
  local app
  app="$(normalize_app "$1")"
  grep -Fxq "$app" "$REGISTRY" 2>/dev/null
}

require_installed_app() {
  local app
  app="$(normalize_app "$1")"
  if ! is_supported "$app"; then
    msg_error "Unsupported application: ${app:-$1}"
    return 2
  fi
  if ! is_installed "$app"; then
    msg_error "${APP_LABEL[$app]} is not installed. Run: getsuite add ${app}"
    return 1
  fi
}

register_app() {
  local app
  app="$(normalize_app "$1")"
  if ! is_installed "$app"; then
    printf '%s\n' "$app" >>"$REGISTRY"
    sort -u -o "$REGISTRY" "$REGISTRY"
  fi
}

unregister_app() {
  local app temp_registry
  app="$(normalize_app "$1")"
  temp_registry="$(mktemp "${BASE_DIR}/.installed.apps.XXXXXX")"
  grep -Fxv "$app" "$REGISTRY" >"$temp_registry" || true
  chmod --reference="$REGISTRY" "$temp_registry" 2>/dev/null || chmod 0644 "$temp_registry"
  mv "$temp_registry" "$REGISTRY"
}

acquire_lock() {
  exec 9>"$LOCK_FILE"
  flock -n 9 || {
    msg_error "Another GetSuite operation is already running."
    exit 1
  }
}

staged_prebuilt_update() {
  local service="$1" label="$2" repository="$3" app_dir="$4" asset="$5" mode="${6:-0755}"
  local stage_dir="${app_dir}.getsuite-new" previous_dir="${app_dir}.getsuite-previous"
  local stage_home="${app_dir}.getsuite-home" marker_name
  marker_name="$(printf '%s' "${label,,}" | tr -d ' ')"

  rm -rf "$stage_dir" "$stage_home"
  install -d -m 0700 "$stage_home"
  HOME="$stage_home" fetch_and_deploy_gh_release "$label" "$repository" "prebuild" "latest" "$stage_dir" "$asset" || {
    rm -rf "$stage_dir" "$stage_home"
    return 1
  }
  chmod "$mode" "$stage_dir" || { rm -rf "$stage_dir" "$stage_home"; return 1; }

  systemctl stop "$service" || { rm -rf "$stage_dir" "$stage_home"; return 1; }
  rm -rf "$previous_dir"
  mv "$app_dir" "$previous_dir" || { rm -rf "$stage_dir" "$stage_home"; systemctl start "$service" || true; return 1; }
  if ! mv "$stage_dir" "$app_dir" || ! systemctl start "$service" || ! systemctl is-active --quiet "$service"; then
    systemctl stop "$service" || true
    rm -rf "$app_dir"
    if mv "$previous_dir" "$app_dir"; then
      systemctl start "$service" || true
    else
      msg_error "${label} update rollback failed; previous files remain at ${previous_dir}"
    fi
    rm -rf "$stage_home"
    return 1
  fi
  [[ -f "${stage_home}/.${marker_name}" ]] && install -m 0644 "${stage_home}/.${marker_name}" "${HOME}/.${marker_name}"
  rm -rf "$stage_home"
  rm -rf "$previous_dir"
}

# Generated from apps/gluetun.sh. Do not edit this block directly.
#!/usr/bin/env bash

readonly GETSUITE_GLUETUN_DATA_DIR="/opt/gluetun-data"
readonly GETSUITE_GLUETUN_ENV="${GETSUITE_GLUETUN_DATA_DIR}/.env"
readonly GETSUITE_GLUETUN_IP_FILE="${GETSUITE_GLUETUN_DATA_DIR}/ip"

write_gluetun_service() {
  cat > /etc/systemd/system/gluetun.service <<'EOF_SERVICE'
[Unit]
Description=GetSuite Gluetun VPN Client
Wants=network-online.target
After=network-online.target
Before=qbittorrent-nox.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/gluetun-data
EnvironmentFile=/opt/gluetun-data/.env
UnsetEnvironment=USER
ExecStartPre=/bin/sh -c 'rm -f /etc/openvpn/target.ovpn'
ExecStart=/usr/local/bin/gluetun
Restart=on-failure
RestartSec=5
AmbientCapabilities=CAP_NET_ADMIN
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF_SERVICE
}

gluetun_tun_preflight() {
  if [[ ! -c /dev/net/tun ]]; then
    msg_error "Gluetun requires /dev/net/tun (enable TUN passthrough for this LXC)"
    return 1
  fi
  if ! exec 9<>/dev/net/tun 2>/dev/null; then
    msg_error "The TUN device exists but cannot be opened"
    return 1
  fi
  exec 9>&-
}

gluetun_detect_lan_cidr() {
  ip -4 route show scope link 2>/dev/null \
    | awk '$1 ~ /^[0-9]+\./ && $1 !~ /^169\.254\./ { print $1; exit }'
}

gluetun_validate_env_value() {
  local label="$1" value="$2"
  if [[ -z "$value" || "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    msg_error "${label} cannot be empty or contain a newline"
    return 1
  fi
}

gluetun_env_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//\$/\\\$}"
  printf '"%s"' "$value"
}

configure_gluetun_openvpn() {
  local provider="${GETSUITE_VPN_PROVIDER:-}"
  local username="${GETSUITE_OPENVPN_USER:-}"
  local password="${GETSUITE_OPENVPN_PASSWORD:-}"
  local countries="${GETSUITE_VPN_COUNTRIES:-}"
  local regions="${GETSUITE_VPN_REGIONS:-}"
  local cities="${GETSUITE_VPN_CITIES:-}"
  local lan_cidr="${GETSUITE_LAN_CIDR:-$(gluetun_detect_lan_cidr)}"
  local input_ports="${GETSUITE_VPN_INPUT_PORTS:-22,8090}"
  local entered_lan=""

  if [[ -r /dev/tty && -w /dev/tty ]] && command -v whiptail >/dev/null 2>&1; then
    if [[ -z "$provider" ]]; then
      provider="$(whiptail --title "Gluetun OpenVPN Setup" \
        --inputbox "VPN provider name as listed by Gluetun:" 10 72 \
        3>&1 1>/dev/tty 2>&3 </dev/tty)" || return 1
    fi
    if [[ -z "$username" ]]; then
      username="$(whiptail --title "Gluetun OpenVPN Setup" \
        --inputbox "OpenVPN username:" 10 72 \
        3>&1 1>/dev/tty 2>&3 </dev/tty)" || return 1
    fi
    if [[ -z "$password" ]]; then
      password="$(whiptail --title "Gluetun OpenVPN Setup" \
        --passwordbox "OpenVPN password:" 10 72 \
        3>&1 1>/dev/tty 2>&3 </dev/tty)" || return 1
    fi
    if [[ -z "$countries$regions$cities" ]]; then
      countries="$(whiptail --title "Gluetun OpenVPN Setup" \
        --inputbox "Preferred VPN country (optional):" 10 72 \
        3>&1 1>/dev/tty 2>&3 </dev/tty)" || return 1
    fi
    entered_lan="$(whiptail --title "Gluetun Firewall Setup" \
      --inputbox "LAN subnet(s) allowed outside the VPN (comma-separated):" \
      10 76 "$lan_cidr" 3>&1 1>/dev/tty 2>&3 </dev/tty)" || return 1
    lan_cidr="$entered_lan"
    printf '\033[2J\033[H' >/dev/tty
  elif [[ -r /dev/tty && -w /dev/tty ]]; then
    [[ -n "$provider" ]] || read -r -p "VPN provider (Gluetun provider name): " provider </dev/tty
    [[ -n "$username" ]] || read -r -p "OpenVPN username: " username </dev/tty
    if [[ -z "$password" ]]; then
      read -r -s -p "OpenVPN password: " password </dev/tty
      printf '\n' >/dev/tty
    fi
    if [[ -z "$countries$regions$cities" ]]; then
      read -r -p "Preferred VPN country (optional): " countries </dev/tty
    fi
    read -r -p "LAN subnet(s) allowed outside VPN [${lan_cidr:-none}]: " entered_lan </dev/tty
    [[ -z "$entered_lan" ]] || lan_cidr="$entered_lan"
  fi

  gluetun_validate_env_value "VPN provider" "$provider" || return
  gluetun_validate_env_value "OpenVPN username" "$username" || return
  gluetun_validate_env_value "OpenVPN password" "$password" || return
  if [[ ! "$provider" =~ ^[a-z0-9][a-z0-9_[:space:]-]*$ ]]; then
    msg_error "Invalid Gluetun provider name: ${provider}"
    return 1
  fi
  if [[ -n "$lan_cidr" ]] && [[ ! "$lan_cidr" =~ ^[0-9.]+/[0-9]{1,2}(,[0-9.]+/[0-9]{1,2})*$ ]]; then
    msg_error "Invalid LAN CIDR list: ${lan_cidr}"
    return 1
  fi
  if [[ ! "$input_ports" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
    msg_error "VPN input ports must be a comma-separated list of port numbers"
    return 1
  fi

  install -d -m 0700 "$GETSUITE_GLUETUN_DATA_DIR"
  umask 077
  {
    printf 'VPN_SERVICE_PROVIDER=%s\n' "$(gluetun_env_quote "$provider")"
    printf 'VPN_TYPE=openvpn\n'
    printf 'OPENVPN_USER=%s\n' "$(gluetun_env_quote "$username")"
    printf 'OPENVPN_PASSWORD=%s\n' "$(gluetun_env_quote "$password")"
    printf 'OPENVPN_PROCESS_USER=root\nPUID=0\nPGID=0\n'
    [[ -n "$countries" ]] && printf 'SERVER_COUNTRIES=%s\n' "$(gluetun_env_quote "$countries")"
    [[ -n "$regions" ]] && printf 'SERVER_REGIONS=%s\n' "$(gluetun_env_quote "$regions")"
    [[ -n "$cities" ]] && printf 'SERVER_CITIES=%s\n' "$(gluetun_env_quote "$cities")"
    printf 'FIREWALL_INPUT_PORTS=%s\n' "$(gluetun_env_quote "$input_ports")"
    [[ -n "$lan_cidr" ]] && printf 'FIREWALL_OUTBOUND_SUBNETS=%s\n' "$(gluetun_env_quote "$lan_cidr")"
    printf 'HTTP_CONTROL_SERVER_ADDRESS=127.0.0.1:8000\n'
    printf 'HEALTH_SERVER_ADDRESS=127.0.0.1:9999\n'
    printf 'DNS_UPSTREAM_RESOLVERS=cloudflare\nLOG_LEVEL=info\n'
    printf 'STORAGE_FILEPATH=/gluetun/servers.json\n'
    printf 'PUBLICIP_FILE=/gluetun/ip\n'
    printf 'VPN_PORT_FORWARDING_STATUS_FILE=/gluetun/forwarded_port\n'
    printf 'TZ=%s\n' "$(gluetun_env_quote "${TZ:-UTC}")"
  } >"$GETSUITE_GLUETUN_ENV"
  chmod 0600 "$GETSUITE_GLUETUN_ENV"
  ln -sfn "$GETSUITE_GLUETUN_DATA_DIR" /gluetun
}

verify_gluetun_connection() {
  local public_ip default_dev
  for _ in {1..30}; do
    if systemctl is-active --quiet gluetun \
      && curl -fsS --max-time 2 http://127.0.0.1:9999/ >/dev/null 2>&1 \
      && [[ -s "$GETSUITE_GLUETUN_IP_FILE" ]]; then
      public_ip="$(tr -d '[:space:]' <"$GETSUITE_GLUETUN_IP_FILE")"
      default_dev="$(ip -4 route get 1.1.1.1 2>/dev/null | awk 'NR == 1 { for (i=1;i<=NF;i++) if ($i=="dev") print $(i+1) }')"
      if [[ "$public_ip" =~ ^[0-9a-fA-F:.]+$ ]] && [[ "$default_dev" =~ ^(tun|wg) ]]; then
        msg_ok "Gluetun connected (public IP: ${public_ip})"
        return 0
      fi
    fi
    sleep 2
  done
  msg_error "Gluetun did not establish a healthy VPN route"
  journalctl -u gluetun -n 20 --no-pager >&2 || true
  return 1
}

install_gluetun() {
  gluetun_tun_preflight || return

  msg_info "Installing Gluetun Dependencies"
  $STD apt install -y openvpn wireguard-tools iptables curl || return
  update-alternatives --set iptables /usr/sbin/iptables-legacy >/dev/null 2>&1 || return
  update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy >/dev/null 2>&1 || return
  ln -sfn /usr/sbin/openvpn /usr/sbin/openvpn2.6
  setup_go || return
  msg_ok "Installed Gluetun Dependencies"

  fetch_and_deploy_gh_release "gluetun" "qdm12/gluetun" "tarball" "latest" || return
  msg_info "Building Gluetun"
  (cd /opt/gluetun && go mod download && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /usr/local/bin/gluetun ./cmd/gluetun/) || return
  msg_ok "Built Gluetun"

  configure_gluetun_openvpn || return
  touch /etc/alpine-release
  write_gluetun_service
  systemctl daemon-reload
  if ! systemctl enable -q --now gluetun || ! verify_gluetun_connection; then
    systemctl disable -q --now gluetun 2>/dev/null || true
    msg_error "Gluetun installation stopped because VPN verification failed"
    return 1
  fi
  install -d -m 0755 /opt/getsuite
  touch /opt/getsuite/gluetun.enabled
  chmod 0644 /opt/getsuite/gluetun.enabled
  msg_ok "Installed Gluetun"
}

reconfigure_gluetun() {
  [[ -x /usr/local/bin/gluetun && -f /etc/systemd/system/gluetun.service ]] || {
    msg_error "Gluetun is not installed. Run: getsuite vpn install"
    return 1
  }
  configure_gluetun_openvpn || return
  systemctl restart gluetun || return
  if ! verify_gluetun_connection; then
    systemctl stop gluetun || true
    return 1
  fi
  touch /opt/getsuite/gluetun.enabled
  msg_ok "Reconfigured Gluetun"
}

update_gluetun() {
  local stage_home stage_dir candidate backup
  if check_for_gh_release "gluetun" "qdm12/gluetun"; then
    stage_home="$(mktemp -d)"
    stage_dir="${stage_home}/source"
    candidate="${stage_home}/gluetun"
    backup="${stage_home}/gluetun.previous"
    HOME="$stage_home" fetch_and_deploy_gh_release \
      "gluetun" "qdm12/gluetun" "tarball" "latest" "$stage_dir" || {
      rm -rf "$stage_home"
      return 1
    }
    (cd "$stage_dir" && go mod download && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o "$candidate" ./cmd/gluetun/) || {
      rm -rf "$stage_home"
      return 1
    }
    [[ -x "$candidate" ]] || { rm -rf "$stage_home"; return 1; }
    cp -a /usr/local/bin/gluetun "$backup" || { rm -rf "$stage_home"; return 1; }
    systemctl stop gluetun || { rm -rf "$stage_home"; return 1; }
    install -m 0755 "$candidate" /usr/local/bin/gluetun
    if ! systemctl start gluetun || ! verify_gluetun_connection; then
      install -m 0755 "$backup" /usr/local/bin/gluetun
      systemctl restart gluetun || true
      verify_gluetun_connection || true
      rm -rf "$stage_home"
      msg_error "Gluetun update failed; restored the previous binary"
      return 1
    fi
    rm -rf "$stage_home"
    msg_ok "Updated Gluetun"
  fi
}

# Generated from apps/qbittorrent.sh. Do not edit this block directly.
#!/usr/bin/env bash

write_qbittorrent_service() {
  cat > /etc/systemd/system/qbittorrent-nox.service <<'EOF_SERVICE'
[Unit]
Description=qBittorrent-nox
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
ExecStart=/opt/qbittorrent/qbittorrent-nox
Restart=on-failure
RestartSec=5
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF_SERVICE
}

write_qbittorrent_vpn_readiness_helper() {
  cat > /usr/local/libexec/getsuite-qbittorrent-vpn-ready <<'EOF_HELPER'
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
EOF_HELPER
  chmod 0755 /usr/local/libexec/getsuite-qbittorrent-vpn-ready
}

qbittorrent_uses_gluetun() {
  [[ "${GETSUITE_GLUETUN_ENABLED:-${GETSUITE_USE_GLUETUN:-0}}" == "1" ]] \
    || [[ -f /opt/getsuite/gluetun.enabled ]]
}

configure_qbittorrent_network_mode() {
  local config=/root/.config/qBittorrent/qBittorrent.conf
  local dropin_dir=/etc/systemd/system/qbittorrent-nox.service.d

  if qbittorrent_uses_gluetun; then
    # qBittorrent's own interface binding is a second kill switch. If Gluetun
    # exits or removes tun0, qBittorrent cannot silently fall back to eth0.
    if grep -q '^Connection\\Interface=' "$config"; then
      sed -i 's/^Connection\\Interface=.*/Connection\\Interface=tun0/' "$config"
    else
      sed -i '/^\[Preferences\]/a Connection\\Interface=tun0' "$config"
    fi

    install -d -m 0755 /usr/local/libexec "$dropin_dir"
    write_qbittorrent_vpn_readiness_helper
    cat >"${dropin_dir}/10-gluetun.conf" <<'EOF_DROPIN'
[Unit]
Requires=gluetun.service
BindsTo=gluetun.service
PartOf=gluetun.service
After=gluetun.service

[Service]
ExecStartPre=/usr/local/libexec/getsuite-qbittorrent-vpn-ready
EOF_DROPIN
  else
    # Installing without Gluetun is an explicit unprotected mode. Do not leave
    # a stale tun0 binding or dependency behind after a reset/reconfiguration.
    sed -i '/^Connection\\Interface=tun0$/d' "$config"
    rm -f "${dropin_dir}/10-gluetun.conf" \
      /usr/local/libexec/getsuite-qbittorrent-vpn-ready
    rmdir "$dropin_dir" 2>/dev/null || true
  fi
}

install_qbittorrent() {
  msg_info "Installing qBittorrent"
  fetch_and_deploy_gh_release \
    "qbittorrent" \
    "userdocs/qbittorrent-nox-static" \
    "singlefile" \
    "latest" \
    "/opt/qbittorrent" \
    "$(arch_resolve "x86_64" "aarch64")-qbittorrent-nox" || return
  mv /opt/qbittorrent/qbittorrent /opt/qbittorrent/qbittorrent-nox || return
  chmod 0755 /opt/qbittorrent/qbittorrent-nox

  install -d -m 0755 /root/.config/qBittorrent
  cat >/root/.config/qBittorrent/qBittorrent.conf <<'EOF_CONFIG'
[LegalNotice]
Accepted=true

[Preferences]
WebUI\Password_PBKDF2="@ByteArray(amjeuVrF3xRbgzqWQmes5A==:XK3/Ra9jUmqUc4RwzCtrhrkQIcYczBl90DJw2rT8DFVTss4nxpoRhvyxhCf87ahVE3SzD8K9lyPdpyUCfmVsUg==)"
WebUI\Port=8090
WebUI\UseUPnP=false
WebUI\Username=admin

[Network]
PortForwardingEnabled=false
EOF_CONFIG

  write_qbittorrent_service
  configure_qbittorrent_network_mode || return
  systemctl daemon-reload
  systemctl enable -q --now qbittorrent-nox || return
  register_app qbittorrent
  msg_ok "Installed qBittorrent"
}

update_qbittorrent() {
  local stage=/opt/qbittorrent.getsuite-new
  local previous=/opt/qbittorrent.getsuite-previous

  if check_for_gh_release "qbittorrent" "userdocs/qbittorrent-nox-static"; then
    rm -rf "$stage" "$previous"
    fetch_and_deploy_gh_release \
      "qbittorrent" \
      "userdocs/qbittorrent-nox-static" \
      "singlefile" \
      "latest" \
      "$stage" \
      "$(arch_resolve "x86_64" "aarch64")-qbittorrent-nox" || return
    mv "$stage/qbittorrent" "$stage/qbittorrent-nox" || { rm -rf "$stage"; return 1; }
    chmod 0755 "$stage/qbittorrent-nox"

    systemctl stop qbittorrent-nox || { rm -rf "$stage"; return 1; }
    mv /opt/qbittorrent "$previous" || return
    if ! mv "$stage" /opt/qbittorrent \
      || ! systemctl start qbittorrent-nox \
      || ! systemctl is-active --quiet qbittorrent-nox; then
      systemctl stop qbittorrent-nox 2>/dev/null || true
      rm -rf /opt/qbittorrent
      mv "$previous" /opt/qbittorrent || return
      systemctl start qbittorrent-nox || true
      return 1
    fi
    rm -rf "$previous"
    msg_ok "Updated qBittorrent"
  fi
}

install_app() {
  local app
  app="$(normalize_app "$1")"

  case "$app" in
    qbittorrent) install_qbittorrent ;;
    *)
      msg_error "Unsupported application: $1"
      return 1
      ;;
  esac
}

update_app() {
  local app
  app="$(normalize_app "$1")"

  case "$app" in
    qbittorrent) update_qbittorrent ;;
    *)
      msg_error "Unsupported application: $1"
      return 1
      ;;
  esac
}

vpn_command() {
  local action="${1:-status}"
  case "$action" in
    install)
      if [[ -f "${BASE_DIR}/gluetun.enabled" ]]; then
        msg_ok "Gluetun is already installed. Run: getsuite vpn configure"
      else
        install_gluetun
      fi
      ;;
    configure) reconfigure_gluetun ;;
    test)
      [[ -f "${BASE_DIR}/gluetun.enabled" ]] || {
        msg_error "Gluetun is not installed. Run: getsuite vpn install"
        return 1
      }
      verify_gluetun_connection
      ;;
    status)
      if [[ ! -f "${BASE_DIR}/gluetun.enabled" ]]; then
        printf 'Gluetun: not installed\n'
        return 0
      fi
      printf 'Gluetun service: %s\n' "$(systemctl is-active gluetun 2>/dev/null || true)"
      if [[ -r /opt/gluetun-data/.env ]]; then
        awk -F= '
          $1 == "VPN_SERVICE_PROVIDER" { gsub(/^"|"$/, "", $2); print "VPN provider: " $2 }
          $1 == "VPN_TYPE" { gsub(/^"|"$/, "", $2); print "VPN protocol: " $2 }
        ' /opt/gluetun-data/.env
      fi
      if [[ -s /opt/gluetun-data/ip ]]; then
        printf 'VPN public IP: %s\n' "$(tr -d '[:space:]' </opt/gluetun-data/ip)"
      else
        printf 'VPN public IP: unavailable\n'
      fi
      ;;
    *)
      msg_error "Usage: getsuite vpn {install|configure|status|test}"
      return 2
      ;;
  esac
}

choose_uninstalled_apps() {
  local -a options=()
  local app conflict selection default_state

  for app in "${SUPPORTED_APPS[@]}"; do
    conflict="$(conflicting_app "$app")"
    if ! is_installed "$app" && { [[ -z "$conflict" ]] || ! is_installed "$conflict"; }; then
      default_state="ON"
      options+=("$app" "${APP_DESCRIPTION[$app]}" "$default_state")
    fi
  done

  if ((${#options[@]} == 0)); then
    msg_ok "Every supported application is already installed" >&2
    return 0
  fi

  if [[ -r /dev/tty && -w /dev/tty ]] && command -v whiptail >/dev/null 2>&1; then
    selection="$(whiptail \
      --title "GetSuite Application Selection" \
      --checklist "Choose applications to install. Space toggles; Enter confirms." \
      18 78 8 \
      "${options[@]}" \
      --separate-output \
      3>&1 1>/dev/tty 2>&3 </dev/tty)" || return 0
    printf '%s\n' "$selection"
    return 0
  fi

  msg_warn "No interactive terminal detected; selecting qBittorrent by default" >&2
  is_installed qbittorrent || printf '%s\n' qbittorrent
}

add_apps() {
  local -a apps=("$@")
  local app conflict failures=0
  local -A requested=()

  if ((${#apps[@]} == 0)); then
    mapfile -t apps < <(choose_uninstalled_apps)
    if [[ -w /dev/tty ]]; then
      printf '\033[2J\033[H' >/dev/tty
    fi
  fi

  if ((${#apps[@]} == 0)); then
    msg_ok "No applications selected"
    return 0
  fi

  for app in "${apps[@]}"; do
    app="$(normalize_app "$app")"
    [[ -z "$app" ]] || requested["$app"]=1
  done

  for app in "${apps[@]}"; do
    app="$(normalize_app "$app")"
    [[ -n "$app" ]] || continue

    if ! is_supported "$app"; then
      msg_error "Unsupported application: $app"
      failures=$((failures + 1))
      continue
    fi

    if is_installed "$app"; then
      msg_ok "${APP_LABEL[$app]} is already installed"
      continue
    fi

    conflict="$(conflicting_app "$app")"
    if [[ -n "$conflict" ]] && { is_installed "$conflict" || [[ -n "${requested[$conflict]:-}" ]]; }; then
      msg_error "${APP_LABEL[$app]} cannot be installed with ${APP_LABEL[$conflict]}; remove ${conflict} first"
      failures=$((failures + 1))
      continue
    fi

    if (set -e; install_app "$app"); then
      :
    else
      msg_error "Failed to install ${APP_LABEL[$app]}"
      failures=$((failures + 1))
    fi
  done

  ((failures == 0))
}

confirm_destructive_action() {
  local prompt="$1" response=""
  if command -v tty >/dev/null 2>&1 && tty -s; then
    if ! read -r -p "${prompt} [y/N] " response </dev/tty 2>/dev/null; then
      msg_error "Confirmation requires an interactive terminal; use --yes to continue"
      return 1
    fi
  else
    msg_error "Confirmation requires an interactive terminal; use --yes to continue"
    return 1
  fi
  [[ "${response,,}" == "y" || "${response,,}" == "yes" ]]
}

remove_app_files() {
  local app="$1" purge="$2" install_dir service
  install_dir="${APP_INSTALL_DIR[$app]}"
  service="${APP_SERVICE[$app]}"

  systemctl disable --now "$service" >/dev/null 2>&1 || true
  rm -f "${SYSTEMD_UNIT_DIR}/${service}.service"
  if [[ "$app" == "qbittorrent" ]]; then
    rm -rf "${SYSTEMD_UNIT_DIR}/qbittorrent-nox.service.d"
    rm -f /usr/local/libexec/getsuite-qbittorrent-vpn-ready
  fi

  rm -rf "$install_dir" "${install_dir}.getsuite-new" \
    "${install_dir}.getsuite-previous" "${install_dir}.getsuite-home"
  rm -f "${RELEASE_MARKER_ROOT}/.${app}"

  if [[ "$purge" == "1" ]]; then
    [[ -z "${APP_DATA_DIR[$app]:-}" ]] || rm -rf "${APP_DATA_DIR[$app]}"
  fi

  systemctl daemon-reload
  systemctl reset-failed "$service" >/dev/null 2>&1 || true
  unregister_app "$app"
}

remove_or_reset_apps() {
  local action="$1" purge=0 assume_yes=0 app failures=0 prompt labels="" suffix=""
  shift
  local -a apps=()

  [[ "$action" != "reset" ]] || purge=1
  while (($#)); do
    case "$1" in
      --purge)
        [[ "$action" == "remove" ]] || { msg_error "--purge is implicit with reset"; return 2; }
        purge=1
        ;;
      --yes|-y) assume_yes=1 ;;
      --*) msg_error "Unknown ${action} option: $1"; return 2 ;;
      *) apps+=("$(normalize_app "$1")") ;;
    esac
    shift
  done
  if ((${#apps[@]} == 0)); then
    if [[ "$action" == "remove" ]]; then
      msg_error "Usage: getsuite remove app [app ...] [--purge] [--yes]"
    else
      msg_error "Usage: getsuite reset app [app ...] [--yes]"
    fi
    return 2
  fi

  for app in "${apps[@]}"; do
    require_installed_app "$app" || return
    labels+="${labels:+, }${APP_LABEL[$app]}"
  done
  if [[ "$action" == "reset" ]]; then
    prompt="Reset ${labels}? All application data will be permanently deleted and the apps reinstalled."
  elif ((purge)); then
    prompt="Remove ${labels} and permanently delete all application data?"
  else
    prompt="Remove ${labels}? Application data will be preserved."
  fi
  if (( ! assume_yes )) && ! confirm_destructive_action "$prompt"; then
    msg_warn "${action^} cancelled"
    return 0
  fi

  for app in "${apps[@]}"; do
    msg_info "${action^}ing ${APP_LABEL[$app]}"
    if ! remove_app_files "$app" "$purge"; then
      msg_error "Failed to remove ${APP_LABEL[$app]}"
      failures=$((failures + 1))
      continue
    fi
    if [[ "$action" == "reset" ]]; then
      if (set -e; install_app "$app"); then
        msg_ok "Reset ${APP_LABEL[$app]}"
      else
        msg_error "Removed ${APP_LABEL[$app]}, but the clean reinstall failed"
        failures=$((failures + 1))
      fi
    else
      suffix=""
      if [[ "$purge" == "0" ]]; then
        suffix="; application data preserved"
      fi
      msg_ok "Removed ${APP_LABEL[$app]}${suffix}"
    fi
  done
  ((failures == 0))
}

update_apps() {
  local -a apps=("$@")
  local app failures=0

  if ((${#apps[@]} == 0)) && [[ -f "${BASE_DIR}/gluetun.enabled" ]]; then
    if ! (set -e; update_gluetun); then
      msg_error "Failed to update Gluetun"
      failures=$((failures + 1))
    fi
  fi

  if ((${#apps[@]} == 0)); then
    mapfile -t apps <"$REGISTRY"
  fi

  if ((${#apps[@]} == 0)); then
    msg_warn "No applications are installed. Run: getsuite add"
    return 0
  fi

  for app in "${apps[@]}"; do
    app="$(normalize_app "$app")"
    [[ -n "$app" ]] || continue

    if ! require_installed_app "$app"; then
      failures=$((failures + 1))
      continue
    fi

    if (set -e; update_app "$app"); then
      :
    else
      msg_error "Failed to update ${APP_LABEL[$app]:-$app}"
      failures=$((failures + 1))
    fi
  done

  if ((failures > 0)); then
    msg_error "${failures} application operation(s) failed; remaining apps were still processed"
    return 1
  fi

  msg_ok "All installed GetSuite applications are current"
}

restart_apps() {
  local -a apps=("$@")
  local app failures=0

  if ((${#apps[@]} == 0)); then
    mapfile -t apps <"$REGISTRY"
  fi
  if ((${#apps[@]} == 0)); then
    msg_warn "No applications are installed"
    return 0
  fi

  for app in "${apps[@]}"; do
    app="$(normalize_app "$app")"
    [[ -n "$app" ]] || continue

    if ! require_installed_app "$app"; then
      failures=$((failures + 1))
      continue
    fi

    msg_info "Restarting ${APP_LABEL[$app]}"
    if systemctl restart "${APP_SERVICE[$app]}" && systemctl is-active --quiet "${APP_SERVICE[$app]}"; then
      msg_ok "Restarted ${APP_LABEL[$app]}"
    else
      msg_error "Failed to restart ${APP_LABEL[$app]}"
      failures=$((failures + 1))
    fi
  done

  if ((failures > 0)); then
    msg_error "${failures} application restart(s) failed; remaining apps were still processed"
    return 1
  fi

  msg_ok "All requested GetSuite applications restarted"
}

self_update() {
  local update_url community_url temp_dir release_version runtime_file backup_file changed=0
  update_url="${GETSUITE_UPDATE_BASE_URL:-}"
  if [[ -z "$update_url" && -r "$UPDATE_URL_FILE" ]]; then
    update_url="$(<"$UPDATE_URL_FILE")"
  fi
  update_url="${update_url:-$DEFAULT_UPDATE_BASE_URL}"
  update_url="${update_url%/}"
  community_url="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}"
  community_url="${community_url%/}"

  temp_dir="$(mktemp -d)"
  if ! curl -fsSL "${update_url}/getsuite-manager" -o "${temp_dir}/getsuite" \
    || ! curl -fsSL "${update_url}/getsuite-motd.sh" -o "${temp_dir}/getsuite-motd.sh" \
    || ! curl -fsSL "${update_url}/fix-console-autologin.sh" -o "${temp_dir}/fix-console-autologin.sh" \
    || ! curl -fsSL "${update_url}/VERSION" -o "${temp_dir}/VERSION" \
    || ! curl -fsSL "${update_url}/SHA256SUMS" -o "${temp_dir}/SHA256SUMS" \
    || ! curl -fsSL "${community_url}/misc/install.func" -o "${temp_dir}/community-functions.sh" \
    || ! curl -fsSL "${community_url}/misc/tools.func" -o "${temp_dir}/community-tools.sh"; then
    rm -rf "$temp_dir"
    msg_error "Failed to download GetSuite update files"
    return 1
  fi

  if ! (cd "$temp_dir" && sha256sum -c --ignore-missing SHA256SUMS >/dev/null \
      && grep -q ' getsuite-manager$' SHA256SUMS \
      && grep -q ' getsuite-motd.sh$' SHA256SUMS \
      && grep -q ' fix-console-autologin.sh$' SHA256SUMS \
      && grep -q ' VERSION$' SHA256SUMS) \
    || ! bash -n "${temp_dir}/getsuite" \
    || ! bash -n "${temp_dir}/getsuite-motd.sh" \
    || ! bash -n "${temp_dir}/fix-console-autologin.sh" \
    || ! grep -q '^fetch_and_deploy_gh_release()' "${temp_dir}/community-tools.sh" \
    || ! grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' "${temp_dir}/VERSION"; then
    rm -rf "$temp_dir"
    msg_error "Downloaded GetSuite update files failed validation"
    return 1
  fi
  release_version="$(<"${temp_dir}/VERSION")"

  msg_info "Updating GetSuite Runtime"
  cmp -s "${temp_dir}/getsuite" "$MANAGER_PATH" || changed=1
  install -d -m 0700 "${temp_dir}/previous"
  for runtime_file in "$MANAGER_PATH" "$MOTD_PATH" "$REPAIR_PATH" "$FUNCTIONS_LIBRARY" "$TOOLS_LIBRARY" "$VERSION_FILE" "$UPDATE_URL_FILE"; do
    [[ ! -e "$runtime_file" ]] || cp -a "$runtime_file" "${temp_dir}/previous/$(basename "$runtime_file")"
  done
  if ! install -m 0755 "${temp_dir}/getsuite" "$MANAGER_PATH" \
    || ! install -m 0755 "${temp_dir}/getsuite-motd.sh" "$MOTD_PATH" \
    || ! install -m 0755 "${temp_dir}/fix-console-autologin.sh" "$REPAIR_PATH" \
    || ! install -m 0644 "${temp_dir}/community-functions.sh" "$FUNCTIONS_LIBRARY" \
    || ! install -m 0644 "${temp_dir}/community-tools.sh" "$TOOLS_LIBRARY" \
    || ! install -m 0644 "${temp_dir}/VERSION" "$VERSION_FILE" \
    || ! printf '%s\n' "$update_url" >"$UPDATE_URL_FILE"; then
    for runtime_file in "$MANAGER_PATH" "$MOTD_PATH" "$REPAIR_PATH" "$FUNCTIONS_LIBRARY" "$TOOLS_LIBRARY" "$VERSION_FILE" "$UPDATE_URL_FILE"; do
      backup_file="${temp_dir}/previous/$(basename "$runtime_file")"
      [[ ! -e "$backup_file" ]] || cp -a "$backup_file" "$runtime_file" || true
    done
    rm -rf "$temp_dir"
    msg_error "Failed to install GetSuite update files; previous runtime restored"
    return 1
  fi
  rm -rf "$temp_dir"

  if ((changed)); then
    msg_ok "Updated GetSuite Runtime to ${release_version}"
  else
    msg_ok "GetSuite Runtime is Already Current at ${release_version}"
  fi
}

show_version() {
  if [[ -r "$VERSION_FILE" ]]; then
    printf 'GetSuite %s\n' "$(<"$VERSION_FILE")"
  else
    printf 'GetSuite development\n'
  fi
}

show_list() {
  local app installed service_state
  printf '%-10s %-11s %-10s %-12s\n' "APP" "INSTALLED" "PORT" "SERVICE"
  printf '%-10s %-11s %-10s %-12s\n' "----------" "-----------" "----------" "------------"

  for app in "${SUPPORTED_APPS[@]}"; do
    installed="no"
    service_state="-"
    if is_installed "$app"; then
      installed="yes"
      service_state="$(systemctl is-active "${APP_SERVICE[$app]}" 2>/dev/null || true)"
    fi
    printf '%-10s %-11s %-10s %-12s\n' \
      "${APP_LABEL[$app]}" \
      "$installed" \
      "${APP_PORT[$app]}" \
      "$service_state"
  done
}

show_status() {
  local -a apps=("$@")
  local app failures=0
  if ((${#apps[@]} == 0)); then
    mapfile -t apps <"$REGISTRY"
  fi
  if ((${#apps[@]} == 0)); then
    msg_warn "No applications are installed"
    return 0
  fi

  for app in "${apps[@]}"; do
    app="$(normalize_app "$app")"
    [[ -n "$app" ]] || continue
    if ! require_installed_app "$app"; then
      failures=$((failures + 1))
      continue
    fi
    echo
    systemctl --no-pager --full status "${APP_SERVICE[$app]}" || true
  done
  ((failures == 0))
}

show_help() {
  cat <<'EOF_HELP'
GetSuite multi-application manager

Usage:
  getsuite add [app ...]       Install apps; opens a checklist when no app is named
  getsuite remove app [app ...] [--purge] [--yes]
                               Remove apps; preserve data unless --purge is used
  getsuite reset app [app ...] [--yes]
                               Delete app data and perform a clean reinstall
  getsuite update [app ...]    Update all installed apps, or only named apps
  getsuite restart [app ...]   Restart all installed apps, or only named apps
  getsuite vpn install         Install and configure native Gluetun
  getsuite vpn configure       Change the named OpenVPN provider configuration
  getsuite vpn status          Show VPN provider, service, and public IP
  getsuite vpn test            Verify health, public IP, and the VPN route
  getsuite self-update         Update GetSuite and Community Scripts helpers
  getsuite version             Show the installed GetSuite release version
  getsuite list                Show supported apps, ports, and service state
  getsuite status [app ...]    Show status for all installed apps, or only named apps
  getsuite help                Show this help

Supported apps:
  qbittorrent  BitTorrent client, port 8090

The Community Scripts command `update` invokes `getsuite update`.
EOF_HELP
}

main() {
  case "${1:-help}" in
    add|install)
      acquire_lock
      shift
      add_apps "$@"
      ;;
    remove|uninstall)
      acquire_lock
      shift
      remove_or_reset_apps remove "$@"
      ;;
    reset)
      acquire_lock
      shift
      remove_or_reset_apps reset "$@"
      ;;
    update|upgrade)
      acquire_lock
      shift
      if [[ "${GETSUITE_SKIP_SELF_UPDATE:-0}" != "1" ]] && ! self_update; then
        msg_warn "GetSuite self-update failed; continuing with application updates"
      fi
      update_apps "$@"
      ;;
    restart)
      acquire_lock
      shift
      restart_apps "$@"
      ;;
    vpn|gluetun)
      acquire_lock
      shift
      vpn_command "$@"
      ;;
    self-update)
      (($# == 1)) || { msg_error "Usage: getsuite self-update"; exit 2; }
      acquire_lock
      self_update
      ;;
    version|--version|-V)
      (($# == 1)) || { msg_error "Usage: getsuite version"; exit 2; }
      show_version
      ;;
    list)
      (($# == 1)) || { msg_error "Usage: getsuite list"; exit 2; }
      show_list
      ;;
    status)
      shift
      show_status "$@"
      ;;
    help|-h|--help)
      (($# == 1)) || { msg_error "Usage: getsuite help"; exit 2; }
      show_help
      ;;
    *)
      msg_error "Unknown command: $1"
      echo >&2
      show_help >&2
      exit 2
      ;;
  esac
}

# The Community Scripts helper installs a global ERR trap. User-facing manager
# failures are handled here, while errexit remains enabled for unexpected
# command failures inside operations.
trap - ERR
main "$@"
EOF_MANAGER

chmod 0755 /usr/local/bin/getsuite
printf '%s\n' "https://github.com/donselkirk/getsuite/releases/latest/download" \
  >/opt/getsuite/update.url
if [[ -n "${GETSUITE_VERSION_URL:-}" ]]; then
  if curl -fsSL "$GETSUITE_VERSION_URL" -o /opt/getsuite/version \
    && grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' /opt/getsuite/version; then
    chmod 0644 /opt/getsuite/version
  else
    rm -f /opt/getsuite/version
  fi
fi
msg_ok "Created GetSuite Manager"

# Establish login access before optional application work. A VPN provider or
# application failure must not leave the new LXC without a usable console.
motd_ssh
customize
configure_getsuite_motd
configure_getsuite_console_autologin

install_gluetun_choice="${GETSUITE_GLUETUN:-}"
if [[ -z "$install_gluetun_choice" ]]; then
  if [[ -r /dev/tty && -w /dev/tty ]] && command -v whiptail >/dev/null 2>&1; then
    if whiptail --title "GetSuite VPN" \
      --yesno "Install and configure Gluetun? Selected download applications will be held until its VPN connection is verified." \
      10 76 </dev/tty >/dev/tty 2>&1; then
      install_gluetun_choice="yes"
    else
      install_gluetun_choice="no"
    fi
  else
    install_gluetun_choice="yes"
  fi
fi

# Remove the completed whiptail dialog before showing Gluetun configuration
# prompts or continuing to application selection.
if [[ -w /dev/tty ]]; then
  printf '\033[2J\033[H' >/dev/tty
fi

case "${install_gluetun_choice,,}" in
  yes|y|1|true|on)
    /usr/local/bin/getsuite vpn install
    export GETSUITE_GLUETUN_ENABLED=1
    ;;
  no|n|0|false|off)
    export GETSUITE_GLUETUN_ENABLED=0
    msg_warn "Gluetun was declined; selected download applications will not use a VPN"
    ;;
  *)
    msg_error "GETSUITE_GLUETUN must be yes or no"
    exit 2
    ;;
esac

if [[ -n "${GETSUITE_APPS:-}" ]]; then
  read -r -a selected_apps <<<"${GETSUITE_APPS//,/ }"
  /usr/local/bin/getsuite add "${selected_apps[@]}"
else
  /usr/local/bin/getsuite add
fi
msg_ok "Installed Selected GetSuite Applications"

# The shared customize() helper creates the standard remote update wrapper.
# Until GetSuite is merged upstream, keep the prototype self-contained and
# make `update` call the local multi-app manager directly.
cat >/usr/bin/update <<'EOF_UPDATE'
#!/usr/bin/env bash
exec /usr/local/bin/getsuite update "$@"
EOF_UPDATE
chmod 0755 /usr/bin/update

cleanup_lxc
