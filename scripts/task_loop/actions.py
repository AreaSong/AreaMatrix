"""Declarative action registry for the AreaMatrix dev console."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable


@dataclass(frozen=True)
class ActionSpec:
    id: str
    command: str = ""
    aliases: tuple[str, ...] = ()
    shortcuts: tuple[str, ...] = ()
    group: str = ""
    label_key: str = ""
    note_key: str = ""
    dangerous: bool = False
    passthrough: bool = False


@dataclass(frozen=True)
class MenuSpec:
    id: str
    title_key: str
    action_ids: tuple[str, ...]


_ACTION_SPECS = (
    ActionSpec("full-status", shortcuts=("",), group="home", label_key="action.full-status.label", note_key="action.full-status.note"),
    ActionSpec("recommended-next", shortcuts=("1",), group="home", label_key="action.recommended-next.label", note_key="action.recommended-next.note"),
    ActionSpec(
        "lifecycle-menu",
        command="lifecycle",
        shortcuts=("2", "lifecycle"),
        group="home",
        label_key="action.lifecycle-menu.label",
        note_key="action.lifecycle-menu.note",
    ),
    ActionSpec(
        "live-queue-menu",
        command="live-queue",
        aliases=("live",),
        shortcuts=("3", "live", "queue", "tasks"),
        group="home",
        label_key="action.live-queue-menu.label",
        note_key="action.live-queue-menu.note",
    ),
    ActionSpec(
        "quick-continue",
        shortcuts=("continue",),
        group="live",
        label_key="action.quick-continue.label",
        note_key="action.quick-continue.note",
    ),
    ActionSpec(
        "tools-menu",
        command="tools",
        shortcuts=("4", "tools", "checks"),
        group="home",
        label_key="action.tools-menu.label",
        note_key="action.tools-menu.note",
    ),
    ActionSpec(
        "language-menu",
        command="lang",
        shortcuts=("lang",),
        group="system",
        label_key="action.language-menu.label",
        note_key="action.language-menu.note",
    ),
    ActionSpec(
        "shortcuts-help",
        command="shortcuts",
        aliases=("?",),
        shortcuts=("?",),
        group="system",
        label_key="action.shortcuts-help.label",
        note_key="action.shortcuts-help.note",
    ),
    ActionSpec("help", command="help", aliases=("-h", "--help"), shortcuts=("h", "help"), group="system", label_key="action.help.label", note_key="action.help.note"),
    ActionSpec("quit", shortcuts=("q", "quit", "exit", "0"), group="system", label_key="action.quit.label", note_key="action.quit.note"),
    ActionSpec("status", command="status", group="task", label_key="action.status.label", note_key="action.status.note"),
    ActionSpec("start", command="start", shortcuts=("s",), group="task", label_key="action.start.label", note_key="action.start.note"),
    ActionSpec(
        "resume-stale",
        command="resume-stale",
        shortcuts=("r",),
        group="recovery",
        label_key="action.resume-stale.label",
        note_key="action.resume-stale.note",
    ),
    ActionSpec(
        "resume-failed",
        command="resume-failed",
        shortcuts=("f",),
        group="recovery",
        label_key="action.resume-failed.label",
        note_key="action.resume-failed.note",
    ),
    ActionSpec("drain", command="drain", shortcuts=("g",), group="recovery", label_key="action.drain.label", note_key="action.drain.note"),
    ActionSpec("logs", command="logs", shortcuts=("l",), group="task", label_key="action.logs.label", note_key="action.logs.note"),
    ActionSpec(
        "verify-summary",
        command="verify-summary",
        shortcuts=("y",),
        group="task",
        label_key="action.verify-summary.label",
        note_key="action.verify-summary.note",
    ),
    ActionSpec("preflight", command="preflight", shortcuts=("p",), group="task", label_key="action.preflight.label", note_key="action.preflight.note"),
    ActionSpec("preview", command="preview", shortcuts=("v",), group="task", label_key="action.preview.label", note_key="action.preview.note"),
    ActionSpec("dry-run", command="dry-run", shortcuts=("d",), group="task", label_key="action.dry-run.label", note_key="action.dry-run.note"),
    ActionSpec("processes", command="processes", aliases=("ps",), shortcuts=("x",), group="tool", label_key="action.processes.label", note_key="action.processes.note"),
    ActionSpec("compact", command="compact", group="tool", label_key="action.compact.label", note_key="action.compact.note"),
    ActionSpec("clear-stale", command="clear-stale", group="danger", label_key="action.clear-stale.label", note_key="action.clear-stale.note", dangerous=True),
    ActionSpec("reset-progress", command="reset-progress", group="danger", label_key="action.reset-progress.label", note_key="action.reset-progress.note", dangerous=True),
    ActionSpec("interrupted-help", group="recovery", label_key="action.interrupted-help.label", note_key="action.interrupted-help.note"),
    ActionSpec("maintenance-menu", group="live", label_key="action.maintenance-menu.label", note_key="action.maintenance-menu.note"),
    ActionSpec("new-version-preview", group="workflow", label_key="action.new-version-preview.label", note_key="action.new-version-preview.note"),
    ActionSpec("workflow-status", group="workflow", label_key="action.workflow-status.label", note_key="action.workflow-status.note"),
    ActionSpec("workflow-doctor", group="workflow", label_key="action.workflow-doctor.label", note_key="action.workflow-doctor.note"),
    ActionSpec("changes-preview", group="workflow", label_key="action.changes-preview.label", note_key="action.changes-preview.note"),
    ActionSpec("check", command="check", shortcuts=("c",), group="tool", label_key="action.check.label", note_key="action.check.note", passthrough=True),
    ActionSpec("build", command="build", group="tool", label_key="action.build.label", note_key="action.build.note", passthrough=True),
    ActionSpec("test", command="test", group="tool", label_key="action.test.label", note_key="action.test.note", passthrough=True),
    ActionSpec("bindings", command="bindings", group="tool", label_key="action.bindings.label", note_key="action.bindings.note", passthrough=True),
    ActionSpec("changes", command="changes", group="workflow", label_key="action.changes.label", note_key="action.changes.note", passthrough=True),
    ActionSpec("workflow", command="workflow", group="workflow", label_key="action.workflow.label", note_key="action.workflow.note", passthrough=True),
)

ACTIONS = {spec.id: spec for spec in _ACTION_SPECS}

MENUS = {
    "home": MenuSpec(
        "home",
        "home.title",
        ("recommended-next", "lifecycle-menu", "live-queue-menu", "tools-menu", "shortcuts-help", "help", "quit"),
    ),
    "live_queue": MenuSpec(
        "live_queue",
        "submenu.live_queue.title",
        (
            "status",
            "quick-continue",
            "start",
            "resume-stale",
            "resume-failed",
            "drain",
            "preflight",
            "preview",
            "dry-run",
            "logs",
            "verify-summary",
            "maintenance-menu",
        ),
    ),
    "maintenance": MenuSpec("maintenance", "submenu.maintenance.title", ("interrupted-help", "clear-stale", "reset-progress")),
    "tools": MenuSpec("tools", "submenu.tools.title", ("check", "processes", "workflow-status", "workflow-doctor", "changes-preview", "language-menu", "help")),
}


def _alias_map(attribute: str) -> dict[str, str]:
    aliases: dict[str, str] = {}
    for spec in _ACTION_SPECS:
        values: Iterable[str]
        if attribute == "command":
            values = (spec.command, *spec.aliases) if spec.command else spec.aliases
        else:
            values = getattr(spec, attribute)
        for value in values:
            if value:
                aliases[value] = spec.id
    return aliases


COMMAND_ALIASES = _alias_map("command")
SHORTCUT_ALIASES = {shortcut: spec.id for spec in _ACTION_SPECS for shortcut in spec.shortcuts}

REQUIRED_COMMANDS = (
    "status",
    "start",
    "resume-stale",
    "resume-failed",
    "drain",
    "logs",
    "verify-summary",
    "preflight",
    "preview",
    "dry-run",
    "processes",
    "compact",
    "clear-stale",
    "reset-progress",
    "help",
    "lifecycle",
    "live-queue",
    "lang",
    "shortcuts",
    "tools",
    "check",
    "build",
    "test",
    "bindings",
    "changes",
    "workflow",
)


def _find_duplicates(values: Iterable[str]) -> list[str]:
    seen: set[str] = set()
    duplicates: list[str] = []
    for value in values:
        if value in seen and value not in duplicates:
            duplicates.append(value)
        seen.add(value)
    return duplicates


def validate_actions(catalog_keys: Iterable[str] | None = None) -> list[str]:
    errors: list[str] = []
    ids = [spec.id for spec in _ACTION_SPECS]
    for duplicate in _find_duplicates(ids):
        errors.append(f"duplicate action id: {duplicate}")
    for duplicate in _find_duplicates(key for spec in _ACTION_SPECS for key in ((spec.command,) if spec.command else ()) + spec.aliases if key):
        errors.append(f"duplicate command alias: {duplicate}")
    for duplicate in _find_duplicates(key for spec in _ACTION_SPECS for key in spec.shortcuts):
        errors.append(f"duplicate shortcut alias: {duplicate}")

    for command in REQUIRED_COMMANDS:
        if command not in COMMAND_ALIASES:
            errors.append(f"missing required command: {command}")
    for alias, action_id in COMMAND_ALIASES.items():
        if action_id not in ACTIONS:
            errors.append(f"command alias {alias} points to unknown action {action_id}")
    for alias, action_id in SHORTCUT_ALIASES.items():
        if action_id not in ACTIONS:
            errors.append(f"shortcut alias {alias} points to unknown action {action_id}")
    for menu in MENUS.values():
        for action_id in menu.action_ids:
            if action_id not in ACTIONS:
                errors.append(f"menu {menu.id} references unknown action {action_id}")
            elif ACTIONS[action_id].dangerous and menu.id == "home":
                errors.append(f"dangerous action must not be on home menu: {action_id}")
    for action_id in ("clear-stale", "reset-progress"):
        if action_id not in ACTIONS or not ACTIONS[action_id].dangerous:
            errors.append(f"dangerous flag missing: {action_id}")
    for spec in _ACTION_SPECS:
        if spec.passthrough and not spec.command:
            errors.append(f"passthrough action requires a command: {spec.id}")
        if not spec.label_key:
            errors.append(f"missing label key: {spec.id}")
        if not spec.note_key:
            errors.append(f"missing note key: {spec.id}")

    if catalog_keys is None:
        try:
            from .i18n import SUPPORTED_LANGS, load_catalog

            catalogs = {lang: set(load_catalog(lang)) for lang in SUPPORTED_LANGS}
        except Exception as exc:  # pragma: no cover - surfaced by caller as a static validation error.
            errors.append(f"could not load locale catalogs: {exc}")
            catalogs = {}
    else:
        catalogs = {"catalog": set(catalog_keys)}

    for lang, keys in catalogs.items():
        for spec in _ACTION_SPECS:
            if spec.label_key not in keys:
                errors.append(f"{lang}: missing action label key {spec.label_key}")
            if spec.note_key not in keys:
                errors.append(f"{lang}: missing action note key {spec.note_key}")
        for menu in MENUS.values():
            if menu.title_key not in keys:
                errors.append(f"{lang}: missing menu title key {menu.title_key}")
    return errors
