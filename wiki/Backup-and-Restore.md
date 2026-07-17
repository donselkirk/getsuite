# Backup and Restore

GetSuite does not yet provide application-level backup or restore commands.
Back up the LXC with Proxmox. The configuration paths that require protection
are `/opt/gluetun-data`, `/opt/getsuite`, and `/root/.config/qBittorrent`.

VPN credentials are present in the LXC backup. Protect backup storage and its
encryption keys accordingly.
