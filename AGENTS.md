# GetSuite Development Instructions

## Purpose and architecture

GetSuite creates one unprivileged Debian 13 Proxmox LXC for multiple native
downloading applications without Docker. Preserve Proxmox Community Scripts
workflow and conventions wherever practical.

Initial components:

- Gluetun: optional primary VPN component, configured separately from apps.
- qBittorrent: selectable native application, Web UI port 8090.

The CT must set `var_tun=yes`; Docker nesting is not required. Gluetun is not a
normal application and must not be stored in `installed.apps`. Its marker is
`/opt/getsuite/gluetun.enabled`; apps are tracked in
`/opt/getsuite/installed.apps`.

## Required VPN behavior

- Prompt for Gluetun before the application checklist and default to yes.
- Support named providers with OpenVPN initially. Prompt separately for the
  provider, credentials, optional location, and detected/editable LAN CIDR.
- Store credentials only in `/opt/gluetun-data/.env` with mode 0600. Never show
  credentials in status, logs, or the login banner.
- Require `/dev/net/tun` before installing Gluetun.
- Keep Gluetun's firewall enabled. Preserve SSH, selected app ports, and LAN
  return traffic; bind its control and health listeners to loopback.
- Verify the Gluetun service, health endpoint, tunnel interface/default route,
  and VPN public-IP file. Failed verification must stop Gluetun and must not
  allow a protected app to start.
- Protected qBittorrent must bind to `tun0`, depend on and stop with Gluetun,
  and use a readiness gate. It may run without Gluetun only when the user
  explicitly declines Gluetun.
- The dynamic login banner must report provider, connection state, tunnel
  interface, VPN public IP, and installed app URLs without delaying login on
  network calls.
- Support `getsuite vpn install|configure|status|test`.

## Manager and update behavior

Support `getsuite add`, `list`, `status`, `update`, `restart`, `remove`, `reset`,
`self-update`, and `version`. Validate supported/installed targets cleanly.
Failed installs must not enter the registry. Updates must stage replacements,
retain the old binary until successful startup, and roll back on failure.
Self-update must validate release `SHA256SUMS`.

Application behavior belongs in `apps/*.sh`; payloads belong under
`templates/`. `src/getsuite-manager.sh.in` and
`src/getsuite-install.sh.in` are editable sources. Never directly edit the
generated `tools/getsuite-manager` or `install/getsuite-install.sh`.

`tools/build-artifacts.sh` must regenerate both artifacts after source, module,
or template changes. Keep the bootstrap, CT completion text, JSON metadata,
README, Wiki, MOTD, workflows, lock file, and tests synchronized when adding an
application.

Base modules on the current Community Scripts implementation. When a script is
not available in `community-scripts/ProxmoxVED`, use the reviewed version from
`community-scripts/ProxmoxVE` and record exact blobs in
`tools/upstream-lock.json`; never execute newly changed upstream content
automatically.

## Verification

Run after every change:

```bash
bash tools/build-artifacts.sh
bash tests/static-checks.sh
bash tests/manager-behavior.sh
git diff --check
```

Static tests cannot prove TUN passthrough, systemd startup, VPN leak prevention,
provider authentication, release downloads, or LAN Web UI access. Test releases
on a disposable Proxmox node, including stopping Gluetun while qBittorrent is
active and rebooting the LXC.

## Release workflow

Commit completed changes to `main` and push when requested. Each push runs the
release workflow. After publishing, verify Actions and the release assets, then
provide a version-pinned install command using `GETSUITE_RELEASE_BASE_URL`.
