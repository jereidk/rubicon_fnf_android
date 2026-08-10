#!/usr/bin/env python3
"""Check every `"..." % [...]` in the diagnostics log against its argument list.

A GDScript format string with more placeholders than arguments does not
raise and does not stop the game: `String % Array` returns the *unformatted*
string. The log then writes `ram=%s gpu=%.2fms ...` for every line of the
session and reads as a working file until someone tries to parse it.

That happened. A `sub_top=%s` was added to the format string and its argument
never landed, because the edit that was supposed to insert it matched nothing,
and one whole build-and-play cycle produced 184 lines of literal format
string. This is the check that would have caught it in a second.

    python3 tools/verify_log_format.py

Exits non-zero and names the offender when a count does not match.
"""

import re
import sys

PATH = "lullaby_mod/scripts/lullaby/debug/lullaby_diagnostics_log.gd"

# %s %d %05.2f %-10s %.1f - everything GDScript's format operator takes.
# %% is an escaped percent and consumes no argument.
PLACEHOLDER = re.compile(r"%(?:%|[-+ #0]*\d*(?:\.\d+)?[sdfxXoc])")


def split_args(text: str) -> list:
    """Top-level comma split, ignoring commas inside (), [], {} or strings."""
    args, depth, quote, current = [], 0, "", ""
    for char in text:
        if quote:
            current += char
            if char == quote:
                quote = ""
            continue
        if char in "\"'":
            quote = char
        elif char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        elif char == "," and depth == 0:
            args.append(current)
            current = ""
            continue
        current += char
    if current.strip():
        args.append(current)
    return [a for a in args if a.strip() and not a.strip().startswith("#")]


def strip_comments(text: str) -> str:
    out = []
    for line in text.split("\n"):
        quote = ""
        for i, char in enumerate(line):
            if quote:
                if char == quote:
                    quote = ""
            elif char in "\"'":
                quote = char
            elif char == "#":
                line = line[:i]
                break
        out.append(line)
    return "\n".join(out)


def main() -> int:
    source = open(PATH, encoding="utf-8").read()
    failures = 0
    checked = 0

    for match in re.finditer(r'"((?:[^"\\]|\\.)*)"\s*%\s*\[', source):
        fmt = match.group(1)
        placeholders = [p for p in PLACEHOLDER.findall(fmt) if p != "%%"]
        if not placeholders:
            continue

        # Walk from the opening bracket to its match.
        depth, index = 0, match.end() - 1
        while index < len(source):
            if source[index] == "[":
                depth += 1
            elif source[index] == "]":
                depth -= 1
                if depth == 0:
                    break
            index += 1

        args = split_args(strip_comments(source[match.end():index]))
        checked += 1
        if len(placeholders) != len(args):
            failures += 1
            line = source[: match.start()].count("\n") + 1
            print(f"{PATH}:{line}: {len(placeholders)} placeholders, {len(args)} arguments")
            print(f"    format starts: {fmt[:70]}...")

    print(f"checked {checked} format strings, {failures} mismatched")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
