extends Control
## HQ Gallery — browse the mod's concept art by category.
## Ports the mod's HQGallery state: category select -> art browser with
## prev/next, zoom (accept), pan (arrows) and help text.

const CATAS: Array[String] = [
	"Girlfriend", "Sayaka", "Mami", "Madoka", "Kyoko", "Homura",
	"Kyubey", "meguca", "Promo", "Fanart", "UI", "Scrapped",
]
const CATA_FOLDERS: Array[String] = [
	"GF", "Sayaka", "Mami", "Madoka", "Kyoko", "Homura",
	"Kyubey", "Meguca", "Promo", "Fan Art", "UI", "Scrapped",
]
const ART_JSON := "res://holyquintet_mod/source/data/gallery_artworks.json"

var is_selecting_cata: bool = true
var is_zoomed: bool = false
var cur_cata: int = 0
var cur_art: int = 0
var _artworks: Array[Dictionary] = []
var _art_tex: TextureRect

@onready var name_label: Label = $NameLabel
@onready var help_label: Label = $HelpLabel
@onready var fade_rect: ColorRect = $FadeRect
@onready var cata_list: VBoxContainer = $CataOverlay/CataList
@onready var cata_overlay: Control = $CataOverlay

func _ready() -> void:
	fade_rect.modulate.a = 1.0
	var tw = create_tween()
	tw.tween_property(fade_rect, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN_OUT)
	_build_cata_list()
	HQSaves.unlock_achievement("ChamberOfLight")

func _build_cata_list() -> void:
	for i in CATAS.size():
		var lbl := Label.new()
		lbl.text = CATAS[i]
		lbl.add_theme_font_size_override("font_size", 40)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cata_list.add_child(lbl)
	_cata_refresh()

func _cata_refresh() -> void:
	for i in cata_list.get_child_count():
		var lbl := cata_list.get_child(i) as Label
		if lbl != null:
			lbl.text = ("►  " if i == cur_cata else "    ") + CATAS[i]
			lbl.modulate = Color.WHITE if i == cur_cata else Color(0.6, 0.6, 0.6)

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		if is_selecting_cata:
			_go_back()
		else:
			_open_cata_select()
		return
	if is_selecting_cata:
		if Input.is_action_just_pressed("ui_up"):
			cur_cata = wrapi(cur_cata - 1, 0, CATAS.size())
			_cata_refresh()
		elif Input.is_action_just_pressed("ui_down"):
			cur_cata = wrapi(cur_cata + 1, 0, CATAS.size())
			_cata_refresh()
		elif Input.is_action_just_pressed("ui_accept"):
			_load_cata()
	else:
		if is_zoomed:
			var amt := 500.0
			if _art_tex != null:
				if Input.is_action_pressed("ui_left"):
					_art_tex.position.x += amt * _delta
				elif Input.is_action_pressed("ui_right"):
					_art_tex.position.x -= amt * _delta
				elif Input.is_action_pressed("ui_up"):
					_art_tex.position.y += amt * _delta
				elif Input.is_action_pressed("ui_down"):
					_art_tex.position.y -= amt * _delta
		else:
			if Input.is_action_just_pressed("ui_left"):
				_switch_art(-1)
			elif Input.is_action_just_pressed("ui_right"):
				_switch_art(1)
		if Input.is_action_just_pressed("ui_accept"):
			_toggle_zoom()

func _load_cata() -> void:
	var data: Variant = _load_json(ART_JSON)
	if data is Dictionary:
		_artworks = data.get(str(cur_cata), [])
		cur_art = 0
		if _artworks.is_empty():
			return
		# Swap to art browser
		cata_overlay.visible = false
		is_selecting_cata = false
		is_zoomed = false
		_show_art()

func _show_art() -> void:
	if _art_tex != null:
		_art_tex.queue_free()
	if _artworks.is_empty():
		return
	var art: Dictionary = _artworks[cur_art]
	var folder := CATA_FOLDERS[cur_cata]
	var path := "res://holyquintet_mod/source/images/ui/gallery/art/%s/%s.png" % [folder, art["file"]]
	if not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	_art_tex = TextureRect.new()
	_art_tex.texture = tex
	_art_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var zoom: float = float(art["zoom"])
	_art_tex.size = Vector2(tex.get_width() * zoom, tex.get_height() * zoom)
	_art_tex.position = (Vector2(1920, 1080) - _art_tex.size) / 2.0
	_art_tex.z_index = 5
	_art_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art_tex)
	name_label.text = "%s\nBy: %s" % [art["art"], art["artist"]]
	help_label.text = "%d / %d  ·  %s  ·  By: %s" % [cur_art + 1, _artworks.size(), art["art"], art["artist"]]
	HQSaves.unlock_achievement("ChamberOfLight")

func _switch_art(amount: int) -> void:
	if _artworks.is_empty():
		return
	cur_art = wrapi(cur_art + amount, 0, _artworks.size())
	_show_art()

func _toggle_zoom() -> void:
	is_zoomed = not is_zoomed
	if is_zoomed:
		help_label.visible = true
		if _art_tex != null:
			_art_tex.position += Vector2(50, 50)
	else:
		_show_art()

func _open_cata_select() -> void:
	is_selecting_cata = true
	cata_overlay.visible = true
	if _art_tex != null:
		_art_tex.queue_free()
		_art_tex = null
	_cata_refresh()

func _go_back() -> void:
	var tw = create_tween()
	tw.tween_property(fade_rect, "modulate:a", 1.0, 0.4).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): get_tree().change_scene_to_file("res://holyquintet_mod/menus/main/main_menu.tscn"))

func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		return null
	return json.data
