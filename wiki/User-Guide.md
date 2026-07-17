# User Guide

The installer first asks whether to install Gluetun. When selected, enter the
provider name used by Gluetun, OpenVPN credentials, an optional preferred
country, and the LAN subnet that should retain local access. GetSuite does not
continue with protected applications unless the VPN connection passes its
health, public-IP, and route checks.

Useful commands:

```bash
getsuite vpn status
getsuite vpn test
getsuite vpn configure
getsuite list
getsuite status qbittorrent
getsuite add qbittorrent
getsuite update
getsuite restart qbittorrent
getsuite remove qbittorrent
getsuite remove qbittorrent --purge
getsuite reset qbittorrent
```

qBittorrent is available at `http://LXC-IP:8090`. When Gluetun is installed,
qBittorrent is bound to `tun0` and systemd stops it with Gluetun. If Gluetun is
declined, the installer warns that qBittorrent is unprotected.

Provider credentials are stored in `/opt/gluetun-data/.env` with mode 0600.
Run `getsuite vpn configure` to replace them; do not edit the generated file
while Gluetun is running.
