extends Control
## Ports ui/ButtonUI.hx — real button-basic.png/button-small.png (3 stacked
## frames: normal/highlighted/disabled), button_selected-*.png (the one-shot
## "confirmed" flash), button_highlight-*.png (the looping selected-pulse
## ring, same math as hq_message_window's own pulse), and the lock icon.
## button_Hold (a hold-to-confirm progress clip) is never actually driven
## anywhere HQMainMenu uses ButtonUI, so it's not ported — there would be
## nothing to verify it against.
##
## `style` ("basic" or "small") MUST be set before this enters the tree —
## like hq_message_window's own text/icon fields, it's read once in _ready().

const GenUtil := preload("res://holyquintet_mod/scripts/gen_util.gd")

var style: String = "basic"
var id: int = -1

var _selected: bool = false
var _locked: bool = false
var _text: String = ""
var _sub_text: String = ""
var _icon: String = "none"

@onready var sprite: TextureRect = $Sprite
@onready var selected_flash: TextureRect = $Selected
@onready var highlight: TextureRect = $Highlight
@onready var text_label: Label = $TextLabel
@onready var sub_text_label: Label = $SubTextLabel
@onready var lock_icon: TextureRect = $Lock
@onready var icon_tex: TextureRect = $Icon

var _atlas_normal: AtlasTexture
var _atlas_highlighted: AtlasTexture
var _atlas_disabled: AtlasTexture
var _highlight_tween: Tween
var _sprite_w: float
var _sprite_h: float


func _ready() -> void:
	var base_tex: Texture2D = load("res://holyquintet_mod/source/images/ui/common/button-%s.png" % style)
	_sprite_w = base_tex.get_width()
	_sprite_h = base_tex.get_height() / 3.0

	_atlas_normal = _make_atlas(base_tex, 0)
	_atlas_highlighted = _make_atlas(base_tex, 1)
	_atlas_disabled = _make_atlas(base_tex, 2)
	sprite.texture = _atlas_normal
	sprite.size = Vector2(_sprite_w, _sprite_h)

	selected_flash.texture = load("res://holyquintet_mod/source/images/ui/common/button_selected-%s.png" % style)
	selected_flash.modulate.a = 0.0
	highlight.texture = load("res://holyquintet_mod/source/images/ui/common/button_highlight-%s.png" % style)
	highlight.modulate.a = 0.0

	lock_icon.texture = load("res://holyquintet_mod/source/images/ui/common/lock.png")
	lock_icon.visible = false
	# GenUtil.alignToCenter(button_Lock, button_Sprite); button_Lock.x += 150; button_Lock.y -= 5;
	# — only meaningful for 'basic' (real code only sets button_Lock.visible for non-'small' styles).
	lock_icon.position = Vector2(
		(_sprite_w - lock_icon.texture.get_width()) * 0.5 + 150.0,
		(_sprite_h - lock_icon.texture.get_height()) * 0.5 - 5.0
	)

	icon_tex.visible = style == "small"
	if style == "small":
		icon_tex.texture = load("res://holyquintet_mod/source/images/ui/common/icons/%s.png" % _icon)

	text_label.custom_minimum_size.x = _sprite_w * 0.8
	text_label.size.x = _sprite_w * 0.8
	sub_text_label.custom_minimum_size.x = _sprite_w * 0.8
	sub_text_label.size.x = _sprite_w * 0.8

	selected = _selected
	locked = _locked
	text = _text
	sub_text = _sub_text
	icon = _icon
	_refresh_text_position()


func _make_atlas(tex: Texture2D, frame: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(0, frame * _sprite_h, _sprite_w, _sprite_h)
	return atlas


var selected: bool:
	get: return _selected
	set(v):
		_selected = v
		if not is_node_ready():
			return
		if v:
			sprite.texture = _atlas_disabled if _locked else _atlas_highlighted
			if not _locked:
				sprite.modulate = Color.WHITE
				highlight.modulate = Color(1, 1, 1, 1)
				text_label.modulate = Color.WHITE
				sub_text_label.modulate = Color.WHITE
				selected_flash.self_modulate = Color.WHITE
				text_label.add_theme_constant_override("outline_size", 6)
				sub_text_label.add_theme_constant_override("outline_size", 6)
			else:
				sprite.modulate = Color.WHITE
				highlight.modulate = Color(0.5, 0.5, 0.5, 1)
				lock_icon.modulate = Color.WHITE
				selected_flash.self_modulate = Color.WHITE
				text_label.modulate = Color(0x51 / 255.0, 0x42 / 255.0, 0x60 / 255.0)
				sub_text_label.modulate = Color(0x51 / 255.0, 0x42 / 255.0, 0x60 / 255.0)
				text_label.add_theme_constant_override("outline_size", 0)
				sub_text_label.add_theme_constant_override("outline_size", 0)
			if style == "small":
				icon_tex.modulate = Color.WHITE
			if _highlight_tween:
				_highlight_tween.kill()
			highlight.scale = Vector2.ONE
			highlight.modulate.a = 1.0
			_highlight_tween = create_tween()
			_highlight_tween.set_loops()
			_highlight_tween.tween_property(highlight, "scale", Vector2(1.05, 1.05), 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_highlight_tween.parallel().tween_property(highlight, "modulate:a", 0.0, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_highlight_tween.tween_interval(0.5)
		else:
			sprite.texture = _atlas_disabled if _locked else _atlas_normal
			if not _locked:
				sprite.modulate = Color(0.5, 0.5, 0.5)
				text_label.modulate = Color(0.5, 0.5, 0.5)
				sub_text_label.modulate = Color(0.5, 0.5, 0.5)
				text_label.add_theme_constant_override("outline_size", 6)
				sub_text_label.add_theme_constant_override("outline_size", 6)
			else:
				sprite.modulate = Color(0.5, 0.5, 0.5)
				lock_icon.modulate = Color(0.5, 0.5, 0.5)
				text_label.modulate = Color(0x20 / 255.0, 0x1a / 255.0, 0x26 / 255.0)
				sub_text_label.modulate = Color(0x20 / 255.0, 0x1a / 255.0, 0x26 / 255.0)
				text_label.add_theme_constant_override("outline_size", 0)
				sub_text_label.add_theme_constant_override("outline_size", 0)
			if style == "small":
				icon_tex.modulate = Color(0.5, 0.5, 0.5)
			if _highlight_tween:
				_highlight_tween.kill()
			highlight.scale = Vector2.ONE
			highlight.modulate.a = 0.0


var locked: bool:
	get: return _locked
	set(v):
		_locked = v
		if not is_node_ready():
			return
		if v:
			sprite.texture = _atlas_disabled
			sprite.modulate = Color.WHITE
			text_label.modulate = Color.WHITE
			sub_text_label.modulate = Color.WHITE
			if style != "small":
				lock_icon.visible = true
		else:
			sprite.texture = _atlas_normal
			sprite.modulate = Color(0.5, 0.5, 0.5)
			text_label.modulate = Color(0.5, 0.5, 0.5)
			sub_text_label.modulate = Color(0.5, 0.5, 0.5)
			lock_icon.visible = false
			if _highlight_tween:
				_highlight_tween.kill()
			highlight.scale = Vector2.ONE
			highlight.modulate.a = 0.0
		_refresh_text_position()


var text: String:
	get: return _text
	set(v):
		_text = v
		if not is_node_ready():
			return
		text_label.text = v
		_refresh_text_position()


var sub_text: String:
	get: return _sub_text
	set(v):
		_sub_text = v
		if not is_node_ready():
			return
		sub_text_label.text = v
		_refresh_text_position()


var icon: String:
	get: return _icon
	set(v):
		_icon = v
		if not is_node_ready() or style != "small":
			return
		icon_tex.texture = load("res://holyquintet_mod/source/images/ui/common/icons/%s.png" % v)


func _refresh_text_position() -> void:
	var text_h: float = text_label.get_theme_font("font").get_height(text_label.get_theme_font_size("font_size"))
	text_label.position = Vector2((_sprite_w - text_label.size.x) * 0.5, (_sprite_h - text_h) * 0.5)
	if _sub_text != "":
		text_label.position.y -= 12.0
	sub_text_label.position = Vector2((_sprite_w - sub_text_label.size.x) * 0.5, (_sprite_h - text_h) * 0.5 + 32.0)

	if _locked:
		text_label.scale.x = 0.9
		sub_text_label.scale.x = 0.9
		text_label.position.x -= 30.0
		sub_text_label.position.x -= 30.0
	else:
		text_label.scale.x = 1.0
		sub_text_label.scale.x = 1.0


## ButtonUI.hx selection(): the one-shot "confirmed" flash — button_Selected
## pops from alpha 1/scale 1 to alpha 0/scale 1.15 over 1.0s, and the
## looping highlight ring is cancelled outright (real code: locked buttons
## just no-op here, since confirmSelection() never lets a locked button
## reach this — it plays 'error' and returns before calling selection()).
func selection() -> void:
	if _locked:
		return
	selected_flash.modulate.a = 1.0
	selected_flash.scale = Vector2.ONE
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(selected_flash, "scale", Vector2(1.15, 1.15), 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(selected_flash, "modulate:a", 0.0, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	if _highlight_tween:
		_highlight_tween.kill()
	highlight.scale = Vector2.ONE
	highlight.modulate.a = 0.0
