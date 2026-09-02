#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKFLOW="${ROOT_DIR}/.github/workflows/cla.yml"
LEDGER="${ROOT_DIR}/signatures/version2/cla.json"
FIXTURE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/fixtures/cla-allowlist-aziz.json"
ACTION_SHA='212a0f2dd659b24b48a30ba35966e06dc41736af'
MUTATION_GROUP="cla-mutation-\${{ github.repository }}-\${{ github.event.pull_request.number || github.event.issue.number }}"

command -v jq >/dev/null
command -v ruby >/dev/null
[[ -f "${WORKFLOW}" && -f "${LEDGER}" && -f "${FIXTURE}" ]]

refs="$(grep -oE "manaflow-ai/cla-github-action@[0-9a-f]{40}" "${WORKFLOW}" | sort -u)"
[[ "${refs}" == "manaflow-ai/cla-github-action@${ACTION_SHA}" ]]
[[ "$(sed -n '1p' "${WORKFLOW}")" == 'name: "CLA Assistant v3"' ]]

# Parse job permissions and mutation lanes as data, so a formatting change
# cannot hide a missing write permission or split the per-PR queue.
ruby - "${WORKFLOW}" "${MUTATION_GROUP}" <<'RUBY'
require "yaml"

workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
expected_group = ARGV.fetch(1)
jobs = workflow.fetch("jobs")

writer = jobs.fetch("CLALedgerWriter")
rerun = jobs.fetch("RerunFailedCLA")
lock = jobs.fetch("LockMergedPullRequest")
groups = [writer, rerun, lock].map { |job| job.fetch("concurrency").fetch("group") }
abort "mutation jobs do not share one per-PR concurrency group" unless groups.all? { |group| group == expected_group }
abort "mutation group contains a run-specific key" if groups.any? { |group| group.include?("run_id") || group.include?("run_attempt") }

writer_permissions = writer.fetch("permissions")
abort "writer permissions are too broad or incomplete" unless writer_permissions == {
  "contents" => "write", "issues" => "write", "pull-requests" => "write"
}
lock_permissions = lock.fetch("permissions")
abort "lock permissions are too broad or incomplete" unless lock_permissions == {
  "contents" => "read", "issues" => "write", "pull-requests" => "write"
}
rerun_permissions = rerun.fetch("permissions")
abort "rerun permissions are too broad or incomplete" unless rerun_permissions == {
  "actions" => "write", "checks" => "read", "contents" => "read",
  "issues" => "read", "pull-requests" => "read"
}
RUBY

jq -e '
  type == "object" and
  (.signedContributors | type == "array") and
  all(.signedContributors[]?;
    (.name | type == "string" and length > 0) and
    (.id | type == "number" and floor == . and . > 0)
  )
' "${LEDGER}" >/dev/null

# The canary models the maintained action's opener-only numeric allowlist.
# It proves Aziz's authenticated opener ID is accepted while an unknown ID is
# rejected; it never signs a CLA or writes repository state.
allowlist="$(grep -m1 -E 'allowlist-ids:' "${WORKFLOW}" | grep -oE '[0-9]{1,20}(,[0-9]{1,20})+')"
[[ "${allowlist}" == '38676809,67667005' ]]
is_allowlisted_opener() {
  case ",${allowlist}," in
    *,"$1",*) return 0 ;;
    *) return 1 ;;
  esac
}
aziz_id="$(jq -er '.pull_request.user.id' "${FIXTURE}")"
untrusted_id="$(jq -er '.untrusted_opener.id' "${FIXTURE}")"
is_allowlisted_opener "${aziz_id}"
if is_allowlisted_opener "${untrusted_id}"; then
  echo "untrusted opener was incorrectly allowlisted" >&2
  exit 1
fi

echo "CLA v3 policy contract and Aziz opener canary passed"
