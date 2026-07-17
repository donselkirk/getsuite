# Upstream Integration

GetSuite tracks reviewed Community Scripts sources in
`tools/upstream-lock.json`.

## Check for changes

```bash
bash tools/check-upstream.sh
```

The checker compares locked references against the current
`community-scripts/ProxmoxVED` repository and falls back to
`community-scripts/ProxmoxVE` only when a script is no longer in development.
Focused reports are written under `upstream-report/`.

An upstream difference is a review prompt, not an automatic update. Never
execute newly discovered upstream content automatically.

## Import reviewed behavior

1. Review the focused upstream diff.
2. Update the relevant `apps/<app>.sh` or template.
3. Update the locked source references.
4. Regenerate and validate:

```bash
bash tools/build-artifacts.sh
bash tests/static-checks.sh
git diff --check
```

This keeps GetSuite releases reproducible while making upstream changes easier
to identify and integrate.
