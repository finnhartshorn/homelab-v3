#!/usr/bin/env bash
# Fail if a Servarr HelmRelease pins an image tag that isn't on ghcr.io.
# Renovate tracks these apps through GitHub releases, which can run ahead of
# (or never reach) the home-operations images.
set -euo pipefail

accept='application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json'
failed=0

for app in sonarr radarr prowlarr; do
  file="kubernetes/apps/arr/${app}/app/helmrelease.yaml"
  repo="home-operations/${app}"
  tag=$(awk -v repo="ghcr.io/${repo}" '
    found && $1 == "tag:" { print $2; exit }
    { found = ($1 == "repository:" && $2 == repo) }
  ' "$file")

  if [[ -z "$tag" ]]; then
    echo "::error file=${file}::no tag found for ghcr.io/${repo}"
    failed=1
    continue
  fi

  token=$(curl -fsS --retry 3 "https://ghcr.io/token?scope=repository:${repo}:pull" | jq -r .token)
  status=$(curl -sS --retry 3 -o /dev/null -w '%{http_code}' --head \
    -H "Authorization: Bearer ${token}" -H "Accept: ${accept}" \
    "https://ghcr.io/v2/${repo}/manifests/${tag}")

  if [[ "$status" == "200" ]]; then
    echo "ok: ghcr.io/${repo}:${tag}"
  else
    echo "::error file=${file}::ghcr.io/${repo}:${tag} is not available (HTTP ${status})"
    failed=1
  fi
done

exit "$failed"
