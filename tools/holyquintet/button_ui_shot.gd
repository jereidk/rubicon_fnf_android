extends Node
# Checks ButtonUI in isolation: basic style selected/unselected/locked, and
# small style with an icon, before wiring it into the much larger HQMainMenu.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/button_ui_shot.tscn

const SHOT_DIR := "/tmp/hq_renders"
const ButtonScene := preload("res://holyquintet_mod/ui/button_ui.tscn")

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var bg := ColorRect.new()
	bg.color = Color(0.15, 0.15, 0.2)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_make("basic", Vector2(50, 50), "Story", false, false)
	_make("basic", Vector2(550, 50), "Freeplay", true, false)
	_make("basic", Vector2(1050, 50), "Gauntlet", false, true)
	_make("basic", Vector2(50, 300), "Gauntlet", true, true)
	_make("small", Vector2(50, 550), "", false, false, "gamejoltoff")
	_make("small", Vector2(300, 550), "", true, false, "shop")

	await get_tree().create_timer(0.6).timeout
	await _shoot("button_ui_states.png")
	print("BUTTON_UI_SHOT: saved")
	get_tree().quit()


func _make(style: String, pos: Vector2, txt: String, sel: bool, lock: bool, icon: String = "none") -> void:
	var b = ButtonScene.instantiate()
	b.style = style
	b.text = txt
	b.icon = icon
	add_child(b)
	b.position = pos
	# real order matters: HQMainMenu sets .locked once right after
	# construction, before changeSelection() ever touches .selected — the
	# selected setter's own color branch depends on locked already being
	# correct by the time it runs.
	b.locked = lock
	b.selected = sel


func _shoot(filename: String) -> void:
	await get_tree().process_frame
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(SHOT_DIR + "/" + filename)
	print("BUTTON_UI_SHOT: saved ", filename)
