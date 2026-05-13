"""Repo-local dev console preferences."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .i18n import normalize_lang_mode


CONFIG_RELATIVE_PATH = Path(".codex/dev-console/config.json")


def config_path(root: Path) -> Path:
    return root / CONFIG_RELATIVE_PATH


def load_config(root: Path) -> dict[str, Any]:
    path = config_path(root)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def saved_lang_mode(root: Path) -> str:
    value = load_config(root).get("lang")
    return normalize_lang_mode(value if isinstance(value, str) else None)


def save_lang_mode(root: Path, lang_mode: str) -> None:
    path = config_path(root)
    data = load_config(root)
    data["lang"] = normalize_lang_mode(lang_mode)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
