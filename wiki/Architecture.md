# Architecture

GetSuite uses the current Proxmox Community Scripts bootstrap to create an
unprivileged Debian 13 LXC. `var_tun=yes` adds `/dev/net/tun` passthrough on the
Proxmox host. Gluetun and qBittorrent run as native systemd services in the
same network namespace; Docker and nesting are not required.

Gluetun owns the VPN route and firewall. LAN destinations are explicitly routed
outside the tunnel using `FIREWALL_OUTBOUND_SUBNETS`, while SSH and qBittorrent's
Web UI are permitted input ports. Control and health endpoints listen only on
loopback.

Protected qBittorrent has a systemd drop-in with `Requires`, `BindsTo`, and
`PartOf` relationships to Gluetun. Its readiness helper checks TUN, `tun0`, the
default route, Gluetun health, and its public-IP file. qBittorrent also binds its
own network interface to `tun0` as a second kill switch.

| Component | Program/data | Unit |
|---|---|---|
| Gluetun | `/usr/local/bin/gluetun`, `/opt/gluetun-data` | `gluetun.service` |
| qBittorrent | `/opt/qbittorrent`, `/root/.config/qBittorrent` | `qbittorrent-nox.service` |

Editable sources live under `src/`, `apps/`, and `templates/`. The artifact
builder produces the standalone manager and embedded installer.
