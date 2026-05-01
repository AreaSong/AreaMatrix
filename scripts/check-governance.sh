#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

fail() {
  failures=$((failures + 1))
  printf 'ERROR: %s\n' "$*" >&2
}

check_file() {
  local path="$1"
  if [ ! -f "$ROOT_DIR/$path" ]; then
    fail "missing file: $path"
  fi
}

require_text() {
  local path="$1"
  local pattern="$2"
  local label="$3"
  if [ ! -f "$ROOT_DIR/$path" ]; then
    fail "missing file for text check: $path"
    return
  fi
  if ! grep -Eq "$pattern" "$ROOT_DIR/$path"; then
    fail "$path missing: $label"
  fi
}

forbid_text() {
  local path="$1"
  local pattern="$2"
  local label="$3"
  if [ ! -f "$ROOT_DIR/$path" ]; then
    return
  fi
  if grep -Eq "$pattern" "$ROOT_DIR/$path"; then
    fail "$path contains forbidden text: $label"
  fi
}

check_workflow_has_no_paths_filter() {
  local path="$1"
  check_file "$path"
  if grep -Eq '^[[:space:]]+paths:' "$ROOT_DIR/$path"; then
    fail "$path must not use PR/push paths filters; enterprise CI runs on every PR"
  fi
}

check_required_files() {
  local files=(
    "CODE_REVIEW.md"
    "SECURITY.md"
    "CONTRIBUTING.md"
    ".github/CODEOWNERS"
    ".github/PULL_REQUEST_TEMPLATE.md"
    ".github/ISSUE_TEMPLATE/bug_report.md"
    ".github/ISSUE_TEMPLATE/feature_request.md"
    ".github/workflows/core-ci.yml"
    ".github/workflows/macos-ci.yml"
    ".github/workflows/governance-ci.yml"
    "docs/development/coding-standards.md"
    "docs/development/testing.md"
    "docs/development/git-workflow.md"
    "docs/development/dependency-policy.md"
    "docs/development/ci-governance.md"
    "tasks/prompts/_shared/engineering-quality-rules.md"
  )

  local file
  for file in "${files[@]}"; do
    check_file "$file"
  done
}

check_security_policy() {
  require_text "SECURITY.md" "GitHub Security Advisory" "private security advisory reporting"
  forbid_text "SECURITY.md" "security@<your-domain>" "placeholder security email"
}

check_codeowners() {
  require_text ".github/CODEOWNERS" "@AreaMatrix/maintainers" "AreaMatrix maintainers owner placeholder"
  require_text ".github/CODEOWNERS" "TODO: Replace @AreaMatrix/maintainers" "replacement note for placeholder owner"
}

check_pr_template() {
  require_text ".github/PULL_REQUEST_TEMPLATE.md" "安全与风险|Security and Risk" "security and risk section"
  require_text ".github/PULL_REQUEST_TEMPLATE.md" "依赖 / 许可证 / 供应链" "dependency/license/supply-chain section"
  require_text ".github/PULL_REQUEST_TEMPLATE.md" "Task-loop Evidence" "task-loop evidence section"
  require_text ".github/PULL_REQUEST_TEMPLATE.md" "CODEOWNERS" "CODEOWNERS checklist"
  require_text ".github/PULL_REQUEST_TEMPLATE.md" "rollback|回滚" "rollback checklist"
}

check_issue_templates() {
  require_text ".github/ISSUE_TEMPLATE/bug_report.md" "数据安全影响|Data Safety Impact" "bug data safety section"
  require_text ".github/ISSUE_TEMPLATE/bug_report.md" "Security Advisory" "private security disclosure reminder"
  require_text ".github/ISSUE_TEMPLATE/feature_request.md" "本地优先|Local-first" "feature local-first section"
  require_text ".github/ISSUE_TEMPLATE/feature_request.md" "FSEvents|iCloud|staging|reindex" "feature filesystem risk prompts"
}

check_docs_navigation() {
  require_text "CONTRIBUTING.md" "CODE_REVIEW.md" "code review entry"
  require_text "CONTRIBUTING.md" "dependency-policy.md" "dependency policy entry"
  require_text "CONTRIBUTING.md" "ci-governance.md" "CI governance entry"
  require_text "docs/README.md" "dependency-policy.md" "dependency policy docs navigation"
  require_text "docs/README.md" "ci-governance.md" "CI governance docs navigation"
  require_text ".ai-governance/README.md" "CODE_REVIEW.md" "code review governance entry"
  require_text ".codex/references/index.md" "CODE_REVIEW.md" "code review Codex index entry"
}

check_prompt_and_skills() {
  require_text "tasks/prompts/_shared/engineering-quality-rules.md" "CODE_REVIEW.md" "enterprise review gate"
  require_text "tasks/prompts/_shared/engineering-quality-rules.md" "dependency-policy.md" "dependency gate"
  require_text ".codex/skills-src/areamatrix-enterprise-governance/SKILL.md" "areamatrix-enterprise-governance" "enterprise governance skill"
  require_text ".codex/skills-src/areamatrix-validation-driver/SKILL.md" "CODE_REVIEW.md" "validation driver enterprise references"
  require_text ".codex/skills-src/areamatrix-git-checkpoint/SKILL.md" "CODE_REVIEW.md" "git checkpoint review references"
}

check_workflows() {
  check_workflow_has_no_paths_filter ".github/workflows/core-ci.yml"
  check_workflow_has_no_paths_filter ".github/workflows/macos-ci.yml"
  require_text ".github/workflows/governance-ci.yml" "check-governance.sh" "governance check"
  require_text ".github/workflows/governance-ci.yml" "check-skills.sh" "skill health"
  require_text ".github/workflows/governance-ci.yml" "check-task-loop.sh" "task-loop health"
  require_text ".github/workflows/governance-ci.yml" "prompt_pipeline.py doctor" "prompt doctor"
  require_text ".github/workflows/governance-ci.yml" "git diff --check" "diff whitespace check"
}

main() {
  check_required_files
  check_security_policy
  check_codeowners
  check_pr_template
  check_issue_templates
  check_docs_navigation
  check_prompt_and_skills
  check_workflows

  if [ "$failures" -gt 0 ]; then
    printf 'governance health: FAILED (%d issue(s))\n' "$failures" >&2
    return 1
  fi

  printf 'governance health: OK\n'
}

main "$@"
