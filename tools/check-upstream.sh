#!/usr/bin/env bash
set -Eeuo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lock_file="${project_root}/tools/upstream-lock.json"
report_dir="${UPSTREAM_REPORT_DIR:-${project_root}/upstream-report}"
api_base="${GITHUB_API_URL:-https://api.github.com}"
changed=0
curl_args=(-fsSL)
[[ -z "${GITHUB_TOKEN:-}" ]] || curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")

command -v jq >/dev/null || { echo "jq is required." >&2; exit 2; }
command -v curl >/dev/null || { echo "curl is required." >&2; exit 2; }
mkdir -p "$report_dir"
rm -f "${report_dir}"/*.diff "${report_dir}/summary.md"

printf '# GetSuite upstream check\n\n' >"${report_dir}/summary.md"
while IFS=$'\t' read -r app kind repository path locked_blob; do
  if [[ "$repository" == "community-scripts/ProxmoxVE" ]]; then
    development_url="${api_base}/repos/community-scripts/ProxmoxVED/contents/${path}?ref=main"
    if development_metadata="$(curl "${curl_args[@]}" "$development_url" 2>/dev/null)"; then
      development_blob="$(jq -r '.sha' <<<"$development_metadata")"
      printf -- '%s\n' "- **${app} ${kind}:** now exists in \`community-scripts/ProxmoxVED\` (\`${development_blob}\`); review migration from the production fallback" \
        | tee -a "${report_dir}/summary.md"
      changed=1
    fi
  fi
  ref_url="${api_base}/repos/${repository}/contents/${path}?ref=main"
  metadata="$(curl "${curl_args[@]}" "$ref_url")" || {
    printf -- '%s\n' "- **${app} ${kind}:** unable to query \`${repository}/${path}\`" | tee -a "${report_dir}/summary.md"
    changed=1
    continue
  }
  current_blob="$(jq -r '.sha' <<<"$metadata")"
  if [[ "$current_blob" == "$locked_blob" ]]; then
    printf -- '%s\n' "- ${app} ${kind}: unchanged (\`${current_blob}\`)" >>"${report_dir}/summary.md"
    continue
  fi

  changed=1
  printf -- '%s\n' \
    "- **${app} ${kind} changed:** \`${locked_blob}\` → \`${current_blob}\` (\`${repository}/${path}\`)" \
    | tee -a "${report_dir}/summary.md"
  old_url="${api_base}/repos/${repository}/git/blobs/${locked_blob}"
  old_file="$(mktemp)"
  new_file="$(mktemp)"
  curl "${curl_args[@]}" "$old_url" | jq -r '.content' | base64 -d >"$old_file"
  jq -r '.content' <<<"$metadata" | base64 -d >"$new_file"
  diff -u --label "locked/${path}" --label "upstream/${path}" "$old_file" "$new_file" \
    >"${report_dir}/${app}-${kind}.diff" || true
  rm -f "$old_file" "$new_file"
done < <(jq -r '.applications | to_entries[] as $app | $app.value | to_entries[] | [$app.key, .key, .value.repository, .value.path, .value.blob] | @tsv' "$lock_file")

cat "${report_dir}/summary.md"
if ((changed)); then
  echo "Upstream changes require review; see ${report_dir}." >&2
  exit 1
fi
echo "All tracked Community Scripts sources are unchanged."
