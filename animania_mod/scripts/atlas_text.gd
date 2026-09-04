class_name AtlasText
extends Node2D
## Funkin's AtlasFont, ported.
##
## The mod letters most of its UI with BITMAP fonts, not TrueType: the atlases
## live in assets/images/fonts/ as png + sparrow xml, and each glyph is a
## SubTexture named after the character it draws ("A", "a", "7") or, for
## punctuation, a spelled-out name ("-period-", "-comma-"). Every glyph carries
## a four-digit frame index because Animate exports them as animations; only
## the first frame is ever needed.
##
## Approximating these with a TTF does not work. VCR sets the same string about
## twice as wide as the mod's `default` face for the same cap height, which is
## what made the story menu's tracklist overflow its box however carefully it
## was positioned.

## Punctuation that the atlas spells out instead of using the character.
const NAMED: Dictionary = {
	".": "-period-", ",": "-comma-", "'": "-apostraphie-", "\"": "-start quote-",
	"?": "-question mark-", "!": "-exclamation point-", "\\": "-back slash-",
	"/": "-forward slash-", "-": "-dash-", "x": "-multiply x-",
}

@export var font_png: String = "res://animania_mod/source/images/fonts/default.png"
@export var text: String = "":
	set(value):
		text = value
		_rebuild()
@export var glyph_scale: float = 1.0
@export var line_spacing: float = 4.0
@export var letter_spacing: float = 0.0
@export var colour: Color = Color.WHITE
## AtlasText.set_fieldWidth / set_wordWrap. Zero leaves the string on one line.
@export var field_width: float = 0.0:
	set(value):
		field_width = value
		_rebuild()

var _glyphs: Dictionary = {}
var _sheet: Texture2D
var _line_height: float = 0.0


## Loaded on demand rather than from _ready. Both guards in tools/animania/ and
## the builders drive scenes from a --script MainLoop where nothing enters the
## tree and _ready never fires, so a font loaded there would never exist.
func _ready() -> void:
	_rebuild()


## The atlas art is SOLID BLACK on transparent - every opaque pixel in
## default.png is (0,0,0). The mod colours it by ADDING (its shaders/ folder
## ships AddColorShader.hx), which turns black into the tint; Godot's modulate
## MULTIPLIES, and black times pink is black, which is exactly why the first
## version of this node drew twenty-one glyphs that were all invisible against
## the black tracks box. So the sheet is rebuilt once with every pixel forced
## to white and only the alpha kept: multiplying THAT by the tint gives what
## the mod shows.
func _whiten(tex: Texture2D) -> Texture2D:
	var img: Image = tex.get_image()
	if img == null:
		return tex
	img = img.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	for y: int in img.get_height():
		for x: int in img.get_width():
			var a: float = img.get_pixel(x, y).a
			if a > 0.0:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)


## Reads the sparrow beside the png and keeps ONE region per glyph - the first
## frame. The four-digit suffix is what distinguishes frames of the same glyph.
func _load_font() -> void:
	var src: Texture2D = load(font_png) as Texture2D
	if src == null:
		return
	_sheet = _whiten(src)
	var xml_path: String = font_png.get_basename() + ".xml"
	var parser := XMLParser.new()
	if parser.open(xml_path) != OK:
		push_warning("AtlasText: no atlas at %s" % xml_path)
		return
	while parser.read() == OK:
		if parser.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		if parser.get_node_name() != "SubTexture":
			continue
		var name: String = parser.get_named_attribute_value_safe("name")
		var key: String = name.substr(0, name.length() - 4)
		if key == "" or _glyphs.has(key):
			continue
		var region := Rect2(
			float(parser.get_named_attribute_value_safe("x")),
			float(parser.get_named_attribute_value_safe("y")),
			float(parser.get_named_attribute_value_safe("width")),
			float(parser.get_named_attribute_value_safe("height")))
		var tex: Texture2D
		if parser.get_named_attribute_value_safe("rotated") == "true":
			# `default.xml` has none of these, `alphabet-white.xml` has 34 of its 89:
			# Animate turns a tall glyph on its side to pack it. An AtlasTexture cannot
			# turn it back, so the glyph is cut out and rotated once, here.
			tex = _unrotate(region)
		else:
			var at := AtlasTexture.new()
			at.atlas = _sheet
			at.region = region
			tex = at
		if tex == null:
			continue
		_glyphs[key] = tex
		_line_height = maxf(_line_height, tex.get_size().y)


## Sparrow's `rotated` means the frame was turned 90 degrees CLOCKWISE to pack it,
## so it comes back with a counter-clockwise turn and its width and height swapped.
func _unrotate(region: Rect2) -> Texture2D:
	var sheet: Image = _sheet.get_image()
	if sheet == null:
		return null
	var cut := Image.create_empty(int(region.size.x), int(region.size.y), false, Image.FORMAT_RGBA8)
	cut.blit_rect(sheet, Rect2i(region), Vector2i.ZERO)
	cut.rotate_90(COUNTERCLOCKWISE)
	return ImageTexture.create_from_image(cut)


func _key_for(c: String) -> String:
	if _glyphs.has(c):
		return c
	if NAMED.has(c) and _glyphs.has(NAMED[c]):
		return NAMED[c]
	# The atlas carries both cases for letters, but not for every symbol.
	if _glyphs.has(c.to_upper()):
		return c.to_upper()
	return ""


func _rebuild() -> void:
	if _sheet == null:
		_load_font()
	for child: Node in get_children():
		remove_child(child)
		child.free()
	if _glyphs.is_empty():
		return
	var pen := Vector2.ZERO
	for line: String in _lines():
		for i: int in line.length():
			var c: String = line[i]
			if c == " ":
				pen.x += _space_width()
				continue
			var key: String = _key_for(c)
			if key == "":
				pen.x += _space_width()
				continue
			var tex: Texture2D = _glyphs[key]
			var s := Sprite2D.new()
			s.texture = tex
			s.centered = false
			s.scale = Vector2.ONE * glyph_scale
			# Sit every glyph on a shared baseline rather than on its own top,
			# or letters with descenders ride up.
			s.position = Vector2(pen.x,
				pen.y + (_line_height - tex.get_size().y) * glyph_scale)
			s.modulate = colour
			add_child(s)
			pen.x += (tex.get_size().x + letter_spacing) * glyph_scale
		pen.x = 0.0
		pen.y += (_line_height * glyph_scale) + line_spacing


func _space_width() -> float:
	return _line_height * 0.28 * glyph_scale


func _run_width(run: String) -> float:
	var w: float = 0.0
	for i: int in run.length():
		var c: String = run[i]
		var key: String = _key_for(c) if c != " " else ""
		if key == "":
			w += _space_width()
			continue
		w += (_glyphs[key].get_size().x + letter_spacing) * glyph_scale
	return w


## Hard newlines always break; `field_width` breaks the rest at word boundaries,
## which is what set_wordWrap(true) plus set_fieldWidth does in the mod.
func _lines() -> PackedStringArray:
	var out := PackedStringArray()
	for hard: String in text.split("\n"):
		if field_width <= 0.0 or _run_width(hard) <= field_width:
			out.append(hard)
			continue
		var current: String = ""
		for word: String in hard.split(" "):
			var candidate: String = word if current == "" else current + " " + word
			if current != "" and _run_width(candidate) > field_width:
				out.append(current)
				current = word
			else:
				current = candidate
		out.append(current)
	return out


## Width and height of what was laid out, for callers that need to place it.
func measure() -> Vector2:
	var w: float = 0.0
	var h: float = 0.0
	for child: Node in get_children():
		var s: Sprite2D = child as Sprite2D
		if s == null or s.texture == null:
			continue
		w = maxf(w, s.position.x + s.texture.get_size().x * s.scale.x)
		h = maxf(h, s.position.y + s.texture.get_size().y * s.scale.y)
	return Vector2(w, h)
