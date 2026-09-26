extends RefCounted

## Etapa 1A - fix de MovieClipInstance con movie_clips_play=true: tiene que
## respetar loop_mode y la ventana first_frame/last_frame del elemento,
## delegando a symbol_instance_frame() (la misma funcion que ya usan los
## Graphics) en vez de un wrapi() ciego sobre el largo TOTAL del sub-simbolo.
##
## cne-flixel-animate/src/animate/internal/elements/MovieClipInstance.hx:223-226:
## getFrameIndex() con swfMode=true delega directo a
## SymbolInstance.getFrameIndex() (super.getFrameIndex), sin ninguna logica
## propia - un MovieClip "jugando" se comporta exactamente como un Graphic
## para efectos de que frame mostrar.
##
## Test de integracion, no solo de la funcion pura: arma un MovieClip con
## ventana first_frame=1,last_frame=2 (LOOP) apuntando a un sub-simbolo de 4
## frames, cada uno un color solido distinto, y verifica por pixel que
## draw_symbol() efectivamente termina mostrando la secuencia correcta
## (GREEN,BLUE,GREEN,BLUE para difference=0,1,2,3) en vez de la que el wrap
## viejo hubiera dado (GREEN,BLUE,YELLOW,RED - se sale de la ventana).

const Helpers = preload("res://addons/gdanimate/tests/_helpers.gd")


func run(tree: SceneTree) -> Dictionary:
	var failures: Array[String] = []

	var atlas: AdobeAtlas = Helpers.make_test_atlas()
	atlas.movie_clips_play = true

	# Sub-simbolo de 4 frames, un color solido distinto por frame, mismo
	# tamano y posicion para que solo cambie el color visible.
	var colors: Array[Color] = [Color.RED, Color.GREEN, Color.BLUE, Color(1, 1, 0, 1)]
	var color_names: Array[String] = ["RED", "GREEN", "BLUE", "YELLOW"]
	for i in colors.size():
		atlas.spritemap[StringName("frame_%d" % i)] = _make_sprite(colors[i], Vector2i(80, 80))

	# Un solo layer con 4 keyframes de 1 frame cada uno (I:0..3).
	var frames_json: Array = []
	for i in colors.size():
		frames_json.push_back(_frame_with_sprite("frame_%d" % i, i, 1))
	var windowed_symbol: AdobeSymbol = atlas.load_layers(true, [
		{"LN": "L", "FR": frames_json},
	])
	atlas.symbols[&"windowed"] = windowed_symbol

	if windowed_symbol.length != 4:
		failures.push_back("sub-simbolo: esperaba length=4, dio %d" % windowed_symbol.length)

	# Root: un layer, un solo keyframe de duracion 4 (para que difference
	# recorra 0..3 dentro del MISMO keyframe), con el MovieClip ventaneado.
	var root_layers: Array = [
		{
			"LN": "Root",
			"FR": [
				{
					"I": 0,
					"DU": 4,
					"E": [
						{
							"SI": {
								"SN": "windowed",
								"ST": "MC",
								"FF": 1,
								"LF": 2,
								"LP": "LP",
								"MX": [1, 0, 0, 1, 0, 0],
							}
						}
					],
				}
			],
		},
	]
	var root_symbol: AdobeSymbol = atlas.load_layers(true, root_layers)
	atlas.symbols[&"root"] = root_symbol
	atlas.stage_symbol = &"root"

	var root_node: Node2D = Node2D.new()
	tree.root.add_child(root_node)

	var symbol_node: AnimateSymbol = AnimateSymbol.new()
	symbol_node.atlases = [atlas]
	symbol_node.symbol = "root"
	symbol_node.centered = false
	# Lejos de la esquina superior izquierda: el overlay de debug (FPS/MEM/
	# SCENE/MODS, del autoload DebugDisplay) dibuja texto blanco encima de
	# esa zona y contamina el muestreo de pixeles.
	symbol_node.position = Vector2(300, 300)
	root_node.add_child(symbol_node)

	# expected[i] = indice de color esperado para difference=i, con la
	# ventana FF=1,LF=2,LOOP: span=2, offset=wrapi(difference,0,2).
	var expected_indices: Array[int] = [1, 2, 1, 2]

	for difference in 4:
		symbol_node.frame = difference
		await Helpers.wait_frames(tree, 2)

		var img: Image = tree.root.get_texture().get_image()
		var expected_color: Color = colors[expected_indices[difference]]
		# No asumo pixeles exactos: el viewport puede tener su propio stretch
		# transform (ya vi el cuadrado terminar en otro lado del que hubiera
		# calculado a mano), asi que busco el primer pixel que matchee
		# CUALQUIERA de los 4 colores de paleta, salteando la franja de
		# arriba donde dibuja el overlay de debug (FPS/MEM/SCENE/MODS).
		var found_color: Color = _find_palette_color(img, colors)
		var found_pos: Vector2i = Vector2i(0, 0) if found_color.r >= 0.0 else Vector2i(-1, -1)

		if found_pos.x == -1:
			failures.push_back("difference=%d: no encontre ningun pixel de la paleta de colores en el viewport (%s)" % [difference, img.get_size()])
		elif not found_color.is_equal_approx(expected_color):
			failures.push_back(
				"difference=%d: esperaba %s (%s), encontre %s en (%d,%d)" % [
					difference, color_names[expected_indices[difference]], expected_color,
					found_color, found_pos.x, found_pos.y,
				]
			)

	# --- movie_clips_play = false: MovieClip congelado en el frame 0 ---
	# MovieClipInstance.hx:220-223: getFrameIndex devuelve literal 0 cuando
	# swfMode esta apagado, NO first_frame. La ventana FF=1/LF=2 de este
	# MovieClip tiene que quedar completamente ignorada y mostrarse siempre
	# el frame 0 del sub-simbolo (RED), no el 1 (GREEN).
	atlas.movie_clips_play = false
	for difference in 4:
		symbol_node.frame = difference
		symbol_node.frame_dirty = true
		symbol_node.queue_redraw()
		await Helpers.wait_frames(tree, 2)

		var frozen_img: Image = tree.root.get_texture().get_image()
		var frozen: Color = _find_palette_color(frozen_img, colors)
		if frozen.r < 0.0:
			failures.push_back("movie_clips_play=false, difference=%d: no encontre ningun pixel de la paleta" % difference)
		elif not frozen.is_equal_approx(Color.RED):
			failures.push_back(
				"movie_clips_play=false, difference=%d: esperaba RED (frame 0 del sub-simbolo), encontre %s" % [difference, frozen]
			)

	atlas.movie_clips_play = true
	symbol_node.frame_dirty = true
	symbol_node.queue_redraw()
	await Helpers.wait_frames(tree, 2)

	var png: String = Helpers.capture_png(tree, "swf_mode.png")

	root_node.queue_free()
	await tree.process_frame

	return {
		"name": "swfMode: MovieClip respeta ventana FF/LF con movie_clips_play=true",
		"passed": failures.is_empty(),
		"failures": failures,
		"png": png,
	}


func _make_sprite(color: Color, size: Vector2i) -> AdobeAtlasSprite:
	var sprite: AdobeAtlasSprite = AdobeAtlasSprite.new()
	sprite.region = Rect2i(Vector2i.ZERO, size)
	sprite.rotated = false
	sprite.texture = Helpers.make_solid_texture(color, size)
	sprite.transform = Transform2D.IDENTITY
	return sprite


func _frame_with_sprite(sprite_name: String, index: int, duration: int) -> Dictionary:
	return {
		"I": index,
		"DU": duration,
		"E": [{"ASI": {"N": sprite_name, "MX": [1, 0, 0, 1, 0, 0]}}],
	}


## Busca el primer pixel que matchee CUALQUIERA de los colores de la paleta,
## salteando la franja de arriba donde el autoload DebugDisplay dibuja el
## overlay (FPS/MEM/SCENE/MODS). Devuelve un color con r < 0 si no encontro
## ninguno. No se asumen coordenadas exactas: el viewport puede tener su
## propio stretch transform.
func _find_palette_color(img: Image, colors: Array[Color]) -> Color:
	for y in range(80, img.get_height()):
		for x in range(0, img.get_width()):
			var p: Color = img.get_pixel(x, y)
			for c: Color in colors:
				if p.is_equal_approx(c):
					return p
	return Color(-1, -1, -1, -1)
