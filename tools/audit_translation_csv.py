#!/usr/bin/env python3
"""Fail when a translation column loses a placeholder, a tag or a row.

`ui_strings.csv` is keyed by the English source string and every other column
is a locale. Godot falls back to the key when a cell is empty, so a missing
translation degrades to English and is harmless. What is NOT harmless is a
translation that drops or mangles something the game substitutes into:

  * `%s` / `%d` / `%.2f%%` / `%03d` - a format string whose arguments no
    longer line up does not fall back to English, it throws at runtime. The
    score screen alone has five of them.
  * `$SPECIAL` / `$BIND` - LullabyInputBinds rewrites these into the key or
    button currently bound. A translated line that lost the token silently
    stops telling the player which button to press.
  * BBCode - `[color=...]`, `[shake ...]`, `[wave ...]`, `[pulse ...]`,
    `[pause]`, `[u]`, `[collector]`, `[table]`. The song lyrics are almost
    entirely markup; an unbalanced tag renders the raw text on screen.

Square brackets around ordinary prose are not markup and are ignored - four
quality-preset descriptions and one button label read like `[Post-processing
off]`, and matching every `[...]` flagged all of them.

Row count and key column are checked too, because the whole file is joined on
the key: a reordered or edited key silently orphans every translation under
it.

Run with:
    python3 tools/audit_translation_csv.py [csv...]
"""

import csv
import re
import sys

BBCODE = re.compile(
    r"\[/?(?:color|shake|wave|pulse|pause|u|b|i|s|collector|table)"
    r"(?:[= ][^\]]*)?\]|\[\]"
)
PLACEHOLDER = re.compile(r"%[0-9.]*[sdf%]|\$[A-Z]+\b")

DEFAULT = ["lullaby_mod/resources/localization/ui_strings.csv"]


def audit(path: str) -> int:
    with open(path, encoding="utf-8", newline="") as handle:
        rows = list(csv.reader(handle))

    if not rows:
        print("%s: vacio" % path)
        return 1

    header = rows[0]
    if header[0] != "keys":
        print("%s: la primera columna deberia llamarse 'keys', es '%s'"
              % (path, header[0]))
        return 1

    locales = header[1:]
    problems = 0
    for line, row in enumerate(rows[1:], start=2):
        if len(row) != len(header):
            print("%s:%d tiene %d columnas y la cabecera %d"
                  % (path, line, len(row), len(header)))
            problems += 1
            continue

        key = row[0]
        for locale, cell in zip(locales, row[1:]):
            if not cell.strip():
                continue
            for what, pattern in (("bbcode", BBCODE), ("marcador", PLACEHOLDER)):
                want = sorted(pattern.findall(key))
                got = sorted(pattern.findall(cell))
                if want == got:
                    continue
                print("%s:%d [%s] %s no coincide" % (path, line, locale, what))
                print("     clave: %s" % (want or "(ninguno)"))
                print("     %-6s %s" % (locale + ":", got or "(ninguno)"))
                problems += 1

    filled = {
        locale: sum(1 for row in rows[1:] if len(row) > i + 1 and row[i + 1].strip())
        for i, locale in enumerate(locales)
    }
    print("%s: %d filas, %d idioma(s) - %s" % (
        path, len(rows) - 1, len(locales),
        ", ".join("%s %d/%d" % (k, v, len(rows) - 1) for k, v in filled.items())))
    return problems


def main(paths: list[str]) -> int:
    problems = 0
    for path in paths:
        problems += audit(path)
    if problems:
        print("\n%d problema(s): una traduccion perdio algo que el juego sustituye"
              % problems)
        return 1
    print("todo OK - ninguna traduccion pierde marcadores ni etiquetas")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or DEFAULT))
