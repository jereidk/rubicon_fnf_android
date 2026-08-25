extends SceneTree

## No .tscn may declare a node before the parent it hangs from.
##
## What this caught, and how it hid. Chimera's `PreludeCaption` was moved from
## `Prelude` (a Node2D on canvas 0) into `UILayer` so the pre-rendered video
## could not bake its translated text. The `parent="..."` was rewritten; the
## block was not moved. It sat at line 14863 declaring `parent="UILayer"`,
## which this same file does not declare until line 14955 - 92 lines further
## down. Godot resolves a parent against nodes it has already built, so the
## caption was dropped from the tree entirely.
##
## Nothing said so. The scene loaded, the song played, and the only trace was
## two lines in a render log:
##
##     WARNING: AnimationMixer: '101_prelude', couldn't resolve track:
##       '../UILayer/PreludeCaption:text'
##       '../UILayer/PreludeCaption:modulate'
##
## Which is a warning, in a step that greps for it and prints a warning back.
## Meanwhile Chimera's prelude story cards - the ones naming Serena - had
## stopped appearing in the game, and the missing text read as the video's
## overlay exclusion WORKING. A bug that looks like a feature succeeding is
## the kind that stays shipped.
##
## The rule is deliberately narrow: only a parent that IS declared in the same
## file, but LATER, is a failure. Inherited scenes are the reason. Six .tscn in
## this project hang nodes off `Armature`, `Skeleton3D` or `HexRig`, which
## exist in a .gltf base scene and are never declared in the .tscn at all - a
## naive "have I seen this parent yet" check calls all six broken. Requiring
## the parent to be present-but-later separates a typo from an inherited tree
## with no guesswork, and reports zero false positives across the project.
##
## Run with:
##   godot --headless --path . --script tools/test_scene_node_order.gd

var _failures: int = 0
var _scenes: int = 0
var _nodes: int = 0


func _initialize() -> void:
	var scenes: PackedStringArray = []
	_collect("res://", scenes)

	var header := RegEx.create_from_string('^\\[node name="([^"]+)"')
	var parent_of := RegEx.create_from_string('parent="([^"]+)"')

	for path: String in scenes:
		var text: String = FileAccess.get_file_as_string(path)
		if text.is_empty():
			continue
		_scenes += 1

		# Primera pasada: donde se declara cada ruta.
		var line_of: Dictionary = {}
		var rows: Array = []
		var line: int = 0
		for raw: String in text.split("\n"):
			line += 1
			var head: RegExMatch = header.search(raw)
			if head == null:
				continue
			var name: String = head.get_string(1)
			var found: RegExMatch = parent_of.search(raw)
			var parent: String = found.get_string(1) if found != null else "."
			var full: String = name if parent == "." else "%s/%s" % [parent, name]
			line_of[full] = line
			rows.append([line, name, parent])
			_nodes += 1

		for row: Array in rows:
			var at: int = row[0]
			var parent: String = row[2]
			if parent == "." or not line_of.has(parent):
				continue
			var declared: int = int(line_of[parent])
			if declared <= at:
				continue
			_failures += 1
			printerr('  FALLO %s:%d  "%s" cuelga de "%s", que no se declara hasta la linea %d'
				% [path, at, row[1], parent, declared])

	print("")
	print("%d escenas, %d nodos, %d fallos" % [_scenes, _nodes, _failures])
	if _failures == 0:
		print("todo OK - ningun nodo se declara antes que su padre")
	quit(1 if _failures > 0 else 0)


## Every .tscn under res://, skipping the import cache.
func _collect(dir_path: String, out: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			_collect(full, out)
		elif entry.ends_with(".tscn"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
