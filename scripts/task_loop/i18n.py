"""Small JSON-backed display text catalog for the AreaMatrix dev console."""

from __future__ import annotations

import json
import string
from functools import lru_cache
from pathlib import Path
from typing import Any


SUPPORTED_LANGS = ("mixed", "zh", "en")


def locale_dir() -> Path:
    return Path(__file__).resolve().parent / "locales"


def normalize_lang_mode(value: str | None) -> str:
    return value if value in SUPPORTED_LANGS else "mixed"


@lru_cache(maxsize=None)
def load_catalog(lang: str) -> dict[str, str | list[str]]:
    normalized = normalize_lang_mode(lang)
    path = locale_dir() / f"{normalized}.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise TypeError(f"locale catalog must be an object: {path}")
    return data


def placeholder_names(value: str | list[str]) -> set[str]:
    values = value if isinstance(value, list) else [value]
    names: set[str] = set()
    formatter = string.Formatter()
    for item in values:
        for _, field_name, _, _ in formatter.parse(item):
            if field_name:
                names.add(field_name.split(".", 1)[0].split("[", 1)[0])
    return names


def _format_value(value: str, params: dict[str, Any]) -> str:
    try:
        return value.format(**params)
    except KeyError as exc:
        missing = exc.args[0]
        raise KeyError(f"missing placeholder value: {missing}") from exc


def t(lang: str, key: str, **params: Any) -> str:
    catalog = load_catalog(lang)
    value = catalog.get(key)
    if value is None:
        raise KeyError(f"missing locale key: {normalize_lang_mode(lang)}:{key}")
    if not isinstance(value, str):
        raise TypeError(f"locale key is not a string: {normalize_lang_mode(lang)}:{key}")
    return _format_value(value, params)


def t_lines(lang: str, key: str, **params: Any) -> list[str]:
    catalog = load_catalog(lang)
    value = catalog.get(key)
    if value is None:
        raise KeyError(f"missing locale key: {normalize_lang_mode(lang)}:{key}")
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise TypeError(f"locale key is not a string list: {normalize_lang_mode(lang)}:{key}")
    return [_format_value(item, params) for item in value]


def validate_catalogs() -> list[str]:
    errors: list[str] = []
    baseline = load_catalog("mixed")
    baseline_keys = set(baseline)
    for lang in SUPPORTED_LANGS:
        catalog = load_catalog(lang)
        keys = set(catalog)
        for key in sorted(baseline_keys - keys):
            errors.append(f"{lang}: missing key {key}")
        for key in sorted(keys - baseline_keys):
            errors.append(f"{lang}: extra key {key}")
        for key in sorted(baseline_keys & keys):
            baseline_value = baseline[key]
            value = catalog[key]
            if type(value) is not type(baseline_value):
                errors.append(f"{lang}:{key}: type mismatch")
                continue
            if placeholder_names(value) != placeholder_names(baseline_value):
                errors.append(f"{lang}:{key}: placeholder mismatch")
    return errors
