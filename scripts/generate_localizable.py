#!/usr/bin/env python3
"""Generate Sources/OpenClip/Resources/Localizable.xcstrings from the translation tables in scripts/translations/."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TRANSLATIONS_DIR = Path(__file__).resolve().parent / "translations"

# Supported target languages
LANGUAGES = ["zh-Hans", "zh-Hant", "fr", "ja"]


def load_translations() -> dict[str, dict[str, str]]:
    tables: dict[str, dict[str, str]] = {}
    for lang in LANGUAGES:
        lang_file = TRANSLATIONS_DIR / f"{lang}.json"
        if lang_file.exists():
            with open(lang_file, "r", encoding="utf-8") as f:
                tables[lang] = json.load(f)
        else:
            tables[lang] = {}
    return tables


# Backwards compatibility export: TRANSLATIONS is zh-Hans
_all_tables = load_translations()
TRANSLATIONS: dict[str, str] = _all_tables.get("zh-Hans", {})


def catalog(tables: dict[str, dict[str, str]]) -> dict:
    all_keys: set[str] = set()
    for lang_dict in tables.values():
        all_keys.update(lang_dict.keys())

    strings = {}
    for key in sorted(all_keys):
        localizations = {}
        for lang in LANGUAGES:
            lang_dict = tables.get(lang, {})
            if key in lang_dict:
                localizations[lang] = {
                    "stringUnit": {
                        "state": "translated",
                        "value": lang_dict[key],
                    }
                }
        strings[key] = {
            "localizations": localizations
        }

    return {
        "sourceLanguage": "en",
        "strings": strings,
        "version": "1.0",
    }


def main() -> None:
    tables = load_translations()
    dest = ROOT / "Sources" / "OpenClip" / "Resources" / "Localizable.xcstrings"
    dest.parent.mkdir(parents=True, exist_ok=True)
    cat = catalog(tables)
    dest.write_text(json.dumps(cat, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    counts = ", ".join(f"{lang}: {len(tables[lang])}" for lang in LANGUAGES)
    print(f"Wrote {len(cat['strings'])} keys to {dest} ({counts})")


if __name__ == "__main__":
    main()
