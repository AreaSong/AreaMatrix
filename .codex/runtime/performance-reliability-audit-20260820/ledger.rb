#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "open3"
require "set"
require "time"

ROOT = File.expand_path("../../..", __dir__)
AUDIT_DIR = __dir__
AUDIT_PREFIX = ".codex/runtime/performance-reliability-audit-20260820/"
INVENTORY_PATH = File.join(AUDIT_DIR, "inventory.jsonl")
COVERAGE_PATH = File.join(AUDIT_DIR, "coverage.jsonl")
SCOPE_PATH = File.join(AUDIT_DIR, "scope.json")
FINDINGS_PATH = File.join(AUDIT_DIR, "findings.jsonl")
VALID_STATUSES = %w[PENDING IN_PROGRESS PASS FINDING NOT_APPLICABLE BLOCKED].freeze
BINARY_EXTENSIONS = %w[
  .a .appiconset .bmp .dmg .gif .icns .ico .jpeg .jpg .pdf .png .sqlite3
  .tif .tiff .xcresult .zip
].freeze

def git_bytes(*args)
  output, error, status = Open3.capture3("git", *args, chdir: ROOT, binmode: true)
  raise "git #{args.join(' ')} failed: #{error}" unless status.success?

  output
end

def git_text(*args)
  git_bytes(*args).force_encoding("UTF-8")
end

def nul_paths(*args)
  git_bytes(*args).split("\0").reject(&:empty?).map { |path| path.force_encoding("UTF-8") }
end

def atomic_write(path, content)
  temporary = "#{path}.tmp-#{Process.pid}"
  File.binwrite(temporary, content)
  File.rename(temporary, path)
ensure
  FileUtils.rm_f(temporary) if defined?(temporary)
end

def repository_paths
  tracked = nul_paths("ls-files", "-z")
  untracked = nul_paths("ls-files", "--others", "--exclude-standard", "-z")
  (tracked + untracked).uniq.reject { |path| path.start_with?(AUDIT_PREFIX) }.sort
end

def tracked_paths
  nul_paths("ls-files", "-z").to_set
end

def git_modes
  nul_paths("ls-files", "-s", "-z").each_with_object({}) do |entry, result|
    metadata, path = entry.split("\t", 2)
    result[path] = metadata.split.first if path
  end
end

def dirty_paths
  unstaged = nul_paths("diff", "--name-only", "-z")
  staged = nul_paths("diff", "--cached", "--name-only", "-z")
  untracked = nul_paths("ls-files", "--others", "--exclude-standard", "-z")
  (unstaged + staged + untracked).uniq.to_set
end

def generated?(path)
  path.include?("/Bridge/UniFFI/") ||
    path.include?("/Bridge/Generated/") ||
    path.include?("/copy-ready/") ||
    path.include?("/verify-ready/") ||
    path.include?("/evidence/artifacts/") ||
    path.end_with?(".generated.swift")
end

def lockfile?(path)
  basename = File.basename(path).downcase
  basename == "cargo.lock" || basename == "package.resolved" || basename.end_with?(".lock")
end

def content_metadata(path)
  absolute = File.join(ROOT, path)
  return ["missing", 0, nil, nil, nil] unless File.exist?(absolute) || File.symlink?(absolute)

  if File.symlink?(absolute)
    target = File.readlink(absolute)
    return ["symlink", target.bytesize, 1, Digest::SHA256.hexdigest(target), "utf-8"]
  end

  digest = Digest::SHA256.new
  size = 0
  newline_count = 0
  last_byte = nil
  sample = +""
  File.open(absolute, "rb") do |file|
    while (chunk = file.read(1024 * 1024))
      digest.update(chunk)
      size += chunk.bytesize
      newline_count += chunk.count("\n")
      last_byte = chunk.getbyte(-1) unless chunk.empty?
      sample << chunk.byteslice(0, [65_536 - sample.bytesize, chunk.bytesize].min) if sample.bytesize < 65_536
    end
  end

  extension = File.extname(path).downcase
  utf8_sample = sample.dup.force_encoding("UTF-8")
  binary = BINARY_EXTENSIONS.include?(extension) || sample.include?("\0") || !utf8_sample.valid_encoding?
  encoding = binary ? "binary" : "utf-8"
  line_count = binary ? nil : (size.zero? ? 0 : newline_count + (last_byte == 10 ? 0 : 1))
  kind = if lockfile?(path)
           "lockfile"
         elsif generated?(path)
           "generated"
         elsif binary
           "binary"
         else
           extension.empty? ? "text-extensionless" : "text-#{extension.delete_prefix('.')}"
         end
  [kind, size, line_count, digest.hexdigest, encoding]
end

def json_lines(rows)
  rows.map { |row| JSON.generate(row) }.join("\n") + "\n"
end

def initialize_ledger
  existing = [SCOPE_PATH, INVENTORY_PATH, COVERAGE_PATH].select { |path| File.exist?(path) }
  raise "refusing to overwrite existing ledger: #{existing.join(', ')}" unless existing.empty?

  paths = repository_paths
  tracked = tracked_paths
  modes = git_modes
  dirty = dirty_paths
  timestamp = Time.now.getlocal.iso8601
  commit = git_text("rev-parse", "HEAD").strip
  branch = git_text("branch", "--show-current").strip

  inventory = paths.map do |path|
    kind, size, lines, sha256, encoding = content_metadata(path)
    {
      path: path,
      type: kind,
      size_bytes: size,
      line_count: lines,
      encoding: encoding,
      tracked: tracked.include?(path),
      git_mode: modes.fetch(path, "untracked"),
      working_tree_state: dirty.include?(path) ? "dirty" : "clean",
      deterministic_generated: generated?(path),
      generation_source: nil,
      content_sha256: sha256,
      snapshot_commit: commit
    }
  end

  coverage = inventory.map do |item|
    {
      path: item.fetch(:path),
      type: item.fetch(:type),
      size_bytes: item.fetch(:size_bytes),
      status: "PENDING",
      reviewed_ranges: [],
      auditor: "UNASSIGNED",
      review_status: "PENDING",
      notes: "等待人工逐行审阅或逐项不适用分类",
      evidence: [],
      content_sha256: item.fetch(:content_sha256),
      recorded_at: timestamp
    }
  end

  scope = {
    audit_id: "performance-reliability-audit-20260820",
    repository_root: ROOT,
    frozen_at: timestamp,
    snapshot_commit: commit,
    branch: branch,
    file_count: inventory.length,
    inclusion_rule: "git tracked files plus non-ignored untracked files present at audit initialization",
    exclusions: [
      { pattern: ".git/**", reason: "Git internal database, not repository content" },
      { pattern: "Git-ignored files", reason: "local build products, caches, runtime state, credentials, and other ignored workspace artifacts" },
      { pattern: "#{AUDIT_PREFIX}**", reason: "current audit outputs are excluded to avoid a self-referential moving scope" }
    ],
    dirty_paths_at_start: dirty.to_a.sort,
    allowed_statuses: VALID_STATUSES,
    coverage_semantics: "append-only events; the last event for each inventory path is the current state"
  }

  atomic_write(SCOPE_PATH, JSON.pretty_generate(scope) + "\n")
  atomic_write(INVENTORY_PATH, json_lines(inventory))
  atomic_write(COVERAGE_PATH, json_lines(coverage))
  atomic_write(FINDINGS_PATH, "") unless File.exist?(FINDINGS_PATH)
  puts JSON.generate(scope.slice(:audit_id, :snapshot_commit, :branch, :file_count, :frozen_at))
end

def append_records(input_path)
  inventory_paths = File.foreach(INVENTORY_PATH).map { |line| JSON.parse(line).fetch("path") }.to_set
  records = File.foreach(input_path).each_with_object([]) do |line, collected|
    next if line.strip.empty?

    record = JSON.parse(line)
    path = record.fetch("path")
    status = record.fetch("status")
    raise "unknown inventory path: #{path}" unless inventory_paths.include?(path)
    raise "invalid status for #{path}: #{status}" unless VALID_STATUSES.include?(status)
    raise "reviewed_ranges must be an array for #{path}" unless record.fetch("reviewed_ranges").is_a?(Array)

    record["recorded_at"] ||= Time.now.getlocal.iso8601
    collected << record
  end
  File.open(COVERAGE_PATH, "ab") { |file| file.write(json_lines(records)) } unless records.empty?
  puts JSON.generate(appended: records.length)
end

def append_tsv(input_path, auditor)
  inventory = File.foreach(INVENTORY_PATH).map { |line| JSON.parse(line) }.to_h { |item| [item.fetch("path"), item] }
  snapshot_commit = JSON.parse(File.read(SCOPE_PATH)).fetch("snapshot_commit")
  records = File.foreach(input_path).each_with_object([]) do |line, collected|
    fields = line.chomp.split("\t", -1)
    fields.shift if fields.first == "COVERAGE"
    next if fields.empty?

    path, status, ranges, review_detail, note = fields
    raise "invalid TSV row for #{path.inspect}" unless path && status && ranges
    raise "unknown inventory path: #{path}" unless inventory.key?(path)
    raise "invalid status for #{path}: #{status}" unless VALID_STATUSES.include?(status)

    if auditor == "swift_macos_opened_not_semantic"
      status = "BLOCKED" if status == "PASS"
      note = [note, "全文已打开但代理明确未完成语义性能审阅"].compact.reject(&:empty?).join("; ")
    elsif auditor == "cross_platform_scripts" && review_detail != "semantic-read"
      status = "BLOCKED" if status == "PASS"
      note = [note, "仅完成结构性打开/核对，未完成逐行语义性能审阅"].compact.reject(&:empty?).join("; ")
    end

    evidence = ["agent TSV", review_detail].compact
    if note&.include?("snapshot-read")
      item = inventory.fetch(path)
      raise "snapshot-read requires a tracked clean-at-freeze path: #{path}" unless item.fetch("tracked") && item.fetch("working_tree_state") == "clean"

      blob = git_bytes("show", "#{snapshot_commit}:#{path}")
      blob_sha = Digest::SHA256.hexdigest(blob)
      raise "snapshot blob SHA mismatch for #{path}: #{blob_sha}" unless blob_sha == item.fetch("content_sha256")

      newline_count = blob.count("\n")
      blob_lines = blob.empty? ? 0 : newline_count + (blob.getbyte(-1) == 10 ? 0 : 1)
      expected_lines = item.fetch("line_count")
      raise "snapshot blob line-count mismatch for #{path}: #{blob_lines}" unless expected_lines.nil? || blob_lines == expected_lines

      evidence << "snapshot commit blob SHA matches frozen inventory"
      evidence << "snapshot_commit=#{snapshot_commit}"
    end

    range_list = ranges == "N/A" ? [] : [ranges]
    collected << {
      "path" => path,
      "status" => status,
      "reviewed_ranges" => range_list,
      "auditor" => auditor,
      "review_status" => status,
      "notes" => [review_detail, note].compact.reject(&:empty?).join("; "),
      "evidence" => evidence,
      "recorded_at" => Time.now.getlocal.iso8601
    }
  end
  File.open(COVERAGE_PATH, "ab") { |file| file.write(json_lines(records)) } unless records.empty?
  puts JSON.generate(appended: records.length, auditor: auditor)
end

def append_non_applicable
  inventory = File.foreach(INVENTORY_PATH).map { |line| JSON.parse(line) }
  records = inventory.each_with_object([]) do |item, collected|
    path = item.fetch("path")
    type = item.fetch("type")
    generated = item.fetch("deterministic_generated")
    binary = item.fetch("encoding") == "binary"
    symlink = type == "symlink"
    lockfile = type == "lockfile"
    next unless generated || binary || symlink || lockfile

    reason = if symlink
               target = File.readlink(File.join(ROOT, path))
               "repo-local skill discovery symlink; source target #{target}; no independent executable/text implementation"
             elsif lockfile
               "dependency lockfile; resolved source is Cargo.toml dependency declarations and Cargo registry metadata; no executable logic"
             elsif path.include?("/Bridge/UniFFI/") || path.include?("Carea_matrixFFI/")
               "deterministic UniFFI/FFI output generated from core/area_matrix.udl via core/build.rs and scripts/dev_tools/build.py"
             elsif path.include?("/copy-ready/") || path.include?("/verify-ready/")
               "deterministic rendered prompt artifact generated from the matching task/manifest and workflow/versions/v1-mvp/execution/_shared/prompt_pipeline.py"
             elsif path.include?("/evidence/artifacts/")
               "binary release evidence artifact; generated by release tooling, not executable source"
             elsif binary
               "tracked binary/brand/resource asset; visual or packaging input, no text control flow to audit"
             else
               "deterministic generated artifact; source and generator are recorded in repository workflow/build tooling"
             end
    collected << {
      "path" => path,
      "status" => "NOT_APPLICABLE",
      "reviewed_ranges" => [],
      "auditor" => "main_scope_classifier",
      "review_status" => "NOT_APPLICABLE",
      "notes" => reason,
      "evidence" => ["inventory type=#{type}", "source/generator=#{reason}"],
      "recorded_at" => Time.now.getlocal.iso8601
    }
  end
  File.open(COVERAGE_PATH, "ab") { |file| file.write(json_lines(records)) } unless records.empty?
  puts JSON.generate(appended: records.length)
end

def validate_ledger
  inventory = File.foreach(INVENTORY_PATH).map { |line| JSON.parse(line) }
  current = {}
  File.foreach(COVERAGE_PATH) do |line|
    next if line.strip.empty?

    record = JSON.parse(line)
    current[record.fetch("path")] = record
  end
  inventory_paths = inventory.map { |item| item.fetch("path") }.to_set
  unknown = current.keys.reject { |path| inventory_paths.include?(path) }
  missing = inventory_paths.reject { |path| current.key?(path) }.to_a
  invalid = current.values.reject { |record| VALID_STATUSES.include?(record["status"]) }.map { |record| record["path"] }
  counts = current.values.each_with_object(Hash.new(0)) { |record, result| result[record.fetch("status")] += 1 }
  result = {
    inventory_count: inventory.length,
    current_coverage_count: current.length,
    status_counts: VALID_STATUSES.to_h { |status| [status, counts[status]] },
    missing_paths: missing.sort,
    unknown_paths: unknown.sort,
    invalid_status_paths: invalid.sort,
    conserved: inventory.length == current.length && missing.empty? && unknown.empty? && invalid.empty?
  }
  puts JSON.pretty_generate(result)
  exit 1 unless result[:conserved]
end

def append_sha_mismatches
  inventory = File.foreach(INVENTORY_PATH).map { |line| JSON.parse(line) }
  current = {}
  File.foreach(COVERAGE_PATH) do |line|
    next if line.strip.empty?

    record = JSON.parse(line)
    current[record.fetch("path")] = record
  end

  timestamp = Time.now.getlocal.iso8601
  records = inventory.each_with_object([]) do |item, collected|
    path = item.fetch("path")
    frozen_sha = item.fetch("content_sha256")
    _kind, _size, _lines, actual_sha, _encoding = content_metadata(path)
    next if actual_sha == frozen_sha

    prior = current.fetch(path)
    next if prior.fetch("evidence", []).include?("snapshot commit blob SHA matches frozen inventory")

    collected << {
      "path" => path,
      "status" => "BLOCKED",
      "reviewed_ranges" => prior.fetch("reviewed_ranges", []),
      "auditor" => "main_snapshot_integrity",
      "review_status" => "BLOCKED",
      "notes" => "冻结审计快照 SHA 已变化；保留既有审阅线索，但无法把当前内容冒充 scope.json 中的冻结内容。frozen_sha=#{frozen_sha}; current_sha=#{actual_sha}; previous_status=#{prior.fetch('status')}",
      "evidence" => ["inventory frozen SHA", "current SHA mismatch", "previous auditor=#{prior.fetch('auditor', 'UNKNOWN')}"],
      "content_sha256" => frozen_sha,
      "recorded_at" => timestamp
    }
  end
  File.open(COVERAGE_PATH, "ab") { |file| file.write(json_lines(records)) } unless records.empty?
  puts JSON.generate(appended: records.length)
end

def repair_full_ranges(source_auditor)
  inventory = File.foreach(INVENTORY_PATH).map { |line| JSON.parse(line) }.to_h { |item| [item.fetch("path"), item] }
  current = {}
  File.foreach(COVERAGE_PATH) do |line|
    next if line.strip.empty?

    record = JSON.parse(line)
    current[record.fetch("path")] = record
  end

  timestamp = Time.now.getlocal.iso8601
  records = current.values.each_with_object([]) do |prior, collected|
    next unless prior.fetch("auditor") == source_auditor
    next unless prior.fetch("reviewed_ranges", []) == ["1"]
    next unless prior.fetch("notes", "").match?(/全文(?:核验|审阅|阅读)/)

    item = inventory.fetch(prior.fetch("path"))
    next unless item.fetch("line_count")
    _kind, _size, _lines, actual_sha, _encoding = content_metadata(prior.fetch("path"))
    next unless actual_sha == item.fetch("content_sha256")

    collected << prior.merge(
      "reviewed_ranges" => ["1-#{item.fetch('line_count')}"],
      "auditor" => "main_range_correction",
      "notes" => "#{prior.fetch('notes')}；更正旧 TSV 将完整审阅区间误写为 1 的字段错误。",
      "evidence" => prior.fetch("evidence", []) + ["inventory line_count=#{item.fetch('line_count')}", "source auditor=#{source_auditor}"],
      "recorded_at" => timestamp
    )
  end
  File.open(COVERAGE_PATH, "ab") { |file| file.write(json_lines(records)) } unless records.empty?
  puts JSON.generate(appended: records.length, source_auditor: source_auditor)
end

case ARGV.shift
when "init"
  initialize_ledger
when "append"
  input = ARGV.shift or raise "usage: ledger.rb append RECORDS.jsonl"
  append_records(input)
when "append-tsv"
  input = ARGV.shift or raise "usage: ledger.rb append-tsv RECORDS.tsv AUDITOR"
  auditor = ARGV.shift or raise "usage: ledger.rb append-tsv RECORDS.tsv AUDITOR"
  append_tsv(input, auditor)
when "append-na"
  append_non_applicable
when "validate"
  validate_ledger
when "mark-sha-mismatch"
  append_sha_mismatches
when "repair-full-ranges"
  source_auditor = ARGV.shift or raise "usage: ledger.rb repair-full-ranges SOURCE_AUDITOR"
  repair_full_ranges(source_auditor)
else
  warn "usage: ledger.rb init | append RECORDS.jsonl | append-tsv RECORDS.tsv AUDITOR | append-na | mark-sha-mismatch | repair-full-ranges SOURCE_AUDITOR | validate"
  exit 2
end
