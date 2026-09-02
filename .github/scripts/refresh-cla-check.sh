#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

# This worker is trusted base-branch code. It has only checks:write and never
# checks out, evaluates, or writes pull-request code. It binds one v3 check to
# the current live pull-request head after revalidating the triggering event.

fail() {
  echo "::error title=CLA check refresh::${1}" >&2
  exit 1
}

no_refresh() {
  printf 'published=false\nno_refresh=true\nconclusion=failure\nhead_sha=\n' >> "${GITHUB_OUTPUT:?}"
  echo "::notice::CLA check refresh skipped because the event is stale or unauthorized."
  exit 0
}

is_id() {
  local value="${1:-}"
  [[ "${value}" =~ ^[1-9][0-9]*$ ]] || return 1
  (( ${#value} <= 16 )) || return 1
  (( ${#value} < 16 || 10#${value} <= 9007199254740991 ))
}

is_sha() {
  [[ "${1:-}" =~ ^[0-9a-fA-F]{40}$ ]]
}

is_safe_text() {
  local value="${1:-}"
  (( ${#value} > 0 && ${#value} <= 255 )) || return 1
  [[ "${value}" != *$'\r'* && "${value}" != *$'\n'* ]]
}

readonly SIGN_PHRASE='I have read the CLA Document v2.2 and I hereby sign the CLA'
readonly CHECK_NAME='CLA Assistant v3'
readonly CHECK_APP_ID='15368'
readonly MAX_PAGES=10
readonly PAGE_SIZE=100
readonly MAX_CHECK_RUNS=$((MAX_PAGES * PAGE_SIZE))
readonly EXTERNAL_ID_PREFIX='cla-v3'
readonly MAX_RESPONSE_BYTES=1048576
readonly MAX_JOB_COUNT=1000

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GH_REPO:?GH_REPO is required}"
: "${EXPECTED_REPO:?EXPECTED_REPO is required}"
: "${CLA_GENERATION:?CLA_GENERATION is required}"
: "${EXPECTED_GENERATION:?EXPECTED_GENERATION is required}"
: "${RUN_ID:?RUN_ID is required}"
: "${RUN_ATTEMPT:?RUN_ATTEMPT is required}"
: "${RUN_HEAD_SHA:?RUN_HEAD_SHA is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

readonly EXPECTED_WORKFLOW_NAME="${EXPECTED_WORKFLOW_NAME:-CLA Assistant v3}"
readonly EXPECTED_WORKFLOW_PATH="${EXPECTED_WORKFLOW_PATH:-.github/workflows/cla.yml}"

# Capture a bounded response before local jq parsing. A sentinel byte makes
# truncation observable and fails closed without loading an unbounded stream.
api_json() {
  local tmp bytes
  local -a pipe_status
  tmp="$(mktemp)" || return 1
  set +e
  gh api "${@}" 2>/dev/null | head -c "$((MAX_RESPONSE_BYTES + 1))" >"${tmp}"
  pipe_status=("${PIPESTATUS[@]}")
  set -e
  bytes="$(wc -c <"${tmp}" | tr -d '[:space:]')"
  if ! [[ "${bytes}" =~ ^[0-9]+$ ]] || (( bytes > MAX_RESPONSE_BYTES )); then
    rm -f -- "${tmp}"
    return 2
  fi
  if (( ${pipe_status[0]:-1} != 0 || ${pipe_status[1]:-1} != 0 )); then
    rm -f -- "${tmp}"
    return 1
  fi
  API_JSON="$(<"${tmp}")"
  rm -f -- "${tmp}"
}

[[ "${GH_REPO}" == "${EXPECTED_REPO}" ]] || fail 'The worker is not running for the canonical repository.'
[[ "${GH_REPO}" =~ ^[^/]+/[^/]+$ ]] || fail 'The canonical repository name is invalid.'
is_safe_text "${CLA_GENERATION}" || fail 'The CLA generation marker is invalid.'
[[ "${CLA_GENERATION}" == "${EXPECTED_GENERATION}" ]] || fail 'The CLA generation marker is not the reviewed action generation.'
is_sha "${WORKFLOW_SHA:-}" || fail 'The trusted workflow revision is invalid.'
is_sha "${RUN_HEAD_SHA:-}" || fail 'The workflow run head SHA is invalid.'
is_id "${REPOSITORY_ID:-}" || fail 'The canonical repository ID is invalid.'
is_id "${PR_NUMBER:-}" || fail 'The pull request number is invalid.'
is_id "${RUN_ID:-}" || fail 'The workflow run ID is invalid.'
is_id "${RUN_ATTEMPT:-}" || fail 'The workflow run attempt is invalid.'
[[ "${GITHUB_RUN_ID:-${RUN_ID}}" == "${RUN_ID}" ]] || fail 'The workflow run ID does not match the event run.'
is_safe_text "${EXPECTED_WORKFLOW_NAME}" || fail 'The expected workflow name is invalid.'
is_safe_text "${EXPECTED_WORKFLOW_PATH}" || fail 'The expected workflow path is invalid.'
[[ "${GATE_RESULT:-}" == success && "${GATE_ADMITTED:-}" == true ]] || fail 'The exact CLA event gate did not admit this event.'

event_kind=''
case "${EVENT_NAME:-}" in
  pull_request_target)
    case "${EVENT_ACTION:-}" in
      opened|reopened|synchronize|edited|ready_for_review) event_kind=lifecycle ;;
      *) fail 'The pull-request event is not an accepted CLA lifecycle event.' ;;
    esac
    ;;
  issue_comment)
    [[ "${EVENT_ACTION:-}" == created && "${EVENT_ISSUE_STATE:-}" == open ]] || fail 'The issue-comment event is not current.'
    [[ "${EVENT_ISSUE_IS_PR:-}" == true ]] || fail 'The issue comment is not attached to a pull request.'
    [[ "${COMMENT_USER_TYPE:-}" == User ]] || fail 'Only authenticated human users may request a CLA refresh.'
    is_id "${COMMENT_ID:-}" || fail 'The issue-comment ID is invalid.'
    is_id "${COMMENT_USER_ID:-}" || fail 'The issue-comment user ID is invalid.'
    case "${COMMENT_BODY:-}" in
      recheck) event_kind=recheck ;;
      "${SIGN_PHRASE}") event_kind=sign ;;
      *) no_refresh ;;
    esac
    ;;
  *) fail 'The worker received an unsupported event.' ;;
esac

if [[ "${event_kind}" == recheck ]]; then
  # The job-level expression also applies this rule. Repeat it in trusted
  # shell so a case-variant or stale event cannot obtain a check write.
  case "${COMMENT_ASSOCIATION:-}" in
    OWNER|MEMBER|COLLABORATOR) ;;
    *) [[ "${COMMENT_USER_ID}" == "${EVENT_OPENER_ID:-}" ]] || no_refresh ;;
  esac
fi

validate_recheck_authorization() {
  [[ "${event_kind}" == recheck ]] || return 0
  jq -e --arg opener_id "${OPENER_ID}" '
    ((.user.id | type == "number" and tostring == $opener_id) or
      (.author_association == "OWNER") or
      (.author_association == "MEMBER") or
      (.author_association == "COLLABORATOR"))
  ' <<<"${1}" >/dev/null || no_refresh
}

api_json "repos/${GH_REPO}/pulls/${PR_NUMBER}" || fail 'Could not read the live pull request.'
pr_json="${API_JSON}"
jq -e \
  --arg repo "${GH_REPO}" --argjson number "${PR_NUMBER}" \
  '.number == $number and .state == "open" and .merged_at == null and
   .base.ref == "main" and (.base.repo.full_name | type == "string") and
   ((.base.repo.full_name | ascii_downcase) == ($repo | ascii_downcase)) and
   (.base.repo.id | type == "number" and floor == . and . > 0 and . <= 9007199254740991) and
   (.base.sha | type == "string" and test("^[0-9a-fA-F]{40}$")) and
   (.head.sha | type == "string" and test("^[0-9a-fA-F]{40}$")) and
   (.head.ref | type == "string" and length > 0 and length <= 255 and (test("[\\r\\n]") | not)) and
   (.head.repo | type == "object") and
   (.head.repo.full_name | type == "string" and length > 0 and length <= 255 and (test("[\\r\\n]") | not)) and
   (.head.repo.id | type == "number" and floor == . and . > 0 and . <= 9007199254740991) and
   (.user.id | type == "number" and floor == . and . > 0 and . <= 9007199254740991)' \
  <<<"${pr_json}" >/dev/null || fail 'The live pull request is not a valid open pull request targeting main.'

HEAD_SHA="$(jq -er '.head.sha | ascii_downcase' <<<"${pr_json}")"
BASE_SHA="$(jq -er '.base.sha | ascii_downcase' <<<"${pr_json}")"
BASE_REF="$(jq -er '.base.ref' <<<"${pr_json}")"
BASE_REPO="$(jq -er '.base.repo.full_name' <<<"${pr_json}")"
BASE_REPO_ID="$(jq -er '.base.repo.id | tostring' <<<"${pr_json}")"
HEAD_REPO="$(jq -er '.head.repo.full_name' <<<"${pr_json}")"
HEAD_REPO_ID="$(jq -er '.head.repo.id | tostring' <<<"${pr_json}")"
OPENER_ID="$(jq -er '.user.id | tostring' <<<"${pr_json}")"
is_sha "${HEAD_SHA}" || fail 'The live pull request head SHA is invalid.'
is_sha "${BASE_SHA}" || fail 'The live pull request base SHA is invalid.'
is_id "${BASE_REPO_ID}" || fail 'The live base repository ID is invalid.'
is_id "${HEAD_REPO_ID}" || fail 'The live head repository ID is invalid.'
is_id "${OPENER_ID}" || fail 'The live pull request opener ID is invalid.'
[[ "${BASE_REPO_ID}" == "${REPOSITORY_ID}" ]] || fail 'The live base repository is not canonical.'

if [[ "${event_kind}" == lifecycle ]]; then
  [[ "${EVENT_PR_NUMBER:-${PR_NUMBER}}" == "${PR_NUMBER}" ]] || fail 'The lifecycle event pull request number changed.'
  [[ "${EVENT_BASE_REF:-}" == "${BASE_REF}" &&
     "${EVENT_BASE_SHA:-}" == "${BASE_SHA}" &&
     "${EVENT_BASE_REPOSITORY,,}" == "${BASE_REPO,,}" &&
     "${EVENT_BASE_REPOSITORY_ID:-}" == "${BASE_REPO_ID}" &&
     "${EVENT_HEAD_REPOSITORY,,}" == "${HEAD_REPO,,}" &&
     "${EVENT_HEAD_REPOSITORY_ID:-}" == "${HEAD_REPO_ID}" &&
     "${EVENT_HEAD_SHA,,}" == "${HEAD_SHA}" ]] || fail 'The lifecycle payload does not match the live pull request.'
else
  expected_issue_url="https://api.github.com/repos/${GH_REPO}/issues/${PR_NUMBER}"
  comment_endpoint="repos/${GH_REPO}/issues/comments/${COMMENT_ID}"
  api_json "${comment_endpoint}" || no_refresh
  comment_json="${API_JSON}"
  jq -e \
    --arg id "${COMMENT_ID}" --arg body "${COMMENT_BODY}" --arg uid "${COMMENT_USER_ID}" \
    --arg created "${COMMENT_CREATED_AT:-}" --arg author "${COMMENT_AUTHOR_ID:-${COMMENT_USER_ID}}" \
    --arg issue_url "${expected_issue_url}" \
    '(.id | type == "number" and tostring == $id) and
     (.body == $body) and (.user.id | type == "number" and tostring == $uid) and
     (.user.type == "User") and (.created_at | type == "string" and length > 0) and
     (.updated_at == .created_at) and (.issue_url == $issue_url) and
     (($created == "") or .created_at == $created) and (.user.id | tostring == $author)' \
    <<<"${comment_json}" >/dev/null || no_refresh
  validate_recheck_authorization "${comment_json}"
fi

case "${event_kind}" in
  sign)
    [[ "${PREFLIGHT_RESULT:-}" == success && "${SIGNER_AUTHORIZED:-}" == true ]] || no_refresh
    is_sha "${SIGNER_HEAD_SHA:-}" || no_refresh
    is_sha "${SIGNER_BASE_SHA:-}" || no_refresh
    [[ "${SIGNER_HEAD_SHA,,}" == "${HEAD_SHA}" && "${SIGNER_BASE_SHA,,}" == "${BASE_SHA}" ]] || no_refresh
    ;;
  recheck)
    [[ "${RECHECK_AUTHORIZED:-true}" == true ]] || no_refresh
    ;;
esac

# The write-capable signer and this check worker are separate jobs. Never
# promote a failed, cancelled, or unsigned writer result to success.
case "${WRITER_RESULT:-}" in
  success) writer_conclusion=success ;;
  failure) writer_conclusion=failure ;;
  cancelled) writer_conclusion=cancelled ;;
  skipped) writer_conclusion=skipped ;;
  timed_out) writer_conclusion=timed_out ;;
  *) fail 'The writer job result is invalid.' ;;
esac
policy_conclusion="${writer_conclusion}"
policy_reason='the maintained CLA writer did not complete a successful all-signed validation'
if [[ "${writer_conclusion}" == success && "${WRITER_POLICY_RESULT:-}" == true ]]; then
  policy_reason='the maintained CLA writer validated the live pull request'
elif [[ "${writer_conclusion}" == success ]]; then
  policy_conclusion=failure
fi
if [[ -n "${WRITER_HEAD_SHA:-}" ]]; then
  is_sha "${WRITER_HEAD_SHA}" || no_refresh
  writer_head_lc="$(printf '%s' "${WRITER_HEAD_SHA}" | tr '[:upper:]' '[:lower:]')"
  [[ "${writer_head_lc}" == "${HEAD_SHA}" ]] || no_refresh
fi

if [[ "${event_kind}" != lifecycle ]]; then
  # Close the gate-to-write race. The comment must still be immutable and
  # exact immediately before the Checks API mutation.
  api_json "${comment_endpoint}" || no_refresh
  comment_json="${API_JSON}"
  jq -e \
    --arg id "${COMMENT_ID}" --arg body "${COMMENT_BODY}" --arg uid "${COMMENT_USER_ID}" \
    --arg created "${COMMENT_CREATED_AT:-}" --arg author "${COMMENT_AUTHOR_ID:-${COMMENT_USER_ID}}" \
    --arg issue_url "${expected_issue_url}" \
    '(.id | type == "number" and tostring == $id) and .body == $body and
     (.user.id | type == "number" and tostring == $uid) and .user.type == "User" and
     (.created_at | type == "string" and length > 0) and .updated_at == .created_at and
     .issue_url == $issue_url and (($created == "") or .created_at == $created) and
     (.user.id | tostring == $author)' <<<"${comment_json}" >/dev/null || no_refresh
  validate_recheck_authorization "${comment_json}"
fi

bind_writer_job() {
  local run_json jobs='[]' page page_json page_count page_total seen=0
  local total_jobs='' writer_candidates writer_count writer_json expected_run_url

  api_json "repos/$GH_REPO/actions/runs/$RUN_ID" ||
    fail 'Could not read the workflow run for writer binding.'
  run_json="$API_JSON"
  jq -e \
    --arg run_id "$RUN_ID" --argjson run_num "$RUN_ID" --argjson attempt_num "$RUN_ATTEMPT" \
    --arg workflow_name "$EXPECTED_WORKFLOW_NAME" --arg workflow_path "$EXPECTED_WORKFLOW_PATH" \
    --arg run_head "$RUN_HEAD_SHA" --arg repo "$GH_REPO" \
    'def safe_id: type == "number" and floor == . and . > 0 and . <= 9007199254740991;
     def safe_sha: type == "string" and test("^[0-9a-fA-F]{40}$");
     (.id | safe_id) and (.id | tostring == $run_id) and
     (.run_attempt | safe_id and . == $attempt_num) and
     (.name == $workflow_name) and (.path == $workflow_path) and
     (.status == "completed") and
     (.head_sha | safe_sha and ascii_downcase == ($run_head | ascii_downcase)) and
     (.repository | type == "object" and
       (.full_name | type == "string" and ascii_downcase == ($repo | ascii_downcase))) and
     (.head_repository == null or
       (.head_repository | type == "object" and
        (.full_name | type == "string" and test("^[^/]+/[^/]+$") and length <= 255) and
        (.id == null or (.id | safe_id)))) and
     (.html_url | type == "string" and startswith("https://github.com/"))' \
    <<<"$run_json" >/dev/null ||
    fail 'The workflow run identity is not bound to this trusted workflow.'

  for ((page = 1; page <= MAX_PAGES; page++)); do
    api_json --method GET \
      "repos/$GH_REPO/actions/runs/$RUN_ID/jobs?per_page=$PAGE_SIZE&page=$page" ||
      fail "Could not read workflow jobs on page $page."
    page_json="$API_JSON"
    jq -e --argjson run_num "$RUN_ID" --argjson attempt_num "$RUN_ATTEMPT" \
      --arg run_head "$RUN_HEAD_SHA" --arg repo "$GH_REPO" '
      def safe_id: type == "number" and floor == . and . > 0 and . <= 9007199254740991;
      def safe_sha: type == "string" and test("^[0-9a-fA-F]{40}$");
      def safe_text: type == "string" and length > 0 and length <= 255 and (test("[\\r\\n]") | not);
      def valid_repo:
        . == null or (type == "object" and
          (.full_name | type == "string" and test("^[^/]+/[^/]+$") and length <= 255) and
          (.id == null or (.id | safe_id)));
      type == "object" and (.total_count | type == "number" and floor == . and . >= 0 and . <= 1000) and
      (.jobs | type == "array" and length <= 100) and
      all(.jobs[];
        (.id | safe_id) and (.run_id | safe_id and . == $run_num) and
        (.run_attempt | safe_id and . == $attempt_num) and (.name | safe_text) and
        (.head_sha | safe_sha and ascii_downcase == ($run_head | ascii_downcase)) and
        (.head_repository | valid_repo) and
        (.html_url | type == "string" and startswith("https://github.com/")) and
        (.run_url | type == "string" and startswith("https://api.github.com/repos/")) and
        (.status | type == "string" and length <= 32) and
        (.conclusion == null or (.conclusion | type == "string" and length <= 32)))
    ' <<<"$page_json" >/dev/null ||
      fail "GitHub returned malformed workflow jobs on page $page."
    page_total="$(jq -er '.total_count' <<<"$page_json")"
    page_count="$(jq -er '.jobs | length' <<<"$page_json")"
    if [[ -z "$total_jobs" ]]; then
      total_jobs="$page_total"
    elif [[ "$page_total" != "$total_jobs" ]]; then
      fail 'The workflow job count changed during bounded pagination.'
    fi
    seen=$((seen + page_count))
    (( seen <= MAX_JOB_COUNT )) || fail 'The workflow has too many jobs for a bounded writer binding.'
    jobs="$(jq -c --argjson old "$jobs" --argjson new "$(jq -c '.jobs' <<<"$page_json")" '$old + $new' <<< 'null')"
    if (( page_count < PAGE_SIZE )); then
      [[ "$seen" == "$total_jobs" ]] || fail 'The workflow job pagination was truncated.'
      break
    fi
    if (( page == MAX_PAGES )); then
      api_json --method GET \
        "repos/$GH_REPO/actions/runs/$RUN_ID/jobs?per_page=$PAGE_SIZE&page=$((MAX_PAGES + 1))" ||
        fail 'Could not verify the workflow job overflow page.'
      page_json="$API_JSON"
      jq -e '.jobs | type == "array" and length <= 100' <<<"$page_json" >/dev/null ||
        fail 'The workflow job overflow page is malformed.'
      [[ "$(jq -er '.jobs | length' <<<"$page_json")" == 0 ]] ||
        fail 'The workflow job list exceeded its bounded pagination limit.'
    fi
  done

  writer_candidates="$(jq -c --argjson run_num "$RUN_ID" \
    '[.[] | select(.name == "CLA Assistant" and .run_id == $run_num)]' <<<"$jobs")"
  writer_count="$(jq -er 'length' <<<"$writer_candidates")"
  [[ "$writer_count" == 1 ]] ||
    fail 'The workflow run does not contain exactly one CLA Assistant writer job.'
  WRITER_JOB_ID="$(jq -er '.[0].id | tostring' <<<"$writer_candidates")"
  is_id "$WRITER_JOB_ID" || fail 'The CLA Assistant writer job ID is invalid.'

  api_json "repos/$GH_REPO/actions/jobs/$WRITER_JOB_ID" ||
    fail 'Could not read the exact CLA Assistant writer job.'
  writer_json="$API_JSON"
  expected_run_url="https://api.github.com/repos/$GH_REPO/actions/runs/$RUN_ID"
  jq -e \
    --argjson job_num "$WRITER_JOB_ID" --argjson run_num "$RUN_ID" --argjson attempt_num "$RUN_ATTEMPT" \
    --arg expected_conclusion "$writer_conclusion" --arg run_head "$RUN_HEAD_SHA" \
    --arg repo "$GH_REPO" --arg run_url "$expected_run_url" \
    'def safe_id: type == "number" and floor == . and . > 0 and . <= 9007199254740991;
     def safe_sha: type == "string" and test("^[0-9a-fA-F]{40}$");
     def valid_repo:
       . == null or (type == "object" and
         (.full_name | type == "string" and test("^[^/]+/[^/]+$") and length <= 255) and
         (.id == null or (.id | safe_id)));
     (.id | safe_id and . == $job_num) and (.run_id | safe_id and . == $run_num) and
     (.run_attempt | safe_id and . == $attempt_num) and (.name == "CLA Assistant") and
     (.status == "completed") and (.conclusion == $expected_conclusion) and
     (.head_sha | safe_sha and ascii_downcase == ($run_head | ascii_downcase)) and
     (.head_repository | valid_repo) and (.run_url == $run_url) and
     (.html_url | type == "string" and startswith("https://github.com/")) and
     (.steps | type == "array" and length <= 100 and
       all(.[]; (.name | type == "string" and length > 0 and length <= 255 and
           (test("[\\r\\n]") | not)) and
         (.status | type == "string" and length <= 32) and
         (.conclusion == null or (.conclusion | type == "string" and length <= 32))))' \
    <<<"$writer_json" >/dev/null ||
    fail 'The exact CLA Assistant writer job is not a completed, run-bound job.'
  WRITER_JOB_URL="$(jq -er '.html_url' <<<"$writer_json")"
}

bind_writer_job
workflow_sha_lc="$(printf '%s' "$WORKFLOW_SHA" | tr '[:upper:]' '[:lower:]')"
head_sha_lc="$(printf '%s' "$HEAD_SHA" | tr '[:upper:]' '[:lower:]')"
external_id_scope="$EXTERNAL_ID_PREFIX:$GH_REPO:$CLA_GENERATION:$workflow_sha_lc:$PR_NUMBER:$head_sha_lc"
external_id="${external_id_scope}:job:$WRITER_JOB_ID:run:$RUN_ID:$RUN_ATTEMPT"
is_safe_text "$external_id" || fail 'The CLA check external ID is too long or malformed.'
build_payload() {
  local title summary
  if [[ "${policy_conclusion}" == success ]]; then
    title='CLA declaration validated'
    summary='The maintained CLA writer validated the current pull request head.'
  else
    title='CLA declaration failed'
    summary="CLA validation failed: ${policy_reason}. Correct the declaration and request a new check."
  fi
  payload="$(jq -n \
    --arg name "${CHECK_NAME}" --arg sha "${HEAD_SHA}" --arg conclusion "${policy_conclusion}" \
    --arg details_url "${WRITER_JOB_URL}" --arg external_id "${external_id}" \
    --arg title "${title}" --arg summary "${summary}" \
    '{name:$name,head_sha:$sha,status:"completed",conclusion:$conclusion,
      details_url:$details_url,external_id:$external_id,
      output:{title:$title,summary:$summary}}')"
}

# Strict, bounded check-run scan. The API check_name filter is case sensitive,
# so canonical and lower-case filters run first. The unfiltered scan is used
# only when those filters find no candidate and then fails closed on overflow.
validate_check_page_v2() {
  jq -e '
    def safe_id: type == "number" and floor == . and . > 0 and . <= 9007199254740991;
    def safe_sha: type == "string" and test("^[0-9a-fA-F]{40}$");
    def safe_text: type == "string" and length > 0 and length <= 255 and (test("[\\r\\n]") | not);
    type == "object" and
    (.total_count | type == "number" and floor == . and . >= 0 and . <= 1000) and
    (.check_runs | type == "array" and length <= 100) and
    all(.check_runs[];
      (.id | safe_id) and (.name | safe_text) and (.head_sha | safe_sha) and
      (.app == null or (.app | type == "object" and (.id | safe_id))) and
      (.external_id == null or
        (.external_id | type == "string" and length <= 255 and (test("[\\r\\n]") | not))) and
      (.status | type == "string" and length <= 32) and
      (.conclusion == null or (.conclusion | type == "string" and length <= 32)))
  ' <<<"$1" >/dev/null
}

fetch_check_runs_v2() {
  local query_name="$1" page page_json page_count page_total seen=0 runs='[]'
  local endpoint="repos/$GH_REPO/commits/$HEAD_SHA/check-runs"
  local total_checks=''
  for ((page = 1; page <= MAX_PAGES; page++)); do
    if [[ -n "$query_name" ]]; then
      api_json --method GET "$endpoint" -f filter=all -f app_id="$CHECK_APP_ID" \
        -f check_name="$query_name" -f per_page="$PAGE_SIZE" -f page="$page" ||
        fail "Could not inspect filtered check runs on page $page."
    else
      api_json --method GET "$endpoint" -f filter=all -f app_id="$CHECK_APP_ID" \
        -f per_page="$PAGE_SIZE" -f page="$page" ||
        fail "Could not inspect check runs on page $page."
    fi
    page_json="$API_JSON"
    validate_check_page_v2 "$page_json" ||
      fail "GitHub returned malformed check data on page $page."
    jq -e --arg sha "$HEAD_SHA" \
      'all(.check_runs[]; (.head_sha | ascii_downcase) == ($sha | ascii_downcase))' \
      <<<"$page_json" >/dev/null ||
      fail 'GitHub returned a check run for an unexpected commit.'
    page_total="$(jq -er '.total_count' <<<"$page_json")"
    page_count="$(jq -er '.check_runs | length' <<<"$page_json")"
    if [[ -z "$total_checks" ]]; then
      total_checks="$page_total"
    elif [[ "$page_total" != "$total_checks" ]]; then
      fail 'The check-run count changed during bounded pagination.'
    fi
    seen=$((seen + page_count))
    (( seen <= MAX_CHECK_RUNS )) || fail 'The check-run list exceeded its bounded limit.'
    runs="$(jq -c --argjson old "$runs" --argjson new "$(jq -c '.check_runs' <<<"$page_json")" '$old + $new' <<< 'null')"
    if (( page_count < PAGE_SIZE )); then
      [[ "$seen" == "$total_checks" ]] || fail 'The check-run list was truncated.'
      break
    fi
    if (( page == MAX_PAGES )); then
      if [[ -n "$query_name" ]]; then
        api_json --method GET "$endpoint" -f filter=all -f app_id="$CHECK_APP_ID" \
          -f check_name="$query_name" -f per_page="$PAGE_SIZE" -f page=$((MAX_PAGES + 1)) ||
          fail 'Could not verify the filtered check-run overflow page.'
      else
        api_json --method GET "$endpoint" -f filter=all -f app_id="$CHECK_APP_ID" \
          -f per_page="$PAGE_SIZE" -f page=$((MAX_PAGES + 1)) ||
          fail 'Could not verify the check-run overflow page.'
      fi
      page_json="$API_JSON"
      validate_check_page_v2 "$page_json" ||
        fail 'GitHub returned malformed check data on the overflow page.'
      [[ "$(jq -er '.check_runs | length' <<<"$page_json")" == 0 ]] ||
        fail 'The check-run list exceeded its bounded pagination limit.'
    fi
  done
  FETCHED_CHECK_RUNS="$runs"
}

collect_matching_check_ids() {
  local all_runs='[]' query_name target_runs identities unknown_count newer
  local check_name_lc
  check_name_lc="$(printf '%s' "$CHECK_NAME" | tr '[:upper:]' '[:lower:]')"
  for query_name in "$CHECK_NAME" "$check_name_lc"; do
    fetch_check_runs_v2 "$query_name"
    all_runs="$(jq -c --argjson old "$all_runs" --argjson new "$FETCHED_CHECK_RUNS" '$old + $new' <<< 'null')"
  done
  all_runs="$(jq -c 'unique_by(.id)' <<<"$all_runs")"
  target_runs="$(jq -c --arg name "$check_name_lc" --arg sha "$HEAD_SHA" \
    '[.[] | select((.name | ascii_downcase) == $name and (.app.id? == 15368) and
      (.head_sha | ascii_downcase) == ($sha | ascii_downcase))]' <<<"$all_runs")"
  if [[ "$(jq -er 'length' <<<"$target_runs")" == 0 ]]; then
    fetch_check_runs_v2 ''
    all_runs="$(jq -c --argjson old "$all_runs" --argjson new "$FETCHED_CHECK_RUNS" '$old + $new' <<< 'null')"
    all_runs="$(jq -c 'unique_by(.id)' <<<"$all_runs")"
    target_runs="$(jq -c --arg name "$check_name_lc" --arg sha "$HEAD_SHA" \
      '[.[] | select((.name | ascii_downcase) == $name and (.app.id? == 15368) and
        (.head_sha | ascii_downcase) == ($sha | ascii_downcase))]' <<<"$all_runs")"
  fi
  identities="$(jq -c --arg scope "$external_id_scope" --arg generation "$CLA_GENERATION" \
    --arg pr "$PR_NUMBER" --arg head "$HEAD_SHA" '
    [ .[] | select(.external_id != null and .external_id != "") |
      if (.external_id | startswith($scope + ":")) then
        (.external_id | ltrimstr($scope + ":") | split(":")) as $p |
        if ($p | length) == 5 and $p[0] == "job" and ($p[1] | test("^[1-9][0-9]{0,15}$")) and
           $p[2] == "run" and ($p[3] | test("^[1-9][0-9]{0,15}$")) and
           ($p[4] | test("^[1-9][0-9]{0,15}$")) then
          {kind:"current",run:($p[3] | tonumber),attempt:($p[4] | tonumber)}
        elif ($p | length) == 3 and $p[0] == "run" and
             ($p[1] | test("^[1-9][0-9]{0,15}$")) and
             ($p[2] | test("^[1-9][0-9]{0,15}$")) then
          # Checks emitted by the previous worker lacked a job identity. Keep
          # them eligible for one bounded reconciliation, but never treat an
          # unknown or malformed identity as our check.
          {kind:"legacy-current",run:($p[1] | tonumber),attempt:($p[2] | tonumber)}
        else {kind:"malformed"} end
      elif (.external_id | startswith("cla-refresh:")) then
        (.external_id | split(":")) as $legacy |
        if ($legacy | length) == 4 and $legacy[0] == "cla-refresh" and
           $legacy[1] == $generation and $legacy[2] == $pr and
           ($legacy[3] | ascii_downcase) == ($head | ascii_downcase) then
          {kind:"legacy"}
        else {kind:"malformed"} end
      else {kind:"unknown"} end ]' <<<"$target_runs")"
  unknown_count="$(jq -er '[.[] | select(.kind == "unknown" or .kind == "malformed")] | length' <<<"$identities")"
  (( unknown_count == 0 )) || fail 'An exact CLA check has an ambiguous external ID.'
  newer="$(jq -er --argjson run "$RUN_ID" --argjson attempt "$RUN_ATTEMPT" \
    'any(.[]; (.kind == "current" or .kind == "legacy-current") and
      ((.run > $run) or (.run == $run and .attempt > $attempt)))' <<<"$identities")"
  [[ "$newer" == false ]] || no_refresh
  existing_ids="$(jq -c '[.[].id] | unique' <<<"$target_runs")"
  match_count="$(jq -er 'length' <<<"$existing_ids")"
}

# Re-read the live PR and, for comment events, the exact comment immediately
# before every Checks API mutation. This protects against a force-push, close,
# comment edit, or author change during the bounded list scan.
validate_final_binding() {
  local final_pr_json final_comment_json
  api_json "repos/${GH_REPO}/pulls/${PR_NUMBER}" || no_refresh
  final_pr_json="${API_JSON}"
  jq -e --arg repo "${GH_REPO}" --argjson number "${PR_NUMBER}" --arg sha "${HEAD_SHA}" \
    --arg base_sha "${BASE_SHA}" '
    .number == $number and .state == "open" and .merged_at == null and
    .base.ref == "main" and ((.base.repo.full_name | ascii_downcase) == ($repo | ascii_downcase)) and
    .base.sha == $base_sha and .head.sha == $sha
  ' <<<"${final_pr_json}" >/dev/null || no_refresh
  if [[ "${event_kind}" != lifecycle ]]; then
    api_json "${comment_endpoint}" || no_refresh
    final_comment_json="${API_JSON}"
    jq -e \
      --arg id "${COMMENT_ID}" --arg body "${COMMENT_BODY}" --arg uid "${COMMENT_USER_ID}" \
      --arg created "${COMMENT_CREATED_AT:-}" --arg author "${COMMENT_AUTHOR_ID:-${COMMENT_USER_ID}}" \
      --arg issue_url "${expected_issue_url}" \
      '(.id | type == "number" and tostring == $id) and .body == $body and
       (.user.id | type == "number" and tostring == $uid) and .user.type == "User" and
       (.created_at | type == "string" and length > 0) and .updated_at == .created_at and
       .issue_url == $issue_url and (($created == "") or .created_at == $created) and
       (.user.id | tostring == $author)' <<<"${final_comment_json}" >/dev/null || no_refresh
    validate_recheck_authorization "${final_comment_json}"
  fi
}

validate_check_response() {
  jq -e --arg sha "${HEAD_SHA}" --arg conclusion "${policy_conclusion}" --arg external_id "${external_id}" \
    --arg name "${CHECK_NAME}" --arg details_url "${WRITER_JOB_URL}" \
    '(.id | type == "number" and . > 0) and .name == $name and
     (.head_sha | type == "string" and ascii_downcase == ($sha | ascii_downcase)) and
     .status == "completed" and .conclusion == $conclusion and .external_id == $external_id and
     .details_url == $details_url and .app.id == 15368' <<<"${1}" >/dev/null ||
    fail 'GitHub did not confirm the expected CLA check.'
}

patch_check() {
  local check_id="$1"
  is_id "${check_id}" || fail 'The existing CLA check ID is invalid.'
  validate_final_binding
  api_json --method PATCH "repos/${GH_REPO}/check-runs/${check_id}" \
    --header 'Accept: application/vnd.github+json' --header 'X-GitHub-Api-Version: 2022-11-28' \
    --input - <<<"${patch_payload}" || fail 'Could not update the exact-head CLA check.'
  validate_check_response "${API_JSON}"
}

collect_matching_check_ids
build_payload
operation=updated
if (( match_count == 0 )); then
  validate_final_binding
  if api_json --method POST "repos/${GH_REPO}/check-runs" \
    --header 'Accept: application/vnd.github+json' --header 'X-GitHub-Api-Version: 2022-11-28' \
    --input - <<<"${payload}"; then
    validate_check_response "${API_JSON}"
    operation=created
  else
    # A concurrent worker may have created the exact check after the scan.
    collect_matching_check_ids
    (( match_count > 0 )) || fail 'Could not create the exact-head CLA check.'
    patch_payload="$(jq 'del(.head_sha)' <<<"${payload}")"
    while IFS= read -r check_id; do
      patch_check "${check_id}"
    done < <(jq -r '.[]' <<<"${existing_ids}")
  fi
else
  patch_payload="$(jq 'del(.head_sha)' <<<"${payload}")"
  while IFS= read -r check_id; do
    patch_check "${check_id}"
  done < <(jq -r '.[]' <<<"${existing_ids}")
  (( match_count <= 1 )) || echo "::notice::Reconciled ${match_count} duplicate exact-head CLA checks."
fi

# Re-enumerate after mutation. A newer run owns this head and makes this worker
# a no-op; same-head duplicates are reconciled to this writer result.
collect_matching_check_ids
(( match_count > 0 )) || fail 'The exact CLA check disappeared during reconciliation.'
if (( match_count > 1 )); then
  patch_payload="$(jq 'del(.head_sha)' <<<"${payload}")"
  while IFS= read -r check_id; do
    patch_check "${check_id}"
  done < <(jq -r '.[]' <<<"${existing_ids}")
  operation=updated
  echo "::notice::Reconciled ${match_count} concurrent exact-head CLA checks."
fi
printf 'published=true\nno_refresh=false\nconclusion=%s\nhead_sha=%s\noperation=%s\n' \
  "${policy_conclusion}" "${HEAD_SHA}" "${operation}" >> "${GITHUB_OUTPUT:?}"
echo "CLA v3 check ${operation} for PR ${PR_NUMBER}, head ${HEAD_SHA}, conclusion ${policy_conclusion}."
