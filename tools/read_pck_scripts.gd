extends SceneTree

## Reads the GDScript sources bundled in the original PC mod's .pck.
##
## Exported Godot projects ship scripts as .gdc, which looks opaque but is
## not compiled bytecode: since Godot 4.3 it is a *binary token* stream that
## still contains every identifier and string constant, zstd-compressed
## behind a "GDSC" header. That makes the string pool recoverable without any
## external tool - which matters because the pck is the only reference for
## how the mod behaved on PC, and several port bugs have turned out to be
## "the data is identical, so it must be the code".
##
## This does not reconstruct source. It recovers the strings, which is enough
## to answer "which script mentions X" and to rule out "nothing mentions X at
## all" - the second one being the more useful answer more often than
## expected. Identifiers are stored XOR'd with 0xb6 while string constants
## are stored plainly, so both passes are needed.
##
## Usage:
##   godot --headless --script tools/read_pck_scripts.gd -- <substring> [...]
##
## Every argument after -- is matched case-insensitively; a script is printed
## if any of its strings contains any of them. With no arguments, prints one
## line per script with its string count.

const PCK_PATH := "res://lullaby_mod/original_pck/Lullaby.pck"
const MIN_RUN := 4

func _init() -> void:
	if not ProjectSettings.load_resource_pack(PCK_PATH, false):
		printerr("could not mount ", PCK_PATH)
		quit(1)
		return

	var needles: Array[String] = []
	for a in OS.get_cmdline_user_args():
		needles.append(a.to_lower())

	var scripts: Array[String] = []
	_walk("res://", scripts)
	print("scripts .gdc: %d   filtros: %s" % [scripts.size(), needles if not needles.is_empty() else "(ninguno)"])

	for path in scripts:
		var strings := _strings_of(path)
		if needles.is_empty():
			print("  %-70s %d cadenas" % [path, strings.size()])
			continue

		var hits: Array[String] = []
		for s in strings:
			var low := s.to_lower()
			for n in needles:
				if n in low and not hits.has(s):
					hits.append(s)
		if not hits.is_empty():
			print("  %s" % path)
			for h in hits:
				print("      %s" % h)
	quit()

## The payload after the 12-byte header is zstd-compressed when the
## decompressed-size field is non-zero, and stored raw when it is zero.
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
				# res://lullaby_mod is the port's own tree, not the pck's.
				if not full.begins_with("res://lullaby_mod") and not full.begins_with("res://.godot"):
					_walk(full, out)
			elif entry.ends_with(".gdc"):
				out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
