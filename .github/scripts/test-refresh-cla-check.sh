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
readonly WORKFLOW_SHA='cccccccccccccccccccccccccccccccccccccccc'
readonly RUN_HEAD_SHA='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
readonly EXTERNAL_ID="cla-v3:manaflow-ai/cmux-skills:test-generation:${WORKFLOW_SHA}:42:${HEAD_SHA}:job:9002:run:1234:1"
TMP_DIR="$(mktemp -d)"
readonly TMP_DIR
trap 'rm -rf -- "${TMP_DIR}"' EXIT
export HEAD_SHA BASE_SHA WORKFLOW_SHA RUN_HEAD_SHA EXTERNAL_ID TEST_REPO

export GH_TOKEN=test-token
export GH_REPO="${TEST_REPO}"
export EXPECTED_REPO="${TEST_REPO}"
export CLA_GENERATION=test-generation
export EXPECTED_GENERATION=test-generation
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
export EVENT_HEAD_REPOSITORY_ID=456
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
export RUN_ID=1234
export RUN_ATTEMPT=1
export RUN_HEAD_SHA
export EXPECTED_WORKFLOW_NAME='CLA Assistant v3'
export EXPECTED_WORKFLOW_PATH='.github/workflows/cla.yml'
export COMMENT_CREATED_AT=
export COMMENT_AUTHOR_ID=

# The production worker is executed in a child bash, so export this replacement
# after the simple legacy fixture above. It keeps a mutable JSON check store to
# model POST/PATCH and the post-mutation reconciliation scan.
gh() {
  local args="$*" body check_id new_check updated tmp
  printf 'REQUEST %s\n' "$args" >>"${FAKE_GH_LOG:-/tmp/cla-test-requests}"
  if [[ "$args" == *"pulls/42"* ]]; then
    jq -cn --arg head "$HEAD_SHA" --arg base "$BASE_SHA" --arg repo "$TEST_REPO" \
      '{number:42,state:"open",merged_at:null,
        base:{ref:"main",sha:$base,repo:{full_name:$repo,id:123}},
        head:{sha:$head,ref:"test-branch",repo:{full_name:$repo,id:456}},
        user:{id:7}}'
    return
  fi
  if [[ "$args" == *"actions/runs/1234/jobs"* ]]; then
    local job_sha="$RUN_HEAD_SHA"
    [[ "${FAKE_JOB_MODE:-}" == head_mismatch ]] && job_sha="$HEAD_SHA"
    jq -cn --arg sha "$job_sha" --arg repo "$TEST_REPO" --arg conclusion "$FAKE_WRITER_CONCLUSION" \
      '{total_count:1,jobs:[{id:9002,name:"CLA Assistant",run_id:1234,run_attempt:1,
        head_sha:$sha,head_repository:null,
        html_url:"https://github.com/\($repo)/actions/runs/1234/job/9002",
        run_url:"https://api.github.com/repos/\($repo)/actions/runs/1234",
        status:"completed",conclusion:$conclusion}]}'
    return
  fi
  if [[ "$args" == *"actions/jobs/9002"* ]]; then
    local job_sha="$RUN_HEAD_SHA"
    [[ "${FAKE_JOB_MODE:-}" == head_mismatch ]] && job_sha="$HEAD_SHA"
    jq -cn --arg sha "$job_sha" --arg repo "$TEST_REPO" --arg conclusion "$FAKE_WRITER_CONCLUSION" \
      '{id:9002,run_id:1234,run_attempt:1,name:"CLA Assistant",status:"completed",
        conclusion:$conclusion,head_sha:$sha,head_repository:null,
        run_url:"https://api.github.com/repos/\($repo)/actions/runs/1234",
        html_url:"https://github.com/\($repo)/actions/runs/1234/job/9002",
        steps:[{name:"writer",status:"completed",conclusion:$conclusion}]}'
    return
  fi
  if [[ "$args" == *"actions/runs/1234"* ]]; then
    local workflow_name='CLA Assistant v3'
    local run_sha="$RUN_HEAD_SHA"
    [[ "${FAKE_JOB_MODE:-}" == mismatch ]] && workflow_name='spoofed workflow'
    [[ "${FAKE_JOB_MODE:-}" == run_head_mismatch ]] && run_sha="$HEAD_SHA"
    jq -cn --arg sha "$run_sha" --arg repo "$TEST_REPO" --arg workflow_name "$workflow_name" \
      '{id:1234,run_attempt:1,name:$workflow_name,path:".github/workflows/cla.yml",
        status:"completed",head_sha:$sha,repository:{full_name:$repo},head_repository:null,
        html_url:"https://github.com/\($repo)/actions/runs/1234"}'
    return
  fi
  if [[ "$args" == *"commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/check-runs"* ]]; then
    local page=1
    if [[ "$args" =~ (^|[[:space:]])page=([0-9]+) ]]; then
      page="${BASH_REMATCH[2]}"
    fi
    jq --argjson page "$page" \
      '{total_count,check_runs:(.check_runs[((($page - 1) * 100)):($page * 100)])}' \
      "$FAKE_CHECKS_FILE"
    return
  fi
  if [[ "$args" == *"--method POST"* ]]; then
    body="$(cat)"
    printf 'POST %s\n' "$body" >>"$FAKE_GH_LOG"
    new_check="$(jq --argjson id "$FAKE_NEXT_ID" '. + {id:$id,app:{id:15368}}' <<<"$body")"
    tmp="${FAKE_CHECKS_FILE}.tmp"
    jq --argjson add "$new_check" '.check_runs += [$add] | .total_count = (.check_runs | length)' "${FAKE_CHECKS_FILE}" >"$tmp"
    mv "$tmp" "$FAKE_CHECKS_FILE"
    FAKE_NEXT_ID=$((FAKE_NEXT_ID + 1))
    export FAKE_NEXT_ID
    printf '%s\n' "$new_check"
    return
  fi
  if [[ "$args" == *"--method PATCH"* ]]; then
    body="$(cat)"
    check_id="${args#*check-runs/}"
    check_id="${check_id%% *}"
    printf 'PATCH %s %s\n' "$check_id" "$body" >>"$FAKE_GH_LOG"
    tmp="${FAKE_CHECKS_FILE}.tmp"
    updated="$(jq --argjson id "$check_id" --argjson patch "$body" \
      '.check_runs[] | select(.id == $id) | . * $patch | . + {app:{id:15368}}' "${FAKE_CHECKS_FILE}")"
    jq --argjson id "$check_id" --argjson patch "$body" \
      '.check_runs = [ .check_runs[] | if .id == $id then . * $patch else . end ]' \
      "${FAKE_CHECKS_FILE}" >"$tmp"
    mv "$tmp" "$FAKE_CHECKS_FILE"
    printf '%s\n' "$updated"
    return
  fi
  printf 'unexpected fake gh request: %s\n' "$args" >&2
  return 1
}
export -f gh
if [[ "$(bash -c 'type -t gh')" != function ]]; then
  echo 'test harness could not export its fake gh function' >&2
  exit 1
fi

run_case() {
  local name="$1" checks="$2" expected_conclusion="$3"
  local output="${TMP_DIR}/${name}.out"
  export FAKE_GH_LOG="${TMP_DIR}/${name}.gh"
  export FAKE_CHECKS_FILE="${TMP_DIR}/${name}.checks"
  printf '%s\n' "${checks}" >"${FAKE_CHECKS_FILE}"
  : >"${FAKE_GH_LOG}"
  case "${WRITER_RESULT}" in
    success) export FAKE_WRITER_CONCLUSION=success ;;
    failure) export FAKE_WRITER_CONCLUSION=failure ;;
    cancelled) export FAKE_WRITER_CONCLUSION=cancelled ;;
    skipped) export FAKE_WRITER_CONCLUSION=skipped ;;
    timed_out) export FAKE_WRITER_CONCLUSION=timed_out ;;
    *) return 1 ;;
  esac
  export FAKE_NEXT_ID=9001
  export GITHUB_OUTPUT="${output}"
  bash "${WORKER}"
  grep -Fx "conclusion=${expected_conclusion}" "${output}" >/dev/null
}

run_expect_failure() {
  local name="$1" checks="$2" mode="${3:-}"
  local output="${TMP_DIR}/${name}.out"
  export FAKE_GH_LOG="${TMP_DIR}/${name}.gh"
  export FAKE_CHECKS_FILE="${TMP_DIR}/${name}.checks"
  printf '%s\n' "${checks}" >"${FAKE_CHECKS_FILE}"
  : >"${FAKE_GH_LOG}"
  export FAKE_NEXT_ID=9001
  export FAKE_JOB_MODE="${mode}"
  export FAKE_WRITER_CONCLUSION=failure
  export GITHUB_OUTPUT="${output}"
  if bash "${WORKER}"; then
    echo "case ${name} unexpectedly succeeded" >&2
    return 1
  fi
  unset FAKE_JOB_MODE
}

success_run="$(jq -cn --arg head "${HEAD_SHA}" --arg external "${EXTERNAL_ID}" \
  '{total_count:1,check_runs:[{id:7001,name:"CLA Assistant v3",head_sha:$head,
    status:"completed",conclusion:"success",external_id:$external,app:{id:15368}}]}')"
export WRITER_RESULT=failure
export WRITER_POLICY_RESULT=false
run_case writer_failure_is_failure "${success_run}" failure
grep -F 'PATCH 7001' "${FAKE_GH_LOG}" >/dev/null
grep -F '"conclusion":"failure"' "${FAKE_GH_LOG}" >/dev/null
if grep -F '"conclusion":"success"' "${FAKE_GH_LOG}" >/dev/null; then
  echo 'writer failure was promoted to success' >&2
  exit 1
fi

duplicate_runs="$(jq -cn --arg head "${HEAD_SHA}" --arg external "${EXTERNAL_ID}" \
  '{total_count:2,check_runs:[
    {id:7001,name:"CLA Assistant v3",head_sha:$head,status:"completed",conclusion:"success",external_id:$external,app:{id:15368}},
    {id:7002,name:"cla assistant v3",head_sha:$head,status:"completed",conclusion:"failure",external_id:"cla-refresh:test-generation:42:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",app:{id:15368}}
  ]}')"
export WRITER_RESULT=success
export WRITER_POLICY_RESULT=true
run_case duplicate_case_variants_converge "${duplicate_runs}" success
[[ "$(grep -c '^PATCH ' "${FAKE_GH_LOG}")" -ge 2 ]]
if grep -F '"conclusion":"failure"' "${FAKE_GH_LOG}" >/dev/null; then
  echo 'duplicate reconciliation attempted to publish a failure' >&2
  exit 1
fi

newer_check="$(jq -cn --arg head "${HEAD_SHA}" \
  '{total_count:1,check_runs:[{id:7010,name:"CLA Assistant v3",head_sha:$head,
    status:"completed",conclusion:"success",
    external_id:"cla-v3:manaflow-ai/cmux-skills:test-generation:cccccccccccccccccccccccccccccccccccccccc:42:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:job:9003:run:1235:1",
    app:{id:15368}}]}')"
run_case newer_run_is_noop "${newer_check}" success
grep -Fx 'no_refresh=true' "${TMP_DIR}/newer_run_is_noop.out" >/dev/null
if grep -E '^(POST|PATCH) ' "${FAKE_GH_LOG}" >/dev/null; then
  echo 'newer run was mutated' >&2
  exit 1
fi

volume_checks="$(jq -cn --arg head "${HEAD_SHA}" --arg external "${EXTERNAL_ID}" '
  [range(0;99) as $i | {id:(8000 + $i),name:"CLA Assistant v3",head_sha:$head,
    status:"completed",conclusion:"failure",external_id:null,app:{id:15368}}] +
  [{id:8099,name:"CLA Assistant v3",head_sha:$head,status:"completed",
    conclusion:"success",external_id:$external,app:{id:15368}}] |
  {total_count:length,check_runs:.}')"
run_case exact_query_ignores_volume "${volume_checks}" success

malformed_check="$(jq -cn --arg head "${HEAD_SHA}" \
  '{total_count:1,check_runs:[{id:7020,name:"CLA Assistant v3",head_sha:$head,
    status:"completed",conclusion:"success",external_id:"cla-v3:spoof",app:{id:15368}}]}')"
run_expect_failure malformed_external_id "${malformed_check}"
run_expect_failure mismatched_writer_job "${success_run}" mismatch
run_expect_failure mismatched_run_head "${success_run}" run_head_mismatch
run_expect_failure mismatched_job_head "${success_run}" head_mismatch

legacy_run="$(jq -cn --arg head "${HEAD_SHA}" \
  '{total_count:1,check_runs:[{id:7030,name:"CLA Assistant v3",head_sha:$head,
    status:"completed",conclusion:"failure",
    external_id:"cla-v3:manaflow-ai/cmux-skills:test-generation:cccccccccccccccccccccccccccccccccccccccc:42:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:run:1234:1",
    app:{id:15368}}]}')"
run_case legacy_current_id_is_reconciled "${legacy_run}" success
grep -F 'PATCH 7030' "${FAKE_GH_LOG}" >/dev/null

echo 'refresh-cla-check behavior tests passed'
