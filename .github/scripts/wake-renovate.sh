#!/usr/bin/env bash
#
# Asks Renovate to run again as soon as a Codex Pooler image newer than the
# chart's appVersion exists, instead of waiting for Renovate's own schedule.
#
# Renovate's hosted scheduler took between one and twenty-three hours to notice a
# new image, while everything after the Renovate pull request (chart-testing,
# the signed chart release, Pages) takes about eight minutes. Ticking the
# "run again" box of the Dependency Dashboard issue is the supported way to
# request an immediate run, and needs no token beyond the workflow's own.
#
# Required environment: GH_TOKEN (issues: write), GITHUB_REPOSITORY.
# FORCE=true skips the version, image and pull-request checks and only requests
# the run; the manual dispatch uses it to prove the request wakes Renovate.
set -euo pipefail

app_repo="${APP_REPOSITORY:-icoretech/codex-pooler}"
image_repo="${IMAGE_REPOSITORY:-icoretech/codex-pooler}"
chart_file="${CHART_FILE:-charts/codex-pooler/Chart.yaml}"
manual_job='<!-- manual job -->'

latest="$(gh api "repos/${app_repo}/releases/latest" --jq .tag_name)"
latest="${latest#codex-pooler-}"
latest="${latest#v}"
current="$(awk -F'"' '/^appVersion:/ {print $2; exit}' "$chart_file")"

if [[ -z "$latest" || -z "$current" ]]; then
  echo "::error::could not read the latest release ('${latest}') or the chart appVersion ('${current}')"
  exit 1
fi

if [[ "${FORCE:-false}" != "true" ]] && { [[ "$latest" == "$current" ]] || [[ "$(printf '%s\n%s\n' "$latest" "$current" | sort -V | tail -1)" == "$current" ]]; }; then
  echo "Chart appVersion ${current} is current for release ${latest}; nothing to do."
  exit 0
fi

# The release is published before the image is: wait until the tag can be pulled.
token="$(curl -fsS "https://ghcr.io/token?scope=repository:${image_repo}:pull" | jq -r .token)"
status="$(curl -sS -o /dev/null -w '%{http_code}' -I \
  -H "Authorization: Bearer ${token}" \
  -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
  "https://ghcr.io/v2/${image_repo}/manifests/${latest}")"
if [[ "${FORCE:-false}" != "true" && "$status" != "200" ]]; then
  echo "Image ${image_repo}:${latest} is not published yet (HTTP ${status}); nothing to do."
  exit 0
fi

# A pull request that already targets this version is Renovate's answer; leave it alone.
if [[ "${FORCE:-false}" != "true" ]] && gh pr list --state open --search 'codex-pooler docker tag in:title' --json title --jq '.[].title' | grep -qF "v${latest}"; then
  echo "A pull request for ${latest} is already open; nothing to do."
  exit 0
fi

dashboard="$(gh issue list --state open --search 'Dependency Dashboard in:title' --json number,title,author \
  --jq '[.[] | select(.title == "Dependency Dashboard" and .author.login == "app/renovate")][0].number // empty')"
if [[ -z "$dashboard" ]]; then
  echo "::error::the Renovate Dependency Dashboard issue was not found"
  exit 1
fi

body="$(gh api "repos/${GITHUB_REPOSITORY}/issues/${dashboard}" --jq .body)"
if grep -qF -- "- [x] ${manual_job}" <<<"$body"; then
  echo "A Renovate run is already requested on issue ${dashboard}."
  exit 0
fi
if ! grep -qF -- "- [ ] ${manual_job}" <<<"$body"; then
  echo "::error::the dashboard has no 'run again' checkbox"
  exit 1
fi

echo "Requesting a Renovate run on issue ${dashboard} for ${image_repo}:${latest} (chart appVersion ${current})."
printf '%s\n' "${body//"- [ ] ${manual_job}"/"- [x] ${manual_job}"}" |
  gh api -X PATCH "repos/${GITHUB_REPOSITORY}/issues/${dashboard}" -F body=@- --silent
