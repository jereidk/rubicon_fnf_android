extends Node2D
## Credits screen - port of animania::states::CreditsMenu (0x138bc90..0x1398785).
##
## It is a card, not a list: one crew member at a time, moved with the two
## diff-selector arrows. The scrolling roll of names this port used to draw does not
## exist anywhere in the binary - create() calls loadCreditsData, createBackground,
## createParticles, createUIElements, createSocialButtons, changeItem(0) and
## sortStickers, and none of those builds a row. Every number below carries the
## address it was read from.

# ─── Constants ─────────────────────────────────────────────────────────────

const MENU := "res://animania_mod/menus/main/main_menu.tscn"
const CREDITS_JSON := "res://animania_mod/source/data/credits.json"
const SOUND_SWITCH := "res://animania_mod/source/sounds/animania/menu/menu_switch.ogg"
const SOUND_CONFIRM := "res://animania_mod/source/sounds/confirmMenu.ogg"
const SOUND_CANCEL := "res://animania_mod/source/sounds/cancelMenu.ogg"

const ART := "res://animania_mod/source/images/menus/credits"
const ROLES_ATLAS := "res://animania_mod/source/images/menus/credits/roles_frames.tres"

## The mod is a 1280x720 game; this project runs at 1920x1080. Everything below is
## in the mod's space and takes this factor on the way out.
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0
const SCREEN := Vector2(1920.0, 1080.0)
const MOD_SCREEN := Vector2(1280.0, 720.0)

## __boot (0x138bfbe / 0x138c01b). Both were guesses before: ARROWS_PAD was 40 and
## BASE_ICON_SIZE was 0.8, read as a scale when it is a width in pixels.
const ARROWS_PAD := 30.0
const BASE_ICON_SIZE := 150.0

## createUIElements, 0x1391000 onwards.
const LOGO_POS := Vector2(40.0, 0.0)
const LOGO_SCALE := 0.5
const NOTE_BG_POS := Vector2(666.0, 63.0)
const NOTE_TXT_POS := Vector2(715.0, 180.0)
const PIC_CLIP_POS := Vector2(1020.0, 452.0)

## setRoles (0x138ef50). The role words are centred in a 550-wide column that starts
## at x=24 - which is exactly the span of the mod's own hand-laid role board, whose
## nine seats the constructor stores in `rolePositions` (director at x=24, animator
## beside artist at 257, charter beside coder at 217, and so on, rightmost edge 567).
## Anything wider than the column is shrunk to it with setGraphicSize.
const ROLE_COLUMN_X := 24.0
const ROLE_COLUMN_W := 550.0
const ROLE_BASE_Y := 244.0
const ROLE_SLOTS := 5
const ROLE_SPREAD := 250.0
const ROLE_BIAS := 1.25

## The stickers are all created at once, stacked one pixel apart, and only their draw
## order changes - `sortStickers` is a FlxTypedGroup.sort, not a rebuild.
## x = FlxG.initialWidth * 0.225 + i (0x1392174), y = FlxG.initialHeight - h - 15
## (0x13921db). `stickerOffset` from the JSON is subtracted from the sprite's offset,
## which moves the art without moving x/y - so the arrows below are unaffected by it.
const STICKER_X_FACTOR := 0.225
const STICKER_SCALE := 0.5
const STICKER_BOTTOM_PAD := 15.0

## 0x1392cf7 (left) and 0x13930a5 (right): both hang off the FIRST sticker's x/y.
const ARROW_SCALE := 1.3
const ARROW_Y_PAD := 20.0
const ARROW_FRAMES := "res://animania_mod/source/images/menus/story/diff_selector_frames.tres"
const ARROW_ANIM := &"difficulty arrow"

## createSocialButtons, 0x138aad8: [key, x, y, angle]. The order is the order the mod
## creates them in, and the index it passes is just that position.
const SOCIAL_SEATS := [
	["youtube", 661.0, 620.0, -6.0],
	["x", 750.0, 630.0, 6.0],
	["soundcloud", 843.0, 600.0, 8.0],
	["newgrounds", 923.0, 620.0, -6.0],
]

# ─── Exports ──────────────────────────────────────────────────────────────

@export var sfx: AudioStreamPlayer

# ─── Fields ───────────────────────────────────────────────────────────────

var crew: Array[Dictionary] = []
var cur_selected: int = 0
var grp_roles: Node2D
## AnimatedSprite2D, not Sprite2D: the roles come out of a SpriteFrames and are
## played by name.
var object_roles: Array[AnimatedSprite2D] = []
var note_bg: Sprite2D
var note_txt: AtlasText
var name_spr: Sprite2D
var stickers_grp: Node2D
var pic_bg_spr: Sprite2D
var pic_spr: Sprite2D
var bg: Sprite2D
var particle_emitter: Node2D
var social_buttons: Node2D
var left_arrow: AnimatedSprite2D
var right_arrow: AnimatedSprite2D

var _leaving: bool = false
var _roles_frames: SpriteFrames
var _sticker_seats: Array[Vector2] = []


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
	change_item(0, false, false)
	sort_stickers()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()


func _process(_delta: float) -> void:
	if _leaving:
		return
	update_particles_cords()


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
		bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


# ─── createUIElements ────────────────────────────────────────────────────

func create_ui_elements() -> void:
	_build_role_pool()
	_build_stickers()
	_place_arrows()


func _build_role_pool() -> void:
	for child: Node in grp_roles.get_children():
		child.queue_free()
	object_roles.clear()
	# 0x139129d: five createSparrow("menus/credits/roles") at (24, 409), reused.
	for i: int in ROLE_SLOTS:
		var sprite := AnimatedSprite2D.new()
		sprite.name = "Role%d" % i
		sprite.centered = false
		sprite.visible = false
		if _roles_frames != null:
			sprite.sprite_frames = _roles_frames
		grp_roles.add_child(sprite)
		object_roles.append(sprite)


func _build_stickers() -> void:
	for child: Node in stickers_grp.get_children():
		child.queue_free()
	_sticker_seats.clear()

	var base_x: float = MOD_SCREEN.x * STICKER_X_FACTOR
	for i: int in crew.size():
		var entry: Dictionary = crew[i]
		var tex: Texture2D = _sticker_texture(entry)
		var frame: Vector2 = Vector2(tex.get_size()) if tex != null else Vector2.ZERO
		# The mod's x/y are the sprite's own, before `offset` moves the art.
		var seat := Vector2(
			base_x + float(i),
			MOD_SCREEN.y - frame.y * STICKER_SCALE - STICKER_BOTTOM_PAD)
		_sticker_seats.append(seat)
		if tex == null:
			continue

		var off: Array = entry.get("stickerOffset", []) as Array
		var shift := Vector2(
			float(off[0]) if off.size() > 0 else 0.0,
			float(off[1]) if off.size() > 1 else 0.0)

		var sticker := Sprite2D.new()
		sticker.name = "Sticker%d" % i
		sticker.centered = false
		sticker.texture = tex
		sticker.scale = Vector2.ONE * (STICKER_SCALE * FUNKIN_TO_RUBICON)
		sticker.position = (seat + shift) * FUNKIN_TO_RUBICON
		if bool(entry.get("pixelSticker", false)):
			sticker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		stickers_grp.add_child(sticker)


func _sticker_texture(entry: Dictionary) -> Texture2D:
	var key: String = String(entry.get("sticker", entry.get("name", ""))).to_lower()
	var path: String = "%s/stickers/%s.png" % [ART, key]
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## 0x1392cf7 / 0x13930a5. Both arrows are placed once, off the first sticker's seat,
## and never move again - which is why the pair is not symmetric about the sticker's
## middle but about its left edge.
func _place_arrows() -> void:
	if _sticker_seats.is_empty():
		return
	var ref: Vector2 = _sticker_seats[0]
	var frames: SpriteFrames = left_arrow.sprite_frames
	if frames == null or not frames.has_animation(ARROW_ANIM):
		return
	var art: Vector2 = Vector2(frames.get_frame_texture(ARROW_ANIM, 0).get_size()) * ARROW_SCALE
	var y: float = ref.y + (BASE_ICON_SIZE - art.y) * 0.5 + ARROW_Y_PAD
	left_arrow.position = Vector2(
		ref.x - BASE_ICON_SIZE * 0.5 - ARROWS_PAD - art.x, y) * FUNKIN_TO_RUBICON
	right_arrow.position = Vector2(
		ref.x + BASE_ICON_SIZE * 0.5 + ARROWS_PAD, y) * FUNKIN_TO_RUBICON
	left_arrow.play(ARROW_ANIM)
	right_arrow.play(ARROW_ANIM)


# ─── createSocialButtons / updateSocial ──────────────────────────────────

func update_social() -> void:
	if social_buttons == null:
		return
	var social: Dictionary = {}
	if not crew.is_empty() and cur_selected < crew.size():
		social = crew[cur_selected].get("social", {}) as Dictionary
	for seat: Array in SOCIAL_SEATS:
		var key: String = String(seat[0])
		var button: Sprite2D = social_buttons.get_node_or_null("Social_" + key) as Sprite2D
		if button == null:
			continue
		var url: String = String(social.get(key, ""))
		button.visible = not url.is_empty()
		button.set_meta(&"url", url)


func handle_social_click(url: String) -> void:
	if url.is_empty():
		return
	OS.shell_open(url)
	play_sound_file(SOUND_CONFIRM)


# ─── createRoleSprite / setRoles ─────────────────────────────────────────

func set_roles(roles: Array) -> void:
	var wanted: Array[String] = []
	for role_variant: Variant in roles:
		var role_name: String = String(role_variant).to_lower()
		if role_name == "none" or role_name.is_empty():
			continue
		wanted.append(role_name)

	var n: int = mini(wanted.size(), object_roles.size())
	for i: int in object_roles.size():
		var sprite: AnimatedSprite2D = object_roles[i]
		if i >= n:
			sprite.visible = false
			continue
		var role_name: String = wanted[i]
		var anim: StringName = _role_animation(role_name)
		if anim == &"":
			sprite.visible = false
			continue
		sprite.animation = anim
		sprite.play(anim)
		sprite.visible = true

		# setGraphicSize(550) when the word is wider than the column, then centre it.
		var art: Vector2 = Vector2(_roles_frames.get_frame_texture(anim, 0).get_size())
		var shrink: float = 1.0
		if art.x > ROLE_COLUMN_W:
			shrink = ROLE_COLUMN_W / art.x
		var drawn: float = art.x * shrink
		var x: float = ROLE_COLUMN_X + (ROLE_COLUMN_W - drawn) * 0.5
		# 0x138f239: ((slots - n) / 1.25 + i) * (spread / slots) + base.
		var y: float = (float(ROLE_SLOTS - n) / ROLE_BIAS + float(i)) \
			* (ROLE_SPREAD / float(ROLE_SLOTS)) + ROLE_BASE_Y
		sprite.scale = Vector2.ONE * (shrink * FUNKIN_TO_RUBICON)
		sprite.position = Vector2(x, y) * FUNKIN_TO_RUBICON


func _role_animation(role_name: String) -> StringName:
	if _roles_frames == null:
		return &""
	if _roles_frames.has_animation(StringName(role_name)):
		return StringName(role_name)
	# The atlas ships a "?" seat for anything it does not letter.
	if _roles_frames.has_animation(&"?"):
		return &"?"
	return &""


# ─── changeItem ──────────────────────────────────────────────────────────

func change_item(amount: int, play_sound: bool = true, animate: bool = true) -> void:
	if _leaving or crew.is_empty():
		return
	cur_selected = wrapi(cur_selected + amount, 0, crew.size())
	if animate and amount != 0:
		animate_arrow_press(right_arrow if amount > 0 else left_arrow)
	update_name_spr()
	update_social()
	sort_stickers()
	if play_sound:
		play_sound_file(SOUND_SWITCH)


# ─── updateNameSpr ───────────────────────────────────────────────────────

func update_name_spr() -> void:
	if crew.is_empty() or cur_selected >= crew.size():
		return
	var entry: Dictionary = crew[cur_selected]
	var pixel_name: bool = bool(entry.get("pixelName", false))

	var name_path: String = "%s/names/%s.png" % [ART, String(entry.get("name", "")).to_lower()]
	var name_tex: Texture2D = load(name_path) as Texture2D if ResourceLoader.exists(name_path) else null
	name_spr.texture = name_tex
	name_spr.visible = name_tex != null
	name_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if pixel_name \
		else CanvasItem.TEXTURE_FILTER_PARENT_NODE
	if name_tex != null:
		# 0x1393863: centred on the note, hung a third of its own height above it.
		var art: Vector2 = Vector2(name_tex.get_size())
		var note_w: float = float(note_bg.texture.get_width())
		name_spr.position = Vector2(
			NOTE_BG_POS.x + note_w * 0.5 - art.x * 0.5,
			NOTE_BG_POS.y - art.y / 3.0) * FUNKIN_TO_RUBICON
		name_spr.rotation = 0.0

	var pic_path: String = "%s/pictures/%s.png" % [ART, String(entry.get("pict", ""))]
	var pic_tex: Texture2D = load(pic_path) as Texture2D if ResourceLoader.exists(pic_path) else null
	pic_spr.texture = pic_tex
	pic_spr.visible = pic_tex != null
	if pic_tex != null:
		# The photo fills the clip that sits over it, so it takes the clip's seat.
		var clip: Vector2 = Vector2(pic_bg_spr.texture.get_size())
		var art: Vector2 = Vector2(pic_tex.get_size())
		var fit: float = minf(clip.x / art.x, clip.y / art.y)
		pic_spr.scale = Vector2.ONE * (fit * FUNKIN_TO_RUBICON)
		pic_spr.position = (PIC_CLIP_POS + (clip - art * fit) * 0.5) * FUNKIN_TO_RUBICON
		pic_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST \
			if bool(entry.get("pixelPic", false)) else CanvasItem.TEXTURE_FILTER_PARENT_NODE
	pic_bg_spr.visible = pic_tex != null

	# 0x13942e2: the note text is scaled by the entry's own `textScale`, and 0x13945b6
	# hands it to AtlasText.startTyping with `textSpeed`/`textPitch`. The typing rate's
	# units are not recovered, so the note is shown whole rather than at an invented
	# speed - and the face is left white, because alphabet-white.png is white with an
	# alpha ramp and nothing in the class tints it.
	var text_scale: float = float(entry.get("textScale", 1.0))
	note_txt.scale = Vector2.ONE * (text_scale * FUNKIN_TO_RUBICON)
	note_txt.text = _strip_img_tags(String(entry.get("text", "")))
	note_bg.visible = true

	set_roles(entry.get("roles", []) as Array)


## The mod's note markup embeds sprites with <img src=... />; nothing in this port
## draws them, so they are dropped rather than printed as literal tags.
func _strip_img_tags(text: String) -> String:
	var out: String = text
	while true:
		var start: int = out.find("<img")
		if start < 0:
			break
		var close: int = out.find(">", start)
		if close < 0:
			out = out.substr(0, start)
			break
		out = out.substr(0, start) + out.substr(close + 1)
	out = out.replace("</img>", "")
	out = out.replace("\\n", "\n")
	return out


# ─── sortStickers ────────────────────────────────────────────────────────

func sort_stickers() -> void:
	if stickers_grp == null:
		return
	# FlxTypedGroup.sort (0x138b642): the order changes, the group does not.
	# All 36 stickers stay on screen - the crew loop builds one per entry, a pixel
	# apart - and only the draw order changes. Nothing here touches their alpha.
	var selected: Node = stickers_grp.get_node_or_null("Sticker%d" % cur_selected)
	if selected != null:
		stickers_grp.move_child(selected, stickers_grp.get_child_count() - 1)


# ─── createParticles ─────────────────────────────────────────────────────

func create_particles() -> void:
	if particle_emitter == null:
		return
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


func update_bg_cords() -> void:
	update_particles_cords()


func on_resize(_width: int, _height: int) -> void:
	update_bg_cords()


# ─── animateArrowPress ──────────────────────────────────────────────────

func animate_arrow_press(arrow: AnimatedSprite2D) -> void:
	if arrow == null:
		return
	# 0x138b901: the mod eases this one with backIn.
	var rest: Vector2 = Vector2.ONE * (ARROW_SCALE * FUNKIN_TO_RUBICON)
	arrow.scale = rest * 1.2
	var tween := create_tween()
	tween.tween_property(arrow, "scale", rest, 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)


# ─── Sound / navigation ──────────────────────────────────────────────────

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
			KEY_LEFT, KEY_A, KEY_UP, KEY_W:
				change_item(-1)
			KEY_RIGHT, KEY_D, KEY_DOWN, KEY_S:
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
	var step: int = entry_at(at)
	if step != 0:
		change_item(step)
		return
	var url: String = social_at(at)
	if not url.is_empty():
		handle_social_click(url)


## -1, +1 or 0. The screen has no rows to hit: the only things that move the
## selection are the two arrows, so the hit test is theirs.
func entry_at(at: Vector2) -> int:
	if _arrow_rect(left_arrow).has_point(at):
		return -1
	if _arrow_rect(right_arrow).has_point(at):
		return 1
	return 0


func social_at(at: Vector2) -> String:
	if social_buttons == null:
		return ""
	for child: Node in social_buttons.get_children():
		var button: Sprite2D = child as Sprite2D
		if button == null or not button.visible or button.texture == null:
			continue
		var size: Vector2 = Vector2(button.texture.get_size()) * button.scale
		if Rect2(button.position, size).has_point(at):
			return String(button.get_meta(&"url", ""))
	return ""


## A finger is fatter than a 22x43 arrow, so the tap target is padded out to the gap
## the mod already leaves around it.
func _arrow_rect(arrow: AnimatedSprite2D) -> Rect2:
	if arrow == null or arrow.sprite_frames == null:
		return Rect2()
	var tex: Texture2D = arrow.sprite_frames.get_frame_texture(ARROW_ANIM, 0)
	if tex == null:
		return Rect2()
	var size: Vector2 = Vector2(tex.get_size()) * arrow.scale
	var pad: float = ARROWS_PAD * FUNKIN_TO_RUBICON
	return Rect2(arrow.position - Vector2(pad, pad), size + Vector2(pad, pad) * 2.0)
