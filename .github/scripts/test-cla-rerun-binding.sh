#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="${repo_root}/.github/scripts/rerun-failed-cla.sh"
work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

remote_url="${TEST_GH_REPO:-$(git -C "${repo_root}" config --get remote.origin.url || true)}"
case "${remote_url}" in
  https://github.com/*|git@github.com:*)
    GH_REPO="${remote_url#https://github.com/}"
    GH_REPO="${GH_REPO#git@github.com:}"
    GH_REPO="${GH_REPO%.git}"
    ;;
  *)
    printf 'Could not derive an in-org test repository from origin: %s\n' "${remote_url}" >&2
    exit 1
    ;;
esac
export GH_REPO
export EVENT_NAME=issue_comment
export ISSUE_NUMBER=123
export PR_NUMBER=123
export COMMENT_ID=900
export COMMENT_BODY=recheck
export COMMENT_CREATED_AT=2026-09-01T08:00:00Z
export COMMENT_AUTHOR_ID=300
export COMMENT_AUTHOR_LOGIN=contributor
export COMMENT_AUTHOR_TYPE=User
export COMMENT_AUTHOR_ASSOCIATION=NONE
export WORKFLOW_PATH=.github/workflows/cla.yml
workflow_sha="$(git -C "${repo_root}" rev-parse HEAD)"
export WORKFLOW_SHA="${workflow_sha}"
export CLA_GENERATION=v2.2-action-212a0f2dd659b24b48a30ba35966e06dc41736af
export TARGET_EVENT=pull_request_target
export TARGET_BASE_REF=main
export SIGNATURE_RECORDED=false

assert_lock_permissions() {
  ruby - "${repo_root}/.github/workflows/cla.yml" <<'RUBY'
require "yaml"

workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
permissions = workflow.fetch("jobs").fetch("LockMergedPullRequest").fetch("permissions")
expected = {"contents" => "read", "issues" => "write", "pull-requests" => "write"}
abort "unexpected LockMergedPullRequest permissions: #{permissions.inspect}" unless permissions == expected
RUBY
}

assert_lock_permissions

gh() {
  local endpoint="" arg
  for arg in "$@"; do
    [[ "${arg}" == repos/* ]] && endpoint="${arg}"
  done
  [[ -n "${endpoint}" ]] || { echo "missing endpoint" >&2; return 1; }
  if [[ " $* " == *" --method POST "* ]]; then
    printf '%s\n' "${endpoint}" >>"${POSTS_FILE}"
    return 0
  fi
  local source_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  local base_sha=cccccccccccccccccccccccccccccccccccccccc
  local mismatch_sha=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  local run_sha="${base_sha}"
  local run_path=.github/workflows/cla.yml
  local run_name='CLA Assistant v3'
  local run_prs
  run_prs="[{\"number\":123,\"base\":{\"ref\":\"main\",\"sha\":\"${base_sha}\",\"repo\":{\"id\":100,\"full_name\":\"${GH_REPO}\"}},\"head\":{\"ref\":\"feature\",\"sha\":\"${source_sha}\",\"repo\":{\"id\":200,\"full_name\":\"contributor/${GH_REPO#*/}\"}}}]"
  local run_head_repository='{"id":200,"full_name":"contributor/cmux-skills"}'
  run_head_repository="{\"id\":200,\"full_name\":\"contributor/${GH_REPO#*/}\"}"
  local check_app_id=15368
  local check_details="https://github.com/${GH_REPO}/actions/runs/400/job/500"
  local check_name='CLA Assistant v3'
  local assistant_generation='CLA generation v2.2-action-212a0f2dd659b24b48a30ba35966e06dc41736af'
  local compatibility_only=false
  local check_lookup_sha="${base_sha}"
  local check_head_sha="${base_sha}"
  local repo_prefix="repos/${GH_REPO}"
  case "${FAKE_MODE:-normal}" in
    base-empty)
      run_prs='[]'
      ;;
    populated-base-mismatch)
      run_prs="$(jq -c --arg mismatch "${mismatch_sha}" 'map(.base.sha = $mismatch)' <<<"${run_prs}")"
      ;;
    fallback-null)
      run_prs='[]'
      run_head_repository=null
      run_sha="${mismatch_sha}"
      check_lookup_sha="${source_sha}"
      check_head_sha="${source_sha}"
      ;;
    fallback-base-mismatch)
      run_prs='[]'
      run_sha="${mismatch_sha}"
      check_lookup_sha="${source_sha}"
      check_head_sha="${mismatch_sha}"
      ;;
    wrong-app)
      check_app_id=999
      ;;
    wrong-details)
      check_details="https://github.com/${GH_REPO}/actions/runs/400/job/999"
      ;;
    compatibility-only)
      compatibility_only=true
      check_name='CLA Assistant'
      check_details="https://github.com/${GH_REPO}/actions/runs/400/job/501"
      ;;
    compatibility-stale-generation)
      compatibility_only=true
      check_name='CLA Assistant'
      check_details="https://github.com/${GH_REPO}/actions/runs/400/job/501"
      assistant_generation='CLA generation v2.1-action-old'
      ;;
    compatibility-wrong-details)
      compatibility_only=true
      check_name='CLA Assistant'
      check_details="https://github.com/${GH_REPO}/actions/runs/400/job/999"
      ;;
    suffix-path)
      run_path=.github/workflows/cla.yml@main
      ;;
    normal) ;;
    *) echo "unexpected fake mode ${FAKE_MODE:-}" >&2; return 1 ;;
  esac
  case "${endpoint}" in
    "${repo_prefix}/issues/123")
      jq -nc --arg url "https://api.github.com/repos/${GH_REPO}/pulls/123" '{state:"open",pull_request:{url:$url}}'
      ;;
    "${repo_prefix}/issues/comments/900")
      jq -nc --arg issue_url "https://api.github.com/repos/${GH_REPO}/issues/123" --arg body "${COMMENT_BODY}" --argjson id "${COMMENT_AUTHOR_ID}" --arg login "${COMMENT_AUTHOR_LOGIN}" --arg type "${COMMENT_AUTHOR_TYPE}" --arg created "${COMMENT_CREATED_AT}" '{issue_url:$issue_url,body:$body,user:{id:$id,login:$login,type:$type},created_at:$created,updated_at:$created}'
      ;;
    "${repo_prefix}/pulls/123")
      jq -nc --arg repo "${GH_REPO}" --arg source_sha "${source_sha}" --arg base_sha "${base_sha}" --arg head_repo "contributor/${GH_REPO#*/}" '{number:123,state:"open",user:{id:300,login:"contributor"},base:{ref:"main",sha:$base_sha,repo:{id:100,full_name:$repo}},head:{ref:"feature",sha:$source_sha,repo:{id:200,full_name:$head_repo}}}'
      ;;
    "${repo_prefix}/commits/"*/pulls)
      printf '[]\n'
      ;;
    "${repo_prefix}/pulls")
      jq -nc --arg repo "${GH_REPO}" --arg source_sha "${source_sha}" --arg base_sha "${base_sha}" --arg head_repo "contributor/${GH_REPO#*/}" '{number:123,state:"open",base:{ref:"main",sha:$base_sha,repo:{id:100,full_name:$repo}},head:{ref:"feature",sha:$source_sha,repo:{id:200,full_name:$head_repo}}}' | jq -sc .
      ;;
    "${repo_prefix}/actions/workflows")
      jq -nc '{workflows:[{id:300,path:".github/workflows/cla.yml",state:"active"}]}'
      ;;
    "${repo_prefix}/actions/workflows/300/runs")
      jq -nc --arg path "${run_path}" --arg name "${run_name}" --arg sha "${run_sha}" --argjson prs "${run_prs}" --argjson head_repo "${run_head_repository}" '{workflow_runs:[{id:400,workflow_id:300,name:$name,path:$path,event:"pull_request_target",status:"completed",conclusion:"failure",head_sha:$sha,head_branch:"feature",head_repository:$head_repo,pull_requests:$prs,created_at:"2026-09-01T07:00:00Z"}]}'
      ;;
    "${repo_prefix}/actions/runs/400")
      jq -nc --arg path "${run_path}" --arg name "${run_name}" --arg sha "${run_sha}" --argjson prs "${run_prs}" --argjson head_repo "${run_head_repository}" '{id:400,workflow_id:300,name:$name,path:$path,event:"pull_request_target",status:"completed",conclusion:"failure",head_sha:$sha,head_branch:"feature",head_repository:$head_repo,pull_requests:$prs,created_at:"2026-09-01T07:00:00Z"}'
      ;;
    "${repo_prefix}/actions/runs/400/jobs")
      if [[ "${compatibility_only}" == true ]]; then
        jq -nc --arg sha "${run_sha}" --arg generation "${assistant_generation}" '{jobs:[{id:500,run_id:400,name:"CLA Assistant v3",workflow_name:"CLA Assistant v3",workflow_id:300,status:"completed",conclusion:"success",head_sha:$sha,head_repository:null,steps:[{name:$generation,status:"completed",conclusion:"success"}]},{id:501,run_id:400,name:"CLA Assistant",workflow_name:"CLA Assistant v3",workflow_id:300,status:"completed",conclusion:"failure",head_sha:$sha,head_repository:null,steps:[{name:"Mirror CLA Assistant compatibility result",status:"completed",conclusion:"failure"}]}]}'
      else
        jq -nc --arg sha "${run_sha}" --arg generation "${assistant_generation}" '{jobs:[{id:500,run_id:400,name:"CLA Assistant v3",workflow_name:"CLA Assistant v3",workflow_id:300,status:"completed",conclusion:"failure",head_sha:$sha,head_repository:null,steps:[{name:$generation,status:"completed",conclusion:"failure"}]}]}'
      fi
      ;;
    "${repo_prefix}/actions/jobs/500")
      local assistant_conclusion='failure'
      [[ "${compatibility_only}" == true ]] && assistant_conclusion='success'
      jq -nc --arg sha "${run_sha}" --arg generation "${assistant_generation}" --arg conclusion "${assistant_conclusion}" '{id:500,run_id:400,name:"CLA Assistant v3",workflow_name:"CLA Assistant v3",workflow_id:300,status:"completed",conclusion:$conclusion,head_sha:$sha,head_repository:null,steps:[{name:$generation,status:"completed",conclusion:$conclusion}]}'
      ;;
    "${repo_prefix}/actions/jobs/501")
      jq -nc --arg sha "${run_sha}" '{id:501,run_id:400,name:"CLA Assistant",workflow_name:"CLA Assistant v3",workflow_id:300,status:"completed",conclusion:"failure",head_sha:$sha,head_repository:null,steps:[{name:"Mirror CLA Assistant compatibility result",status:"completed",conclusion:"failure"}]}'
      ;;
    "${repo_prefix}/commits/"*/check-runs)
      local commit_prefix="${repo_prefix}/commits/"
      local requested_sha="${endpoint#"${commit_prefix}"}"
      requested_sha="${requested_sha%/check-runs}"
      [[ "${requested_sha}" == "${check_lookup_sha}" ]] || {
        echo "helper queried ${requested_sha}, expected ${check_lookup_sha}" >&2
        return 1
      }
      jq -nc --arg details "${check_details}" --argjson app_id "${check_app_id}" --arg head_sha "${check_head_sha}" --arg name "${check_name}" '{total_count:1,check_runs:[{id:9000,name:$name,status:"completed",conclusion:"failure",head_sha:$head_sha,app:{id:$app_id,slug:"github-actions"},details_url:$details}]}'
      ;;
    *) echo "unexpected endpoint ${endpoint}" >&2; return 1 ;;
  esac
}
export -f gh

run_case() {
  local mode="$1" expected_status="$2" expected_posts="$3" expected_endpoint="${4:-}"
  : >"${work}/posts"
  set +e
  output="$(FAKE_MODE="${mode}" POSTS_FILE="${work}/posts" bash "${script}" 2>&1)"
  status=$?
  set -e
  posts="$(wc -l <"${work}/posts" | tr -d ' ')"
  [[ "${status}" == "${expected_status}" ]] || { printf 'FAIL %s: status %s\n%s\n' "${mode}" "${status}" "${output}" >&2; exit 1; }
  [[ "${posts}" == "${expected_posts}" ]] || { printf 'FAIL %s: posts %s\n%s\n' "${mode}" "${posts}" "${output}" >&2; exit 1; }
  if [[ "${expected_posts}" == 1 ]]; then
    [[ "$(cat "${work}/posts")" == "${expected_endpoint}" ]] || {
      printf 'FAIL %s: endpoint %s\n%s\n' "${mode}" "$(cat "${work}/posts")" "${output}" >&2
      exit 1
    }
  fi
  printf 'PASS %s\n' "${mode}"
}

run_case normal 0 1 "repos/${GH_REPO}/actions/jobs/500/rerun"
run_case base-empty 0 1 "repos/${GH_REPO}/actions/jobs/500/rerun"
run_case populated-base-mismatch 1 0
run_case fallback-null 1 0
run_case fallback-base-mismatch 1 0
run_case wrong-app 1 0
run_case wrong-details 1 0
run_case suffix-path 0 0
run_case compatibility-only 0 1 "repos/${GH_REPO}/actions/runs/400/rerun-failed-jobs"
run_case compatibility-stale-generation 1 0
run_case compatibility-wrong-details 1 0
