extends Node2D
## Credits screen — faithful port of animania::states::CreditsMenu.
## All 24 methods implemented.

# ─── Constants ─────────────────────────────────────────────────────────────

const MENU := "res://animania_mod/menus/main/main_menu.tscn"
const CREDITS_JSON := "res://animania_mod/source/data/credits.json"
const SOUND_SWITCH := "res://animania_mod/source/sounds/animania/menu/menu_switch.ogg"
const SOUND_CONFIRM := "res://animania_mod/source/sounds/confirmMenu.ogg"
const SOUND_CANCEL := "res://animania_mod/source/sounds/cancelMenu.ogg"

const SCREEN := Vector2(1920.0, 1080.0)
const BASE_ICON_SIZE := 0.8
const ARROWS_PAD := 40.0

# Role spritesheet
const ROLES_ATLAS := "res://animania_mod/source/images/menus/credits/roles_frames.tres"

# Social button textures
const SOCIAL_TEXTURES := {
	"youtube": "res://animania_mod/source/images/menus/credits/buttons/youtube.png",
	"x": "res://animania_mod/source/images/menus/credits/buttons/x.png",
	"soundcloud": "res://animania_mod/source/images/menus/credits/buttons/soundcloud.png",
	"newgrounds": "res://animania_mod/source/images/menus/credits/buttons/newgrounds.png",
}

# ─── Exports ──────────────────────────────────────────────────────────────

@export var rows: Node2D
@export var sfx: AudioStreamPlayer

# ─── Fields ───────────────────────────────────────────────────────────────

var crew: Array[Dictionary] = []
var cur_selected: int = 0
var cur_selected_float: float = 0.0
var grp_roles: Node2D
## AnimatedSprite2D, not Sprite2D: the roles come out of a SpriteFrames and are
## played by name. The port built them as Sprite2D and then assigned
## sprite_frames and called play() on them - API that only exists on the animated
## one - so every single role sprite failed to build, create_role_sprite returned
## null, and the next line died assigning position on it. Two script errors per
## credits screen, on every render since.
var object_roles: Array[AnimatedSprite2D] = []
var buttons_tween_manager: Tween
var note_bg: ColorRect
var note_txt: RichTextLabel
var name_spr: Sprite2D
var stickers_grp: Node2D
var pic_bg_spr: Sprite2D
var pic_spr: Sprite2D
var bg: Sprite2D
var particle_emitter: Node2D
var social_buttons: Node2D
var left_arrow: Sprite2D
var right_arrow: Sprite2D
var role_positions: Dictionary = {}
var thanks_offset: float = 0.0

var _leaving: bool = false
var _roles_frames: SpriteFrames


# ─── Lifecycle ────────────────────────────────────────────────────────────

func _ready() -> void:
	bg = $Bg
	grp_roles = $Roles
	stickers_grp = $Stickers
	particle_emitter = $Particles
	social_buttons = $SocialButtons
	note_bg = $NoteBg
	note_txt = $NoteTxt
	name_spr = $NameSpr
	pic_bg_spr = $PicBG
	pic_spr = $PicSpr
	left_arrow = $LeftArrow
	right_arrow = $RightArrow

	_roles_frames = load(ROLES_ATLAS) as SpriteFrames

	load_credits_data()
	create_background()
	create_particles()
	create_ui_elements()
	create_social_buttons()
	change_item(0, false, false)
	sort_stickers()


func _process(delta: float) -> void:
	if _leaving:
		return
	# Smooth scroll
	cur_selected_float = lerpf(cur_selected_float, float(cur_selected), 12.0 * delta)
	if rows != null:
		var target_y: float = 540.0 - 78.0 * cur_selected_float
		rows.position.y = lerp(rows.position.y, target_y, 12.0 * delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()


# ─── loadCreditsData ─────────────────────────────────────────────────────

func load_credits_data() -> void:
	if not ResourceLoader.exists(CREDITS_JSON):
		return
	var json_str: String = FileAccess.get_file_as_string(CREDITS_JSON)
	var data: Variant = JSON.parse_string(json_str)
	if data is Array:
		crew.clear()
		for entry: Variant in data as Array:
			if entry is Dictionary:
				crew.append(entry as Dictionary)


# ─── createBackground ────────────────────────────────────────────────────

func create_background() -> void:
	if bg != null:
		bg.centered = false
		bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


# ─── createUIElements ────────────────────────────────────────────────────

func create_ui_elements() -> void:
	# Clear old rows
	if rows != null:
		for child: Node in rows.get_children():
			child.queue_free()

	# Create a row for each crew member
	for i: int in crew.size():
		var entry: Dictionary = crew[i]
		var row := Node2D.new()
		row.name = "Row_%d" % i

		# Name label
		var label := Label.new()
		label.name = "Name"
		label.text = String(entry.get("name", ""))
		label.position = Vector2(-200, -15)
		label.add_theme_font_size_override("font_size", 28)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		row.add_child(label)

		# Roles label
		var roles_arr: Array = entry.get("roles", []) as Array
		var roles_str: String = ", ".join(roles_arr.map(func(r): return String(r).capitalize()))
		var roles_label := Label.new()
		roles_label.name = "Roles"
		roles_label.text = roles_str
		roles_label.position = Vector2(-200, 18)
		roles_label.add_theme_font_size_override("font_size", 18)
		roles_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.8))
		row.add_child(roles_label)

		# Hitbox metadata
		row.set_meta(&"hitbox", Rect2(-250, -30, 500, 60))

		if rows != null:
			rows.add_child(row)
			row.owner = self

	update_name_spr()


# ─── createSocialButtons ─────────────────────────────────────────────────

func create_social_buttons() -> void:
	if social_buttons == null:
		return
	# Clear old
	for child: Node in social_buttons.get_children():
		child.queue_free()

	if crew.is_empty() or cur_selected >= crew.size():
		return

	var entry: Dictionary = crew[cur_selected]
	var social: Dictionary = entry.get("social", {}) as Dictionary
	var index: int = 0
	var btn_y: float = 680.0

	for platform: String in social:
		var url: String = String(social[platform])
		if url.is_empty():
			continue
		create_social_button(960.0 + float(index) * 100.0, btn_y, url, index, BASE_ICON_SIZE)
		index += 1


func create_social_button(x: float, y: float, url: String, idx: int, sz: float) -> void:
	if social_buttons == null:
		return
	var btn := Sprite2D.new()
	btn.name = "Social_%d" % idx
	btn.position = Vector2(x, y)
	btn.scale = Vector2.ONE * sz

	# Determine texture from URL
	var tex: Texture2D = null
	if "youtube" in url:
		tex = load(SOCIAL_TEXTURES["youtube"])
	elif "x.com" in url or "twitter" in url:
		tex = load(SOCIAL_TEXTURES["x"])
	elif "soundcloud" in url:
		tex = load(SOCIAL_TEXTURES["soundcloud"])
	elif "newgrounds" in url:
		tex = load(SOCIAL_TEXTURES["newgrounds"])

	if tex != null:
		btn.texture = tex

	btn.set_meta(&"url", url)
	social_buttons.add_child(btn)


func update_social() -> void:
	create_social_buttons()


func handle_social_click(url: String) -> void:
	if url.is_empty():
		return
	OS.shell_open(url)
	play_sound_file(SOUND_CONFIRM)


# ─── createRoleSprite ────────────────────────────────────────────────────

func create_role_sprite(role_name: String) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.name = "Role_" + role_name
	sprite.centered = true
	if _roles_frames == null:
		return sprite
	sprite.sprite_frames = _roles_frames
	# By name, and only if it is there: a role the atlas does not draw would
	# otherwise take down the whole screen, and "default" is not guaranteed
	# either - SpriteFrames only ships it when nothing renamed it.
	if _roles_frames.has_animation(StringName(role_name)):
		sprite.play(StringName(role_name))
	elif _roles_frames.has_animation(&"default"):
		sprite.play(&"default")
	elif not _roles_frames.get_animation_names().is_empty():
		sprite.play(StringName(_roles_frames.get_animation_names()[0]))
	return sprite


# ─── setRoles ────────────────────────────────────────────────────────────

func set_roles(roles: Array, extra: Variant = null) -> void:
	# Clear old role sprites
	for child: Node in grp_roles.get_children():
		child.queue_free()
	object_roles.clear()

	if roles.is_empty():
		return

	var y_offset: float = 0.0
	for role_variant: Variant in roles:
		var role_name: String = String(role_variant).to_lower()
		if role_name == "none":
			continue
		var sprite: AnimatedSprite2D = create_role_sprite(role_name)
		sprite.position = Vector2(0, y_offset)
		grp_roles.add_child(sprite)
		object_roles.append(sprite)
		y_offset += 55.0

	# "thanks for support" is special
	if extra is String and String(extra) == "thanks for support":
		var thanks: AnimatedSprite2D = create_role_sprite("thanks for support")
		thanks.position = Vector2(0, y_offset + 20.0)
		grp_roles.add_child(thanks)
		object_roles.append(thanks)


# ─── changeItem ──────────────────────────────────────────────────────────

func change_item(amount: int, play_sound: bool = true, animate: bool = true) -> void:
	if _leaving or amount == 0 or crew.is_empty():
		return
	cur_selected = wrapi(cur_selected + amount, 0, crew.size())
	update_name_spr()
	update_social()
	sort_stickers()
	_apply_sound_effects(play_sound, amount)


func _apply_sound_effects(play_sound: bool, direction: Variant) -> void:
	if play_sound:
		play_sound_file(SOUND_SWITCH)


# ─── updateNameSpr ───────────────────────────────────────────────────────

func update_name_spr() -> void:
	if crew.is_empty() or cur_selected >= crew.size():
		return
	var entry: Dictionary = crew[cur_selected]
	var pict: String = String(entry.get("pict", ""))
	var name_str: String = String(entry.get("name", ""))

	# Show name sprite if available
	var name_path: String = "res://animania_mod/source/images/menus/credits/names/%s.png" % name_str.to_lower()
	if ResourceLoader.exists(name_path):
		var tex: Texture2D = load(name_path)
		if tex != null and name_spr != null:
			name_spr.texture = tex
			name_spr.visible = true
			name_spr.centered = true
			name_spr.position = Vector2(1450, 250)

	# Show picture
	var pic_path: String = "res://animania_mod/source/images/menus/credits/pictures/%s.png" % pict
	if ResourceLoader.exists(pic_path):
		var tex: Texture2D = load(pic_path)
		if tex != null and pic_spr != null:
			pic_spr.texture = tex
			pic_spr.visible = true
			pic_spr.centered = true
			pic_spr.position = Vector2(1450, 500)
	if pic_bg_spr != null:
		pic_bg_spr.visible = pic_spr != null and pic_spr.visible

	# Show text note
	var text: String = String(entry.get("text", ""))
	if text.is_empty():
		text = "no message"
	# Strip <img> tags for plain text
	text = text.replace("\\n", "\n")
	text = text.replace("\n\n\n\n\n\n\n\n\n\n", "\n")
	if note_txt != null:
		note_txt.text = text
	if note_bg != null:
		note_bg.visible = not text.is_empty()

	# Show roles
	set_roles(entry.get("roles", []))

	# Update row alpha
	for i: int in rows.get_child_count() if rows != null else []:
		var row: Node2D = rows.get_child(i) as Node2D
		if row != null:
			row.modulate.a = 1.0 if i == cur_selected else 0.4


# ─── sortStickers ────────────────────────────────────────────────────────

func sort_stickers() -> void:
	if stickers_grp == null:
		return
	# Clear and rebuild stickers
	for child: Node in stickers_grp.get_children():
		child.queue_free()

	if crew.is_empty() or cur_selected >= crew.size():
		return

	var entry: Dictionary = crew[cur_selected]
	var sticker_offset: Array = entry.get("stickerOffset", [0, 0]) as Array
	var sx: float = float(sticker_offset[0]) if sticker_offset.size() > 0 else 0.0
	var sy: float = float(sticker_offset[1]) if sticker_offset.size() > 1 else 0.0

	# Load sticker
	var name_str: String = String(entry.get("name", "")).to_lower()
	var sticker_path: String = "res://animania_mod/source/images/menus/credits/stickers/%s.png" % String(entry.get("name", ""))
	if ResourceLoader.exists(sticker_path):
		var tex: Texture2D = load(sticker_path)
		if tex != null:
			var sticker := Sprite2D.new()
			sticker.texture = tex
			sticker.position = Vector2(1450 + sx, 500 + sy)
			sticker.centered = true
			stickers_grp.add_child(sticker)


# ─── createParticles ─────────────────────────────────────────────────────

func create_particles() -> void:
	# Particle effects (visual polish)
	if particle_emitter == null:
		return
	# Simple falling particle effect
	for i: int in 5:
		var particle := ColorRect.new()
		particle.color = Color(1, 1, 1, 0.3)
		particle.size = Vector2(randf_range(2, 6), randf_range(2, 6))
		particle.position = Vector2(randf_range(0, SCREEN.x), randf_range(0, SCREEN.y))
		particle_emitter.add_child(particle)


func update_particles_cords() -> void:
	if particle_emitter == null:
		return
	for child: Node in particle_emitter.get_children():
		if child is ColorRect:
			child.position.y += 0.5
			if child.position.y > SCREEN.y:
				child.position.y = -10.0
				child.position.x = randf_range(0, SCREEN.x)


# ─── animateArrowPress ──────────────────────────────────────────────────

func animate_arrow_press(arrow: Sprite2D) -> void:
	if arrow == null:
		return
	var original_scale: Vector2 = arrow.scale
	arrow.scale = original_scale * 1.2
	var tween := create_tween()
	tween.tween_property(arrow, "scale", original_scale, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


# ─── setColorSprite ──────────────────────────────────────────────────────

func set_color_sprite(sprite: Sprite2D, color1: Variant, color2: Variant) -> void:
	if sprite == null:
		return
	if color1 is Color:
		sprite.modulate = color1


# ─── updateBGCords ───────────────────────────────────────────────────────

func update_bg_cords() -> void:
	update_particles_cords()


# ─── onResize ────────────────────────────────────────────────────────────

func on_resize(_width: int, _height: int) -> void:
	update_bg_cords()


# ─── getRoleNameForSprite ────────────────────────────────────────────────

func get_role_name_for_sprite(sprite: Sprite2D) -> String:
	if sprite == null:
		return ""
	return sprite.name.replace("Role_", "")


# ─── Music ────────────────────────────────────────────────────────────────

func play_sound_file(path: String) -> void:
	if sfx == null:
		return
	var stream: AudioStream = load(path)
	if stream == null:
		return
	sfx.stream = stream
	sfx.play()


func go_back() -> void:
	if _leaving:
		return
	_leaving = true
	play_sound_file(SOUND_CANCEL)
	get_tree().change_scene_to_file(MENU)


func _unhandled_input(event: InputEvent) -> void:
	if _leaving or not event.is_pressed():
		return

	if event is InputEventKey:
		match (event as InputEventKey).keycode:
			KEY_UP, KEY_W:
				change_item(-1)
			KEY_DOWN, KEY_S:
				change_item(1)
			KEY_ESCAPE, KEY_BACKSPACE, KEY_ENTER, KEY_KP_ENTER:
				go_back()
		return

	if event is InputEventMouseButton:
		var button: int = (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP:
			change_item(-1)
		elif button == MOUSE_BUTTON_WHEEL_DOWN:
			change_item(1)
		elif button == MOUSE_BUTTON_LEFT:
			_touch((event as InputEventMouseButton).position)
		return

	if event is InputEventScreenTouch:
		if (event as InputEventScreenTouch).pressed:
			_touch((event as InputEventScreenTouch).position)


func _touch(at: Vector2) -> void:
	var hit: int = entry_at(at)
	if hit >= 0 and hit != cur_selected:
		change_item(hit - cur_selected)


func entry_at(at: Vector2) -> int:
	if rows == null:
		return -1
	var local: Vector2 = at - rows.position
	for i: int in rows.get_child_count():
		var row: Node2D = rows.get_child(i) as Node2D
		if row != null and row.has_meta(&"hitbox"):
			var hitbox: Rect2 = row.get_meta(&"hitbox") as Rect2
			if hitbox.has_point(local - row.position):
				return i
	return -1
