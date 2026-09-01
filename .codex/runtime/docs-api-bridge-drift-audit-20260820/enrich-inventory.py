#!/usr/bin/env python3
"""Add path-based ownership and provenance hints without changing audit status."""

from __future__ import annotations

import json
from pathlib import Path


AUDIT_DIR = Path(__file__).resolve().parent
INVENTORY = AUDIT_DIR / "inventory.jsonl"


def classify(path: str, file_type: str) -> dict[str, object]:
    name = Path(path).name.lower()
    result: dict[str, object] = {
        "source_fact_layer": "repository_support",
        "role": "support_source",
        "generated_source": None,
        "generator": None,
        "generator_command": None,
    }

    if path.startswith("docs/"):
        result.update(source_fact_layer="product_architecture_api_source", role="authoritative_source")
    elif path.startswith(".ai-governance/"):
        result.update(source_fact_layer="ai_governance_source", role="authoritative_source")
    elif path in {"README.md", "README.zh-CN.md"}:
        result.update(source_fact_layer="user_entrypoint", role="summary_navigation")
    elif path == "AGENTS.md" or path.endswith("/AGENTS.md"):
        result.update(source_fact_layer="agent_entrypoint", role="governance_adapter")
    elif path == "core/area_matrix.udl":
        result.update(source_fact_layer="core_api_projection", role="udl_contract")
    elif path.startswith("core/src/api/"):
        result.update(source_fact_layer="core_implementation", role="rust_public_api")
    elif path.startswith("core/src/"):
        result.update(source_fact_layer="core_implementation", role="rust_implementation")
    elif path.startswith("core/tests/") or path.startswith("core/benches/"):
        result.update(source_fact_layer="verification", role="rust_test_or_benchmark")
    elif path.startswith("core/resources/"):
        result.update(source_fact_layer="core_implementation", role="schema_or_runtime_resource")
    elif path.startswith("core/"):
        result.update(source_fact_layer="core_build", role="build_or_dependency_metadata")
    elif path.startswith("apps/macos/AreaMatrix/Bridge/UniFFI/"):
        result.update(
            source_fact_layer="generated_bridge_projection",
            role="tracked_generated_binding",
            generated_source="core/area_matrix.udl + core Rust crate",
            generator="UniFFI 0.27.x through repository bindings tooling",
            generator_command="./dev bindings update",
        )
    elif path.startswith("apps/macos/AreaMatrix/Bridge/Generated/"):
        result.update(
            source_fact_layer="generated_bridge_projection",
            role="ignored_local_generated_binding",
            generated_source="core/area_matrix.udl + core Rust crate",
            generator="UniFFI through repository bindings tooling",
            generator_command="./dev bindings update",
        )
    elif path.startswith("apps/macos/AreaMatrix/Bridge/"):
        result.update(source_fact_layer="platform_bridge", role="handwritten_swift_bridge")
    elif path.startswith("apps/macos/AreaMatrixTests/"):
        result.update(source_fact_layer="verification", role="macos_test")
    elif path.startswith("apps/macos/"):
        result.update(source_fact_layer="platform_consumer", role="macos_source_or_project_metadata")
    elif path.startswith("apps/ios/Carea_matrixFFI/"):
        result.update(
            source_fact_layer="generated_bridge_projection",
            role="tracked_generated_binding_subset",
            generated_source="apps/macos/AreaMatrix/Bridge/UniFFI/area_matrixFFI.h",
            generator="repository iOS binding subset tooling",
            generator_command="./dev bindings update",
        )
    elif path.startswith("apps/ios/"):
        result.update(source_fact_layer="platform_consumer", role="ios_source_or_package_metadata")
    elif path.startswith("apps/windows/"):
        result.update(source_fact_layer="platform_projection", role="windows_source_or_project_metadata")
    elif path.startswith("apps/linux/"):
        result.update(source_fact_layer="platform_projection", role="linux_source_or_project_metadata")
    elif path.startswith("workflow/versions/v1-mvp/execution/_shared/copy-ready/") or path.startswith(
        "workflow/versions/v1-mvp/execution/_shared/verify-ready/"
    ):
        result.update(
            source_fact_layer="prompt_projection",
            role="deterministic_rendered_prompt",
            generated_source="matching task + manifest + shared prompt rules",
            generator="workflow/versions/v1-mvp/execution/_shared/prompt_pipeline.py",
            generator_command="python3 workflow/versions/v1-mvp/execution/_shared/prompt_pipeline.py export --all",
        )
    elif path.startswith("workflow/versions/v1-mvp/execution/phase-"):
        result.update(source_fact_layer="prompt_execution_source", role="historical_task_source")
    elif "/execution/_shared/manifests/" in path:
        result.update(source_fact_layer="prompt_execution_source", role="prompt_manifest")
    elif path.startswith("workflow/versions/v1-mvp/source-docs/"):
        result.update(source_fact_layer="historical_archive", role="historical_source_doc")
    elif "/evidence/" in path or "/closeout/" in path:
        result.update(source_fact_layer="historical_evidence", role="evidence_or_closeout")
    elif path.startswith("workflow/residuals/") or "/residuals/" in path:
        result.update(source_fact_layer="residual_index", role="index_projection")
    elif path.startswith("workflow/"):
        result.update(source_fact_layer="workflow_planning", role="workflow_source_or_template")
    elif path.startswith("tasks/"):
        result.update(source_fact_layer="task_tracking", role="task_or_index_projection")
    elif path.startswith(".codex/runtime/"):
        result.update(source_fact_layer="local_runtime_evidence", role="prior_audit_or_runtime_artifact")
    elif path.startswith(".codex/skills-src/"):
        result.update(source_fact_layer="codex_adapter", role="repo_local_skill_source")
    elif path.startswith(".codex/"):
        result.update(source_fact_layer="codex_adapter", role="codex_reference_or_template")
    elif path.startswith(".agents/skills/"):
        result.update(
            source_fact_layer="discovery_projection",
            role="skill_symlink_projection",
            generated_source=".codex/skills-src matching directory",
            generator="filesystem symlink",
            generator_command="./dev check skills",
        )
    elif path.startswith(".cursor/"):
        result.update(source_fact_layer="cursor_adapter", role="cursor_projection")
    elif path.startswith(".github/"):
        result.update(source_fact_layer="ci_governance_adapter", role="ci_or_github_metadata")
    elif path.startswith("scripts/") or path in {"dev", "task-loop"}:
        result.update(source_fact_layer="tooling", role="checker_generator_or_runner")
    elif path.startswith("assets/"):
        result.update(source_fact_layer="brand_or_prototype_asset", role="binary_asset" if file_type == "binary" else "asset_source_or_manifest")
    elif path.startswith(".areaflow/"):
        result.update(source_fact_layer="external_adapter", role="areaflow_projection")
    elif path.startswith(".cargo/") or path.startswith(".vscode/"):
        result.update(source_fact_layer="developer_tooling", role="tool_configuration")
    elif path in {"CODE_REVIEW.md", "SECURITY.md", "CONTRIBUTING.md", "CODE_OF_CONDUCT.md"}:
        result.update(source_fact_layer="governance_summary", role="governance_entrypoint")
    elif path in {"LICENSE", "COMMERCIAL_LICENSE.md"}:
        result.update(source_fact_layer="legal", role="legal_contract")

    if name in {"cargo.lock", "package.resolved"} or name.endswith(".lock"):
        result["role"] = "lockfile"
        result["generated_source"] = "declared dependency manifests and resolver state"
        result["generator"] = "package manager resolver"
    return result


def main() -> None:
    rows = []
    for line in INVENTORY.read_text(encoding="utf-8").splitlines():
        row = json.loads(line)
        row.update(classify(row["path"], row["file_type"]))
        rows.append(row)
    INVENTORY.write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows),
        encoding="utf-8",
    )
    print(json.dumps({"enriched": len(rows)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
