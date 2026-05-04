"""Skill health checks implemented with the Python standard library."""

from __future__ import annotations

import ast
from pathlib import Path
from typing import Any


class SimpleYAMLError(ValueError):
    pass


def _parse_scalar(raw: str, path: Path, line_no: int) -> object:
    value = raw.strip()
    if value in {"true", "True"}:
        return True
    if value in {"false", "False"}:
        return False
    if value in {"null", "Null", "~"}:
        return None
    if value.startswith(('"', "'")):
        try:
            parsed = ast.literal_eval(value)
        except (SyntaxError, ValueError) as exc:
            raise SimpleYAMLError(f"{path}:{line_no}: invalid quoted scalar") from exc
        if not isinstance(parsed, str):
            raise SimpleYAMLError(f"{path}:{line_no}: quoted scalar must be a string")
        return parsed
    if value.startswith(("[", "{", "&", "*", "!", "|", ">")):
        raise SimpleYAMLError(f"{path}:{line_no}: unsupported YAML scalar syntax: {value}")
    return value


def parse_simple_yaml(text: str, path: Path) -> dict[str, Any]:
    """Parse the small mapping-only YAML subset used by repo skill metadata."""

    root: dict[str, Any] = {}
    stack: list[tuple[int, dict[str, Any]]] = [(-1, root)]

    for line_no, raw_line in enumerate(text.splitlines(), start=1):
        if not raw_line.strip() or raw_line.lstrip().startswith("#"):
            continue
        if "\t" in raw_line:
            raise SimpleYAMLError(f"{path}:{line_no}: tabs are not supported")
        indent = len(raw_line) - len(raw_line.lstrip(" "))
        if indent % 2 != 0:
            raise SimpleYAMLError(f"{path}:{line_no}: indentation must use two-space steps")
        stripped = raw_line.strip()
        if stripped.startswith("- "):
            raise SimpleYAMLError(f"{path}:{line_no}: lists are not supported")
        if ":" not in stripped:
            raise SimpleYAMLError(f"{path}:{line_no}: expected key: value mapping")

        key, value = stripped.split(":", 1)
        key = key.strip()
        if not key or any(ch.isspace() for ch in key):
            raise SimpleYAMLError(f"{path}:{line_no}: unsupported key syntax: {key!r}")

        while stack and indent <= stack[-1][0]:
            stack.pop()
        if not stack:
            raise SimpleYAMLError(f"{path}:{line_no}: invalid indentation")
        parent = stack[-1][1]
        if key in parent:
            raise SimpleYAMLError(f"{path}:{line_no}: duplicate key: {key}")

        if value.strip() == "":
            child: dict[str, Any] = {}
            parent[key] = child
            stack.append((indent, child))
        else:
            parent[key] = _parse_scalar(value, path, line_no)

    return root


def parse_frontmatter(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        raise SimpleYAMLError(f"missing frontmatter: {path}")
    end = text.find("\n---\n", 4)
    if end == -1:
        raise SimpleYAMLError(f"missing closing frontmatter marker: {path}")
    return parse_simple_yaml(text[4:end], path)

