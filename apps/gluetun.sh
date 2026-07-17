#!/usr/bin/env bash

readonly GETSUITE_GLUETUN_DATA_DIR="/opt/gluetun-data"
readonly GETSUITE_GLUETUN_ENV="${GETSUITE_GLUETUN_DATA_DIR}/.env"
readonly GETSUITE_GLUETUN_IP_FILE="${GETSUITE_GLUETUN_DATA_DIR}/ip"

write_gluetun_service() {
  cat > /etc/systemd/system/gluetun.service <<'EOF_SERVICE'
# GETSUITE_TEMPLATE systemd/gluetun.service
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
  write_gluetun_diagnostics
  journalctl -u gluetun -n 40 --no-pager >&2 || true
  msg_error "Diagnostics saved to /opt/getsuite/gluetun-last-error.log"
  return 1
}

write_gluetun_diagnostics() {
  local diagnostic_file=/opt/getsuite/gluetun-last-error.log
  install -d -m 0755 /opt/getsuite
  {
    printf 'GetSuite Gluetun diagnostics\n'
    printf 'Generated: %s\n\n' "$(date --iso-8601=seconds 2>/dev/null || date)"
    printf '%s\n' '--- TUN device ---'
    ls -l /dev/net/tun 2>&1 || true
    printf '\n%s\n' '--- Tunnel interfaces ---'
    ip -details link show type tun 2>&1 || true
    ip -details link show type wireguard 2>&1 || true
    printf '\n%s\n' '--- IPv4 routes ---'
    ip -4 route show table all 2>&1 || true
    printf '\n%s\n' '--- Route test ---'
    ip -4 route get 1.1.1.1 2>&1 || true
    printf '\n%s\n' '--- Gluetun service ---'
    systemctl --no-pager --full status gluetun 2>&1 || true
    printf '\n%s\n' '--- Gluetun journal ---'
    journalctl -u gluetun -n 100 --no-pager 2>&1 || true
  } >"$diagnostic_file"
  chmod 0600 "$diagnostic_file"
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
