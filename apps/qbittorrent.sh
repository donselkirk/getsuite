write_qbittorrent_service() {
  cat > /etc/systemd/system/qbittorrent-nox.service <<'EOF_SERVICE'
# GETSUITE_TEMPLATE systemd/qbittorrent.service
EOF_SERVICE
}

write_qbittorrent_vpn_readiness_helper() {
  cat > /usr/local/libexec/getsuite-qbittorrent-vpn-ready <<'EOF_HELPER'
# GETSUITE_TEMPLATE systemd/qbittorrent-vpn-ready.sh
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
