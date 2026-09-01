#!/usr/bin/env ruby

require "digest"
require "json"
require "open3"
require "time"

ROOT = File.expand_path("../../../", __dir__)
AUDIT = File.join(ROOT, ".codex/runtime/ci-governance-release-recovery-audit-20260820")
AUDITOR = "/root"
REVIEWER = "PENDING"
STARTED_AT = "2026-08-20T04:46:21+08:00"
FINISHED_AT = ENV.fetch("AUDIT_FINISHED_AT", Time.now.iso8601)

# These are the only ranges that were directly read during this audit. An
# excerpt is deliberately kept BLOCKED so it cannot be mistaken for a full read.
FULL_PATHS = %w[
  AGENTS.md
  core/AGENTS.md
  apps/macos/AGENTS.md
  workflow/AGENTS.md
  CODE_REVIEW.md
  SECURITY.md
  .github/CODEOWNERS
  .github/PULL_REQUEST_TEMPLATE.md
  .github/workflows/core-ci.yml
  .github/workflows/governance-ci.yml
  .github/workflows/macos-ci.yml
  .github/workflows/remote-governance.yml
  .github/workflows/release-evidence.yml
  docs/development/ci-governance.md
  docs/development/release.md
  docs/development/recovery.md
  docs/development/testing.md
  docs/development/dependency-policy.md
  docs/governance/enterprise-workflow-baseline.md
  docs/governance/operations-lifecycle.md
  workflow/residuals/README.md
  workflow/residuals/schema.md
  workflow/residuals/residuals.yaml
  workflow/versions/v1-mvp/residuals/README.md
  workflow/versions/v1-mvp/residuals/residuals.yaml
  workflow/versions/v2/residuals/README.md
  workflow/versions/v2/residuals/residuals.yaml
  workflow/versions/v1-mvp/execution/README.md
  workflow/versions/v1-mvp/execution/_shared/engineering-quality-rules.md
  workflow/versions/v1-mvp/execution/_shared/prompt_pipeline.py
  workflow/versions/v1-mvp/evidence/release-checklist.md
  workflow/versions/v1-mvp/evidence/distribution-signing-notarization.md
  workflow/versions/v1-mvp/evidence/recovery-scenarios.md
  workflow/versions/v1-mvp/evidence/final-tag-release-evidence.md
  workflow/versions/v1-mvp/evidence/alpha-feedback-route.md
  workflow/versions/v1-mvp/evidence/icloud-placeholder-smoke-evidence.md
  workflow/versions/v1-mvp/closeout/closeout.yaml
  workflow/versions/v1-mvp/closeout/closeout-decision.md
  workflow/versions/v1-mvp/closeout/checkpoint-gaps.md
  tasks/indexes/residuals.md
  CHANGELOG.md
  .ai-governance/workflows/prompt-task-runtime.md
  .ai-governance/workflows/external-capability-admission.md
  .ai-governance/workflows/subagent-boundaries.md
  .codex/skills-src/areamatrix-enterprise-governance/SKILL.md
  .codex/skills-src/areamatrix-validation-driver/SKILL.md
  .codex/skills-src/areamatrix-git-checkpoint/SKILL.md
  .codex/skills-src/areamatrix-residual-ledger/SKILL.md
  .codex/skills-src/areamatrix-task-loop/SKILL.md
  .codex/skills-src/areamatrix-file-safety/SKILL.md
  .codex/skills-src/areamatrix-doc-sync/SKILL.md
  .cursor/skills/areamatrix-pre-push-review/SKILL.md
  .cursor/rules/areamatrix-cursor-workflow.mdc
  .cursor/hooks/guard-live-mainline.sh
  .cursor/hooks/stop-closeout.sh
  scripts/task_loop/git.py
  scripts/dev_tools/remote_governance.py
  scripts/dev_tools/core_sdk_artifact.py
  scripts/dev_tools/release.py
  scripts/dev_tools/release_status.py
  scripts/dev_tools/governance_status.py
]

PARTIAL_RANGES = {
  "docs/governance/governance-register.yaml" => [[1, 260], [1340, 1387]],
  "scripts/dev_tools/checks.py" => [[80, 160], [390, 450], [1340, 1387], [1950, 2005]],
  "scripts/dev_tools/cli.py" => [[147, 166], [980, 1030]],
  "scripts/dev_tools/workflow.py" => [[63, 79], [221, 236]],
  "scripts/task_loop/runner.py" => [[760, 890], [1500, 1570], [1590, 1675], [1800, 1900]],
  "scripts/task_loop/state.py" => [[68, 69]],
  "scripts/task_loop/lifecycle.py" => [],
  "scripts/task_loop/actions.py" => [],
  "scripts/task_loop/console.py" => [],
  "scripts/task_loop/self_check.py" => [[1283, 1308], [1357, 1360], [1890, 1896]],
  "scripts/task_loop/cli.py" => [],
  "scripts/task_loop/dev_config.py" => [],
  "workflow/versions/v1-mvp/execution/_shared/prompt_pipeline_lib/commands.py" => [[160, 225], [387, 391]],
  "workflow/versions/v1-mvp/execution/_shared/prompt_pipeline_lib/repository.py" => [[185, 240]],
  "workflow/versions/v1-mvp/execution/_shared/prompt_pipeline_lib/rendering.py" => [[429, 432]],
  "workflow/versions/v1-mvp/execution/_shared/prompt_pipeline_lib/failure_recovery.py" => [],
  ".ai-governance/workflows/cursor-adapter-layer.md" => [],
  ".codex/skills-src/areamatrix-task-loop/references/failure-recovery.md" => [],
  ".codex/skills-src/areamatrix-task-loop/references/runbook.md" => [],
  ".codex/skills-src/areamatrix-git-checkpoint/references/checkpoint-policy.md" => [],
  ".codex/skills-src/areamatrix-git-checkpoint/references/review-checklist.md" => [],
  ".codex/skills-src/areamatrix-enterprise-governance/references/governance-map.md" => [],
  ".codex/skills-src/areamatrix-enterprise-governance/references/review-security-ci.md" => [],
  "core/tests/recovery_scenarios.rs" => [[218, 247]],
  "core/tests/release_evidence_checklist.rs" => [[1, 220]],
  "scripts/dev_tools/test_release_tools.py" => [[479, 487], [930, 940], [1512, 1518], [1641, 1682]],
}

FINDING_IDS = {
  ".github/workflows/core-ci.yml" => ["F-CI-005"],
  ".github/workflows/macos-ci.yml" => ["F-CI-005"],
  ".github/workflows/remote-governance.yml" => ["F-CI-002", "F-CI-004"],
  ".github/workflows/release-evidence.yml" => ["F-CI-001", "F-CI-003"],
  "docs/development/release.md" => ["F-REL-002", "F-REL-003"],
  "workflow/versions/v1-mvp/evidence/distribution-signing-notarization.md" => ["F-REL-001", "F-REL-002"],
  "workflow/versions/v1-mvp/evidence/recovery-scenarios.md" => ["F-REC-001"],
  "workflow/versions/v1-mvp/evidence/release-checklist.md" => ["F-REMOTE-001"],
  "scripts/dev_tools/release_status.py" => ["F-REL-001", "F-REL-003"],
  "scripts/task_loop/git.py" => ["F-GOV-001"],
  "workflow/versions/v1-mvp/execution/_shared/prompt_pipeline_lib/commands.py" => ["F-GOV-002"],
  "workflow/versions/v1-mvp/execution/_shared/prompt_pipeline_lib/repository.py" => ["F-GOV-002"],
  "scripts/task_loop/runner.py" => ["F-GOV-001"],
  ".ai-governance/workflows/prompt-task-runtime.md" => ["F-GOV-003"],
  "core/tests/recovery_scenarios.rs" => ["F-REC-001"],
  "apps/macos/AreaMatrix/Bridge/UniFFI/libarea_matrix_core.a" => ["F-SC-001"],
  "docs/development/build.md" => ["F-SC-001"],
  "apps/macos/AreaMatrix.xcodeproj/project.pbxproj" => ["F-SC-001"],
}

def git_provenance(path)
  out, status = Open3.capture2("git", "log", "-1", "--format=%H%x00%cI", "--", path)
  return {"last_commit" => nil, "commit_time" => nil, "git_lookup_status" => status.exitstatus} unless status.success?
  commit, time = out.strip.split("\0", 2)
  {"last_commit" => commit, "commit_time" => time, "git_lookup_status" => 0}
end

def digest_for(path, symlink)
  return Digest::SHA256.hexdigest(File.readlink(path)) if symlink
  Digest::SHA256.file(path).hexdigest
end

def line_interval(start_line, end_line, method)
  {"start" => start_line, "end" => end_line, "method" => method}
end

inventory_path = File.join(AUDIT, "inventory.jsonl")
rows = File.readlines(inventory_path, chomp: true).reject(&:empty?).map { |line| JSON.parse(line) }
inventory_paths = rows.map { |row| row.fetch("path") }
missing_manual_map = (FULL_PATHS + PARTIAL_RANGES.keys).uniq - inventory_paths
warn("manual coverage paths absent from inventory: #{missing_manual_map.join(', ')}") unless missing_manual_map.empty?

updated_rows = []
coverage_rows = []
rows.each do |row|
  path = row.fetch("path")
  absolute = File.join(ROOT, path)
  kind = row.fetch("file_kind")
  finding_ids = FINDING_IDS.fetch(path, [])
  intervals = []
  status = "BLOCKED"
  review_method = "not_read"
  notes = []
  provenance = {}

  if kind == "text"
    if FULL_PATHS.include?(path) && File.file?(absolute)
      line_count = row["line_count"]
      if line_count
        intervals = [line_interval(1, line_count, "direct_read")]
        status = finding_ids.empty? ? "PASS" : "FINDING"
        review_method = "direct_read_full_file"
      else
        notes << "line_count_missing"
      end
    elsif PARTIAL_RANGES.key?(path)
      intervals = PARTIAL_RANGES.fetch(path).map { |range| line_interval(range[0], range[1], "excerpt_or_rg") }
      notes << "unread_lines_remain"
      review_method = intervals.empty? ? "path_or_keyword_only" : "excerpt_only"
    else
      notes << "no_manual_line_coverage_recorded"
    end
  elsif kind == "binary-or-opaque"
    provenance = git_provenance(path)
    provenance["current_sha256"] = File.file?(absolute) ? digest_for(absolute, false) : nil
    provenance["signature_metadata"] = "not_run_in_read_only_audit"
    provenance["generation_timestamp"] = provenance["commit_time"]
    if path.end_with?(".dmg")
      status = "BLOCKED"
      provenance["artifact_role"] = "release_artifact_candidate"
      provenance["documented_generation_command"] = "hdiutil/codesign/notarytool/stapler (not executed)"
      notes << "formal_signature_notarization_staple_gate_not_independently_verified"
    elsif path.end_with?(".a")
      status = "BLOCKED"
      provenance["artifact_role"] = "tracked_compiled_static_library"
      provenance["documented_generation_command"] = "./dev build core; documented output is Bridge/Generated, not this tracked path"
      notes << "opaque_binary_source_fingerprint_and_consumer_binding_not_proven"
    else
      status = "NOT_APPLICABLE"
      provenance["artifact_role"] = "tracked_product_asset"
      provenance["documented_generation_command"] = path.start_with?("assets/brand/") ? "python3 scripts/brand/export_assets.py --refresh" : nil
      provenance["evidence_use"] = false
      provenance["signature_metadata"] = "not_applicable_non_release_asset"
      notes << "binary_asset_not_line_read; checksum_and_git_provenance_recorded"
    end
  elsif kind == "symlink"
    provenance = git_provenance(path)
    target = File.readlink(absolute) rescue nil
    resolved = target ? File.expand_path(target, File.dirname(absolute)) : nil
    within_root = resolved && (resolved == ROOT || resolved.start_with?(ROOT + File::SEPARATOR))
    provenance["link_target"] = target
    provenance["target_exists"] = !!(resolved && File.exist?(resolved))
    provenance["target_within_repository"] = !!within_root
    provenance["current_sha256"] = File.symlink?(absolute) ? digest_for(absolute, true) : nil
    if target && provenance["target_exists"]
      status = "NOT_APPLICABLE"
      notes << "symlink_provenance_checked; target reviewed as a separate inventory path"
    else
      status = "BLOCKED"
      notes << "broken_or_unresolved_symlink"
    end
  end

  if File.exist?(absolute) || File.symlink?(absolute)
    current_sha = digest_for(absolute, kind == "symlink")
    row["current_sha256"] = current_sha
    row["scope_drift"] = current_sha == row["sha256"] ? "unchanged" : "content_changed_after_snapshot"
    if row["scope_drift"] != "unchanged"
      status = "BLOCKED"
      notes << "snapshot_hash_changed_after_initial_inventory"
    end
  else
    row["scope_drift"] = "missing_at_finalize"
    status = "BLOCKED"
    notes << "path_missing_at_finalize"
  end

  notes << "finding_ids=#{finding_ids.join(',')}" unless finding_ids.empty?
  row.merge!(
    "status" => status,
    "reviewer" => REVIEWER,
    "auditor" => AUDITOR,
    "started_at" => STARTED_AT,
    "completed_at" => FINISHED_AT,
    "manual_line_intervals" => intervals,
    "manual_review_method" => review_method,
    "finding_ids" => finding_ids,
    "provenance" => provenance,
    "notes" => notes.join("; "),
  )
  updated_rows << row
  coverage_rows << {
    "record_type" => "file",
    "path" => path,
    "file_kind" => kind,
    "source_state" => row["source_state"],
    "category" => row["category"],
    "gate" => row["gate"],
    "owner" => row["owner"],
    "manual_line_intervals" => intervals,
    "status" => status,
    "finding_ids" => finding_ids,
    "auditor" => AUDITOR,
    "reviewer" => REVIEWER,
    "started_at" => STARTED_AT,
    "completed_at" => FINISHED_AT,
    "review_method" => review_method,
    "scope_drift" => row["scope_drift"],
    "notes" => notes.join("; "),
  }
end

status_counts = coverage_rows.group_by { |row| row["status"] }.transform_values(&:length)
current_paths = Open3.capture2("git", "ls-files", "-z", "-co", "--exclude-standard").first
  .split("\0")
  .reject { |path| path.empty? || path.start_with?(".codex/runtime/ci-governance-release-recovery-audit-20260820/") }
initial_path_set = rows.map { |row| row.fetch("path") }.to_h { |path| [path, true] }
current_path_set = current_paths.to_h { |path| [path, true] }
drift_paths = {
  "added" => (current_path_set.keys - initial_path_set.keys).sort,
  "removed" => (initial_path_set.keys - current_path_set.keys).sort,
  "changed" => updated_rows.map do |row|
    row["path"] if row["scope_drift"] == "content_changed_after_snapshot"
  end.compact.sort,
}
header = {
  "record_type" => "ledger_header",
  "audit_id" => "ci-governance-release-recovery-audit-20260820",
  "status" => "BLOCKED",
  "auditor" => AUDITOR,
  "reviewer" => REVIEWER,
  "started_at" => STARTED_AT,
  "completed_at" => FINISHED_AT,
  "scope_snapshot_files" => rows.length,
  "coverage_records" => coverage_rows.length,
  "status_counts" => status_counts,
  "manual_review_complete" => false,
  "scope_drift" => {
    "initial_paths" => rows.length,
    "current_paths_excluding_audit_output" => current_paths.length,
    "added_count" => drift_paths["added"].length,
    "removed_count" => drift_paths["removed"].length,
    "changed_count" => drift_paths["changed"].length,
    "added_paths" => drift_paths["added"],
    "removed_paths" => drift_paths["removed"],
    "changed_paths" => drift_paths["changed"],
  },
  "reason" => "unread text ranges, external evidence, and scope drift remain",
}

def atomic_write(path, content)
  temporary = "#{path}.tmp.#{$$}"
  File.write(temporary, content)
  File.rename(temporary, path)
ensure
  File.delete(temporary) if temporary && File.exist?(temporary)
end

atomic_write(inventory_path, updated_rows.map { |row| JSON.generate(row) }.join("\n") + "\n")
coverage_path = File.join(AUDIT, "coverage.jsonl")
atomic_write(coverage_path, ([header] + coverage_rows).map { |row| JSON.generate(row) }.join("\n") + "\n")
puts JSON.pretty_generate({"scope_snapshot_files" => rows.length, "coverage_records" => coverage_rows.length, "status_counts" => status_counts, "finished_at" => FINISHED_AT})
