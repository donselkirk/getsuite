#!/usr/bin/env bash
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || {
  echo "Run this script as root inside the LXC." >&2
  exit 1
}

passwd -d root >/dev/null 2>&1 || true

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
  systemctl enable console-getty.service >/dev/null 2>&1 || true
fi

systemctl daemon-reload
systemctl unmask container-getty@1.service console-getty.service >/dev/null 2>&1 || true
systemctl enable container-getty@1.service console-getty.service >/dev/null 2>&1 || true
systemctl reset-failed container-getty@1.service console-getty.service >/dev/null 2>&1 || true
systemctl restart container-getty@1.service >/dev/null 2>&1 || true
systemctl restart console-getty.service >/dev/null 2>&1 || true

echo "Console auto-login has been configured for root."
