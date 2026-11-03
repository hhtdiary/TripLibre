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


def specs(s: str) -> tuple[dict[int, str], bool]:
    """Conversion type by argument position (plain specifiers count up from 1, `%2$@` names its position), and
    whether the string mixes plain and numbered specifiers."""
    by_position: dict[int, str] = {}
    plain = numbered = 0
    for m in SPEC.finditer(s.replace("%%", "")):
        if m.group(1):
            numbered += 1
            position = int(m.group(1))
        else:
            plain += 1
            position = plain
        by_position[position] = m.group(2)
    return by_position, bool(plain and numbered)


def check_value(key: str, lang: str, value: str, plural_form: str | None, errors: list[str]) -> None:
    where = f"{lang}{'/' + plural_form if plural_form else ''}"
    if not value.strip():
        errors.append(f"{where}: empty translation: {key!r}")
        return
    (want, _), (got, mixed) = specs(key), specs(value)
    if mixed:
        errors.append(f"{where}: mixes numbered and plain specifiers: {key!r}")
    # a plural form other than "other" may spell its number out ("one visit"), so it may drop the count; whatever it
    # keeps must still have the key's type at each position
    partial = plural_form not in (None, "other")
    if (partial and any(want.get(p) != t for p, t in got.items())) or (not partial and got != want):
        errors.append(f"{where}: specifiers by position {got} != {want}: {key!r}")


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
