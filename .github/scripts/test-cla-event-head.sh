#!/usr/bin/env bash
set -euo pipefail

# Regression fixture for pull_request_target. GitHub sets github.sha to the
# base revision for this event; CLA policy must use the source head in the
# event payload when binding a lifecycle write.
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="${ROOT_DIR}/fixtures/pull-request-target-head.json"
WORKFLOW="${ROOT_DIR}/../workflows/cla.yml"

command -v jq >/dev/null
[[ -f "${FIXTURE}" && -f "${WORKFLOW}" ]]

event_name="$(jq -er '.event_name' "${FIXTURE}")"
event_head="$(jq -er '.pull_request.head.sha' "${FIXTURE}")"
event_base="$(jq -er '.pull_request.base.sha' "${FIXTURE}")"
github_sha="$(jq -er '.github_sha' "${FIXTURE}")"

[[ "${event_name}" == pull_request_target ]]
[[ "${event_head}" =~ ^[0-9a-f]{40}$ ]]
[[ "${event_base}" =~ ^[0-9a-f]{40}$ ]]
[[ "${github_sha}" =~ ^[0-9a-f]{40}$ ]]
[[ "${event_head}" != "${event_base}" ]]
[[ "${event_head}" != "${github_sha}" ]]

# Keep the workflow's binding expression explicit. A future edit must not
# silently substitute github.sha, which would bind a fork PR to the base.
grep -Fq "EVENT_HEAD_SHA: \${{ github.event.pull_request.head.sha || '' }}" "${WORKFLOW}" || {
  echo "CLA lifecycle result must read pull_request.head.sha" >&2
  exit 1
}
if grep -Fq "RUN_HEAD_SHA: \${{ github.sha" "${WORKFLOW}"; then
  echo "CLA workflow must not bind a lifecycle run to github.sha" >&2
  exit 1
fi
if grep -Fq "expected-head-sha: \"\${{ github.sha" "${WORKFLOW}"; then
  echo "CLA writer must not use github.sha as the expected PR head" >&2
  exit 1
fi

echo "CLA pull_request_target head binding fixture passed"
