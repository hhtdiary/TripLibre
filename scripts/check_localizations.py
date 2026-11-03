#!/usr/bin/env python3
"""Check the app's string catalogs (issue #90). Run: python3 scripts/check_localizations.py

- every key is translated into every shipped language (and plural keys have each language's plural forms);
- translations keep the key's format specifiers (%@, %lld, %.1f…), in any order when numbered (%2$@);
- every `L("…")` key used in App/ is in the catalog.

Keys are the English text, so English needs no entry except for plural forms.
"""

import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOGS = [ROOT / "App/Localizable.xcstrings", ROOT / "App/InfoPlist.xcstrings"]
LANGUAGES = ["zh-Hans", "zh-Hant", "fr", "de", "es", "pt", "ru", "ar", "ja", "ko"]
# CLDR plural categories the app provides for each language (integers only).
PLURALS = {
    "en": {"one", "other"}, "fr": {"one", "other"}, "de": {"one", "other"}, "es": {"one", "other"},
    "pt": {"one", "other"}, "ru": {"one", "few", "many", "other"},
    "ar": {"zero", "one", "two", "few", "many", "other"},
    "zh-Hans": {"other"}, "zh-Hant": {"other"}, "ja": {"other"}, "ko": {"other"},
}
SPEC = re.compile(r"%(?:(\d+)\$)?(@|lld|d|(?:\.\d+)?f)")


def specs(s: str) -> Counter:
    return Counter(m.group(2) for m in SPEC.finditer(s.replace("%%", "")))


def check_value(key: str, lang: str, value: str, plural_form: str | None, errors: list[str]) -> None:
    want, got = specs(key), specs(value)
    numbered = [m.group(1) for m in SPEC.finditer(value) if m.group(1)]
    if numbered and len(numbered) != sum(got.values()):
        errors.append(f"{lang}: mixes numbered and plain specifiers: {key!r}")
    if numbered and sorted(int(n) for n in numbered) != list(range(1, len(numbered) + 1)):
        errors.append(f"{lang}: numbered specifiers must be %1$…%{len(numbered)}$: {key!r}")
    # a plural form other than "other" may spell its number out ("one visit"), so it may drop the count
    if plural_form not in (None, "other"):
        if got - want:
            errors.append(f"{lang}/{plural_form}: specifiers {dict(got)} not in key: {key!r}")
    elif got != want:
        errors.append(f"{lang}{'/' + plural_form if plural_form else ''}: specifiers {dict(got)} != {dict(want)}: {key!r}")


def check_catalog(path: Path, errors: list[str]) -> set[str]:
    data = json.loads(path.read_text(encoding="utf-8"))
    for key, entry in data["strings"].items():
        locs = entry.get("localizations", {})
        needs_plural = "plural" in json.dumps(locs)
        for lang in LANGUAGES + (["en"] if needs_plural else []):
            loc = locs.get(lang)
            if loc is None:
                errors.append(f"{lang}: missing translation: {key!r}")
                continue
            if "stringUnit" in loc:
                unit = loc["stringUnit"]
                if unit.get("state") != "translated":
                    errors.append(f"{lang}: state {unit.get('state')!r}: {key!r}")
                if needs_plural and PLURALS[lang] != {"other"}:
                    errors.append(f"{lang}: needs plural forms {sorted(PLURALS[lang])}: {key!r}")
                check_value(key, lang, unit["value"], None, errors)
            else:
                forms = loc.get("variations", {}).get("plural", {})
                if set(forms) != PLURALS[lang]:
                    errors.append(f"{lang}: plural forms {sorted(forms)} != {sorted(PLURALS[lang])}: {key!r}")
                for form, v in forms.items():
                    check_value(key, lang, v["stringUnit"]["value"], form, errors)
    return set(data["strings"])


def used_keys() -> dict[str, str]:
    """`L("literal"…)` keys in the app, with where they are used."""
    found = {}
    call = re.compile(r'\bL\(\s*(?:[\w.]+\s*\?\s*)?"((?:[^"\\]|\\.)*)"(?:\s*:\s*"((?:[^"\\]|\\.)*)")?')
    for f in sorted((ROOT / "App").rglob("*.swift")):
        for n, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            for m in call.finditer(line):
                for g in m.groups():
                    if g is not None and "\\(" not in g:
                        found.setdefault(g.replace('\\"', '"').replace("\\n", "\n"), f"{f.relative_to(ROOT)}:{n}")
    return found


def main() -> int:
    errors: list[str] = []
    keys = set()
    for path in CATALOGS:
        keys |= check_catalog(path, errors)
    for key, where in used_keys().items():
        if key not in keys:
            errors.append(f"{where}: L({key!r}) is not in App/Localizable.xcstrings")
    for e in errors:
        print(e)
    print(f"{len(keys)} keys, {len(LANGUAGES)} languages: {'OK' if not errors else f'{len(errors)} problem(s)'}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
