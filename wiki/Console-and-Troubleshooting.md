# Console and Troubleshooting

When the LXC root password is blank, GetSuite configures automatic root login
for:

| Service | Console |
|---|---|
| `container-getty@1.service` | Proxmox web UI on `/dev/tty1` |
| `console-getty.service` | `pct console` on `/dev/console` |

The Debian 13 overrides clear inherited credential imports using an empty
`ImportCredential=` directive. Removing it can cause `243/CREDENTIALS` in an
unprivileged LXC.

## Repair a blank console

Enter the container from the Proxmox host:

```bash
pct enter <CTID>
```

Then run:

```bash
curl -fsSL https://github.com/donselkirk/getsuite/releases/latest/download/fix-console-autologin.sh | bash
```

## Useful diagnostics

```bash
getsuite list
getsuite status
systemctl status container-getty@1.service
systemctl status console-getty.service
journalctl -u <app>.service --no-pager
df -h
```

Application-targeted commands fail cleanly when the requested application is
not installed and show the corresponding `getsuite add <app>` command.
