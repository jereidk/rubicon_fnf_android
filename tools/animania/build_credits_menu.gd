# Authors animania_mod/menus/credits/credits_menu.tscn.
#
#   godot --headless --path . --script tools/animania/build_credits_menu.gd
#
# The screen is NOT a scrolling list of names. animania::states::CreditsMenu shows one
# crew member at a time - name plate, photo, note and roles - and moves between them
# with the two diff-selector arrows. The list this port used to draw, and the row
# hitboxes that went with it, were invented; nothing in the binary creates them.
#
# Every coordinate below is read out of createUIElements (0x1390fa0) and lives in the
# script next to its address. This builder only wires nodes and art, and mirrors the
# mod's own draw order through zIndex.
extends SceneTree

const OUT := "res://animania_mod/menus/credits/credits_menu.tscn"
const SCRIPT := "res://animania_mod/menus/credits/credits_menu.gd"
const ART := "res://animania_mod/source/images/menus/credits"
const DIFF_FRAMES := "res://animania_mod/source/images/menus/story/diff_selector_frames.tres"

var _root: Node2D
var _k: Dictionary


func _init() -> void:
	_root = Node2D.new()
	_root.name = "CreditsMenu"
	_root.set_script(load(SCRIPT))
	_k = (_root.get_script() as Script).get_script_constant_map()

	var s: float = _k["FUNKIN_TO_RUBICON"]
	var screen: Vector2 = _k["SCREEN"]

	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.position = screen * 0.5
	_add(camera)

	# createBackground: coolBg, screenCenter'd. The mod also lays a bg-stripe backdrop
	# over it at a random angle; that stays where this port already had it.
	var bg := Sprite2D.new()
	bg.name = "Bg"
	bg.centered = false
	bg.texture = load("%s/coolBg.png" % ART)
	bg.scale = Vector2.ONE * s
	bg.position = (screen - Vector2(bg.texture.get_size()) * s) * 0.5
	_add(bg)

	var stripe := Sprite2D.new()
	stripe.name = "BgStripe"
	stripe.centered = true
	stripe.texture = load("%s/bg-stripe.png" % ART)
	stripe.position = screen * 0.5
	stripe.modulate = Color(1.0, 1.0, 1.0, 0.35)
	_add(stripe)

	var particles := Node2D.new()
	particles.name = "Particles"
	_add(particles)

	# 0x1391000: FunkinSprite.create(40, 0, "AnimaniaLogo Smaller"), scale 0.5.
	var logo := Sprite2D.new()
	logo.name = "Logo"
	logo.centered = false
	logo.texture = load("%s/AnimaniaLogo Smaller.png" % ART)
	logo.scale = Vector2.ONE * (float(_k["LOGO_SCALE"]) * s)
	logo.position = Vector2(_k["LOGO_POS"]) * s
	_add(logo)

	# The five pooled role sprites live here; setRoles fills and places them.
	var roles := Node2D.new()
	roles.name = "Roles"
	_add(roles)

	var stickers := Node2D.new()
	stickers.name = "Stickers"
	_add(stickers)

	# 0x1391bb0: create(666, 63, "textnote").
	var note_bg := Sprite2D.new()
	note_bg.name = "NoteBg"
	note_bg.centered = false
	note_bg.texture = load("%s/textnote.png" % ART)
	note_bg.scale = Vector2.ONE * s
	note_bg.position = Vector2(_k["NOTE_BG_POS"]) * s
	_add(note_bg)

	# 0x1391119: AtlasText(715, 180, "", "alphabet-white"), then set_wordWrap(true) and
	# set_fieldWidth(noteBg.width - 2 * (noteTxt.x - noteBg.x)) at 0x1391c56. The font is
	# a bitmap face, not a TTF, and it is vendored beside `default` now. Its wrap width
	# is in the mod's own units because changeItem scales the whole node by the entry's
	# `textScale`, so the node carries the x1.5 and the glyphs do not.
	var note_txt := AtlasText.new()
	note_txt.name = "NoteTxt"
	note_txt.font_png = "res://animania_mod/source/images/fonts/alphabet-white.png"
	note_txt.field_width = float(note_bg.texture.get_width()) \
		- 2.0 * (float(Vector2(_k["NOTE_TXT_POS"]).x) - float(Vector2(_k["NOTE_BG_POS"]).x))
	note_txt.scale = Vector2.ONE * s
	_add(note_txt)
	note_txt.position = Vector2(_k["NOTE_TXT_POS"]) * s

	# updateNameSpr centres this on the note and hangs it a third of its own height
	# above the note's top edge, so the scene only needs the node.
	var name_spr := Sprite2D.new()
	name_spr.name = "NameSpr"
	name_spr.centered = false
	name_spr.visible = false
	name_spr.scale = Vector2.ONE * s
	_add(name_spr)

	# 0x1391e7b: create(1020, 452, "pic-clip"), with the photo behind it.
	var pic_spr := Sprite2D.new()
	pic_spr.name = "PicSpr"
	pic_spr.centered = false
	pic_spr.visible = false
	_add(pic_spr)

	var pic_bg := Sprite2D.new()
	pic_bg.name = "PicBG"
	pic_bg.centered = false
	pic_bg.texture = load("%s/pic-clip.png" % ART)
	pic_bg.scale = Vector2.ONE * s
	pic_bg.position = Vector2(_k["PIC_CLIP_POS"]) * s
	_add(pic_bg)

	# 0x1392aff / 0x1392edb: two copies of the story menu's diff-selector, one
	# animation, scale 1.3. setArrows places them off the first sticker.
	var diff: SpriteFrames = load(DIFF_FRAMES)
	for entry: Array in [["LeftArrow", true], ["RightArrow", false]]:
		var arrow := AnimatedSprite2D.new()
		arrow.name = String(entry[0])
		arrow.centered = false
		arrow.sprite_frames = diff
		arrow.animation = &"difficulty arrow"
		arrow.flip_h = bool(entry[1])
		arrow.scale = Vector2.ONE * (float(_k["ARROW_SCALE"]) * s)
		_add(arrow)

	# createSocialButtons (0x138aa70): four fixed seats, each with its own tilt.
	var social := Node2D.new()
	social.name = "SocialButtons"
	_add(social)
	for seat: Array in _k["SOCIAL_SEATS"]:
		var key: String = String(seat[0])
		var button := Sprite2D.new()
		button.name = "Social_" + key
		button.centered = false
		button.texture = load("%s/buttons/%s.png" % [ART, key])
		button.scale = Vector2.ONE * s
		button.position = Vector2(float(seat[1]), float(seat[2])) * s
		button.rotation_degrees = float(seat[3])
		button.visible = false
		social.add_child(button)
		button.owner = _root

	var sfx := AudioStreamPlayer.new()
	sfx.name = "Sfx"
	sfx.bus = &"Master"
	_add(sfx)

	_root.set(&"sfx", sfx)

	var packed := PackedScene.new()
	packed.pack(_root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT).get_base_dir())
	var err: int = ResourceSaver.save(packed, OUT)
	print("OUT %s %s" % ["saved" if err == OK else "FAILED", OUT])
	quit(0 if err == OK else 1)


func _add(node: Node) -> void:
	_root.add_child(node)
	node.owner = _root
