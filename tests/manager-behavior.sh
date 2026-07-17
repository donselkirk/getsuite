#!/usr/bin/env bash
set -Eeuo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manager="${project_root}/tools/getsuite-manager"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/bin" "$test_root/lib" "$test_root/run" \
  "$test_root/runtime" "$test_root/opt" "$test_root/systemd" \
  "$test_root/app-data"
: >"$test_root/installed.apps"

cat >"$test_root/lib/community-functions.sh" <<'EOF_FUNCTIONS'
color() { :; }
msg_info() { :; }
msg_ok() { printf '%s\n' "$*"; }
msg_warn() { printf 'WARN: %s\n' "$*" >&2; }
msg_error() { printf 'ERROR: %s\n' "$*" >&2; }
arch_resolve() { printf '%s' "$1"; }
EOF_FUNCTIONS

cat >"$test_root/lib/community-tools.sh" <<'EOF_TOOLS'
fetch_and_deploy_gh_release() { return 1; }
check_for_gh_release() { return 1; }
setup_go() { return 1; }
EOF_TOOLS

cat >"$test_root/bin/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
if [[ "${1:-}" == "is-active" ]]; then
  printf 'inactive\n'
  exit 3
fi
exit 0
EOF_SYSTEMCTL
chmod 0755 "$test_root/bin/systemctl"

run_manager() {
  GETSUITE_BASE_DIR="$test_root" \
    GETSUITE_REGISTRY="$test_root/installed.apps" \
    GETSUITE_ALLOW_NON_ROOT=1 \
    GETSUITE_SKIP_SELF_UPDATE=1 \
    GETSUITE_FUNCTIONS_LIBRARY="$test_root/lib/community-functions.sh" \
    GETSUITE_TOOLS_LIBRARY="$test_root/lib/community-tools.sh" \
    GETSUITE_LOCK_FILE="$test_root/run/getsuite.lock" \
    GETSUITE_MANAGER_PATH="$test_root/runtime/getsuite" \
    GETSUITE_MOTD_PATH="$test_root/runtime/getsuite-motd.sh" \
    GETSUITE_REPAIR_PATH="$test_root/runtime/fix-console-autologin" \
    GETSUITE_APP_DATA_ROOT="$test_root/app-data" \
    GETSUITE_APP_INSTALL_ROOT="$test_root/opt" \
    GETSUITE_SYSTEMD_UNIT_DIR="$test_root/systemd" \
    GETSUITE_RELEASE_MARKER_ROOT="$test_root/runtime" \
    PATH="$test_root/bin:$PATH" \
    "$manager" "$@"
}

list_output="$(run_manager list)"
grep -q '^qBittorrent[[:space:]]\+no[[:space:]]\+8090' <<<"$list_output"

vpn_output="$(run_manager vpn status)"
grep -q '^Gluetun: not installed$' <<<"$vpn_output"

if unknown_output="$(run_manager does-not-exist 2>&1)"; then
  echo "Unknown command unexpectedly succeeded" >&2
  exit 1
fi
grep -q 'ERROR: Unknown command: does-not-exist' <<<"$unknown_output"
grep -q 'Usage:' <<<"$unknown_output"
! grep -q 'in line' <<<"$unknown_output"

if run_manager add qbittorrent; then
  echo "Failed install unexpectedly succeeded" >&2
  exit 1
fi
[[ ! -s "$test_root/installed.apps" ]]

if uninstalled_output="$(run_manager status qbittorrent 2>&1)"; then
  echo "Status of an uninstalled app unexpectedly succeeded" >&2
  exit 1
fi
grep -q 'qBittorrent is not installed. Run: getsuite add qbittorrent' <<<"$uninstalled_output"

help_output="$(run_manager help)"
grep -q 'getsuite vpn configure' <<<"$help_output"
grep -q 'getsuite update \[app ...\]' <<<"$help_output"

printf 'GetSuite manager behavior checks passed.\n'
