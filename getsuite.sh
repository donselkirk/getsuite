#!/usr/bin/env bash
# Community Scripts helpers reference several optional environment variables
# directly. Explicitly disable inherited nounset before loading any helpers.
set +u
set -Eeo pipefail

readonly COMMUNITY_RAW_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}"
readonly DEFAULT_RELEASE_BASE_URL="https://github.com/donselkirk/getsuite/releases/latest/download"

if [[ -n "${GETSUITE_REPOSITORY_RAW_URL:-}" ]]; then
  source_base_url="${GETSUITE_REPOSITORY_RAW_URL%/}"
  ct_url="${source_base_url}/ct/getsuite.sh"
  install_url="${source_base_url}/install/getsuite-install.sh"
  version_url=""
else
  release_base_url="${GETSUITE_RELEASE_BASE_URL:-$DEFAULT_RELEASE_BASE_URL}"
  release_base_url="${release_base_url%/}"
  ct_url="${release_base_url}/getsuite-ct.sh"
  install_url="${release_base_url}/getsuite-install.sh"
  version_url="${release_base_url}/VERSION"
fi

bootstrap_dir="$(mktemp -d)"
trap 'rm -rf "$bootstrap_dir"' EXIT

build_func="${bootstrap_dir}/build.func"
curl -fsSL "${COMMUNITY_RAW_URL}/misc/build.func" -o "$build_func"

# Keep the live Community Scripts framework and its helper URLs intact. Only
# redirect the two locations that fetch the application-specific installer
# (the normal path and the APT-recovery retry path).
# shellcheck disable=SC2016 # Match literal variable references in build.func.
sed -i \
  -e 's|"$COMMUNITY_SCRIPTS_URL/install/${var_install}.sh"|"$GETSUITE_INSTALL_URL"|g' \
  -e 's|"https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/install/${var_install}.sh"|"$GETSUITE_INSTALL_URL"|g' \
  "$build_func"

# shellcheck disable=SC2016 # Verify the literal reference inserted above.
redirect_count="$(grep -c 'curl -fsSL "$GETSUITE_INSTALL_URL"' "$build_func" || true)"
if [[ "$redirect_count" -lt 2 ]]; then
  echo "Unable to redirect the Community Scripts installer URLs; upstream build.func may have changed." >&2
  exit 1
fi

export GETSUITE_BUILD_FUNC_PATH="$build_func"
export GETSUITE_INSTALL_URL="$install_url"
export GETSUITE_VERSION_URL="$version_url"

source <(curl -fsSL "$ct_url")
