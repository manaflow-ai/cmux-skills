#!/usr/bin/env bash
set -euo pipefail

# Behavior tests for refresh-cla-check.sh. The production worker is copied to
# the other approved consumer repositories. This test uses an exported fake
# gh function so it never calls GitHub or writes a real check run.

WORKER="${WORKER_OVERRIDE:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/refresh-cla-check.sh}"
readonly WORKER
TEST_REPO="${TEST_REPO:-manaflow-ai/cmux-skills}"
readonly TEST_REPO
readonly HEAD_SHA='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
readonly BASE_SHA='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
readonly EXTERNAL_ID="cla-refresh:test-generation:42:${HEAD_SHA}"
TMP_DIR="$(mktemp -d)"
readonly TMP_DIR
trap 'rm -rf -- "${TMP_DIR}"' EXIT
export HEAD_SHA BASE_SHA EXTERNAL_ID TEST_REPO

export GH_TOKEN=test-token
export GH_REPO="${TEST_REPO}"
export EXPECTED_REPO="${TEST_REPO}"
export CLA_GENERATION=test-generation
export EXPECTED_GENERATION=test-generation
export WORKFLOW_SHA="${HEAD_SHA}"
export REPOSITORY_ID=123
export PR_NUMBER=42
export EVENT_PR_NUMBER=42
export EVENT_NAME=pull_request_target
export EVENT_ACTION=synchronize
export EVENT_BASE_REF=main
export EVENT_BASE_SHA="${BASE_SHA}"
export EVENT_BASE_REPOSITORY="${TEST_REPO}"
export EVENT_BASE_REPOSITORY_ID=123
export EVENT_HEAD_REPOSITORY="${TEST_REPO}"
export EVENT_HEAD_REPOSITORY_ID=123
export EVENT_HEAD_SHA="${HEAD_SHA}"
export EVENT_ISSUE_STATE=
export EVENT_ISSUE_IS_PR=
export EVENT_OPENER_ID=7
export COMMENT_ID=
export COMMENT_BODY=
export COMMENT_USER_ID=
export COMMENT_USER_TYPE=
export COMMENT_ASSOCIATION=
export GATE_RESULT=success
export GATE_ADMITTED=true
export PREFLIGHT_RESULT=
export SIGNER_AUTHORIZED=
export SIGNER_HEAD_SHA=
export SIGNER_BASE_SHA=
export WRITER_HEAD_SHA="${HEAD_SHA}"
export GITHUB_SERVER_URL=https://github.com
export GITHUB_RUN_ID=1234

gh() {
  local args="$*" body check_id
  printf 'REQUEST %s\n' "${args}" >>"${FAKE_GH_LOG:-/tmp/cla-test-requests}"
  if [[ "${args}" == *"pulls/42"* ]]; then
    jq -cn --arg head "${HEAD_SHA}" --arg base "${BASE_SHA}" --arg repo "${TEST_REPO}" \
      '{number:42,state:"open",merged_at:null,
        base:{ref:"main",sha:$base,repo:{full_name:$repo,id:123}},
        head:{sha:$head,ref:"test-branch",repo:{full_name:$repo,id:123}},
        user:{id:7}}'
    return
  fi
  if [[ "${args}" == *"commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/check-runs"* ]]; then
    if [[ "${args}" == *"check_name="* ]]; then
      printf '%s\n' "${FAKE_FILTERED_CHECK_RUNS}"
    else
      printf '%s\n' '{"total_count":0,"check_runs":[]}'
    fi
    return
  fi
  if [[ "${args}" == *"--method POST"* ]]; then
    body="$(cat)"
    printf 'POST %s\n' "${body}" >>"${FAKE_GH_LOG}"
    jq --arg head "${HEAD_SHA}" '. + {id:9001,head_sha:$head,app:{id:15368}}' <<<"${body}"
    return
  fi
  if [[ "${args}" == *"--method PATCH"* ]]; then
    body="$(cat)"
    check_id="${args#*check-runs/}"
    check_id="${check_id%% *}"
    printf 'PATCH %s %s\n' "${check_id}" "${body}" >>"${FAKE_GH_LOG}"
    jq --arg id "${check_id}" --arg head "${HEAD_SHA}" \
      '. + {id:($id|tonumber),head_sha:$head,app:{id:15368}}' <<<"${body}"
    return
  fi
  printf 'unexpected fake gh request: %s\n' "${args}" >&2
  return 1
}
export -f gh
if [[ "$(bash -c 'type -t gh')" != function ]]; then
  echo 'test harness could not export its fake gh function' >&2
  exit 1
fi

run_case() {
  local name="$1" filtered="$2" expected_conclusion="$3"
  local output="${TMP_DIR}/${name}.out"
  export FAKE_FILTERED_CHECK_RUNS="${filtered}"
  export FAKE_GH_LOG="${TMP_DIR}/${name}.gh"
  : >"${FAKE_GH_LOG}"
  export GITHUB_OUTPUT="${output}"
  bash "${WORKER}"
  grep -Fx "conclusion=${expected_conclusion}" "${output}" >/dev/null
}

# A stale writer failure must preserve a prior successful exact-head result.
success_run="$(jq -cn --arg head "${HEAD_SHA}" --arg external "${EXTERNAL_ID}" \
  '{total_count:1,check_runs:[{id:7001,name:"CLA Assistant v3",head_sha:$head,
    status:"completed",conclusion:"success",external_id:$external,app:{id:15368}}]}')"
export WRITER_RESULT=failure
export WRITER_POLICY_RESULT=failure
run_case stale_failure_preserves_success "${success_run}" success
grep -F 'PATCH 7001' "${FAKE_GH_LOG}" >/dev/null
grep -F '"conclusion": "success"' "${FAKE_GH_LOG}" >/dev/null

# Duplicate exact-head runs must all converge to the monotonic successful
# result, including a concurrent failure run found during reconciliation.
duplicate_runs="$(jq -cn --arg head "${HEAD_SHA}" --arg external "${EXTERNAL_ID}" \
  '{total_count:2,check_runs:[
    {id:7001,name:"CLA Assistant v3",head_sha:$head,status:"completed",conclusion:"success",external_id:$external,app:{id:15368}},
    {id:7002,name:"cla assistant v3",head_sha:$head,status:"completed",conclusion:"failure",external_id:$external,app:{id:15368}}
  ]}')"
export WRITER_RESULT=success
export WRITER_POLICY_RESULT=true
run_case duplicate_runs_converge "${duplicate_runs}" success
[[ "$(grep -c '^PATCH ' "${FAKE_GH_LOG}")" -ge 2 ]]
if grep -F '"conclusion": "failure"' "${FAKE_GH_LOG}" >/dev/null; then
  echo 'duplicate reconciliation attempted to publish a failure' >&2
  exit 1
fi

echo 'refresh-cla-check behavior tests passed'
