#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_ROOT="$ROOT_DIR/.codex/skills-src"
DISCOVERY_ROOT="$ROOT_DIR/.agents/skills"

failures=0

fail() {
  failures=$((failures + 1))
  printf 'ERROR: %s\n' "$*" >&2
}

check_file() {
  local path="$1"
  if [ ! -f "$path" ]; then
    fail "missing file: $path"
  fi
}

check_dir() {
  local path="$1"
  if [ ! -d "$path" ]; then
    fail "missing directory: $path"
  fi
}

check_symlink() {
  local name="$1"
  local link="$DISCOVERY_ROOT/$name"
  local expected="../../.codex/skills-src/$name"

  if [ ! -L "$link" ]; then
    fail "missing symlink: $link"
    return
  fi

  local actual
  actual="$(readlink "$link")"
  if [ "$actual" != "$expected" ]; then
    fail "bad symlink target for $link: expected $expected got $actual"
  fi

  if [ ! -e "$link" ]; then
    fail "broken symlink: $link"
  fi
}

check_skill_frontmatter() {
  local name="$1"
  local file="$2"

  ruby - "$name" "$file" <<'RUBY'
require "yaml"

name = ARGV.fetch(0)
file = ARGV.fetch(1)
text = File.read(file)
match = text.match(/\A---\n(.*?)\n---\n/m)
abort("missing frontmatter: #{file}") unless match
data = YAML.safe_load(match[1], permitted_classes: [], aliases: false)
abort("frontmatter is not a mapping: #{file}") unless data.is_a?(Hash)
abort("frontmatter name mismatch in #{file}: #{data["name"].inspect}") unless data["name"] == name
description = data["description"]
abort("missing description in #{file}") unless description.is_a?(String) && !description.strip.empty?
RUBY
}

check_openai_yaml() {
  local name="$1"
  local file="$2"

  ruby - "$name" "$file" <<'RUBY'
require "yaml"

name = ARGV.fetch(0)
file = ARGV.fetch(1)
data = YAML.load_file(file)
abort("openai.yaml is not a mapping: #{file}") unless data.is_a?(Hash)
interface = data["interface"]
abort("missing interface in #{file}") unless interface.is_a?(Hash)
%w[display_name short_description default_prompt].each do |key|
  value = interface[key]
  abort("missing interface.#{key} in #{file}") unless value.is_a?(String) && !value.strip.empty?
end
unless interface["default_prompt"].include?("$#{name}")
  abort("default_prompt must mention $#{name} in #{file}")
end
policy = data["policy"]
abort("missing policy in #{file}") unless policy.is_a?(Hash)
unless [true, false].include?(policy["allow_implicit_invocation"])
  abort("policy.allow_implicit_invocation must be boolean in #{file}")
end
RUBY
}

check_references() {
  local name="$1"
  local skill_dir="$2"
  local references_dir="$skill_dir/references"

  check_dir "$references_dir"
  if [ -d "$references_dir" ]; then
    local count
    count="$(find "$references_dir" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d '[:space:]')"
    if [ "$count" -lt 1 ]; then
      fail "no reference markdown files for $name"
    fi
  fi
}

main() {
  check_dir "$SKILL_ROOT"
  check_dir "$DISCOVERY_ROOT"

  local found=0
  while IFS= read -r skill_dir; do
    found=$((found + 1))
    local name
    name="$(basename "$skill_dir")"
    local skill_file="$skill_dir/SKILL.md"
    local openai_file="$skill_dir/agents/openai.yaml"

    check_file "$skill_file"
    check_file "$openai_file"
    check_symlink "$name"
    check_references "$name" "$skill_dir"

    if [ -f "$skill_file" ]; then
      check_skill_frontmatter "$name" "$skill_file" || fail "invalid SKILL.md: $skill_file"
    fi
    if [ -f "$openai_file" ]; then
      check_openai_yaml "$name" "$openai_file" || fail "invalid openai.yaml: $openai_file"
    fi
  done < <(find "$SKILL_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'areamatrix-*' | sort)

  if [ "$found" -eq 0 ]; then
    fail "no AreaMatrix skills found under $SKILL_ROOT"
  fi

  if [ "$failures" -gt 0 ]; then
    printf 'skill health: FAILED (%d issue(s))\n' "$failures" >&2
    return 1
  fi

  printf 'skill health: OK (%d skill(s))\n' "$found"
}

main "$@"
