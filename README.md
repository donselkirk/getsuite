# GetSuite Community Script

GetSuite creates one unprivileged Debian 13 Proxmox LXC for native downloading
applications, without Docker. Its layout and install flow are based on the
[Proxmox VE Community Scripts](https://community-scripts.org/).

The initial release supports native Gluetun and qBittorrent:

| Component | Port | Install flow |
|---|---:|---|
| Gluetun | loopback control only | Separate VPN prompt, selected by default |
| qBittorrent | 8090 | Application checklist, selected by default |

When Gluetun is selected, GetSuite configures a named OpenVPN provider, enables
the VPN firewall, preserves access from the chosen LAN subnet, and starts
qBittorrent only after the VPN health, public IP, and default route pass checks.
qBittorrent is also bound to `tun0` and stops with Gluetun. `/dev/net/tun` is
enabled by the LXC bootstrap; Docker and LXC nesting are not required.

## Install

Run as `root` in the Proxmox VE host shell:

```bash
bash -c "$(curl -fsSL https://github.com/donselkirk/getsuite/releases/latest/download/getsuite.sh)"
```

The installer asks whether to include Gluetun, then requests its provider,
OpenVPN username/password, optional country, and the LAN subnet allowed outside
the tunnel. It confirms the VPN connection before installing protected apps.

## Commands

```bash
getsuite vpn status
getsuite vpn test
getsuite vpn configure
getsuite list
getsuite status [app ...]
getsuite add [app ...]
getsuite update [app ...]
getsuite restart [app ...]
getsuite remove app [--purge]
getsuite reset app
getsuite self-update
```

Installed applications are tracked in `/opt/getsuite/installed.apps`.
Gluetun’s separate state is tracked by `/opt/getsuite/gluetun.enabled`, while
its restricted provider configuration is stored at `/opt/gluetun-data/.env`.
The login banner dynamically reports VPN connection state, provider, interface,
public IP, and application URLs.

Local static checks do not replace a full install and leak test on a disposable
Proxmox node.
