extends SceneTree

## The three sequence voicelines load on first use instead of with the room.
## This checks the lookup still finds them.
##
## sequence_intro is a megabyte of audio that plays once in a save's lifetime,
## sequence_outro half of that, and both used to be ExtResources in
## env_collector_shop.tscn - loaded on every visit. The shop's cold load is
## bound by per-file cost, so they should arrive later.
##
## The failure mode is a cutscene that plays silently with its animation
## running normally, which nothing in the log would report, so both the data
## and the lookup are pinned here.
##
## Run with:
##   godot --headless --path . --script tools/test_sequence_voicelines.gd

const SHOP := "res://lullaby_mod/rooms/env_collector_shop.tscn"
const SCRIPT := "res://lullaby_mod/scripts/lullaby/collectors_shop/Sequences.gd"
const EXPECTED := ["sequence_intro", "sequence_outro", "sequence_sign_intro"]

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	_scene_case()
	await _lookup_case()

	print("")
	if _checks < 8:
		print("FALLO: solo %d de 8 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - las secuencias resuelven su audio")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

## The data: paths present, references gone, files real.
func _scene_case() -> void:
	var file := FileAccess.open(SHOP, FileAccess.READ)
	if file == null:
		_check("se puede leer la escena de la tienda", false)
		return
	var text: String = file.get_as_text()
	file.close()

	_check("la escena usa voiceline_paths", text.contains("voiceline_paths = {"))
	_check("y ya no un diccionario de AudioStream",
		not text.contains("voicelines = {"))

	# Each path must name a file that is really there. A migration that got an
	# id wrong would produce a plausible-looking path to nothing.
	for key in EXPECTED:
		var found: String = ""
		for line in text.split("\n"):
			if line.begins_with('"%s": "res://' % key):
				found = line.split('"')[3]
				break
		_check("%s apunta a un archivo real" % key,
			not found.is_empty() and ResourceLoader.exists(found),
			found.get_file() if not found.is_empty() else "sin ruta")

## The lookup: resolves, caches, and says null for an animation with no line.
func _lookup_case() -> void:
	var node := Node.new()
	node.set_script(load(SCRIPT))
	# Typed to match the export, or the assignment is rejected outright.
	var paths: Dictionary[String, String] = {
		"sequence_intro": "res://lullaby_mod/resources/audio/vox/vox_collector_firstjoin.ogg",
	}
	node.voiceline_paths = paths
	root.add_child(node)
	await process_frame

	var first: Variant = node.get_voiceline("sequence_intro")
	_check("resuelve la linea", first is AudioStream,
		"%s" % ("AudioStream" if first is AudioStream else str(first)))

	# Same object on the second ask, or every frame of a sequence reloads it.
	var second: Variant = node.get_voiceline("sequence_intro")
	_check("y la cachea", first == second)

	_check("una animacion sin linea da null", node.get_voiceline("dance_idle") == null)

	node.queue_free()
	await process_frame

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-44s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-44s%s" % [label, "  (%s)" % detail if detail else ""])
