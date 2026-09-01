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

readonly SIGN_PHRASE='I have read the CLA Document and I hereby sign the CLA'
readonly CHECK_NAME='CLA Assistant v3'
readonly CHECK_APP_ID='15368'
readonly MAX_PAGES=10
readonly PAGE_SIZE=100

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GH_REPO:?GH_REPO is required}"
: "${EXPECTED_REPO:?EXPECTED_REPO is required}"
: "${CLA_GENERATION:?CLA_GENERATION is required}"
: "${EXPECTED_GENERATION:?EXPECTED_GENERATION is required}"

[[ "${GH_REPO}" == "${EXPECTED_REPO}" ]] || fail 'The worker is not running for the canonical repository.'
[[ "${CLA_GENERATION}" == "${EXPECTED_GENERATION}" ]] || fail 'The CLA generation marker is not the reviewed action generation.'
is_sha "${WORKFLOW_SHA:-}" || fail 'The trusted workflow revision is invalid.'
is_id "${REPOSITORY_ID:-}" || fail 'The canonical repository ID is invalid.'
is_id "${PR_NUMBER:-}" || fail 'The pull request number is invalid.'
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

pr_json="$(gh api "repos/${GH_REPO}/pulls/${PR_NUMBER}" 2>/dev/null)" || fail 'Could not read the live pull request.'
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
  comment_json="$(gh api "${comment_endpoint}" 2>/dev/null)" || no_refresh
  jq -e \
    --arg id "${COMMENT_ID}" --arg body "${COMMENT_BODY}" --arg uid "${COMMENT_USER_ID}" \
    --arg issue_url "${expected_issue_url}" \
    '(.id | type == "number" and tostring == $id) and
     (.body == $body) and (.user.id | type == "number" and tostring == $uid) and
     (.user.type == "User") and (.created_at | type == "string" and length > 0) and
     (.updated_at == .created_at) and (.issue_url == $issue_url)' \
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

# The write-capable signer and this check worker are separate jobs. A signer
# failure is a policy failure on this exact head, while a stale writer result
# must not overwrite a newer head's check.
policy_conclusion=success
policy_reason='the maintained CLA writer validated the live pull request'
if [[ "${WRITER_RESULT:-}" != success ]]; then
  policy_conclusion=failure
  policy_reason='the maintained CLA writer did not complete successfully'
fi
if [[ -n "${WRITER_HEAD_SHA:-}" ]]; then
  is_sha "${WRITER_HEAD_SHA}" || no_refresh
  [[ "${WRITER_HEAD_SHA,,}" == "${HEAD_SHA}" ]] || no_refresh
fi

if [[ "${event_kind}" != lifecycle ]]; then
  # Close the gate-to-write race. The comment must still be immutable and
  # exact immediately before the Checks API mutation.
  comment_json="$(gh api "${comment_endpoint}" 2>/dev/null)" || no_refresh
  jq -e \
    --arg id "${COMMENT_ID}" --arg body "${COMMENT_BODY}" --arg uid "${COMMENT_USER_ID}" \
    --arg issue_url "${expected_issue_url}" \
    '(.id | type == "number" and tostring == $id) and .body == $body and
     (.user.id | type == "number" and tostring == $uid) and .user.type == "User" and
     (.created_at | type == "string" and length > 0) and .updated_at == .created_at and
     .issue_url == $issue_url' <<<"${comment_json}" >/dev/null || no_refresh
  validate_recheck_authorization "${comment_json}"
fi

external_id="cla-refresh:${CLA_GENERATION}:${PR_NUMBER}:${HEAD_SHA}"
if [[ "${policy_conclusion}" == success ]]; then
  title='CLA declaration validated'
  summary='The maintained CLA writer validated the current pull request head.'
else
  title='CLA declaration failed'
  summary="CLA validation failed: ${policy_reason}. Correct the declaration and request a new check."
fi
run_url="${GITHUB_SERVER_URL}/${GH_REPO}/actions/runs/${GITHUB_RUN_ID}"
payload="$(jq -n \
  --arg name "${CHECK_NAME}" --arg sha "${HEAD_SHA}" --arg conclusion "${policy_conclusion}" \
  --arg details_url "${run_url}" --arg external_id "${external_id}" \
  --arg title "${title}" --arg summary "${summary}" \
  '{name:$name,head_sha:$sha,status:"completed",conclusion:$conclusion,
    details_url:$details_url,external_id:$external_id,
    output:{title:$title,summary:$summary}}')"

# Enumerate all matching check runs. The API check_name filter is case
# sensitive, while branch protection context matching is not, so name matching
# is case-folded locally. Bounded pagination and an overflow probe fail closed.
pages='[]'
last_count=0
for ((page=1; page<=MAX_PAGES; page++)); do
  page_json="$(gh api --method GET "repos/${GH_REPO}/commits/${HEAD_SHA}/check-runs" \
    -f filter=all -f app_id="${CHECK_APP_ID}" -f per_page="${PAGE_SIZE}" -f page="${page}" 2>/dev/null)" ||
    fail "Could not inspect check runs on page ${page}."
  jq -e --arg sha "${HEAD_SHA}" '
    type == "object" and (.total_count | type == "number" and floor == . and . >= 0 and . <= 1000) and
    (.check_runs | type == "array" and length <= 100) and
    all(.check_runs[]; (.id | type == "number" and floor == . and . > 0 and . <= 9007199254740991) and
      (.name | type == "string") and
      (.head_sha | type == "string" and ascii_downcase == ($sha | ascii_downcase)) and
      (.app == null or (.app | type == "object" and (.id | type == "number" and . > 0))) )
  ' <<<"${page_json}" >/dev/null || fail "GitHub returned malformed or unbounded check data on page ${page}."
  pages="$(jq -c --argjson page "${page_json}" '. + [$page]' <<<"${pages}")"
  last_count="$(jq -er '.check_runs | length' <<<"${page_json}")"
  (( last_count < PAGE_SIZE )) && break
done
(( last_count < PAGE_SIZE )) || fail 'The check-run list exceeded the bounded page window.'
overflow_json="$(gh api --method GET "repos/${GH_REPO}/commits/${HEAD_SHA}/check-runs" \
  -f filter=all -f app_id="${CHECK_APP_ID}" -f per_page="${PAGE_SIZE}" -f page=$((MAX_PAGES + 1)) 2>/dev/null)" ||
  fail 'Could not inspect the check-run overflow page.'
jq -e '.check_runs | type == "array" and length == 0' <<<"${overflow_json}" >/dev/null ||
  fail 'The check-run list is larger than the bounded safety limit.'

existing_ids="$(jq -c \
  --arg external_id "${external_id}" \
  '[.[] | .check_runs[] | select((.name | ascii_downcase) == "cla assistant v3" and
    (.app.id? == 15368) and .external_id == $external_id) | .id]' <<<"${pages}")"
match_count="$(jq -er 'length' <<<"${existing_ids}")"
(( match_count <= 1 )) || fail 'More than one exact-head CLA v3 check exists for this generation.'

# Re-read the live PR immediately before the only state-changing Checks API
# call. A force-push or close during pagination must never publish a result for
# a different head or a closed pull request.
final_pr_json="$(gh api "repos/${GH_REPO}/pulls/${PR_NUMBER}" 2>/dev/null)" || no_refresh
jq -e --arg repo "${GH_REPO}" --argjson number "${PR_NUMBER}" --arg sha "${HEAD_SHA}" \
  --arg base_sha "${BASE_SHA}" '
  .number == $number and .state == "open" and .merged_at == null and
  .base.ref == "main" and ((.base.repo.full_name | ascii_downcase) == ($repo | ascii_downcase)) and
  .base.sha == $base_sha and .head.sha == $sha
' <<<"${final_pr_json}" >/dev/null || no_refresh
if [[ "${event_kind}" != lifecycle ]]; then
  comment_json="$(gh api "${comment_endpoint}" 2>/dev/null)" || no_refresh
  jq -e \
    --arg id "${COMMENT_ID}" --arg body "${COMMENT_BODY}" --arg uid "${COMMENT_USER_ID}" \
    --arg issue_url "${expected_issue_url}" \
    '(.id | type == "number" and tostring == $id) and .body == $body and
     (.user.id | type == "number" and tostring == $uid) and .user.type == "User" and
     (.created_at | type == "string" and length > 0) and .updated_at == .created_at and
     .issue_url == $issue_url' <<<"${comment_json}" >/dev/null || no_refresh
  validate_recheck_authorization "${comment_json}"
fi

if (( match_count == 1 )); then
  check_id="$(jq -er '.[0]' <<<"${existing_ids}")"
  is_id "${check_id}" || fail 'The existing CLA check ID is invalid.'
  response="$(jq 'del(.head_sha)' <<<"${payload}")"
  response="$(gh api --method PATCH "repos/${GH_REPO}/check-runs/${check_id}" \
    --header 'Accept: application/vnd.github+json' --header 'X-GitHub-Api-Version: 2022-11-28' \
    --input - <<<"${response}" 2>/dev/null)" || fail 'Could not update the exact-head CLA check.'
  operation=updated
else
  response="$(gh api --method POST "repos/${GH_REPO}/check-runs" \
    --header 'Accept: application/vnd.github+json' --header 'X-GitHub-Api-Version: 2022-11-28' \
    --input - <<<"${payload}" 2>/dev/null)" || fail 'Could not create the exact-head CLA check.'
  operation=created
fi
jq -e --arg sha "${HEAD_SHA}" --arg conclusion "${policy_conclusion}" --arg external_id "${external_id}" \
  --arg name "${CHECK_NAME}" \
  '(.id | type == "number" and . > 0) and .name == $name and
   (.head_sha | type == "string" and ascii_downcase == ($sha | ascii_downcase)) and
   .status == "completed" and .conclusion == $conclusion and .external_id == $external_id and
   .app.id == 15368' <<<"${response}" >/dev/null || fail 'GitHub did not confirm the expected CLA check.'
printf 'published=true\nno_refresh=false\nconclusion=%s\nhead_sha=%s\n' "${policy_conclusion}" "${HEAD_SHA}" >> "${GITHUB_OUTPUT:?}"
echo "CLA v3 check ${operation} for PR ${PR_NUMBER}, head ${HEAD_SHA}, conclusion ${policy_conclusion}."
