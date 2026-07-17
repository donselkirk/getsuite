#!/usr/bin/env bash
set -Eeuo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
builder="${project_root}/tools/build-artifacts.sh"
manager="${project_root}/tools/getsuite-manager"
installer="${project_root}/install/getsuite-install.sh"
motd="${project_root}/tools/getsuite-motd.sh"
tmp_manager="$(mktemp)"
tmp_motd="$(mktemp)"
trap 'rm -f "$tmp_manager" "$tmp_motd"' EXIT

"$builder" --check

for script in \
  "${project_root}/getsuite.sh" \
  "${project_root}/ct/getsuite.sh" \
  "$installer" \
  "${project_root}/src/getsuite-install.sh.in" \
  "${project_root}/src/getsuite-manager.sh.in" \
  "$manager" \
  "$motd" \
  "$builder" \
  "${project_root}/tools/check-upstream.sh" \
  "${project_root}/tools/fix-console-autologin.sh" \
  "${project_root}/templates/update.sh"; do
  bash -n "$script"
done
bash -n "${project_root}/tests/manager-behavior.sh"

for module in "${project_root}"/apps/*.sh; do
  bash -n "$module"
  app="$(basename "$module" .sh)"
  grep -q "write_${app}_service()" "$module"
  grep -q "install_${app}()" "$module"
  grep -q "update_${app}()" "$module"
done

awk '
  /^cat > \/usr\/local\/bin\/getsuite <<'"'"'EOF_MANAGER'"'"'$/ { capture=1; next }
  /^EOF_MANAGER$/ { capture=0 }
  capture
' "$installer" >"$tmp_manager"
cmp -s "$tmp_manager" "$manager"

awk '
  /^  cat >\/etc\/profile\.d\/00_lxc-details\.sh <<'"'"'EOF_MOTD'"'"'$/ { capture=1; next }
  /^EOF_MOTD$/ { capture=0 }
  capture
' "$installer" >"$tmp_motd"
cmp -s "$tmp_motd" "$motd"

python3 -m json.tool "${project_root}/json/getsuite.json" >/dev/null
python3 -m json.tool "${project_root}/tools/upstream-lock.json" >/dev/null

grep -q 'SUPPORTED_APPS=(qbittorrent)' "$manager"
grep -q 'install_gluetun()' "$manager"
grep -q 'install_qbittorrent()' "$manager"
grep -q 'var_tun="${var_tun:-yes}"' "${project_root}/ct/getsuite.sh"
grep -q 'GETSUITE_INSTALL_URL' "${project_root}/getsuite.sh"
grep -q 'releases/latest/download' "${project_root}/getsuite.sh"
grep -q '^set +u$' "${project_root}/getsuite.sh"
grep -q 'SHA256SUMS' "$manager"
grep -q '^trap - ERR$' "$manager"
grep -q '^main "$@"$' "$manager"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -e SC1090,SC1091 \
    "${project_root}/getsuite.sh" \
    "${project_root}/ct/getsuite.sh" \
    "${project_root}/src/getsuite-install.sh.in" \
    "${project_root}/src/getsuite-manager.sh.in" \
    "$manager" "$motd" "$builder" \
    "${project_root}/tools/check-upstream.sh" \
    "${project_root}/tools/fix-console-autologin.sh" \
    "${project_root}/templates/update.sh" \
    "${project_root}/tests/manager-behavior.sh" \
    "${project_root}"/apps/*.sh
fi

printf 'GetSuite static checks passed.\n'
