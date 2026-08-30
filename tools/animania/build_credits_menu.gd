# Authors animania_mod/menus/credits/credits_menu.tscn.
#
#   godot --headless --path . --script tools/animania/build_credits_menu.gd
#
# The roll is read from animania_mod/source/data/credits.json, which is the mod's own file
# vendored - 36 entries, each with a name and a list of roles. CreditsMenu itself is
# compiled and its layout was not recovered, so the placement here is this port's and is
# marked as such.
extends SceneTree

const OUT := "res://animania_mod/menus/credits/credits_menu.tscn"
const DATA := "res://animania_mod/source/data/credits.json"
const SCREEN := Vector2(1920.0, 1080.0)

var _root: Node2D


func _init() -> void:
	_root = Node2D.new()
	_root.name = "CreditsMenu"
	_root.set_script(load("res://animania_mod/menus/credits/credits_menu.gd"))

	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.position = SCREEN * 0.5
	_add(camera)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.07, 0.06, 0.11, 1.0)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(backdrop)
	backdrop.set(&"layout_mode", 0)
	backdrop.size = SCREEN

	var rows := Node2D.new()
	rows.name = "Rows"
	_add(rows)

	var constants: Dictionary = _root.get_script().get_script_constant_map()
	var row_height: float = constants["ROW_HEIGHT"]
	var centre: Vector2 = constants["LIST_CENTRE"]

	var entries: Array = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	for i: int in entries.size():
		var entry: Dictionary = entries[i]
		var roles: Array = entry.get("roles", [])

		var row := Node2D.new()
		row.name = "Row%d" % i
		row.position = Vector2(centre.x, row_height * float(i))
		rows.add_child(row)
		row.owner = _root

		var name_label := Label.new()
		name_label.name = "Name"
		name_label.text = String(entry["name"])
		name_label.add_theme_font_size_override("font_size", 40)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(name_label)
		name_label.owner = _root
		name_label.set(&"layout_mode", 0)
		name_label.position = Vector2(0.0, -26.0)

		var roles_label := Label.new()
		roles_label.name = "Roles"
		roles_label.text = ", ".join(roles)
		roles_label.add_theme_font_size_override("font_size", 24)
		roles_label.add_theme_color_override("font_color", Color(0.72, 0.68, 0.85, 1.0))
		roles_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(roles_label)
		roles_label.owner = _root
		roles_label.set(&"layout_mode", 0)
		roles_label.position = Vector2(420.0, -18.0)

		# In the row's LOCAL space, the same shape every other list in this port uses. Wide
		# enough to cover the name and the roles beside it.
		row.set_meta(&"hitbox", Rect2(Vector2(-30.0, -34.0), Vector2(1100.0, 68.0)))

	var sfx := AudioStreamPlayer.new()
	sfx.name = "Sfx"
	sfx.bus = &"Master"
	_add(sfx)

	_root.set(&"rows", rows)
	_root.set(&"sfx", sfx)

	var packed := PackedScene.new()
	packed.pack(_root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT).get_base_dir())
	var err: int = ResourceSaver.save(packed, OUT)
	print("OUT %d entradas, %s %s" % [entries.size(), "saved" if err == OK else "FAILED", OUT])
	quit(0 if err == OK else 1)


func _add(node: Node) -> void:
	_root.add_child(node)
	node.owner = _root
