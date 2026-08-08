extends SceneTree

## Diffs every ported script's string pool against the same script in the PC pck.
##
## Why this exists: an exported .gdc is a binary *token* stream, and its
## identifier and constant tables survive intact. So for any script the port
## carried over, the pck tells us every node name, property name, animation
## name, path and string literal the original used - and anything in that list
## that does not appear anywhere in our source is a place the port drifted.
##
## This found its first bug immediately. monochrome/typing_challenge.gdc uses
## Color("333333") twice in the original; ours says Color(0.247, 0.247, 0.247)
## twice. 0x33/255 is 0.2, not 0.247 - the hex was converted by hand and got
## the wrong value, so Celebi's dimmed state renders brighter than it should.
## Nothing else would have caught that: the data is identical, the scene is
## identical, and the code "looks right".
##
## It is a lead generator, not a verdict. A miss can mean the port renamed
## something deliberately, computed a literal instead of writing it, or split
## one script into two. Read each hit, do not bulk-fix them.
##
## Usage:
##   godot --headless --script tools/sweep_pck_strings.gd            # summary
##   godot --headless --script tools/sweep_pck_strings.gd -- <substr> # detail

const PCK_PATH := "res://lullaby_mod/original_pck/Lullaby.pck"
const MIN_RUN := 4

## The pck is the mod's own root; the port re-homes most of it under
## lullaby_mod/ but keeps addons/ where it was. Both are tried.
const PREFIXES := ["res://lullaby_mod/", "res://"]

## Brute-forcing printable runs out of a token stream yields real strings plus
## noise from the token bytes themselves. Anything that is not a plausible
## identifier or a human-readable phrase is dropped rather than reported as a
## difference nobody can act on.
func _is_meaningful(s: String) -> bool:
	if s.length() < MIN_RUN:
		return false

	# Hex colour literals are the highest-value case this sweep has found and
	# they carry no letters at all, so they are admitted before the
	# letters-based noise filter below can throw them out. Color("333333") in
	# the original against Color(0.247, ...) in the port was exactly this.
	if s.is_valid_hex_number(false) and (s.length() == 6 or s.length() == 8):
		return true

	var letters := 0
	for i in s.length():
		var c := s[i]
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z"):
			letters += 1
	# Mostly-punctuation runs like ",/////o" and repeated-glyph runs like
	# "IIII" are token bytes, not content.
	if letters < 3 or float(letters) / float(s.length()) < 0.5:
		return false

	var distinct := {}
	for i in s.length():
		distinct[s[i]] = true
	return distinct.size() >= 3

func _init() -> void:
	var needles: Array[String] = []
	for a in OS.get_cmdline_user_args():
		needles.append(a.to_lower())

	if not ProjectSettings.load_resource_pack(PCK_PATH, false):
		printerr("could not mount ", PCK_PATH)
		quit(1)
		return

	var scripts: Array[String] = []
	_walk("res://", scripts)

	var missing_total := 0
	var compared := 0
	var absent: Array[String] = []
	var report: Array = []

	for pck_path in scripts:
		var ours := _port_path(pck_path)
		if ours.is_empty():
			absent.append(pck_path)
			continue

		var source := FileAccess.get_file_as_string(ours)
		if source.is_empty():
			absent.append(pck_path)
			continue

		compared += 1
		var missing: Array[String] = []
		for s in _strings_of(pck_path):
			if not _is_meaningful(s):
				continue
			if s in source:
				continue
			if not missing.has(s):
				missing.append(s)

		if not missing.is_empty():
			missing_total += missing.size()
			report.append([missing.size(), pck_path, ours, missing])

	report.sort_custom(func(a, b): return a[0] > b[0])

	print("pck scripts: %d   compared against port source: %d   no counterpart found: %d"
		% [scripts.size(), compared, absent.size()])
	print("scripts with at least one missing string: %d   missing strings total: %d\n"
		% [report.size(), missing_total])

	for row in report:
		if not needles.is_empty():
			var hay: String = String(row[1]).to_lower()
			var match_found := false
			for n in needles:
				if n in hay:
					match_found = true
			if not match_found:
				continue
		print("%3d  %s" % [row[0], row[1]])
		print("     -> %s" % row[2])
		if not needles.is_empty():
			for s in row[3]:
				print("        %s" % s)

	if needles.is_empty():
		print("\n(pass a path substring after -- to list the missing strings for a script)")

	quit()

func _port_path(pck_path: String) -> String:
	var rest := pck_path.substr("res://".length())
	var as_gd := rest.trim_suffix(".gdc") + ".gd"
	for prefix in PREFIXES:
		var candidate: String = prefix + as_gd
		if FileAccess.file_exists(candidate):
			return candidate
	return ""

func _strings_of(path: String) -> Array[String]:
	var out: Array[String] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out

	var raw := file.get_buffer(file.get_length())
	if raw.size() < 12 or raw.slice(0, 4).get_string_from_ascii() != "GDSC":
		return out

	var decompressed_size := raw.decode_u32(8)
	var body: PackedByteArray = raw.slice(12)
	if decompressed_size > 0:
		body = body.decompress(decompressed_size, FileAccess.COMPRESSION_ZSTD)

	# Identifiers are stored XOR'd with 0xb6, string constants plainly.
	out.append_array(_scan(body, 0))
	out.append_array(_scan(body, 0xb6))
	return out

func _scan(bytes: PackedByteArray, key: int) -> Array[String]:
	var found: Array[String] = []
	var current := ""
	for i in bytes.size():
		var c := bytes[i] ^ key
		if c >= 32 and c < 127:
			current += char(c)
		else:
			if current.length() >= MIN_RUN:
				found.append(current)
			current = ""
	if current.length() >= MIN_RUN:
		found.append(current)
	return found

func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full: String = dir_path.path_join(entry)
			if dir.current_is_dir():
				# res://lullaby_mod is the port's own tree overlaid on the
				# mount, not the pck's content.
				if not full.begins_with("res://lullaby_mod") and not full.begins_with("res://.godot"):
					_walk(full, out)
			elif entry.ends_with(".gdc"):
				out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
