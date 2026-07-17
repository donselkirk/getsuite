# Building and Development

Follow the repository's `AGENTS.md` instructions for all changes.

## Generate artifacts

Editable sources are assembled into the standalone manager and self-contained
installer:

```bash
bash tools/build-artifacts.sh
```

Do not edit `tools/getsuite-manager` or `install/getsuite-install.sh` directly.

## Validate

```bash
bash tests/static-checks.sh
git diff --check
```

The suite covers:

- Bash syntax;
- JSON parsing;
- generated artifact synchronization;
- byte-for-byte embedded template checks;
- manager behavior;
- ShellCheck when installed.

Local checks do not prove LXC creation, systemd startup, release downloads, or
web interface availability. Test release-affecting changes on a disposable
Proxmox node.

## Releases

Every push to `main` runs GitHub Actions validation. A successful run creates
the next patch release with generated notes, `SHA256SUMS`, and stable runtime
assets.

The Markdown files under `wiki/` are the canonical Wiki sources. Changes to
them on `main` are published automatically by `.github/workflows/wiki.yml`;
avoid editing the published GitHub Wiki separately.

## Install a specific release

Version-pinned installation is intended for development and regression
testing. Use the same release base URL for the bootstrap and all assets:

```bash
export GETSUITE_RELEASE_BASE_URL="https://github.com/donselkirk/getsuite/releases/download/<version>"
bash -c "$(curl -fsSL "${GETSUITE_RELEASE_BASE_URL}/getsuite.sh")"
```

## Adding an application

Create `apps/<app>.sh` and its systemd template, then update:

- supported application arrays and maps;
- labels, description, port, and architecture behavior;
- install, update, and dispatch cases;
- initial checklist and help output;
- login banner and CT completion output;
- JSON metadata, documentation, and tests.

Base behavior on the current individual Community Scripts implementation.
