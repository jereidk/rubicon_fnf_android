#!/usr/bin/env python3
"""Find _input() handlers that react to an action's release as well as its press.

Every synthetic action in this project arrives TWICE - a press, then a
release one frame later. RubiconActionButton._dispatch(), RubiconVirtualDPad
._dispatch_action() and native_back_button_handler.gd all do this on purpose,
because some listeners read the raw InputEvent while others poll
Input.is_action_just_released next frame, so both halves have to fire for a
tap to behave like a real key.

InputEvent.is_action() matches both halves. A handler that uses it without
rejecting the release therefore runs twice per tap. That has been a real bug
here more than once, and its worst shape is a doubled
SceneChanger.change_to(): the second call reassigns _current_loader while the
first loading screen is still parented to a CanvasLayer at layer 128, so the
scene loads and plays underneath a black screen nothing owns any more.

Run it after adding an _input() handler:

    python3 tools/audit_input_guards.py

Note what it CANNOT see. is_action_pressed() is safe by construction and is
skipped. So is any handler that rejects the release, and there are several
spellings of that in this repo - `not event.is_pressed()`, `and
event.is_pressed()`, `and not event.is_action_released(...)`. All are
recognised below; if you invent a sixth, add it here rather than letting the
tool cry wolf, because a checker with false positives stops being read.
"""

import glob
import re
import sys

SEARCH_ROOTS = ("lullaby_mod/**/*.gd", "addons/**/*.gd", "menus/**/*.gd")

HANDLERS = r"^func (_input|_unhandled_input|_gui_input)\(.*?\n(?=^\S|\Z)"

# Any one of these, anywhere in the handler, means the release is dealt with.
GUARDS = (
    r"not\s+event\.is_pressed\(\)",
    r"event\.is_pressed\(\)\s+and",
    r"and\s+event\.is_pressed\(\)",
    r"if\s+event\.is_pressed\(\)",
    r"not\s+event\.is_action_released\(",
    r"event\.is_action_pressed\(",
)


def main() -> int:
    findings = []

    for pattern in SEARCH_ROOTS:
        for path in sorted(glob.glob(pattern, recursive=True)):
            source = open(path, encoding="utf8", errors="replace").read()

            for match in re.finditer(HANDLERS, source, re.M | re.S):
                body = match.group(0)
                actions = re.findall(r'\bevent\.is_action\(&?"([^"]+)"\)', body)
                if not actions:
                    continue
                if any(re.search(guard, body) for guard in GUARDS):
                    continue

                line = source[: match.start()].count("\n") + 1
                findings.append((path, line, match.group(1), sorted(set(actions))))

    for path, line, handler, actions in findings:
        print("%s:%d  %s()  reacts to release too: %s" % (path, line, handler, ", ".join(actions)))

    print("\n%d unguarded handler(s)." % len(findings))
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
