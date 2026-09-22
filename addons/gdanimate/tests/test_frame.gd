extends RefCounted

## F5 - Frame.hx (448) de MaybeMaru/flixel-animate@dcaa33c.
##
## Blend a nivel KEYFRAME: FlxAnimateJson.hx:135-138 lo parsea, Frame.hx:214
## lo guarda y Frame.hx:389 lo resuelve contra el heredado antes de dibujar
## los elementos del keyframe:
##     var blend = Blend.resolve(this.blend, blend);

const Helpers = preload("res://addons/gdanimate/tests/_helpers.gd")

const NORMAL := AdobeSymbolInstance.AdobeBlendMode.NORMAL
const MULTIPLY := AdobeSymbolInstance.AdobeBlendMode.MULTIPLY
const SCREEN := AdobeSymbolInstance.AdobeBlendMode.SCREEN


func run(_tree: SceneTree) -> Dictionary:
	var failures: Array[String] = []

	_test_frame_blend_parsed(failures)

	return {
		"name": "frame: blend por keyframe (Frame.hx:214 + FrameJson.B)",
		"passed": failures.is_empty(),
		"failures": failures,
	}


func _test_frame_blend_parsed(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()
	atlas.spritemap[&"s"] = _sprite()

	var sym: AdobeSymbol = atlas.load_layers(true, [
		{
			"LN": "L",
			"FR": [
				# Sin B: queda en NORMAL, o sea hereda.
				{"I": 0, "DU": 1, "E": [{"ASI": {"N": "s", "MX": [1, 0, 0, 1, 0, 0]}}]},
				# Con B corto.
				{"I": 1, "DU": 1, "B": MULTIPLY, "E": [{"ASI": {"N": "s", "MX": [1, 0, 0, 1, 0, 0]}}]},
			],
		},
	])
	# Y la clave larga "blend" tiene que funcionar igual (F1: cada campo se
	# resuelve corta ?? larga).
	var long_form: AdobeSymbol = atlas.load_layers(false, [
		{
			"Layer_name": "L",
			"Frames": [
				{"index": 0, "duration": 1, "blend": SCREEN, "elements": [{"ATLAS_SPRITE_instance": {"name": "s", "Matrix": [1, 0, 0, 1, 0, 0]}}]},
			],
		},
	])

	var frames: Array[AdobeLayerFrame] = sym.layers[0].frames
	if frames.size() != 2:
		failures.push_back("esperaba 2 keyframes, hay %d" % frames.size())
		return

	if frames[0].blend_mode != NORMAL:
		failures.push_back("keyframe sin B: esperaba NORMAL (hereda), dio %d" % frames[0].blend_mode)
	if frames[1].blend_mode != MULTIPLY:
		failures.push_back("keyframe con B: esperaba MULTIPLY, dio %d" % frames[1].blend_mode)
	if long_form.layers[0].frames[0].blend_mode != SCREEN:
		failures.push_back("keyframe con \"blend\" (clave larga): esperaba SCREEN, dio %d" % long_form.layers[0].frames[0].blend_mode)

	# Y la precedencia contra el heredado es la de Blend.resolve: gana el del
	# keyframe salvo que sea NORMAL.
	if atlas.resolve_blend(frames[1].blend_mode, SCREEN) != MULTIPLY:
		failures.push_back("precedencia: el blend del keyframe tiene que ganarle al heredado")
	if atlas.resolve_blend(frames[0].blend_mode, SCREEN) != SCREEN:
		failures.push_back("precedencia: un keyframe NORMAL tiene que heredar el de arriba")


func _sprite() -> AdobeAtlasSprite:
	var sprite: AdobeAtlasSprite = AdobeAtlasSprite.new()
	sprite.region = Rect2i(0, 0, 10, 10)
	sprite.rotated = false
	sprite.texture = Helpers.make_solid_texture(Color.RED, Vector2i(10, 10))
	sprite.transform = Transform2D.IDENTITY
	return sprite
