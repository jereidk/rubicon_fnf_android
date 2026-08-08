#!/usr/bin/env python3
"""Reconstructs GDScript source from an exported .gdc (Godot 4.3+).

Why this exists: this port replaced parts of the mod's engine, and the only
reference for what the original did is the pck, which ships scripts as .gdc.
tools/read_pck_scripts.gd recovers the *strings* from those files, which
answers "does anything mention X" but cannot answer "what did this function
do". That gap is what left the gdanimate rewrite un-diffable.

A Godot 4.3+ .gdc is not compiled bytecode - it is the binary output of the
GDScript *tokenizer*, so the token stream, the identifier table, the constant
table and the per-token line numbers are all still there. Reconstruction is
therefore close to lossless: everything comes back except comments, blank-line
placement and the original spacing inside a line.

GDRE Tools does this properly and is the right tool when you can get it. This
environment cannot download it - github.com returns 403 for repositories
outside the session's scope - but the anonymous git lane does serve public
clones, so the format and both token tables were read out of gdsdecomp's
source (bytecode/gdscript_v2_tokenizer_buffer.cpp for the container,
bytecode_ebc36a7.{h,cpp} for the version-101 token enum, and
bytecode_base.cpp's decompile_buffer for the token-to-text mapping) and
reimplemented here. Regenerate the tables with --dump-tables if a future
Godot bumps the bytecode version.

Bytecode version 101 covers Godot 4.5 through 4.7 - the mod's pck and this
port both report it.

Usage:
    python3 tools/gdc_decompile.py <file.gdc> [...]
    python3 tools/gdc_decompile.py --out <dir> <file.gdc> [...]
"""

import argparse
import os
import struct
import sys

try:
    import zstandard
except ImportError:
    sys.exit("needs zstandard:  pip install zstandard")

# ---------------------------------------------------------------------------
# Tables, generated from gdsdecomp. See module docstring.
# ---------------------------------------------------------------------------

from gdc_tables import LOCAL_TOKENS, LOCAL_TO_GLOBAL, TOKEN_TEXT

TOKEN_BITS = 8
# Note the -1: the v2 buffer masks with 0x7F, not 0xFF, because bit 7 of the
# first byte is the wide-record flag. Using 0xFF here decodes every token as
# an error and is easy to get wrong from the v1 tokenizer's constants, which
# do use (1 << TOKEN_BITS) - 1.
TOKEN_MASK = (1 << (TOKEN_BITS - 1)) - 1
TOKEN_BYTE_MASK = 0x80

# Godot Variant type ids (core/variant/variant.h). Only the ones a GDScript
# constant pool actually carries are decoded; anything else is reported rather
# than guessed at, so a wrong literal can never be mistaken for a real one.
VAR_NIL, VAR_BOOL, VAR_INT, VAR_FLOAT, VAR_STRING = 0, 1, 2, 3, 4
VAR_VECTOR2, VAR_VECTOR2I = 5, 6
VAR_COLOR = 20
VAR_STRING_NAME, VAR_NODE_PATH = 21, 22
VAR_DICTIONARY, VAR_ARRAY = 27, 28

ENCODE_FLAG_64 = 1 << 16


class Reader:
    def __init__(self, buf, pos=0):
        self.buf = buf
        self.pos = pos

    def u32(self):
        v = struct.unpack_from("<I", self.buf, self.pos)[0]
        self.pos += 4
        return v

    def i64(self):
        v = struct.unpack_from("<q", self.buf, self.pos)[0]
        self.pos += 8
        return v

    def i32(self):
        v = struct.unpack_from("<i", self.buf, self.pos)[0]
        self.pos += 4
        return v

    def f32(self):
        v = struct.unpack_from("<f", self.buf, self.pos)[0]
        self.pos += 4
        return v

    def f64(self):
        v = struct.unpack_from("<d", self.buf, self.pos)[0]
        self.pos += 8
        return v

    def string(self):
        n = self.u32()
        s = self.buf[self.pos:self.pos + n].decode("utf-8", "replace")
        # Godot pads every encoded string to a 4-byte boundary.
        self.pos += n + ((4 - (n % 4)) % 4 if n % 4 else 0)
        return s


def decode_variant(r):
    """Returns (python_value, godot_type_id)."""
    head = r.u32()
    t = head & 0xFFFF
    flags = head & 0xFFFF0000

    if t == VAR_NIL:
        return None, t
    if t == VAR_BOOL:
        return bool(r.u32()), t
    if t == VAR_INT:
        return (r.i64() if flags & ENCODE_FLAG_64 else r.i32()), t
    if t == VAR_FLOAT:
        return (r.f64() if flags & ENCODE_FLAG_64 else r.f32()), t
    if t in (VAR_STRING, VAR_STRING_NAME):
        return r.string(), t
    if t == VAR_NODE_PATH:
        # Not a plain string: the leading u32 has its high bit set to mark the
        # current format, and reading it as a length is what sent this decoder
        # 2GB past the end of the buffer the first time.
        head2 = r.u32()
        if not (head2 & 0x80000000):
            raise ValueError("pre-4.x NodePath encoding")
        namecount = head2 & 0x7FFFFFFF
        subnamecount = r.u32()
        flags = r.u32()
        if flags & 2:  # obsolete layout, property split out of the subpath
            subnamecount += 1
        parts = [r.string() for _ in range(namecount + subnamecount)]
        path = "/".join(parts[:namecount])
        if subnamecount:
            path += ":" + ":".join(parts[namecount:])
        return ("/" + path if flags & 1 else path), t
    if t in (VAR_VECTOR2, VAR_VECTOR2I):
        return ((r.f32(), r.f32()) if t == VAR_VECTOR2 else (r.i32(), r.i32())), t
    if t == VAR_COLOR:
        return (r.f32(), r.f32(), r.f32(), r.f32()), t
    if t == VAR_ARRAY:
        n = r.u32() & 0x7FFFFFFF
        return [decode_variant(r)[0] for _ in range(n)], t
    if t == VAR_DICTIONARY:
        n = r.u32() & 0x7FFFFFFF
        d = {}
        for _ in range(n):
            k = decode_variant(r)[0]
            d[k if isinstance(k, (str, int, float, bool)) else str(k)] = decode_variant(r)[0]
        return d, t
    raise ValueError(f"unhandled Variant type {t}")


def literal(value, t):
    if t == VAR_NIL:
        return "null"
    if t == VAR_BOOL:
        return "true" if value else "false"
    if t == VAR_STRING:
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t") + '"'
    if t == VAR_STRING_NAME:
        return '&"' + value.replace('"', '\\"') + '"'
    if t == VAR_NODE_PATH:
        return '^"' + value.replace('"', '\\"') + '"'
    if t == VAR_FLOAT:
        # A float constant that is integral still has to print a decimal point,
        # or "1.0" comes back as "1" and silently changes the type.
        return f"{value!r}" if value != int(value) else f"{int(value)}.0"
    if t in (VAR_VECTOR2, VAR_VECTOR2I):
        return f"Vector2({value[0]}, {value[1]})"
    if t == VAR_COLOR:
        return f"Color({value[0]}, {value[1]}, {value[2]}, {value[3]})"
    if isinstance(value, list):
        return "[" + ", ".join(str(v) for v in value) + "]"
    return str(value)


def parse(path):
    raw = open(path, "rb").read()
    if raw[:4] != b"GDSC":
        raise ValueError(f"{path}: not a GDSC buffer")

    version = struct.unpack_from("<I", raw, 4)[0]
    dsize = struct.unpack_from("<I", raw, 8)[0]
    body = raw[12:] if dsize == 0 else zstandard.ZstdDecompressor().decompress(
        raw[12:], max_output_size=dsize)

    r = Reader(body)
    ident_count = r.u32()
    const_count = r.u32()
    line_count = r.u32()
    # The token count moved in the revision that changed the content header;
    # version 101 is after that change, so it sits at offset 12.
    token_count = r.u32()

    identifiers = []
    for _ in range(ident_count):
        n = r.u32()
        chars = []
        for j in range(n):
            b = bytes(x ^ 0xB6 for x in body[r.pos + j * 4: r.pos + j * 4 + 4])
            chars.append(chr(struct.unpack("<I", b)[0]))
        r.pos += n * 4
        identifiers.append("".join(chars))

    constants = [decode_variant(r) for _ in range(const_count)]

    token_lines = {}
    for _ in range(line_count):
        idx = r.u32()
        token_lines[idx] = r.u32()
    token_columns = {}
    for _ in range(line_count):
        idx = r.u32()
        token_columns[idx] = r.u32()

    tokens = []
    for _ in range(token_count):
        # 5-byte record (1 byte of token, 4 of line) unless bit 7 of the first
        # byte is set, in which case the token itself is 4 bytes because it
        # carries an identifier or constant index above it.
        if body[r.pos] & TOKEN_BYTE_MASK:
            val = r.u32()
        else:
            val = body[r.pos]
            r.pos += 1
        end_line = r.u32()
        local = val & TOKEN_MASK
        payload = val >> TOKEN_BITS
        name = LOCAL_TOKENS[local] if local < len(LOCAL_TOKENS) else "TK_ERROR"
        tokens.append((LOCAL_TO_GLOBAL.get(name, "G_TK_ERROR"), payload, end_line))

    return version, identifiers, constants, token_lines, token_columns, tokens


# A token that has to be separated from a bare word next to it, or "func"
# and the function name run together into "func_enter_tree". The token table
# carries a trailing space on most keywords but not on all of them.
_WORDY = ("G_TK_IDENTIFIER", "G_TK_CONSTANT", "G_TK_ANNOTATION", "G_TK_SELF",
          "G_TK_PR_SUPER", "G_TK_UNDERSCORE", "G_TK_CONST_PI", "G_TK_CONST_TAU",
          "G_TK_CONST_INF", "G_TK_CONST_NAN", "G_TK_WILDCARD")


def render(identifiers, constants, token_lines, token_columns, tokens):
    """Godot 4.x does NOT emit newline/indent/dedent tokens - they were the
    obvious thing to look for and they are simply not in the stream. Line
    structure lives entirely in the sparse line/column tables: an entry at
    token index i means token i is the first one on a new line, and its column
    is that line's indentation. Everything here is driven off that."""
    out = []
    line = ""
    indent = 0
    prev_line = 0

    def flush():
        nonlocal line
        out.append(("\t" * indent + line).rstrip() if line.strip() else "")
        line = ""

    prev_kind = None
    for i, (g, payload, _end) in enumerate(tokens):
        if i in token_lines:
            if line or out:
                flush()
            new_line = token_lines[i]
            # Blank lines are not tokenised either; the jump in line number is
            # the only surviving evidence of them.
            for _ in range(max(0, new_line - prev_line - 1)):
                out.append("")
            prev_line = new_line
            # Columns are 1-based and the sources use tabs, so the column of
            # the first token on the line is its indent depth plus one.
            indent = max(0, token_columns.get(i, 1) - 1)
            prev_kind = None

        if g in ("G_TK_EOF", "G_TK_EMPTY"):
            continue

        if g == "G_TK_IDENTIFIER":
            text = identifiers[payload] if payload < len(identifiers) else "<?ident>"
        elif g == "G_TK_ANNOTATION":
            # The identifier already carries the leading @.
            text = identifiers[payload] if payload < len(identifiers) else "@<?ann>"
        elif g == "G_TK_CONSTANT":
            text = literal(*constants[payload]) if payload < len(constants) else "<?const>"
        else:
            text = TOKEN_TEXT.get(g, f"<?{g}>")

        # Two bare words must not fuse. The token table gives most keywords a
        # trailing space but nothing puts one *before* them, which is how
        # "@export var" came back as "@exportvar" and "func _enter_tree" as
        # "func_enter_tree". Keying this on identifiers alone was not enough -
        # "return" followed by a literal produced "return24.0" and
        # 'return"Unknown"', both syntax errors. The rule is about word
        # characters and quotes, not about which token type it is; "(" after an
        # identifier is a call and must stay glued.
        if (line and not line.endswith(" ") and text
                and (line[-1].isalnum() or line[-1] == "_")
                and (text[0].isalnum() or text[0] in "_\"'&^@$")):
            line += " "
        line += text
        prev_kind = g

    if line.strip():
        flush()
    return "\n".join(out).rstrip() + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--out", help="write <name>.gd into this directory instead of stdout")
    args = ap.parse_args()

    for path in args.files:
        version, identifiers, constants, token_lines, token_columns, tokens = parse(path)
        src = render(identifiers, constants, token_lines, token_columns, tokens)
        if args.out:
            os.makedirs(args.out, exist_ok=True)
            dest = os.path.join(args.out, os.path.basename(path)[:-4] + ".gd")
            open(dest, "w").write(src)
            print(f"{dest}  ({len(src.splitlines())} lines, bytecode v{version}, "
                  f"{len(identifiers)} identifiers, {len(constants)} constants, "
                  f"{len(tokens)} tokens)")
        else:
            print(f"########## {path}  (bytecode v{version})")
            print(src)


if __name__ == "__main__":
    main()
