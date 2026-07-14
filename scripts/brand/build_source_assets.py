#!/usr/bin/env python3
"""Build supplementary SVG sources from the canonical AreaMatrix logo geometry."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT_HINT = Path(__file__).resolve().parents[2]
if str(ROOT_HINT) not in sys.path:
    sys.path.insert(0, str(ROOT_HINT))

from scripts.brand.assets import ROOT


BRAND = ROOT / "assets/brand"
FINAL = BRAND / "final"
OUTLINES = BRAND / "wordmark-outlines.json"


def main() -> int:
    outlines = json.loads(OUTLINES.read_text(encoding="utf-8"))
    area = outlines["areaPath"]
    matrix = outlines["matrixPath"]
    write_app_icon_variants()
    write_symbols()
    write_lockups(area, matrix)
    write_wordmarks(area, matrix)
    write_stacked(area, matrix)
    write_social(area, matrix)
    print("supplementary brand SVG sources generated")
    return 0


def write_app_icon_variants() -> None:
    for theme in ("dark", "light"):
        source = (FINAL / f"areamatrix-app-icon-{theme}.svg").read_text(encoding="utf-8")
        background = "#0A201E" if theme == "dark" else "#E1F2EA"
        opaque = source.replace(
            "</desc>",
            f"</desc>\n  <rect width=\"1024\" height=\"1024\" fill=\"{background}\"/>",
            1,
        ).replace(f"App Icon {theme.title()}", f"App Icon Opaque {theme.title()}")
        write(FINAL / f"areamatrix-app-icon-opaque-{theme}.svg", opaque)
        write(FINAL / f"areamatrix-app-icon-small-{theme}.svg", small_icon(theme))
        write(FINAL / f"areamatrix-app-icon-maskable-{theme}.svg", maskable_icon(theme))


def small_icon(theme: str) -> str:
    dark = theme == "dark"
    background = "#0A201E" if dark else "#F0FAF5"
    panel = "#F8FCF8" if dark else "#FFFFFF"
    grid = "#CFE3DD" if dark else "#AFCFC6"
    edge = "#173A33" if dark else "#BFD8D1"
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-labelledby="title desc">
  <title id="title">AreaMatrix Small App Icon {theme.title()}</title>
  <desc id="desc">Simplified AreaMatrix app icon optimized for 16, 32, and 48 pixel rendering.</desc>
  <defs><linearGradient id="trace" x1="250" y1="760" x2="770" y2="240" gradientUnits="userSpaceOnUse"><stop stop-color="#15B49F"/><stop offset="0.55" stop-color="#37CAB6"/><stop offset="0.8" stop-color="#F1B84E"/><stop offset="1" stop-color="#E96D5A"/></linearGradient></defs>
  <rect width="1024" height="1024" rx="214" fill="{background}"/>
  <rect x="286" y="300" width="452" height="452" rx="100" fill="{panel}" stroke="{edge}" stroke-width="18"/>
  <g fill="{grid}"><circle cx="402" cy="420" r="34"/><circle cx="512" cy="420" r="34"/><circle cx="622" cy="420" r="34"/><circle cx="402" cy="540" r="34"/><circle cx="512" cy="540" r="34"/><circle cx="622" cy="540" r="34"/><circle cx="402" cy="660" r="34"/><circle cx="512" cy="660" r="34"/></g>
  <path d="M222 742C374 724 474 620 520 456C550 350 632 286 774 242" fill="none" stroke="url(#trace)" stroke-width="98" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M396 662H672" stroke="#16B7A2" stroke-width="78" stroke-linecap="round"/>
  <circle cx="222" cy="742" r="54" fill="#15B49F"/><circle cx="520" cy="456" r="60" fill="#F1B84E"/><circle cx="774" cy="242" r="52" fill="#E96D5A"/><circle cx="672" cy="662" r="46" fill="#173A33"/>
</svg>'''


def maskable_icon(theme: str) -> str:
    dark = theme == "dark"
    background = "#0A201E" if dark else "#E1F2EA"
    panel = "#F8FCF8" if dark else "#FFFFFF"
    grid = "#CFE3DD" if dark else "#AFCFC6"
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-labelledby="title desc">
  <title id="title">AreaMatrix Maskable App Icon {theme.title()}</title>
  <desc id="desc">Full-bleed AreaMatrix app icon with the logo inside the PWA maskable safe zone.</desc>
  <defs><linearGradient id="trace" x1="250" y1="760" x2="770" y2="240" gradientUnits="userSpaceOnUse"><stop stop-color="#15B49F"/><stop offset="0.55" stop-color="#37CAB6"/><stop offset="0.8" stop-color="#F1B84E"/><stop offset="1" stop-color="#E96D5A"/></linearGradient></defs>
  <rect width="1024" height="1024" fill="{background}"/>
  <g transform="translate(512 512) scale(.78) translate(-512 -512)">
    <rect x="292" y="306" width="440" height="440" rx="94" fill="{panel}"/>
    <g fill="{grid}"><circle cx="386" cy="404" r="30"/><circle cx="512" cy="404" r="30"/><circle cx="638" cy="404" r="30"/><circle cx="386" cy="530" r="30"/><circle cx="512" cy="530" r="30"/><circle cx="638" cy="530" r="30"/><circle cx="386" cy="656" r="30"/><circle cx="512" cy="656" r="30"/><circle cx="638" cy="656" r="30"/></g>
    <path d="M220 736C364 722 470 626 520 456C550 354 630 290 770 246" fill="none" stroke="url(#trace)" stroke-width="84" stroke-linecap="round" stroke-linejoin="round"/>
    <path d="M394 660H668" stroke="#16B7A2" stroke-width="68" stroke-linecap="round"/>
    <circle cx="220" cy="736" r="48" fill="#15B49F"/><circle cx="520" cy="456" r="54" fill="#F1B84E"/><circle cx="770" cy="246" r="46" fill="#E96D5A"/><circle cx="668" cy="660" r="40" fill="#173A33"/>
  </g>
</svg>'''


def write_symbols() -> None:
    for theme in ("dark", "light"):
        dark = theme == "dark"
        panel = "#173A33" if dark else "#F8FCF8"
        dots = "#CFE3DD"
        outline = "#0A201E" if dark else "#BFD8D1"
        endpoint = "#173A33" if dark else "#F4FBF8"
        svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-labelledby="title desc">
  <title id="title">AreaMatrix Logo Symbol {theme.title()}</title>
  <desc id="desc">Transparent color AreaMatrix symbol for {'light' if dark else 'dark'} backgrounds.</desc>
  <defs><linearGradient id="trace" x1="240" y1="734" x2="720" y2="250" gradientUnits="userSpaceOnUse"><stop stop-color="#15B49F"/><stop offset="0.52" stop-color="#37CAB6"/><stop offset="0.78" stop-color="#F1B84E"/><stop offset="1" stop-color="#E96D5A"/></linearGradient></defs>
  <rect x="292" y="306" width="440" height="440" rx="94" fill="{panel}" stroke="{outline}" stroke-width="12"/>
  <g fill="{dots}"><circle cx="386" cy="404" r="30"/><circle cx="512" cy="404" r="30"/><circle cx="638" cy="404" r="30"/><circle cx="386" cy="530" r="30"/><circle cx="512" cy="530" r="30"/><circle cx="638" cy="530" r="30"/><circle cx="386" cy="656" r="30"/><circle cx="512" cy="656" r="30"/><circle cx="638" cy="656" r="30"/></g>
  <path d="M220 706C342 548 472 476 606 494C704 507 775 568 824 640" fill="none" stroke="{outline}" stroke-width="38" stroke-linecap="round"/>
  <path d="M220 736C364 722 470 626 520 456C550 354 630 290 770 246" fill="none" stroke="url(#trace)" stroke-width="84" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M394 660H668" stroke="#16B7A2" stroke-width="68" stroke-linecap="round"/>
  <circle cx="220" cy="736" r="48" fill="#15B49F"/><circle cx="520" cy="456" r="54" fill="#F1B84E"/><circle cx="770" cy="246" r="46" fill="#E96D5A"/><circle cx="668" cy="660" r="40" fill="{endpoint}"/>
</svg>'''
        write(FINAL / f"areamatrix-logo-symbol-{theme}.svg", svg)


def write_lockups(area: str, matrix: str) -> None:
    for suffix in ("", "-dark", "-light"):
        source = FINAL / f"areamatrix-logo-lockup{suffix}.svg"
        content = source.read_text(encoding="utf-8")
        area_color = "#173A33" if suffix == "-light" else "#F4FBF8"
        content = replace_text(content, "Area", f'<path d="{area}" transform="scale(.92 1)" fill="{area_color}"/>')
        content = replace_text(content, "Matrix", f'<path d="{matrix}" transform="translate(238 0) scale(.92 1)" fill="#15B49F"/>')
        content = content.replace("Logo Lockup", "Logo Lockup Outlined", 1)
        content = re.sub(r"<desc id=\"desc\">.*?</desc>", '<desc id="desc">AreaMatrix horizontal logo with the wordmark converted to vector outlines.</desc>', content)
        write(FINAL / f"areamatrix-logo-lockup-outlined{suffix}.svg", content)
    write(FINAL / "areamatrix-logo-lockup-mono-dark.svg", mono_lockup(area, matrix, "#173A33", "Dark"))
    write(FINAL / "areamatrix-logo-lockup-mono-light.svg", mono_lockup(area, matrix, "#F4FBF8", "Light"))


def mono_lockup(area: str, matrix: str, color: str, label: str) -> str:
    mark = svg_body(FINAL / ("areamatrix-logo-mark-mono-dark.svg" if label == "Dark" else "areamatrix-logo-mark-mono-light.svg"))
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1600 520" role="img" aria-labelledby="title desc">
  <title id="title">AreaMatrix Logo Lockup Mono {label}</title>
  <desc id="desc">Single-color AreaMatrix horizontal logo for {'light' if label == 'Dark' else 'dark'} backgrounds.</desc>
  <svg x="90" y="50" width="420" height="420" viewBox="0 0 1024 1024">{mark}</svg>
  <g transform="translate(588 0)" fill="{color}">
    <path d="{area}" transform="scale(.92 1)"/><path d="{matrix}" transform="translate(238 0) scale(.92 1)"/>
    <path d="M4 306H604" fill="none" stroke="{color}" stroke-width="11" stroke-linecap="round"/>
    <circle cx="226" cy="306" r="10"/><circle cx="604" cy="306" r="10"/>
  </g>
</svg>'''


def write_wordmarks(area: str, matrix: str) -> None:
    for theme in ("dark", "light"):
        area_color = "#173A33" if theme == "dark" else "#F4FBF8"
        svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 336" role="img" aria-labelledby="title desc">
  <title id="title">AreaMatrix Wordmark {theme.title()}</title>
  <desc id="desc">Outlined AreaMatrix wordmark for {'light' if theme == 'dark' else 'dark'} backgrounds.</desc>
  <g transform="translate(292 0)"><path d="{area}" transform="scale(.92 1)" fill="{area_color}"/><path d="{matrix}" transform="translate(238 0) scale(.92 1)" fill="#15B49F"/></g>
  <path d="M296 300H900" stroke="#15B49F" stroke-width="10" stroke-linecap="round"/><circle cx="520" cy="300" r="9" fill="#F1B84E"/><circle cx="900" cy="300" r="9" fill="{area_color}"/>
</svg>'''
        write(FINAL / f"areamatrix-wordmark-{theme}.svg", svg)


def write_stacked(area: str, matrix: str) -> None:
    for theme in ("dark", "light"):
        mark = svg_body(FINAL / f"areamatrix-logo-mark-{theme}.svg")
        area_color = "#F4FBF8" if theme == "dark" else "#173A33"
        svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-labelledby="title desc">
  <title id="title">AreaMatrix Stacked Logo {theme.title()}</title>
  <desc id="desc">Stacked AreaMatrix logo for {'dark' if theme == 'dark' else 'light'} presentation.</desc>
  <svg x="242" y="100" width="540" height="540" viewBox="0 0 1024 1024">{mark}</svg>
  <g transform="translate(232 520) scale(.92)"><path d="{area}" transform="scale(.92 1)" fill="{area_color}"/><path d="{matrix}" transform="translate(238 0) scale(.92 1)" fill="#15B49F"/></g>
  <path d="M235 820H789" stroke="#15B49F" stroke-width="12" stroke-linecap="round"/><circle cx="444" cy="820" r="10" fill="#F1B84E"/><circle cx="789" cy="820" r="10" fill="{area_color}"/>
</svg>'''
        write(FINAL / f"areamatrix-logo-stacked-{theme}.svg", svg)


def write_social(area: str, matrix: str) -> None:
    directory = FINAL / "social"
    for theme in ("dark", "light"):
        dark = theme == "dark"
        background = "#0A201E" if dark else "#EEF7F3"
        panel = "#12342F" if dark else "#FFFFFF"
        area_color = "#F4FBF8" if dark else "#173A33"
        symbol = svg_body(FINAL / f"areamatrix-logo-symbol-{'light' if dark else 'dark'}.svg")
        svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 630" role="img" aria-labelledby="title desc">
  <title id="title">AreaMatrix Social Preview {theme.title()}</title>
  <desc id="desc">AreaMatrix social sharing preview using the canonical symbol and outlined wordmark.</desc>
  <rect width="1200" height="630" fill="{background}"/><rect x="58" y="58" width="1084" height="514" rx="28" fill="{panel}"/>
  <g opacity=".16" stroke="#15B49F" stroke-width="3"><path d="M700 112H1080M700 188H1080M700 264H1080M700 340H1080M700 416H1080M700 492H1080"/><path d="M760 90V540M850 90V540M940 90V540M1030 90V540"/></g>
  <svg x="95" y="105" width="260" height="260" viewBox="0 0 1024 1024">{symbol}</svg>
  <g transform="translate(390 90) scale(1.12)"><path d="{area}" transform="scale(.92 1)" fill="{area_color}"/><path d="{matrix}" transform="translate(238 0) scale(.92 1)" fill="#15B49F"/></g>
  <path d="M100 484C320 484 430 454 610 460C790 466 900 504 1094 476" fill="none" stroke="#15B49F" stroke-width="14" stroke-linecap="round"/><circle cx="420" cy="470" r="13" fill="#F1B84E"/><circle cx="1094" cy="476" r="13" fill="#E96D5A"/>
</svg>'''
        write(directory / f"areamatrix-social-preview-{theme}.svg", svg)
    write(directory / "areamatrix-social-preview.svg", (directory / "areamatrix-social-preview-light.svg").read_text(encoding="utf-8"))


def replace_text(content: str, word: str, replacement: str) -> str:
    pattern = rf"<text\b[^>]*>\s*{word}\s*</text>"
    updated, count = re.subn(pattern, replacement, content, count=1, flags=re.DOTALL)
    if count != 1:
        raise RuntimeError(f"could not replace {word} text in lockup")
    return updated


def svg_body(path: Path) -> str:
    content = path.read_text(encoding="utf-8")
    content = re.sub(r"^<svg\b[^>]*>", "", content, count=1)
    content = re.sub(r"</svg>\s*$", "", content, count=1)
    content = re.sub(r"\s*<title\b.*?</title>", "", content, flags=re.DOTALL)
    content = re.sub(r"\s*<desc\b.*?</desc>", "", content, flags=re.DOTALL)
    return content.strip()


def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content.rstrip() + "\n", encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
