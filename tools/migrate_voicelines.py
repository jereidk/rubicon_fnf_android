#!/usr/bin/env python3
"""Turns each voiceline's direct audio reference into a path.

A VoicelineEntry used to hold `stream = ExtResource("N")`, which means the
.ogg loads whenever the group does - and the Collector's Shop reaches 32
groups holding 109 of them, 21% of the files behind a room that needs none of
them to appear. VoicelineEntry now takes `stream_path` and resolves it on
first use, so this rewrites the data to match.

Mechanical and narrow by design: for each group it maps the AudioStream
ext_resource ids to their paths, rewrites `stream = ExtResource("N")` into
`stream_path = "<path>"`, and drops the ext_resource lines that nothing
references any more. Anything it does not fully understand is left alone and
reported rather than guessed at - a mangled .tres is a voice line that goes
silent without saying so.

Dry run by default. Pass --write to apply.

Usage:
    python3 tools/migrate_voicelines.py [--write] [dir]
"""

import re
import sys
from pathlib import Path

WRITE = "--write" in sys.argv
args = [a for a in sys.argv[1:] if not a.startswith("--")]
ROOT = Path(args[0]) if args else Path("lullaby_mod")

EXT_AUDIO = re.compile(
    r'^\[ext_resource type="AudioStream"[^\]]*?path="(res://[^"]+)"[^\]]*?id="([^"]+)"\]\s*$',
    re.M,
)
STREAM = re.compile(r'^(\s*)stream = ExtResource\("([^"]+)"\)\s*$', re.M)
ANY_EXTRES = re.compile(r'ExtResource\("([^"]+)"\)')

changed = skipped = lines_moved = 0

for path in sorted(ROOT.rglob("*.tres")):
    text = path.read_text(encoding="utf-8")
    if "VoicelineEntry.gd" not in text:
        continue

    audio = {m.group(2): m.group(1) for m in EXT_AUDIO.finditer(text)}
    if not audio:
        continue

    refs = STREAM.findall(text)
    if not refs:
        continue

    # Every stream= must point at an AudioStream ext_resource this file
    # declares. If one does not, something about this file is not the shape
    # the migration assumes, and it is left untouched.
    unknown = [rid for _, rid in refs if rid not in audio]
    if unknown:
        print("SALTADO %s: stream= apunta a ids no-audio %s" % (path, unknown))
        skipped += 1
        continue

    def to_path(m):
        return '%sstream_path = "%s"' % (m.group(1), audio[m.group(2)])

    new_text = STREAM.sub(to_path, text)

    # Drop only the audio ext_resource lines nothing else still uses.
    still_used = set(ANY_EXTRES.findall(new_text))
    kept_dangling = []
    out = []
    for line in new_text.splitlines(keepends=True):
        m = EXT_AUDIO.match(line)
        if m and m.group(2) not in still_used:
            lines_moved += 1
            continue
        if m:
            kept_dangling.append(m.group(2))
        out.append(line)
    new_text = "".join(out)

    if kept_dangling:
        print("  aviso %s: ext_resource de audio aun referenciados: %s"
              % (path.name, kept_dangling))

    print("%-56s %2d lineas -> stream_path" % (path.name, len(refs)))
    changed += 1
    if WRITE:
        path.write_text(new_text, encoding="utf-8")

print()
print("%d archivos %s, %d ext_resource de audio retirados, %d saltados"
      % (changed, "reescritos" if WRITE else "a reescribir (simulacro)",
         lines_moved, skipped))
if not WRITE:
    print("simulacro - vuelve a lanzarlo con --write para aplicar")
