#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="${repo_root}/.github/scripts/rerun-failed-cla.sh"
work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

export GH_REPO=manaflow-ai/cmux-skills
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
  local run_sha=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  local run_path=.github/workflows/cla.yml
  local run_name='CLA Assistant v3'
  local run_prs='[{"number":123,"base":{"ref":"main","sha":"cccccccccccccccccccccccccccccccccccccccc","repo":{"id":100,"full_name":"manaflow-ai/cmux-skills"}},"head":{"ref":"feature","sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","repo":{"id":200,"full_name":"contributor/cmux-skills"}}}]'
  local run_head_repository='{"id":200,"full_name":"contributor/cmux-skills"}'
  local check_app_id=15368
  local check_details='https://github.com/manaflow-ai/cmux-skills/actions/runs/400/job/500'
  if [[ "${FAKE_MODE:-}" == fallback-null ]]; then
    run_prs='[]'
    run_head_repository=null
  elif [[ "${FAKE_MODE:-}" == wrong-app ]]; then
    check_app_id=999
  elif [[ "${FAKE_MODE:-}" == wrong-details ]]; then
    check_details='https://github.com/manaflow-ai/cmux-skills/actions/runs/400/job/999'
  elif [[ "${FAKE_MODE:-}" == suffix-path ]]; then
    run_path=.github/workflows/cla.yml@main
  fi
  case "${endpoint}" in
    repos/manaflow-ai/cmux-skills/issues/123)
      jq -nc '{state:"open",pull_request:{url:"https://api.github.com/repos/manaflow-ai/cmux-skills/pulls/123"}}'
      ;;
    repos/manaflow-ai/cmux-skills/issues/comments/900)
      jq -nc --arg body "${COMMENT_BODY}" --argjson id "${COMMENT_AUTHOR_ID}" --arg login "${COMMENT_AUTHOR_LOGIN}" --arg type "${COMMENT_AUTHOR_TYPE}" --arg created "${COMMENT_CREATED_AT}" '{issue_url:"https://api.github.com/repos/manaflow-ai/cmux-skills/issues/123",body:$body,user:{id:$id,login:$login,type:$type},created_at:$created,updated_at:$created}'
      ;;
    repos/manaflow-ai/cmux-skills/pulls/123)
      jq -nc '{number:123,state:"open",user:{id:300,login:"contributor"},base:{ref:"main",sha:"cccccccccccccccccccccccccccccccccccccccc",repo:{id:100,full_name:"manaflow-ai/cmux-skills"}},head:{ref:"feature",sha:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",repo:{id:200,full_name:"contributor/cmux-skills"}}}'
      ;;
    repos/manaflow-ai/cmux-skills/commits/*/pulls)
      printf '[]\n'
      ;;
    repos/manaflow-ai/cmux-skills/pulls)
      jq -nc '{number:123,state:"open",base:{ref:"main",sha:"cccccccccccccccccccccccccccccccccccccccc",repo:{id:100,full_name:"manaflow-ai/cmux-skills"}},head:{ref:"feature",sha:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",repo:{id:200,full_name:"contributor/cmux-skills"}}}' | jq -sc .
      ;;
    repos/manaflow-ai/cmux-skills/actions/workflows)
      jq -nc '{workflows:[{id:300,path:".github/workflows/cla.yml",state:"active"}]}'
      ;;
    repos/manaflow-ai/cmux-skills/actions/workflows/300/runs)
      jq -nc --arg path "${run_path}" --arg name "${run_name}" --arg sha "${run_sha}" --argjson prs "${run_prs}" --argjson head_repo "${run_head_repository}" '{workflow_runs:[{id:400,workflow_id:300,name:$name,path:$path,event:"pull_request_target",status:"completed",conclusion:"failure",head_sha:$sha,head_branch:"feature",head_repository:$head_repo,pull_requests:$prs,created_at:"2026-09-01T07:00:00Z"}]}'
      ;;
    repos/manaflow-ai/cmux-skills/actions/runs/400)
      jq -nc --arg path "${run_path}" --arg name "${run_name}" --arg sha "${run_sha}" --argjson prs "${run_prs}" --argjson head_repo "${run_head_repository}" '{id:400,workflow_id:300,name:$name,path:$path,event:"pull_request_target",status:"completed",conclusion:"failure",head_sha:$sha,head_branch:"feature",head_repository:$head_repo,pull_requests:$prs,created_at:"2026-09-01T07:00:00Z"}'
      ;;
    repos/manaflow-ai/cmux-skills/actions/runs/400/jobs)
      jq -nc --arg sha "${run_sha}" '{jobs:[{id:500,run_id:400,name:"CLA Assistant v3",workflow_name:"CLA Assistant v3",workflow_id:300,status:"completed",conclusion:"failure",head_sha:$sha,head_repository:null,steps:[{name:"CLA generation v2.2-action-212a0f2dd659b24b48a30ba35966e06dc41736af",status:"completed",conclusion:"failure"}]}]}'
      ;;
    repos/manaflow-ai/cmux-skills/actions/jobs/500)
      jq -nc --arg sha "${run_sha}" '{id:500,run_id:400,name:"CLA Assistant v3",workflow_name:"CLA Assistant v3",workflow_id:300,status:"completed",conclusion:"failure",head_sha:$sha,head_repository:null,steps:[{name:"CLA generation v2.2-action-212a0f2dd659b24b48a30ba35966e06dc41736af",status:"completed",conclusion:"failure"}]}'
      ;;
    repos/manaflow-ai/cmux-skills/commits/*/check-runs)
      jq -nc --arg details "${check_details}" --argjson app_id "${check_app_id}" '{total_count:1,check_runs:[{id:9000,name:"CLA Assistant v3",status:"completed",conclusion:"failure",head_sha:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",app:{id:$app_id,slug:"github-actions"},details_url:$details}]}'
      ;;
    *) echo "unexpected endpoint ${endpoint}" >&2; return 1 ;;
  esac
}
export -f gh

run_case() {
  local mode="$1" expected_status="$2" expected_posts="$3"
  : >"${work}/posts"
  set +e
  output="$(FAKE_MODE="${mode}" POSTS_FILE="${work}/posts" bash "${script}" 2>&1)"
  status=$?
  set -e
  posts="$(wc -l <"${work}/posts" | tr -d ' ')"
  [[ "${status}" == "${expected_status}" ]] || { printf 'FAIL %s: status %s\n%s\n' "${mode}" "${status}" "${output}" >&2; exit 1; }
  [[ "${posts}" == "${expected_posts}" ]] || { printf 'FAIL %s: posts %s\n%s\n' "${mode}" "${posts}" "${output}" >&2; exit 1; }
  printf 'PASS %s\n' "${mode}"
}

run_case normal 0 1
run_case fallback-null 0 1
run_case wrong-app 1 0
run_case wrong-details 1 0
run_case suffix-path 0 0
