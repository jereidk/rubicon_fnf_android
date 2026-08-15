extends SceneTree

## Loads every scene this session edited by hand, and says why if one fails.
##
## Four .tscn files were rewritten with text scripts rather than through the
## editor: the shop's voiceline dictionary, its sequence audio, its
## AnimationLibrary entry, and the console's portrait sheet. Every test written
## alongside those changes checks the text and the dependency list. None of
## them ever asked Godot to parse the result, so a malformed line - a dangling
## SubResource, an ext_resource id removed while something still pointed at it,
## a broken bracket - would pass all of them and only surface when the player
## opened the room.
##
## It cannot do that by calling load(). This checkout's imported textures are
## Git LFS pointers that were never pulled, so load() fails on the assets and
## a blanket "did it open" would be red for reasons that have nothing to do
## with the edits. So the file is read as text instead and every reference it
## makes internally is resolved against its own declarations - which is
## precisely the damage a text edit does, and needs no asset at all.
##
## Run with:
##   godot --headless --path . --script tools/test_scenes_parse.gd

const EDITED := [
	"res://lullaby_mod/rooms/env_collector_shop.tscn",
	"res://lullaby_mod/resources/console/console.tscn",
]

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	for path: String in EDITED:
		_check_scene(path)

	print("")
	if _checks < EDITED.size() * 2:
		print("FALLO: solo %d comprobaciones de %d" % [_checks, EDITED.size() * 2])
		quit(1)
		return
	if _failures == 0:
		print("todo OK - las escenas editadas siguen siendo texto valido")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

func _check_scene(path: String) -> void:
	_check("%s existe" % path.get_file(), ResourceLoader.exists(path))

	# The structural read: parse the file as text and confirm every reference
	# it makes internally still resolves. This is what the hand edits could
	# have broken, and unlike load() it does not need a single texture.
	var problems: PackedStringArray = _structure_problems(path)
	_check("%s no tiene referencias colgando" % path.get_file(),
		problems.is_empty(),
		"; ".join(problems) if not problems.is_empty() else "")

## Every ExtResource(...) and SubResource(...) used in the body must be
## declared in a header block, and nothing may be declared twice.
##
## This is exactly the damage a text edit does: removing an [ext_resource]
## line while an assignment still names its id, or removing the last
## assignment and leaving the declaration behind. The first breaks the scene
## at load; the second is dead weight that keeps the dependency alive.
func _structure_problems(path: String) -> PackedStringArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedStringArray(["no se puede abrir"])
	var text: String = file.get_as_text()
	file.close()

	var problems: PackedStringArray = PackedStringArray()

	# Anchored on a space before id= on purpose. A plain find("id=") matches
	# the "id=" inside uid= first, which reads every declaration's uid as its
	# id - and then every numeric ExtResource in the body looks undeclared.
	# The first run of this test reported three hundred dangling references on
	# two files that are perfectly fine.
	var declares := RegEx.new()
	declares.compile('^\\[(ext|sub)_resource .*? id="([^"]+)"\\]')

	var declared_ext: Dictionary = {}
	var declared_sub: Dictionary = {}
	for line in text.split("\n"):
		var m := declares.search(line)
		if m == null:
			continue
		var id: String = m.get_string(2)
		if m.get_string(1) == "ext":
			if declared_ext.has(id):
				problems.append("ext_resource id %s declarado dos veces" % id)
			declared_ext[id] = 0
		else:
			if declared_sub.has(id):
				problems.append("sub_resource id %s declarado dos veces" % id)
			declared_sub[id] = 0

	var used_ext := RegEx.new()
	used_ext.compile('ExtResource\\("([^"]+)"\\)')
	for m in used_ext.search_all(text):
		var id: String = m.get_string(1)
		if not declared_ext.has(id):
			problems.append("ExtResource(\"%s\") usado sin declarar" % id)
		else:
			declared_ext[id] += 1

	var used_sub := RegEx.new()
	used_sub.compile('SubResource\\("([^"]+)"\\)')
	for m in used_sub.search_all(text):
		var id: String = m.get_string(1)
		if not declared_sub.has(id):
			problems.append("SubResource(\"%s\") usado sin declarar" % id)
		else:
			declared_sub[id] += 1

	# Orphaned declarations are not a load failure, so they are reported
	# separately rather than folded into the same verdict - except that on a
	# scene edited to REMOVE a dependency, an orphan is the edit not having
	# worked.
	var orphans: Array[String] = []
	for id in declared_ext:
		if declared_ext[id] == 0:
			orphans.append(id)
	if not orphans.is_empty():
		problems.append("ext_resource declarados y sin usar: %s" % ", ".join(orphans))

	return problems

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-52s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-52s%s" % [label, "  (%s)" % detail if detail else ""])
