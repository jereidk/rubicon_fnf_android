extends CanvasLayer
## ChangeLog sub-state — faithful port of animania::states::substates::ChangeLogSubState.
##
## An overlay with tabs: NEWS!, Changelog, Socials. Shows scrolling text content
## with a Nessie character that plays dialogue animations and sounds per tab.

# ─── Constants ─────────────────────────────────────────────────────────────

const SCREEN := Vector2(1920.0, 1080.0)
const SOUND_SWITCH := "res://animania_mod/source/sounds/animania/menu/menu_switch.ogg"
const SOUND_CONFIRM := "res://animania_mod/source/sounds/confirmMenu.ogg"
const SOUND_CANCEL := "res://animania_mod/source/sounds/cancelMenu.ogg"

const TABS := ["NEWS!", "Changelog", "Socials"]
const TAB_KEYS := ["news", "changelog", "socials"]

const BANNER_PATH := "res://animania_mod/source/images/menus/changelog/banners/06.png"
const BOARD_BG_PATH := "res://animania_mod/source/images/menus/changelog/board_bg.png"
const SMALL_BOARD_PATH := "res://animania_mod/source/images/menus/changelog/small board.png"
const SMALLER_BOARD_PATH := "res://animania_mod/source/images/menus/changelog/smaller_board.png"
const MAIN_BOARD_PATH := "res://animania_mod/source/images/menus/changelog/main board.png"
const STRIPE_PATH := "res://animania_mod/source/images/menus/changelog/backboard_stripe.png"
const NOODLES_PATH := "res://animania_mod/source/images/menus/changelog/backboard_noodles.png"
const SCROLL_LINE_PATH := "res://animania_mod/source/images/menus/changelog/menu_scroll_line.png"
const NETWORK_CONN_PATH := "res://animania_mod/source/images/menus/changelog/network_connection.png"
const SKIPSQUARE_PATH := "res://animania_mod/source/images/menus/changelog/skipsqare.png"

const FONT_PATH := "res://animania_mod/source/fonts/dephun2.ttf"
const FONT_SMALL_PATH := "res://animania_mod/source/fonts/5by7.ttf"

const NESSIE_DATA_DIR := "res://animania_mod/source/data/changelog/nessie/"

# ─── Fields ───────────────────────────────────────────────────────────────

var _menu_state: Node  ## Parent state reference
var transitioning: bool = false
var current_tab: int = 0
var bg_cam: Camera2D
var changelog_camera: Camera2D
var board: RichTextLabel
var board_label: Label
var board_smaller: RichTextLabel
var socials_visible: bool = false

# UI nodes
var back_panel: ColorRect
var cool_bg: ColorRect
var board_bg: Sprite2D
var text_bg: ColorRect
var stripe: Sprite2D
var noodles: Sprite2D
var banner: Sprite2D
var network_connection: AnimatedSprite2D
var socials_logo: Sprite2D
var scrolling_line: AnimatedSprite2D
var scrolling_square: Sprite2D
var tab_buttons: Array[Label] = []
var back_button: Label
var tab_container: Node2D

# Socials
var socials_nodes: Array[Node2D] = []
var socials_button: Label

# Nessie
var nessie_spr: AnimatedSprite2D
var nessie_tween: Tween

# ─── Lifecycle ────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 10
	_build_ui()
	_create_cameras()
	_create_background()
	_create_board()
	_create_tabs()
	_create_socials()
	_create_nessie()
	_select_tab(0)


func _unhandled_input(event: InputEvent) -> void:
	if transitioning:
		return

	if event.is_action_pressed("ui_cancel"):
		close_self()
	elif event.is_action_pressed("ui_left"):
		_select_tab(wrapi(current_tab - 1, 0, TABS.size()))
	elif event.is_action_pressed("ui_right"):
		_select_tab(wrapi(current_tab + 1, 0, TABS.size()))
	elif event.is_action_pressed("ui_accept"):
		if current_tab == 2:  # Socials tab
			# Socials don't have further selection
			pass


func _process(delta: float) -> void:
	# Animate network connection
	if network_connection and not network_connection.is_playing():
		network_connection.play("idle")


# ─── Scene building ───────────────────────────────────────────────────────

func _build_ui() -> void:
	# Dark overlay background
	cool_bg = ColorRect.new()
	cool_bg.name = "CoolBg"
	cool_bg.offset_right = SCREEN.x
	cool_bg.offset_bottom = SCREEN.y
	cool_bg.color = Color(0, 0, 0, 0.7)
	add_child(cool_bg)

	# Back panel
	back_panel = ColorRect.new()
	back_panel.name = "BackPanel"
	back_panel.offset_right = SCREEN.x
	back_panel.offset_bottom = SCREEN.y
	back_panel.color = Color(0.06, 0.05, 0.1, 1.0)
	add_child(back_panel)

	# Board background
	board_bg = Sprite2D.new()
	board_bg.name = "BoardBg"
	if ResourceLoader.exists(BOARD_BG_PATH):
		board_bg.texture = load(BOARD_BG_PATH) as Texture2D
	board_bg.position = Vector2(SCREEN.x * 0.5, SCREEN.y * 0.5)
	add_child(board_bg)

	# Stripe decoration
	stripe = Sprite2D.new()
	stripe.name = "Stripe"
	if ResourceLoader.exists(STRIPE_PATH):
		stripe.texture = load(STRIPE_PATH) as Texture2D
	stripe.position = Vector2(SCREEN.x * 0.5, SCREEN.y * 0.15)
	stripe.modulate.a = 0.3
	add_child(stripe)

	# Noodles decoration
	noodles = Sprite2D.new()
	noodles.name = "Noodles"
	if ResourceLoader.exists(NOODLES_PATH):
		noodles.texture = load(NOODLES_PATH) as Texture2D
	noodles.position = Vector2(SCREEN.x * 0.85, SCREEN.y * 0.5)
	noodles.modulate.a = 0.2
	add_child(noodles)

	# Banner
	banner = Sprite2D.new()
	banner.name = "Banner"
	if ResourceLoader.exists(BANNER_PATH):
		banner.texture = load(BANNER_PATH) as Texture2D
	banner.position = Vector2(SCREEN.x * 0.5, 60)
	add_child(banner)

	# Scrolling line
	scrolling_line = AnimatedSprite2D.new()
	scrolling_line.name = "ScrollingLine"
	_setup_scroll_line_frames()
	scrolling_line.position = Vector2(SCREEN.x * 0.5, SCREEN.y - 20)
	add_child(scrolling_line)

	# Network connection indicator
	network_connection = AnimatedSprite2D.new()
	network_connection.name = "NetworkConnection"
	_setup_network_frames()
	network_connection.position = Vector2(SCREEN.x - 80, 40)
	add_child(network_connection)

	# Tab container
	tab_container = Node2D.new()
	tab_container.name = "TabContainer"
	add_child(tab_container)

	# Socials logo
	socials_logo = Sprite2D.new()
	socials_logo.name = "SocialsLogo"
	socials_logo.position = Vector2(SCREEN.x * 0.5, SCREEN.y * 0.3)
	socials_logo.visible = false
	add_child(socials_logo)


func _create_cameras() -> void:
	bg_cam = Camera2D.new()
	bg_cam.name = "BgCam"
	bg_cam.position = Vector2(SCREEN.x * 0.5, SCREEN.y * 0.5)
	add_child(bg_cam)

	changelog_camera = Camera2D.new()
	changelog_camera.name = "ChangelogCamera"
	changelog_camera.position = Vector2(SCREEN.x * 0.5, SCREEN.y * 0.5)
	add_child(changelog_camera)


func _create_background() -> void:
	pass  # Background is built in _build_ui


func _create_board() -> void:
	# Main text board (RichTextLabel for formatted text)
	board = RichTextLabel.new()
	board.name = "Board"
	board.position = Vector2(SCREEN.x * 0.15, SCREEN.y * 0.2)
	board.custom_minimum_size = Vector2(SCREEN.x * 0.7, SCREEN.y * 0.6)
	board.fit_content = false
	board.scroll_active = true
	board.bbcode_enabled = true
	if ResourceLoader.exists(FONT_PATH):
		var font := load(FONT_PATH) as Font
		if font:
			board.add_theme_font_size_override("normal_font_size", 20)
	board.add_theme_color_override("default_color", Color.WHITE)
	add_child(board)

	# Board label (tab title)
	board_label = Label.new()
	board_label.name = "BoardLabel"
	board_label.position = Vector2(SCREEN.x * 0.5 - 100, SCREEN.y * 0.12)
	board_label.add_theme_font_size_override("font_size", 32)
	board_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	board_label.custom_minimum_size = Vector2(200, 40)
	add_child(board_label)

	# Smaller board (for sub-content)
	board_smaller = RichTextLabel.new()
	board_smaller.name = "BoardSmaller"
	board_smaller.position = Vector2(SCREEN.x * 0.2, SCREEN.y * 0.25)
	board_smaller.custom_minimum_size = Vector2(SCREEN.x * 0.6, SCREEN.y * 0.5)
	board_smaller.fit_content = false
	board_smaller.scroll_active = true
	board_smaller.bbcode_enabled = true
	board_smaller.visible = false
	add_child(board_smaller)


func _create_tabs() -> void:
	tab_buttons.clear()
	var tab_y := SCREEN.y * 0.85
	var tab_spacing := 250.0
	var start_x := SCREEN.x * 0.5 - (TABS.size() - 1) * tab_spacing * 0.5

	for i in TABS.size():
		var tab := Label.new()
		tab.name = "Tab_%s" % TAB_KEYS[i]
		tab.text = TABS[i]
		tab.add_theme_font_size_override("font_size", 28)
		tab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tab.custom_minimum_size = Vector2(200, 40)
		tab.position = Vector2(start_x + i * tab_spacing, tab_y)
		tab.modulate.a = 0.5 if i != current_tab else 1.0
		tab_container.add_child(tab)
		tab_buttons.append(tab)


func _create_socials() -> void:
	socials_nodes.clear()
	var socials_dir := "res://animania_mod/source/images/menus/changelog/socials/"
	var socials_data := [
		["youtube", Vector2(SCREEN.x * 0.3, SCREEN.y * 0.5)],
		["twitter", Vector2(SCREEN.x * 0.5, SCREEN.y * 0.5)],
		["tiktok", Vector2(SCREEN.x * 0.7, SCREEN.y * 0.5)],
	]
	for data in socials_data:
		var name: String = data[0]
		var pos: Vector2 = data[1]
		var spr := Sprite2D.new()
		spr.name = "Social_%s" % name
		var path := socials_dir + name + "icon.png"
		if ResourceLoader.exists(path):
			spr.texture = load(path) as Texture2D
		spr.position = pos
		spr.visible = false
		add_child(spr)
		socials_nodes.append(spr)

	# News logo for socials tab
	if ResourceLoader.exists(socials_dir + "newslogo.png"):
		socials_logo.texture = load(socials_dir + "newslogo.png") as Texture2D


func _create_nessie() -> void:
	nessie_spr = AnimatedSprite2D.new()
	nessie_spr.name = "Nessie"
	_setup_nessie_frames()
	nessie_spr.position = Vector2(SCREEN.x * 0.15, SCREEN.y * 0.7)
	nessie_spr.visible = false
	add_child(nessie_spr)


# ─── Frame setup ──────────────────────────────────────────────────────────

func _setup_scroll_line_frames() -> void:
	var sf := SpriteFrames.new()
	sf.add_animation(&"scroll")
	var tex := load(SCROLL_LINE_PATH) as Texture2D
	if tex == null:
		return
	var xml_path := SCROLL_LINE_PATH.replace(".png", ".xml")
	if ResourceLoader.exists(xml_path):
		var frames := _parse_adobe_atlas(xml_path)
		for fd in frames:
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(fd["x"], fd["y"], fd["w"], fd["h"])
			sf.add_frame(&"scroll", atlas)
	if sf.get_frame_count(&"scroll") > 0:
		scrolling_line.sprite_frames = sf
		scrolling_line.animation = &"scroll"
		scrolling_line.play()


func _setup_network_frames() -> void:
	var sf := SpriteFrames.new()
	sf.add_animation(&"idle")
	var tex := load(NETWORK_CONN_PATH) as Texture2D
	if tex == null:
		return
	var xml_path := NETWORK_CONN_PATH.replace(".png", ".xml")
	if ResourceLoader.exists(xml_path):
		var frames := _parse_adobe_atlas(xml_path)
		for fd in frames:
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(fd["x"], fd["y"], fd["w"], fd["h"])
			sf.add_frame(&"idle", atlas)
	if sf.get_frame_count(&"idle") > 0:
		network_connection.sprite_frames = sf
		network_connection.animation = &"idle"
		network_connection.play()


func _setup_nessie_frames() -> void:
	var sf := SpriteFrames.new()
	sf.add_animation(&"idle")
	var tex_path := "res://animania_mod/source/images/menus/changelog/nessie/spritemap1.png"
	var json_path := "res://animania_mod/source/images/menus/changelog/nessie/spritemap1.json"
	var tex := load(tex_path) as Texture2D
	if tex == null:
		return
	if ResourceLoader.exists(json_path):
		var frames := _parse_adobe_atlas(json_path)
		for fd in frames:
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(fd["x"], fd["y"], fd["w"], fd["h"])
			sf.add_frame(&"idle", atlas)
	if sf.get_frame_count(&"idle") > 0:
		nessie_spr.sprite_frames = sf
		nessie_spr.animation = &"idle"


func _parse_adobe_atlas(path: String) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	var xml_text := FileAccess.get_file_as_string(path)
	if xml_text.is_empty():
		return frames
	var parser := XMLParser.new()
	parser.open_buffer(xml_text.to_utf8_buffer())
	while parser.read() != ERR_FILE_EOF:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT:
			if parser.get_node_name() == "SubTexture":
				var frame := {}
				for i in range(parser.get_attribute_count()):
					frame[parser.get_attribute_name(i)] = parser.get_attribute_value(i)
				if frame.has("x") and frame.has("y") and frame.has("width") and frame.has("height"):
					frames.append({
						"x": float(frame.get("x", "0")),
						"y": float(frame.get("y", "0")),
						"w": float(frame.get("width", "0")),
						"h": float(frame.get("height", "0")),
					})
	return frames


# ─── Tab management ───────────────────────────────────────────────────────

func _select_tab(index: int) -> void:
	if index < 0 or index >= TABS.size():
		return
	current_tab = index
	_play(SOUND_SWITCH)

	# Update tab button highlights
	for i in tab_buttons.size():
		tab_buttons[i].modulate.a = 1.0 if i == current_tab else 0.5

	# Hide socials
	_set_socials_visible(current_tab == 2)

	# Load content for the selected tab
	match TAB_KEYS[current_tab]:
		"news":
			change_text("news")
		"changelog":
			change_text("changelog")
		"socials":
			change_text("socials")

	# Play nessie sound
	_play_nessie_sound(TAB_KEYS[current_tab])


func change_text(tab_key: String) -> void:
	# Load changelog data
	var data_path := NESSIE_DATA_DIR + "Changelog.json"
	if tab_key == "socials":
		data_path = NESSIE_DATA_DIR + "Socials.json"

	# For now, show a placeholder text
	if board:
		match tab_key:
			"news":
				board_label.text = "NEWS!"
				if board:
					board.text = "[center][color=#FFD700]Latest News[/color]\n\nStay tuned for updates![/center]"
			"changelog":
				board_label.text = "Changelog"
				if board:
					board.text = "[center][color=#87CEEB]Version 1.0[/color]\n\n• Initial port to Godot\n• All menus ported from Animania\n• Options system implemented\n• Key binding support[/center]"
			"socials":
				board_label.text = "Socials"
				if board:
					board.text = ""  # Empty for socials, icons shown instead


func _set_socials_visible(vis: bool) -> void:
	socials_visible = vis
	for node in socials_nodes:
		node.visible = vis
	if socials_logo:
		socials_logo.visible = vis


# ─── Nessie ───────────────────────────────────────────────────────────────

func _play_nessie_sound(tab_key: String) -> void:
	var sound_path := "res://animania_mod/source/sounds/nessie/Nessie%s.ogg" % tab_key.capitalize()
	if ResourceLoader.exists(sound_path):
		var audio := AudioStreamPlayer.new()
		audio.stream = load(sound_path) as AudioStream
		audio.bus = "SFX"
		add_child(audio)
		audio.play()
		audio.finished.connect(audio.queue_free)


func on_nessie_phrase_start() -> void:
	if nessie_spr:
		nessie_spr.visible = true
		nessie_spr.play()


func on_nessie_phrase_end() -> void:
	if nessie_spr:
		nessie_spr.visible = false
		nessie_spr.stop()


# ─── Close ────────────────────────────────────────────────────────────────

func close_self() -> void:
	if transitioning:
		return
	transitioning = true
	_play(SOUND_CANCEL)

	# Blur out and fade
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3).set_ease(Tween.EASE_IN)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_callback(queue_free)


# ─── Helpers ──────────────────────────────────────────────────────────────

func _play(path: String) -> void:
	if ResourceLoader.exists(path):
		var audio := AudioStreamPlayer.new()
		audio.stream = load(path) as AudioStream
		audio.bus = "SFX"
		add_child(audio)
		audio.play()
		audio.finished.connect(audio.queue_free)
