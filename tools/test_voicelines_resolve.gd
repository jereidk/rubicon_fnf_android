extends SceneTree

## Every voiceline in every group has to resolve to real audio.
##
## Voicelines are no longer loaded with the room: a VoicelineEntry holds a path
## and resolves it on first use, which takes 109 files off a cold load that is
## bound by per-file cost. The data for 32 groups was rewritten mechanically to
## match, and the failure mode of getting that wrong is the worst kind - a line
## whose audio is silently missing plays as silence, with the dialogue text
## still on screen and no error anywhere.
##
## So this walks every group and insists each line has audio that exists. It is
## written to pass both before and after the migration, so it can be run on
## either side of it and mean the same thing.
##
## Run with:
##   godot --headless --path . --script tools/test_voicelines_resolve.gd

const GROUPS_DIR := "res://lullaby_mod/resources/audio/vox/groups"

var _failures: int = 0
var _groups: int = 0
var _entries: int = 0
var _by_path: int = 0
var _by_ref: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var dir := DirAccess.open(GROUPS_DIR)
	if dir == null:
		print("FALLO: no pude abrir %s" % GROUPS_DIR)
		quit(1)
		return

	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		_check_group(GROUPS_DIR.path_join(file))

	print("")
	print("%d grupos, %d lineas (%d por ruta, %d por referencia directa)" % [
		_groups, _entries, _by_path, _by_ref,
	])

	if _groups == 0:
		print("FALLO: no se examino ningun grupo")
		quit(1)
		return

	# The shop reaches 109 lines through these groups. A migration that quietly
	# dropped entries would still report every surviving one as fine, so the
	# count is part of the check.
	if _entries < 100:
		print("FALLO: solo %d lineas, se esperaban ~109" % _entries)
		quit(1)
		return

	if _failures == 0:
		print("todo OK - cada linea tiene audio")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

func _check_group(path: String) -> void:
	var group: Resource = ResourceLoader.load(path)
	if group == null:
		_fail(path.get_file(), "el grupo no carga")
		return
	if not (group is VoicelineGroup):
		return

	_groups += 1
	var index: int = 0
	for entry in group.voicelines:
		var label: String = "%s[%d]" % [path.get_file(), index]
		index += 1

		if entry == null:
			_fail(label, "entrada nula")
			continue

		_entries += 1

		# One of the two has to be there. Both empty is a silent line.
		var has_ref: bool = entry.stream != null
		var has_path: bool = not entry.stream_path.is_empty()

		if not has_ref and not has_path:
			_fail(label, "sin audio: stream nulo y stream_path vacio (\"%s\")"
				% entry.dialogue_text.substr(0, 40))
			continue

		if has_ref:
			_by_ref += 1
			continue

		_by_path += 1
		if not ResourceLoader.exists(entry.stream_path):
			_fail(label, "la ruta no existe: %s" % entry.stream_path)
			continue

		# The path resolving is the migration's contract; loading it is the
		# engine's. Both are checked because a path can exist and still not be
		# an AudioStream if the rewrite crossed two ids.
		var stream: Variant = entry.get_stream()
		if stream == null:
			_fail(label, "get_stream() devolvio null para %s" % entry.stream_path)
		elif not (stream is AudioStream):
			_fail(label, "no es AudioStream: %s" % entry.stream_path)

func _fail(label: String, why: String) -> void:
	_failures += 1
	print("  FALLO %-40s %s" % [label, why])
