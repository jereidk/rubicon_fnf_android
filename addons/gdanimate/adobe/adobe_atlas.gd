@tool
extends AnimateAtlas
class_name AdobeAtlas




@export_dir var folder_path: String = "":
	set(v):
		folder_path = v
		if not folder_path.get_extension().is_empty():
			folder_path = folder_path.get_base_dir() + "/"
		elif not folder_path.ends_with("/"):
			folder_path += "/"

		parse()


@export var movie_clips_play: bool = false:
	set(v):
		movie_clips_play = v
		ask_redraw = true


@export var clip_texture_uvs: bool = true:
	set(v):
		clip_texture_uvs = v
		ask_redraw = true

var spritemap: Dictionary[StringName, AdobeAtlasSprite] = {}
var symbols: Dictionary[StringName, AdobeSymbol] = {}
var framerate: float = 24.0
var stage_symbol: StringName = &""
var stage_transform: Transform2D = Transform2D.IDENTITY
## Stage background: tamaño (de metadata W x H, default 1280x720) y color
## (BGC, default blanco). FlxAnimate dibuja un rect de este color detras
## del contenido del simbolo. Si el color tiene alpha 0, se omite.
var stage_rect: Rect2 = Rect2(0, 0, 1280, 720)
var stage_color: Color = Color.WHITE
var render_stage: bool = false
## Scratch for one draw_on() call, handed to the drawing symbol at the end of
## it. draw_symbol() is a thirteen-parameter recursive function called
## positionally from four places, so the cache is collected here and moved
## rather than threaded through as a fourteenth.
##
## It used to be the cache itself, and use_backbuffer_cache used to sit beside
## it. Both are per-symbol state and this resource is shared by every symbol
## that names it, so they now live on AnimateDrawInfo - see the note there.
var _backbuffer_scratch: Array[Dictionary] = []
## Botones encontrados en el dibujo actual, con su hitbox recien calculado.
## Mismo patron que _backbuffer_scratch: se llena durante draw_symbol() y
## draw_on() lo entrega al nodo al final.
var _button_scratch: Array[AdobeButtonInstance] = []


func parse() -> void :
	super ()
	format = "adobe"

	var base_dir: String = folder_path
	if not folder_path.ends_with("/"):
		base_dir = folder_path.get_base_dir() + "/"

	var cache_path: String = _cache_path_for(base_dir)
	if ResourceLoader.exists(cache_path):
		var cached: AdobeAtlasCached = load(cache_path)
		if is_instance_valid(cached):
			spritemap = cached.spritemap
			symbols = cached.symbols
			framerate = cached.framerate
			stage_symbol = cached.stage_symbol
			stage_transform = cached.stage_transform
			stage_rect = cached.stage_rect
			stage_color = cached.stage_color
			render_stage = cached.render_stage
			# F6: migrar caches viejos que no tienen layer_type, frame_indices
			# ni parent_layer. AdobeSymbol.migrate_all_layers_from_legacy()
			# hace los tres pasos (inferir tipo, rellenar indices, resolver
			# clipper ref). Idempotente.
			for sym_name: StringName in symbols:
				var sym: AdobeSymbol = symbols[sym_name]
				sym.migrate_all_layers_from_legacy()
			return

	spritemap.clear()
	symbols.clear()

	var animation_json: String = "%s/Animation.json" % [base_dir]
	if not ResourceLoader.exists(animation_json):
		push_error("[GDAnimate] " + "Atlas path (%s) is missing Animation.json!" % [base_dir])
		return

	load_spritemaps()
	load_animation()


func cache() -> void :
	super ()

	var base_dir: String = folder_path
	if not folder_path.ends_with("/"):
		base_dir = folder_path.get_base_dir() + "/"

	var cached: AdobeAtlasCached = AdobeAtlasCached.new()
	cached.spritemap = spritemap
	cached.symbols = symbols
	cached.framerate = framerate
	cached.stage_symbol = stage_symbol
	cached.stage_transform = stage_transform
	cached.stage_rect = stage_rect
	cached.stage_color = stage_color
	cached.render_stage = render_stage
	# res:// es read-only en Android (el pck es inmutable). Escribimos el
	# cache en user:// con un path basado en un hash del folder + el mtime
	# del Animation.json, para que se regenere si el mod se actualiza.
	var cache_path := _cache_path_for(base_dir)
	var cache_dir := cache_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(cache_dir)
	cached.take_over_path(cache_path)
	ResourceSaver.save(cached, cache_path, ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_REPLACE_SUBRESOURCE_PATHS)


## Devuelve el path del cache para un base_dir. El hash del path
## diferencia entre atlases, y el mtime del Animation.json invalida
## el cache cuando el mod se actualiza (mismo hash, mtime distinto,
## path distinto, cache se regenera).
func _cache_path_for(base_dir: String) -> String:
	var anim_json: String = base_dir + "Animation.json"
	var mtime: int = 0
	if FileAccess.file_exists(anim_json):
		mtime = FileAccess.get_modified_time(anim_json)
	return "user://mods_cache/gdanimate/%s_%d.res" % [str(base_dir.hash()), mtime]


func draw_on(canvas_item: RID, draw_info: AnimateDrawInfo) -> void :
	super (canvas_item, draw_info)

	if stage_symbol.is_empty():
		return

	var use_stage: bool = not symbols.has(draw_info.symbol)
	var key: StringName = stage_symbol if use_stage else draw_info.symbol
	var transform: Transform2D = Transform2D.IDENTITY
	transform = transform.translated(draw_info.offset)

	# CORRECCION DE FUENTE: el comentario original de este fix citaba
	# Dot-Stuff/flxanimate, que NO es el engine que usa el mod. CodenameEngine
	# (haxelib "flixel-animate") vendorea su propio fork reescrito,
	# CodenameCrew/cne-flixel-animate (paquete `animate`, no `flxanimate`) -
	# ver FIDELITY.md seccion "Fuente de verdad". Todas las referencias de
	# abajo son a ESE repo.
	#
	# FlxAnimate aplica el stage matrix ANTES del scale del sprite
	# (prepareDrawMatrix, cne-flixel-animate/src/animate/FlxAnimate.hx:304-319)
	# siempre que applyStageMatrix este activo. Codename lo activa siempre en
	# FunkinSprite (FunkinSprite.hx:97 applyStageMatrix = true), asi que los
	# Animation.json del mod HQ dependen de el.
	#
	# Antes este bloque solo se ejecutaba con use_stage=true (symbol NO
	# encontrado en el diccionario). Los root symbols del HQ
	# (Story_Animation, Freeplay_Animation, etc.) SI existen en symbols,
	# asi que use_stage=false y el stage matrix se ignoraba por completo.
	# Eso obligo a calibrar las posiciones del mod a mano.
	#
	# Fix: respetar draw_info.apply_stage_matrix explicitamente.
	# Verificado en el source: como los M3D de los Animation.json del HQ
	# son solo traslacion (a=d=1, b=c=0), aplicar el stage como translate
	# local en el stage_item produce el mismo resultado final que el
	# pipeline de FlxAnimate (T(pos)*R*S*T(stage.tx, stage.ty)).
	#
	# LIMITE CONOCIDO (no arreglado aca, ver FIDELITY.md): esto es una
	# aproximacion, no una reproduccion literal de prepareDrawMatrix. El
	# pipeline real hace translate(-bounds.x,-bounds.y) ANTES de concatenar
	# el stage matrix (FlxAnimate.hx:224-225 en drawAnimate) y translate(
	# bounds.x*matrix.a, bounds.y*matrix.d) despues (FlxAnimate.hx:317), algo
	# que no tiene un analogo directo aca porque AnimateSymbol no normaliza
	# su dibujo a un "frame" con bounds como FlxSprite - dibuja los RIDs
	# directamente en coordenadas de Animate. Si un futuro Animation.json
	# trae un M3D de stage con rotacion o escala no trivial, este approach
	# puede divergir y hay que revisar la formula completa.
	var should_apply_stage: bool = draw_info.apply_stage_matrix or use_stage
	if should_apply_stage and stage_transform != Transform2D.IDENTITY:
		transform *= stage_transform

	# El camino barato reusa los RIDs del dibujo anterior y no vuelve a pasar
	# por draw_symbol(), asi que tampoco recalcula hitboxes. Como estos quedan
	# en coordenadas locales del nodo, no se invalidan cuando el nodo se mueve
	# y el camino barato sigue siendo seguro con botones; lo unico que hay que
	# hacer es NO vaciar la lista que el nodo ya tiene.
	if draw_info.use_backbuffer_cache:
		if Engine.is_editor_hint():
			draw_info.backbuffer_cache.clear()
			return

		for cached: Dictionary in draw_info.backbuffer_cache:
			RenderingServer.canvas_item_set_copy_to_backbuffer(
				cached.get(&"rid"),
				true,
				draw_info.screen_transform * transform * cached.get(&"rect"),
			)

		return

	_backbuffer_scratch.clear()
	_button_scratch.clear()

	# StageBG: rect del color de fondo del "stage" de Adobe Animate.
	# FlxAnimate tiene renderStage = false por default (FlxAnimate.hx:96)
	# y el mod original nunca lo activa. Se deja apagado para matchear.
	if render_stage and stage_color.a > 0.0:
		var bg_item: RID = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_transform(bg_item, draw_info.screen_transform)
		RenderingServer.canvas_item_set_parent(bg_item, canvas_item)
		RenderingServer.canvas_item_set_draw_behind_parent(bg_item, true)
		RenderingServer.canvas_item_set_use_parent_material(bg_item, true)
		RenderingServer.canvas_item_set_light_mask(bg_item, draw_info.light_mask)
		RenderingServer.canvas_item_set_visibility_layer(bg_item, draw_info.visibility_layer)
		RenderingServer.canvas_item_add_rect(bg_item, stage_rect, stage_color)
		draw_info.items.push_back(bg_item)

	var stage_item: RID = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_transform(stage_item, transform)
	RenderingServer.canvas_item_set_parent(stage_item, canvas_item)
	RenderingServer.canvas_item_set_draw_behind_parent(stage_item, true)
	RenderingServer.canvas_item_set_use_parent_material(stage_item, true)
	RenderingServer.canvas_item_set_light_mask(stage_item, draw_info.light_mask)
	RenderingServer.canvas_item_set_visibility_layer(stage_item, draw_info.visibility_layer)
	draw_info.items.push_back(stage_item)

	draw_symbol(symbols[key], 
		stage_item, 
		Transform2D.IDENTITY, 
		draw_info.frame, 
		false, 
		draw_info.items, 
		AdobeSymbolInstance.AdobeBlendMode.NORMAL, 
		draw_info.material, 
		null, 
		Rect2(), 
		draw_info.screen_transform * transform, 
		draw_info.additive_material,
		draw_info.light_mask,
		draw_info.visibility_layer,
	)

	# Hand the rebuild's cache to the symbol that asked for it. assign() fills
	# the array the symbol passed in rather than replacing the reference, so
	# the symbol keeps hold of its own cache across draws.
	draw_info.backbuffer_cache.assign(_backbuffer_scratch)

	# Los hitboxes se calcularon en el espacio del stage_item; `transform` es
	# lo que lleva ese espacio al del nodo (offset + stage matrix). Aplicarlo
	# aca, de una sola vez, los deja en coordenadas locales del nodo, que es
	# donde AnimateSymbol hace el hit-test con get_local_mouse_position().
	for button: AdobeButtonInstance in _button_scratch:
		button.last_hitbox = transform * button.last_hitbox

	draw_info.buttons.assign(_button_scratch)


## Lee W/H/BGC del bloque metadata. Acepta tanto la version "optimizada"
## (W, H, BGC) como la legacy de Adobe Animate (width, height, backgroundColor).
## Default 1280x720 blanco, mismo que FlxAnimateFrames.hx usa cuando W o H <= 0.
func _parse_stage_metadata(meta: Dictionary) -> void:
	var w: float = float(meta.get("W", meta.get("width", 0)))
	var h: float = float(meta.get("H", meta.get("height", 0)))
	if w > 0.0 and h > 0.0:
		stage_rect = Rect2(0, 0, w, h)
	else:
		stage_rect = Rect2(0, 0, 1280, 720)

	var bgc_raw: String = str(meta.get("BGC", meta.get("backgroundColor", "#FFFFFF")))
	# Color.from_string de Godot no acepta el "#" inicial.
	stage_color = Color.from_string(bgc_raw.trim_prefix("#"), Color.WHITE)


func get_framerate() -> float:
	return framerate


func get_base_dir() -> String:
	return folder_path.get_base_dir()


func get_filename() -> String:
	return folder_path.get_base_dir().get_file()


func get_symbols() -> String:
	var string: String = ""
	var keys: Array = symbols.keys()
	keys.sort_custom( func(a: Variant, b: Variant):
		if a is StringName and b is StringName:
			return a.to_lower() < b.to_lower()

		return a < b
	)

	for symbol_name: StringName in keys:
		string += "%s," % [symbol_name.json_escape()]

	if not string.is_empty():
		string.remove_char(string.length() - 1)

	return ("" if string.is_empty() else " ,") + string


func get_length_of(symbol: StringName) -> int:
	if not symbols.has(symbol):
		symbol = stage_symbol

	if symbols.has(symbol):
		return symbols[symbol].length

	return 0


func draw_symbol(target: AdobeSymbol, parent: RID, 
				t: Transform2D, frame: int, 
				is_clipper: bool, items: Array[RID], 
				blend_mode: AdobeSymbolInstance.AdobeBlendMode = AdobeSymbolInstance.AdobeBlendMode.NORMAL, 
				material: Material = null, 
				color_matrix: AdobeColorMatrix = null, 
				screen_rect: Rect2 = Rect2(), 
				screen_transform: Transform2D = Transform2D.IDENTITY, 
				additive_material: Material = null, 
				light_mask: int = 1, 
				visibility_layer: int = 1, ) -> Rect2:
	if frame > target.length - 1:
		frame = target.length - 1

	var to_push: Array[RID] = []
	var clip_pushes: Dictionary[StringName, Array] = {}
	var rids: Dictionary[StringName, RID] = {}
	for layer: AdobeLayer in target.layers:
		# Layer.hx:158-163: capa clipeada sin su Clipper -> oculta por completo,
		# no se crea ningun RID para ella. Ver AdobeLayer.hidden.
		if layer.hidden:
			continue

		var layer_rid: RID
		var layer_parent: RID = parent
		if not is_clipper:
			layer_rid = RenderingServer.canvas_item_create()
			items.push_back(layer_rid)

			RenderingServer.canvas_item_set_use_parent_material(layer_rid, true)
			RenderingServer.canvas_item_set_light_mask(layer_rid, light_mask)
			RenderingServer.canvas_item_set_visibility_layer(layer_rid, visibility_layer)

			rids.set(layer.name, layer_rid)

			if layer.clipping:
				RenderingServer.canvas_item_set_canvas_group_mode(layer_rid, RenderingServer.CANVAS_GROUP_MODE_CLIP_ONLY)
				RenderingServer.canvas_item_set_use_parent_material(layer_rid, false)
			elif not layer.clipped_by.is_empty():
				if not clip_pushes.has(layer.clipped_by):
					clip_pushes.set(layer.clipped_by, [])

				clip_pushes[layer.clipped_by].push_front(layer_rid)
				layer_parent = rids.get(layer.clipped_by, parent)
		else:
			layer_rid = parent

		var rendered: bool = false
		# Glow de la frame activa del layer. Solo una frame por layer esta
		# activa en el frame actual, asi que sobreescribir esta bien.
		var layer_glow: Dictionary = {}
		# Idem para el blend: Frame.hx:389 arranca draw() con
		#     var blend = Blend.resolve(this.blend, blend);
		# o sea que el blend propio del keyframe pisa al heredado (salvo que
		# sea NORMAL) para todos sus elementos. Como solo hay un keyframe
		# activo por capa, se resuelve una vez y se usa tanto para los
		# elementos como para el material de la capa.
		var layer_blend: AdobeSymbolInstance.AdobeBlendMode = blend_mode
		for layer_frame: AdobeLayerFrame in layer.frames:
			if frame > layer_frame.starting_index + layer_frame.duration - 1:
				continue
			if frame < layer_frame.starting_index:
				continue

			var difference: int = frame - layer_frame.starting_index
			rendered = true
			layer_glow = layer_frame.glow
			layer_blend = resolve_blend(layer_frame.blend_mode, blend_mode)
			for element: AdobeDrawable in layer_frame.elements:
				# Frame.hx:423-426 (maru dcaa33c): el loop de dibujo del
				# keyframe saltea todo elemento con visible == false.
				if not element.visible:
					continue

				if element is AdobeSymbolInstance:
					# SymbolInstance.hx:57-58 (maru dcaa33c):
					#     if (libraryItem == null)
					#         visible = false;
					# Una instancia que apunta a un simbolo que no esta en la
					# libreria no se dibuja. El port iba directo a
					# symbols[element.key] y reventaba con "Invalid access to
					# property or key ... on a base object of type Dictionary",
					# un error que ABORTA la funcion: el resto del keyframe (y
					# del layer) se dejaba de dibujar por un solo nombre roto.
					#
					# El chequeo va aca y no en load_symbol_instance() porque en
					# tiempo de parseo no alcanza: load_symbols() carga los
					# simbolos de a uno, asi que mientras se parsea el simbolo 1
					# los que vienen despues todavia no estan en el diccionario y
					# se marcarian como faltantes sin serlo.
					if not symbols.has(element.key):
						continue

					var symbol_frame: int = instance_frame_index(
						element, symbols[element.key].length, difference)

					# ButtonInstance.hx:73-75, updateButtonState():
					#     _hitbox = getBounds(0, _hitbox, drawMatrix);
					# y getBounds (ButtonInstance.hx:45-51) usa el frame HIT del
					# sub-simbolo, NO el que se esta mostrando. element_bounds()
					# ya hace esa distincion.
					#
					# El hitbox queda en el espacio del stage_item; draw_on() lo
					# pasa a coordenadas LOCALES del nodo al final del dibujo.
					# El source lo guarda en espacio de camara, pero aca conviene
					# local: no se invalida cuando el nodo se mueve, asi que
					# sobrevive al camino barato del backbuffer cache (que no
					# vuelve a pasar por aca).
					if element is AdobeButtonInstance:
						var button: AdobeButtonInstance = element as AdobeButtonInstance
						button.last_hitbox = t * element_bounds(element, difference)
						_button_scratch.push_back(button)

					var next_matrix: AdobeColorMatrix = color_matrix
					if next_matrix == null:
						next_matrix = element.color_matrix
					elif element.color_matrix != null:
						next_matrix = next_matrix.concat(element.color_matrix)

					# SymbolInstance.hx:190-211, draw(): cuando la instancia
					# tiene color propio (isColored), el source concatena su
					# ColorTransform con el heredado y despues:
					#     if (transform.alphaMultiplier <= 0)
					#         return;
					# o sea que ni se mete en la timeline del sub-simbolo. El
					# resultado en pantalla es el mismo -alpha 0 no pinta nada-
					# pero aca ademas evita crear los canvas_item del subarbol
					# y, con blend activo, evita que ese subarbol invisible
					# agrande el screen_rect que dimensiona la copia al
					# backbuffer.
					#
					# El guard va condicionado a element.color_matrix != null
					# para calcar el `if (isColored)` del source: una instancia
					# sin color propio no entra en esa rama ni aunque herede un
					# alpha 0.
					if element.color_matrix != null and next_matrix != null:
						if next_matrix.color_multipliers[3].w <= 0.0:
							continue
					var symbol_rect: Rect2 = draw_symbol(
						symbols[element.key], 
						layer_rid, 
						t * element.transform, 
						symbol_frame, 
						is_clipper or layer.clipping, 
						items, 
						resolve_blend(element.blend_mode, layer_blend), 
						material, 
						next_matrix, 
						screen_rect, 
						screen_transform, 
						additive_material, 
						light_mask, 
						visibility_layer, 
					)

					if layer_blend != AdobeSymbolInstance.AdobeBlendMode.NORMAL:
						screen_rect = screen_rect.merge(symbol_rect)
				elif element is AdobeAtlasSprite:
					var sprite: AdobeAtlasSprite = element as AdobeAtlasSprite

					if layer_blend != AdobeSymbolInstance.AdobeBlendMode.NORMAL:
						var sprite_rect: Rect2 = t * sprite.bounding_box
						screen_rect = screen_rect.merge(sprite_rect)

					draw_atlas_sprite(
						sprite, 
						layer_rid, 
						t, 
					)

		if ( not is_clipper) and layer_parent == parent:
			if rendered:
				if is_instance_valid(material):
					var use_material: bool = layer_blend != AdobeSymbolInstance.AdobeBlendMode.NORMAL
					if not use_material:
						use_material = color_matrix != null
					# GlowFilter: activar material tambien cuando hay glow, aunque
					# no haya blend ni color matrix.
					if not use_material and not layer_glow.is_empty():
						use_material = true
					var used_matrix: AdobeColorMatrix = color_matrix
					if used_matrix == null:
						used_matrix = AdobeColorMatrix.new()

					var used_material: = material
					if use_material:
						if layer_blend == AdobeSymbolInstance.AdobeBlendMode.ADD:
							used_material = additive_material
						elif layer_blend != AdobeSymbolInstance.AdobeBlendMode.NORMAL or not layer_glow.is_empty():
							if Engine.is_editor_hint():


								RenderingServer.canvas_item_set_copy_to_backbuffer(layer_rid, true, Rect2())
							else:
								RenderingServer.canvas_item_set_copy_to_backbuffer(layer_rid, true, screen_transform * screen_rect)
								_backbuffer_scratch.push_back({
									&"rid": layer_rid, 
									&"rect": screen_rect, 
								})

							# GlowFilter: activar canvas group TRANSPARENT y pasar
							# uniforms al shader antes de aplicar el material.
							if not layer_glow.is_empty():
								RenderingServer.canvas_item_set_canvas_group_mode(
									layer_rid,
									RenderingServer.CANVAS_GROUP_MODE_TRANSPARENT)
								var gcolor_raw: String = String(layer_glow.get("color", "#FFFFFF")).trim_prefix("#")
								var gcolor: Color = Color.from_string(gcolor_raw, Color.WHITE)
								RenderingServer.canvas_item_set_instance_shader_parameter(layer_rid, &"glow_enabled", 1)
								RenderingServer.canvas_item_set_instance_shader_parameter(layer_rid, &"glow_color", Vector4(
									gcolor.r, gcolor.g, gcolor.b, float(layer_glow.get("alpha", 1.0)),
								))
								RenderingServer.canvas_item_set_instance_shader_parameter(layer_rid, &"glow_blur", float(layer_glow.get("blur_x", 6.0)))
								RenderingServer.canvas_item_set_instance_shader_parameter(layer_rid, &"glow_strength", float(layer_glow.get("strength", 1.0)))
								RenderingServer.canvas_item_set_instance_shader_parameter(layer_rid, &"glow_inner", 1 if bool(layer_glow.get("inner", false)) else 0)
								RenderingServer.canvas_item_set_instance_shader_parameter(layer_rid, &"glow_knockout", 1 if bool(layer_glow.get("knockout", false)) else 0)

						RenderingServer.canvas_item_set_use_parent_material(layer_rid, false)
						RenderingServer.canvas_item_set_material(layer_rid, used_material.get_rid())
						RenderingServer.canvas_item_set_instance_shader_parameter(layer_rid, &"blend_mode", int(layer_blend))
						RenderingServer.canvas_item_set_instance_shader_parameter(layer_rid, &"color_multipliers", Vector4(
							used_matrix.color_multipliers[0][0], 
							used_matrix.color_multipliers[1][1], 
							used_matrix.color_multipliers[2][2], 
							used_matrix.color_multipliers[3][3], 
						))
						RenderingServer.canvas_item_set_instance_shader_parameter(layer_rid, &"color_offsets", used_matrix.color_offsets)

				to_push.push_front(layer_rid)

	var i: int = items.size() - 1
	for item: RID in to_push:
		items.push_back(item)
		RenderingServer.canvas_item_set_parent(item, parent)
		RenderingServer.canvas_item_set_draw_index(item, i)
		i += 1

	for key: StringName in clip_pushes.keys():
		var array: Array = clip_pushes[key]
		var clip_parent: RID = rids[key]

		i = items.size() - 1
		for item: RID in array:
			items.push_back(item)
			RenderingServer.canvas_item_set_parent(item, clip_parent)
			RenderingServer.canvas_item_set_draw_index(item, i)
			i += 1

	return screen_rect


## getFrameIndex polimorfico: que frame del sub-simbolo muestra una instancia,
## segun su tipo. En el source son tres implementaciones de la misma funcion
## virtual y el despacho lo hace la jerarquia de clases; aca va en una sola
## funcion porque el port tiene un unico AdobeSymbolInstance con un campo
## `type`.
##
##  - GRAPHIC: SymbolInstance.getFrameIndex (SymbolInstance.hx:100-140).
##  - BUTTON:  ButtonInstance.hx:53-56 -> min(curButtonState, frameCount - 1).
##             El estado UP/OVER/DOWN se mapea directo a los frames 0/1/2 del
##             sub-simbolo; HIT (3) se usa solo para el hitbox, no para dibujar.
##  - MOVIE_CLIP: MovieClipInstance.hx:220-223 -> literal 0 con swfMode
##             apagado (= movie_clips_play), o el de SymbolInstance con
##             swfMode prendido.
##
## Se extrajo de draw_symbol() porque symbol_bounds() necesita exactamente el
## mismo despacho: en el source los bounds tambien pasan por getFrameIndex.
func instance_frame_index(
	element: AdobeSymbolInstance, symbol_length: int, difference: int
) -> int:
	match element.type:
		AdobeSymbolInstance.AdobeSymbolType.BUTTON:
			var button: AdobeButtonInstance = element as AdobeButtonInstance
			return button.button_frame_index(symbol_length)

		AdobeSymbolInstance.AdobeSymbolType.MOVIE_CLIP:
			if not movie_clips_play:
				return 0

			return symbol_instance_frame(element, symbol_length, difference)

	# GRAPHIC y cualquier cosa no reconocida: el source cae en SymbolInstance
	# por default (Frame.hx:225-231).
	return symbol_instance_frame(element, symbol_length, difference)


## Bounds de un simbolo EN UN FRAME dado, en el espacio de `t`.
##
## Port de Timeline.getBounds - maru/src/animate/internal/Timeline.hx:244-290.
## Recorre las capas visibles, saca el keyframe activo de cada una, pide sus
## bounds y los une; al final aplica la matriz.
##
## OJO, no confundir con AdobeSymbol.bounding_box, que ya existia: ese es el
## equivalente de getWholeBounds (Timeline.hx:203), la union sobre TODOS los
## frames. Este es por frame.
##
## Lo que todavia NO esta porteado de esa funcion, porque depende de otros
## archivos: el cache de bounds por frame (`useCachedBounds`, F7) y los bounds
## expandidos por filtros (`includeFilters`, F13). Los dos flags del source se
## comportan aca como si fueran false y true respectivamente.
func symbol_bounds(
	target: AdobeSymbol, frame: int, 
	t: Transform2D = Transform2D.IDENTITY, 
	include_hidden_layers: bool = false
) -> Rect2:
	var rect: Rect2 = Rect2()
	var first: bool = true

	for layer: AdobeLayer in target.layers:
		if layer.hidden and not include_hidden_layers:
			continue

		var layer_frame: AdobeLayerFrame = layer.get_frame_at_index(frame)
		if layer_frame == null or layer_frame.elements.is_empty():
			continue

		var bounds: Rect2 = frame_bounds(
			layer_frame, frame - layer_frame.starting_index, target, layer)
		if bounds.size == Vector2.ZERO:
			continue

		if first:
			first = false
			rect = bounds
		else:
			rect = rect.merge(bounds)

	# applyMatrixToRect (Timeline.hx:292-341) sobre un rect vacio devuelve un
	# punto en (m.tx, m.ty); `t * Rect2()` de Godot da exactamente eso.
	return t * rect


## Port de Layer.getFrameAtIndex - Layer.hx. El source usa un array
## `frameIndices` precalculado; aca se escanea, que es lo que ya hacia
## draw_symbol().
func layer_frame_at_index(layer: AdobeLayer, frame: int) -> AdobeLayerFrame:
	frame = maxi(frame, 0)
	for layer_frame: AdobeLayerFrame in layer.frames:
		if frame < layer_frame.starting_index:
			continue
		if frame > layer_frame.starting_index + layer_frame.duration - 1:
			continue

		return layer_frame

	return null


## Port de Frame.getBounds - Frame.hx:165-196.
##
## OJO: el source NO chequea element.visible aca. El flag solo se mira en el
## loop de dibujo (Frame.hx:423-426); para bounds entran todos los elementos.
func frame_bounds(
	layer_frame: AdobeLayerFrame, difference: int, 
	owner: AdobeSymbol, layer: AdobeLayer
) -> Rect2:
	if layer_frame.elements.is_empty():
		return Rect2()

	var rect: Rect2 = element_bounds(layer_frame.elements[0], difference)
	for i in range(1, layer_frame.elements.size()):
		rect = rect.merge(element_bounds(layer_frame.elements[i], difference))

	# Frame.hx:186-192: una capa clipeada recorta sus bounds contra los de su
	# clipper. El source llega al clipper por layer.parentLayer; aca la capa
	# guarda el NOMBRE (clipped_by) y se busca en el mismo simbolo.
	if layer.parent_layer != null:
		var masker_frame: AdobeLayerFrame = layer.parent_layer.get_frame_at_index(
			difference + layer_frame.starting_index)
		var masker: Rect2 = Rect2()
		if masker_frame != null:
			masker = frame_bounds(
				masker_frame, 
				difference + layer_frame.starting_index - masker_frame.starting_index, 
				owner, 
				layer.parent_layer
			)
		rect = mask_bounds(rect, masker)

	return rect


## Bounds de un elemento suelto. Los AdobeAtlasSprite ya los tienen cacheados
## (AtlasInstance.getBounds, F2); una instancia de simbolo recursiona
## (SymbolInstance.hx:163-185), y un boton usa el frame HIT en vez del que
## dibuja (ButtonInstance.hx:45-51).
func element_bounds(element: AdobeDrawable, difference: int) -> Rect2:
	if element is not AdobeSymbolInstance:
		return element.bounding_box

	var instance: AdobeSymbolInstance = element as AdobeSymbolInstance
	if not symbols.has(instance.key):
		# SymbolInstance.hx:57-58: sin libraryItem la instancia queda invisible;
		# el source reventaria al pedirle bounds, aca no aporta nada.
		return Rect2()

	var sub: AdobeSymbol = symbols[instance.key]
	var sub_frame: int
	if instance is AdobeButtonInstance:
		# ButtonInstance.hx:47: boundsIndex = min(ButtonState.HIT, frameCount - 1).
		# El hitbox del boton es el frame HIT, no el que se esta mostrando.
		sub_frame = mini(AdobeButtonInstance.ButtonState.HIT, maxi(sub.length - 1, 0))
	else:
		sub_frame = instance_frame_index(instance, sub.length, difference)

	return symbol_bounds(sub, sub_frame, instance.transform)


## Port de Timeline.maskBounds - Timeline.hx. Interseca, y si el masker esta
## vacio devuelve el rect sin tocar (NO lo anula).
func mask_bounds(masked: Rect2, masker: Rect2) -> Rect2:
	if masker.size.x <= 0.0 or masker.size.y <= 0.0:
		return masked

	var x1: float = maxf(masked.position.x, masker.position.x)
	var y1: float = maxf(masked.position.y, masker.position.y)
	var x2: float = minf(masked.end.x, masker.end.x)
	var y2: float = minf(masked.end.y, masker.end.y)

	if x2 <= x1 or y2 <= y1:
		return Rect2()

	return Rect2(x1, y1, x2 - x1, y2 - y1)


## Que blend gana cuando una instancia con blend propio esta adentro de otra
## que tambien tiene blend. Port de Blend.resolve -
## maru/src/animate/internal/filters/Blend.hx:
##
##     public static function resolve(?blend:BlendMode, ?drawBlend:BlendMode):Null<BlendMode>
##     {
##         if (Frame.__isDirtyCall) return NORMAL;
##         if (blend == null || blend == NORMAL) return drawBlend;
##         return blend;
##     }
##
## O sea: gana el PROPIO, salvo que el propio sea NORMAL, en cuyo caso se
## hereda el de arriba. SymbolInstance.hx:213 lo llama asi:
##     var b = Blend.resolve(this.blend, blend);
##
## El port tenia la precedencia al reves - se quedaba con el heredado salvo
## que el heredado fuera NORMAL - asi que una instancia MULTIPLY adentro de
## una SCREEN se dibujaba en SCREEN cuando el motor la dibuja en MULTIPLY.
##
## La rama `Frame.__isDirtyCall -> NORMAL` es del sistema de baking de
## keyframes, que el port no tiene todavia (F5).
func resolve_blend(
	own: AdobeSymbolInstance.AdobeBlendMode, 
	inherited: AdobeSymbolInstance.AdobeBlendMode
) -> AdobeSymbolInstance.AdobeBlendMode:
	if own == AdobeSymbolInstance.AdobeBlendMode.NORMAL:
		return inherited

	return own


func draw_atlas_sprite(sprite: AdobeAtlasSprite, parent: RID, t: Transform2D) -> void :
	# AtlasInstance.hx:98-99: `if (frame == null || frame.frame == null)
	# return;`. El equivalente del port: el sprite no tiene textura (nombre
	# que no esta en el spritemap) o su region es de area cero. Sin esto,
	# sprite.texture.get_rid() reventaba con "Cannot call method 'get_rid'
	# on a null value" en cada frame, por cada elemento roto.
	if sprite.texture == null or sprite.region.size.x <= 0 or sprite.region.size.y <= 0:
		return

	# AtlasInstance.hx:101-103:
	#     _mat.copyFrom(tileMatrix); _mat.concat(matrix); _mat.concat(parentMatrix);
	# En convencion de columnas (Godot) eso es parent * matrix * tile.
	var transform: Transform2D = t * sprite.transform * sprite.tile_matrix

	RenderingServer.canvas_item_add_set_transform(parent, transform)
	RenderingServer.canvas_item_add_texture_rect_region(
		parent, 
		Rect2(Vector2.ZERO, Vector2(sprite.region.size)), 
		sprite.texture.get_rid(), 
		Rect2(sprite.region), 
		Color.WHITE, 
		false, 
		clip_texture_uvs
	)


func load_spritemaps() -> void :
	var files: PackedStringArray = ResourceLoader.list_directory(folder_path.get_base_dir())
	for file: String in files:
		if not file.begins_with("spritemap"):
			continue
		if not file.get_extension() == "json":
			continue

		load_spritemap(file)


func load_spritemap(spritemap_name: String) -> void :
	var base_dir: String = folder_path.get_base_dir()
	var raw_json: String = FileAccess.get_file_as_string("%s/%s" % [base_dir, spritemap_name])
	var json: Variant = JSON.parse_string(raw_json)
	if json == null:
		push_error("[GDAnimate] " + "Failed to parse %s/%s as JSON!" % [base_dir, spritemap_name])
		return

	var texture: Texture2D = load("%s/%s.png" % [base_dir, spritemap_name.get_basename()])
	if not is_instance_valid(texture):
		push_error("[GDAnimate] " + "Failed to load %s/%s.png as Texture2D!" % [base_dir, spritemap_name.get_basename()])
		return

	var data: Dictionary = json as Dictionary
	if not data.has("ATLAS"):
		push_error("[GDAnimate] " + "Malformed spritemap json has no ATLAS property!")
		return
	data = data.get("ATLAS")

	var image: Image = null
	var sprites: Array = data.get("SPRITES", [])
	for sprite: Dictionary in sprites:
		var sprite_data: Dictionary = sprite.get("SPRITE", {})
		var atlas_sprite: AdobeAtlasSprite = AdobeAtlasSprite.new()
		atlas_sprite.region = Rect2i(
			Vector2i(
				int(sprite_data.get("x", 0.0)), 
				int(sprite_data.get("y", 0.0))
			), 
			Vector2i(
				int(sprite_data.get("w", 0.0)), 
				int(sprite_data.get("h", 0.0))
			)
		)
		atlas_sprite.rotated = sprite_data.get("rotated", false)
		atlas_sprite.texture = texture

		spritemap.set(StringName(sprite_data.get("name", "")), atlas_sprite)


func load_animation() -> void :
	var base_dir: String = folder_path.get_base_dir()
	var raw_json: String = FileAccess.get_file_as_string("%s/Animation.json" % [base_dir])
	var json: Variant = JSON.parse_string(raw_json)
	if json == null:
		push_error("[GDAnimate] " + "Failed to parse %s/Animation.json as JSON!" % [base_dir])
		return

	var data: Dictionary = json as Dictionary
	var optimized: bool = data.has("AN")

	if ResourceLoader.exists("%s/metadata.json" % [base_dir]):
		var raw_meta: String = FileAccess.get_file_as_string("%s/metadata.json" % [base_dir])
		var json_meta: Variant = JSON.parse_string(raw_meta)
		if json_meta == null:
			push_error("[GDAnimate] " + "Failed to parse %s/metadata.json as JSON!" % [base_dir])
			return

		var meta: Dictionary = json_meta as Dictionary
		framerate = meta.get("framerate", meta.get("FRT", 24))
		_parse_stage_metadata(meta)
	else:
		# MetadataJson, FlxAnimateJson.hx:625-644. El bloque puede faltar
		# entero (atlas sin metadata inline y sin metadata.json); antes eso
		# dejaba `meta` en null y framerate tomaba null. El default de 24 es
		# el mismo que ya usa la rama de metadata.json de arriba.
		var raw_meta: Variant = get_pair(optimized, data, "metadata", "MD")
		var meta: Dictionary = raw_meta if raw_meta is Dictionary else {}
		var raw_framerate: Variant = get_pair(optimized, meta, "framerate", "FRT")
		framerate = float(raw_framerate) if raw_framerate != null else 24.0
		_parse_stage_metadata(meta)

	if has_pair(optimized, data, "SYMBOL_DICTIONARY", "SD"):
		var symbol_dict: Dictionary = get_pair(optimized, data, "SYMBOL_DICTIONARY", "SD")
		var symbol_array: Array = get_pair(optimized, symbol_dict, "Symbols", "S")
		load_symbols(optimized, symbol_array)
	elif DirAccess.dir_exists_absolute("%s/LIBRARY" % [base_dir]):
		var dir: DirAccess = DirAccess.open("%s/LIBRARY" % [base_dir])
		if dir == null:
			push_error("[GDAnimate] " + "Failed to open %s/LIBRARY directory!" % [base_dir])
			return

		load_symbol_directory(optimized, dir)

	var anim: Dictionary = get_pair(optimized, data, "ANIMATION", "AN")
	stage_symbol = get_pair(optimized, anim, "SYMBOL_name", "SN")
	load_symbol(optimized, anim)

	if has_pair(optimized, anim, "StageInstance", "STI"):
		var stage: Dictionary = get_pair(optimized, anim, "StageInstance", "STI")
		var instance: Dictionary = get_pair(optimized, stage, "SYMBOL_Instance", "SI")

		stage_transform = resolve_matrix(instance)
	else:
		stage_transform = Transform2D.IDENTITY


func load_symbol_directory(optimized: bool, dir: DirAccess, folder: String = "") -> void :
	if dir == null:
		return

	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if dir.current_is_dir() and name != "." and name != "..":
			load_symbol_directory(optimized, DirAccess.open(dir.get_current_dir() + "/" + name), folder + name + "/")
		elif name.get_extension() == "json":
			var raw: String = FileAccess.get_file_as_string(dir.get_current_dir() + "/" + name)
			var json: Variant = JSON.parse_string(raw)
			if json == null:
				push_error("[GDAnimate] " + "Failed to parse %s as JSON!" % [folder + name])
				return

			var symbol_name: String = folder + name.get_file().get_basename()
			symbols[StringName(symbol_name)] = load_layers(
				optimized, 
				get_pair(optimized, json as Dictionary, "LAYERS", "L")
			)

		name = dir.get_next()


func load_symbols(optimized: bool, symbol_array: Array) -> void :
	for symbol: Dictionary in symbol_array:
		load_symbol(optimized, symbol)


func load_symbol(optimized: bool, symbol: Dictionary) -> void :
	var key: String = get_pair(optimized, symbol, "SYMBOL_name", "SN")
	var timeline: Dictionary = get_pair(optimized, symbol, "TIMELINE", "TL")
	if has_pair(optimized, timeline, "LAYERS", "L"):
		var gd_symbol: AdobeSymbol = load_layers(optimized, 
			get_pair(optimized, timeline, "LAYERS", "L"))
		symbols[StringName(key)] = gd_symbol


func load_layers(optimized: bool, layers: Array) -> AdobeSymbol:
	# Port fiel de Layer.hx:130-198. Diferencias con el port viejo:
	#   - Precedencia Clpb > LT (Layer.hx:141-164): si Clpb esta presente la
	#     capa es CLIPPED y el LT no se mira.
	#   - FOLDER no parsea frames (Layer.hx:181-193).
	#   - frame_indices se rellena con un slot por frame de duracion de cada
	#     keyframe (Layer.hx:186-188).
	#   - parent_layer es una referencia directa al clipper, no el nombre.
	var gd_symbol: AdobeSymbol = AdobeSymbol.new()

	for layer: Dictionary in layers:
		var gd_layer: AdobeLayer = AdobeLayer.new()
		gd_layer.name = get_pair(optimized, layer, "Layer_name", "LN")

		var clipped_by: String = ""
		if has_pair(optimized, layer, "Clipped_by", "Clpb"):
			clipped_by = get_pair(optimized, layer, "Clipped_by", "Clpb")

		if not clipped_by.is_empty():
			# CLIPPED (Layer.hx:141-166): busca hacia arriba el clipper que la
			# referencia. Si no lo encuentra, la capa queda invisible pero
			# mantiene layer_type CLIPPED y clipped_by intacto (source no los
			# limpia).
			gd_layer.layer_type = AdobeLayer.LayerType.CLIPPED
			gd_layer.clipped_by = clipped_by

			var found: AdobeLayer = null
			for i in range(gd_symbol.layers.size() - 1, -1, -1):
				var existing: AdobeLayer = gd_symbol.layers[i]
				if existing.name == clipped_by and existing.layer_type == AdobeLayer.LayerType.CLIPPER:
					found = existing
					break

			if found != null:
				gd_layer.parent_layer = found
			else:
				gd_layer.hidden = true
		else:
			# Layer.hx:167-176: switch por LT.
			if has_pair(optimized, layer, "Layer_type", "LT"):
				var lt: String = get_pair(optimized, layer, "Layer_type", "LT")
				match lt:
					"Clp", "Clipper":
						gd_layer.layer_type = AdobeLayer.LayerType.CLIPPER
					"Fld", "Folder":
						gd_layer.layer_type = AdobeLayer.LayerType.FOLDER
					_:
						gd_layer.layer_type = AdobeLayer.LayerType.NORMAL

		# Compat: mantener `clipping` sincronizado para caches viejos.
		gd_layer.clipping = gd_layer.layer_type == AdobeLayer.LayerType.CLIPPER

		# Layer.hx:181-193: FOLDER no parsea frames.
		var duration: int = 0
		if gd_layer.layer_type != AdobeLayer.LayerType.FOLDER:
			if has_pair(optimized, layer, "Frames", "FR"):
				var frames: Array = get_pair(optimized, layer, "Frames", "FR")
				for frame_idx in frames.size():
					gd_layer.frames.push_back(load_frame(optimized, frames[frame_idx]))
					var last: AdobeLayerFrame = gd_layer.frames[gd_layer.frames.size() - 1]
					duration += last.duration
					# Layer.hx:186-188: un slot por frame de duracion.
					for _j in last.duration:
						gd_layer.frame_indices.append(frame_idx)

		if gd_symbol.length < duration:
			gd_symbol.length = duration

		gd_symbol.layers.push_back(gd_layer)

	return gd_symbol


func load_frame(optimized: bool, frame: Dictionary) -> AdobeLayerFrame:
	var gd_frame: AdobeLayerFrame = AdobeLayerFrame.new()
	# Defaults del ctor de Frame (Frame.hx:49-53): index 0, duration 1. El
	# port los tomaba directo del JSON sin chequear null, asi que un keyframe
	# sin I o sin DU -que no aparece en exports reales pero si en JSON a
	# mano- reventaba al asignar Nil a un int tipado.
	var raw_index: Variant = get_pair(optimized, frame, "index", "I")
	gd_frame.starting_index = int(raw_index) if raw_index != null else 0
	var raw_duration: Variant = get_pair(optimized, frame, "duration", "DU")
	gd_frame.duration = int(raw_duration) if raw_duration != null else 1

	# cne-flixel-animate/src/animate/internal/Frame.hx:216:
	#   this.name = frame.N ?? "";
	# El label puede faltar (los keyframes sin label no traen la key en el
	# JSON), por eso el null check antes de convertir. Coincide con el ?? ""
	# del engine real.
	var raw_label: Variant = get_pair(optimized, frame, "name", "N")
	if raw_label != null:
		gd_frame.frame_label = String(raw_label)

	# FrameJson.B (FlxAnimateJson.hx:135-138) -> Frame.hx:214
	# `this.blend = frame.B`. Blend a nivel KEYFRAME, que despues Frame.draw
	# resuelve contra el heredado. No estaba porteado.
	if has_pair(optimized, frame, "blend", "B"):
		gd_frame.blend_mode = get_pair(optimized, frame, "blend", "B") as AdobeSymbolInstance.AdobeBlendMode

	# Despacho de elementos, port de Frame.hx:216-249 (maru dcaa33c): se
	# prueba SI, despues ASI, despues TFI, y si no es ninguno el elemento se
	# IGNORA (el source no hace push de nada en ese caso).
	#
	# Antes el else caia siempre en load_atlas_sprite, asi que un elemento
	# TFI (campo de texto) o cualquier tipo futuro entraba ahi con
	# get_pair() devolviendo null y reventaba al reasignar `element`.
	#
	# El `E` puede faltar directamente: el source lo chequea (`var e =
	# frame.E; if (e != null)`) antes de iterar. Un keyframe vacio - comun
	# en capas guia o en huecos de la timeline - no trae la key.
	var elements: Variant = get_pair(optimized, frame, "elements", "E")
	if elements is Array:
		for element: Dictionary in elements:
			if has_pair(optimized, element, "SYMBOL_Instance", "SI"):
				gd_frame.elements.push_back(load_symbol_instance(optimized, element))
			elif has_pair(optimized, element, "ATLAS_SPRITE_instance", "ASI"):
				gd_frame.elements.push_back(load_atlas_sprite(optimized, element))
			elif has_pair(optimized, element, "textFIELD_Instance", "TFI"):
				# TextFieldInstance no esta porteado todavia (F12 del plan de
				# fidelidad). El source crea uno aca; el port lo saltea en vez
				# de dibujar basura. Sin warning a proposito: seria uno por
				# elemento y por frame.
				pass

	return gd_frame


## Que frame del sub-simbolo muestra una instancia, `difference` frames despues del
## keyframe que la contiene.
##
## Transcripcion literal de SymbolInstance.getFrameIndex -
## MaybeMaru/flixel-animate@dcaa33c src/animate/internal/elements/SymbolInstance.hx:100-140.
## La firma del source es getFrameIndex(index, frameIndex = 0), donde index es el frame
## absoluto de la timeline padre y frameIndex el indice del keyframe que contiene a la
## instancia; la primera linea hace `frameIndex = firstFrame + (index - frameIndex)`, o
## sea que lo unico que importa de los dos es la resta - el `difference` de aca.
##
## Antes esto era una reimplementacion a mano equivalente en 5 de los 6 casos, pero
## DISTINTA en el sexto: LOOP con first_frame > 0 y sin last_frame. El source hace
## `FlxMath.wrap(frameIndex, 0, lastIndex)`, o sea que al pasarse del final vuelve al
## frame 0 del sub-simbolo; la version vieja envolvia dentro de [first_frame, final] y
## volvia a first_frame. Con FF=7 en un simbolo de 10 frames el source da
## 7,8,9,0,1,2,... y la version vieja daba 7,8,9,7,8,9. En los assets del mod
## holyquintet ese caso aparece 5736 veces repartido en 24 Animation.json, los
## personajes principales incluidos.
func symbol_instance_frame(
	element: AdobeSymbolInstance, length: int, difference: int
) -> int:
	if length <= 0:
		return 0

	var first_frame: int = element.first_frame
	var last_frame: int = element.last_frame
	var frame_index: int = first_frame + difference

	var last_index: int = length - 1
	var has_last_frame: bool = last_frame > - 1
	var do_wrap: bool = has_last_frame and last_frame < first_frame

	# El source llama `length` a esta variable local, que NO es el largo del
	# sub-simbolo (eso es lastIndex + 1) sino el tramo que va de first_frame
	# hasta el final efectivo. Se renombra a span para no pisar el parametro.
	var span: int
	if do_wrap:
		span = last_index
	elif has_last_frame:
		span = mini(last_frame, last_index)
	else:
		span = last_index
	span = span - first_frame + 1

	# `totalLength` del source: cuando la ventana se pasa del final y sigue
	# desde 0, el largo total es la cola mas la cabeza.
	var total_span: int = span + (last_frame + 1) if do_wrap else span

	match element.loop_mode:
		AdobeSymbolInstance.AdobeSymbolLoopMode.LOOP:
			if do_wrap:
				if total_span <= 0:
					return first_frame
				# ((x % t) + t) % t del source = posmod.
				frame_index = posmod(frame_index - first_frame, total_span)
			else:
				if has_last_frame:
					return _flx_wrap(frame_index, first_frame, mini(last_frame, last_index))
				return _flx_wrap(frame_index, 0, last_index)

		AdobeSymbolInstance.AdobeSymbolLoopMode.ONE_SHOT:
			frame_index = mini(frame_index - first_frame, total_span - 1)

		AdobeSymbolInstance.AdobeSymbolLoopMode.FREEZE_FRAME:
			return first_frame

	if frame_index < span:
		return first_frame + frame_index

	if do_wrap:
		return frame_index - span

	# Rama inalcanzable con los tres loop types actuales (LOOP y FREEZE_FRAME
	# ya devolvieron, y ONE_SHOT deja frame_index <= total_span - 1 < span
	# cuando no hay wrap). Se portea igual para no cambiar el codigo si
	# upstream agrega un modo.
	return - 1 + (frame_index - span)


## Port de FlxMath.wrap - flixel 6.2.0, flixel/math/FlxMath.hx:
##     var range = max - min + 1;
##     if (value < min) value += range * Std.int((min - value) / range + 1);
##     return min + (value - min) % range;
## `max` es INCLUSIVO, al reves que wrapi() de Godot, que lo trata como
## exclusivo. Se transcribe en vez de usar wrapi(v, min, max + 1) para que
## la equivalencia no dependa de como Godot maneje los negativos.
func _flx_wrap(value: int, min_value: int, max_value: int) -> int:
	var range: int = max_value - min_value + 1
	if range <= 0:
		return min_value

	if value < min_value:
		@warning_ignore("integer_division")
		value += range * int(float(min_value - value) / float(range) + 1.0)

	return min_value + (value - min_value) % range


func load_symbol_instance(optimized: bool, element: Dictionary) -> AdobeSymbolInstance:
	element = get_pair(optimized, element, "SYMBOL_Instance", "SI")

	# cne-flixel-animate/src/animate/internal/Frame.hx:_loadJson crea la
	# instancia segun si.ST: "B"/"button" -> ButtonInstance,
	# "MC"/"movieclip" -> MovieClipInstance, resto -> SymbolInstance
	# (ver SymbolInstance.hx + ButtonInstance.hx:33 this.elementType = BUTTON).
	# En el port todo cuelga de AdobeSymbolInstance, pero el tipo BUTTON
	# necesita su propia clase (AdobeButtonInstance) para la logica de
	# estado + frame index por estado.
	var raw_type: String = get_pair(optimized, element, "symbolType", "ST")
	var is_button: bool = raw_type == "B" or raw_type == "button"
	var symbol_instance: AdobeSymbolInstance
	if is_button:
		symbol_instance = AdobeButtonInstance.new()
	else:
		symbol_instance = AdobeSymbolInstance.new()

	var key: String = get_pair(optimized, element, "SYMBOL_name", "SN")
	symbol_instance.key = StringName(key)
	if has_pair(optimized, element, "firstFrame", "FF"):
		symbol_instance.first_frame = get_pair(optimized, element, "firstFrame", "FF")
	else:
		symbol_instance.first_frame = 0

	if has_pair(optimized, element, "lastFrame", "LF"):
		symbol_instance.last_frame = get_pair(optimized, element, "lastFrame", "LF")
	else:
		symbol_instance.last_frame = -1

	symbol_instance.transform = resolve_matrix(element)

	# Blend de la instancia, port de SymbolInstanceJson.get_B -
	# maru/src/animate/FlxAnimateJson.hx:222-240. Primero B/blend (lo que
	# escribe BetterTextureAtlas); si no esta, el metodo LEGACY: el blend
	# venia codificado en el NOMBRE de instancia (IN), como "algo_bl9_loque"
	# -> indice 9. Ese fallback no estaba porteado, asi que cualquier atlas
	# viejo exportado con esa convencion se dibujaba en NORMAL.
	if has_pair(optimized, element, "blend", "B"):
		symbol_instance.blend_mode = get_pair(optimized, element, "blend", "B") as AdobeSymbolInstance.AdobeBlendMode
	else:
		var instance_name: Variant = element.get("IN")
		if instance_name is String:
			var raw_name: String = instance_name
			if not raw_name.is_empty() and raw_name.contains("_bl"):
				# Mismo troceo que el source: split("_bl")[1].split("_")[0].
				var tail: String = raw_name.split("_bl")[1].split("_")[0]
				# Std.parseInt de Haxe parsea los digitos de adelante y
				# devuelve null si no hay ninguno; String.to_int() de GDScript
				# hace lo primero pero devuelve 0 (= ADD) en vez de null, asi
				# que el digito inicial se chequea a mano.
				if not tail.is_empty() and tail[0] >= "0" and tail[0] <= "9":
					symbol_instance.blend_mode = tail.to_int() as AdobeSymbolInstance.AdobeBlendMode

	if has_pair(optimized, element, "color", "C"):
		symbol_instance.color_matrix = AdobeColorMatrix.parse(optimized, get_pair(optimized, element, "color", "C"))

	if has_pair(optimized, element, "loop", "LP"):
		var loop_mode: String = get_pair(optimized, element, "loop", "LP")
		# cne-flixel-animate/src/animate/internal/elements/SymbolInstance.hx:49-54:
		# el motor real solo distingue "PO"/"playonce" (ONE_SHOT) y
		# "SF"/"singleframe" (FREEZE_FRAME) explicitamente; CUALQUIER otro
		# valor -incluido "LP" y cualquier variante no reconocida como
		# "POR"/"REV"- cae en LOOP por default (`default: LoopType.LOOP`).
		# No existe un modo reverse en el engine que usa el mod: los valores
		# POR/REV que este parser aceptaba antes eran inventados, no venian
		# de ningun Animation.json real ni tenian soporte en FlxAnimate.
		if optimized:
			match loop_mode:
				"PO":
					symbol_instance.loop_mode = AdobeSymbolInstance.AdobeSymbolLoopMode.ONE_SHOT
				"SF":
					symbol_instance.loop_mode = AdobeSymbolInstance.AdobeSymbolLoopMode.FREEZE_FRAME
				_:
					symbol_instance.loop_mode = AdobeSymbolInstance.AdobeSymbolLoopMode.LOOP
		else:
			match loop_mode:
				"playonce":
					symbol_instance.loop_mode = AdobeSymbolInstance.AdobeSymbolLoopMode.ONE_SHOT
				"singleframe":
					symbol_instance.loop_mode = AdobeSymbolInstance.AdobeSymbolLoopMode.FREEZE_FRAME
				_:
					symbol_instance.loop_mode = AdobeSymbolInstance.AdobeSymbolLoopMode.LOOP
	else:
		symbol_instance.loop_mode = AdobeSymbolInstance.AdobeSymbolLoopMode.LOOP

	# El tipo ya se leyo arriba (raw_type) para decidir la clase; aca se
	# normaliza al enum. Orden de deteccion: BUTTON > MOVIE_CLIP > GRAPHIC.
	if optimized:
		if raw_type == "B":
			symbol_instance.type = AdobeSymbolInstance.AdobeSymbolType.BUTTON
		elif raw_type == "MC":
			symbol_instance.type = AdobeSymbolInstance.AdobeSymbolType.MOVIE_CLIP
		else:
			symbol_instance.type = AdobeSymbolInstance.AdobeSymbolType.GRAPHIC
	else:
		if raw_type == "button":
			symbol_instance.type = AdobeSymbolInstance.AdobeSymbolType.BUTTON
		elif raw_type == "movieclip":
			symbol_instance.type = AdobeSymbolInstance.AdobeSymbolType.MOVIE_CLIP
		else:
			symbol_instance.type = AdobeSymbolInstance.AdobeSymbolType.GRAPHIC

	return symbol_instance


func load_atlas_sprite(optimized: bool, element: Dictionary) -> AdobeAtlasSprite:
	element = get_pair(optimized, element, "ATLAS_SPRITE_instance", "ASI")

	var key_raw: String = get_pair(optimized, element, "name", "N")
	var key: StringName = StringName(key_raw)

	# AtlasInstance.hx:43-48 (maru dcaa33c):
	#     this.frame = parent.getByName(data.N);
	#     this.sourceFrame = this.frame;
	#     this.matrix = data.MX.toMatrix();
	# getByName devuelve null si el sprite no esta, pero la MATRIZ se asigna
	# igual - el elemento existe, solo que sin frame que dibujar (draw() lo
	# saltea, AtlasInstance.hx:98-99). El port devolvia un AdobeAtlasSprite
	# recien creado y perdia la matriz, asi que si alguna vez ese sprite se
	# llena a mano (replace_frame) aparecia en el origen.
	var sprite: AdobeAtlasSprite
	if spritemap.has(key):
		sprite = spritemap[key].duplicate()
	else:
		sprite = AdobeAtlasSprite.new()

	sprite.transform = resolve_matrix(element)
	return sprite


## Saca la transform de un elemento del JSON (symbol instance, atlas sprite
## o stage instance), probando las mismas fuentes y en el mismo orden que
## MatrixJson.resolve - maru/src/animate/FlxAnimateJson.hx:717-747:
##
##     var mat2D = input.MX ?? input.Matrix;        -> si esta, esa
##     var m3d   = input.M3D ?? input.Matrix3D;     -> si esta, from3Dto2D
##     var pos   = input.POS ?? input.Position;     -> [1,0,0,1,pos.x,pos.y]
##     return [1, 0, 0, 1, 0, 0];                   -> identidad
##
## Los tres call sites del parser resolvian esto a mano y ninguno tenia el
## tercer paso: POS/Position es como el texture atlas legacy de Adobe
## Animate 2018 guarda la posicion de un elemento cuando no hay matriz.
## Sin ese fallback, cada elemento de un atlas 2018 caia en identidad y se
## amontonaba todo en el origen.
func resolve_matrix(element: Dictionary) -> Transform2D:
	var mat_2d: Variant = element.get("MX")
	if mat_2d == null:
		mat_2d = element.get("Matrix")
	if mat_2d != null:
		return parse_matrix(mat_2d)

	var mat_3d: Variant = element.get("M3D")
	if mat_3d == null:
		mat_3d = element.get("Matrix3D")
	if mat_3d != null:
		return parse_matrix(mat_3d)

	var pos: Variant = element.get("POS")
	if pos == null:
		pos = element.get("Position")
	if pos is Dictionary:
		var p: Dictionary = pos
		return Transform2D(
			Vector2(1.0, 0.0), 
			Vector2(0.0, 1.0), 
			Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
		)

	return Transform2D.IDENTITY


func parse_matrix(matrix: Variant) -> Transform2D:
	if matrix == null:
		return Transform2D.IDENTITY

	# M3D escrito como objeto (m00..m33) en vez de array. Se arma el array
	# de 16 y se pasa por la MISMA reduccion 3D->2D que la forma array, en
	# vez de leer solo las 6 celdas utiles: asi el chequeo de perspectiva
	# (que mira m03/m13/m23/m33) tambien corre para esta forma.
	if matrix is Dictionary:
		var d: Dictionary = matrix
		var flat: Array = []
		for row: int in 4:
			for col: int in 4:
				var key: String = "m%d%d" % [row, col]
				flat.push_back(float(d.get(key, 1.0 if row == col else 0.0)))
		return _matrix_3d_to_2d(flat)

	if matrix is not Array:
		return Transform2D.IDENTITY

	var arr: Array = matrix
	if arr.size() == 6:
		return Transform2D(
			Vector2(arr[0], arr[1]), 
			Vector2(arr[2], arr[3]), 
			Vector2(arr[4], arr[5])
		)

	if arr.size() < 16:
		return Transform2D.IDENTITY

	return _matrix_3d_to_2d(arr)


## Port de MatrixJson.from3Dto2D - maru/src/animate/FlxAnimateJson.hx:749-776.
##
## El camino comun (sin perspectiva) es el mismo aplanado de siempre: se
## toman a,b,c,d,tx,ty de los indices 0,1,4,5,12,13 y se tira el resto. El
## camino con perspectiva - que el port no tenia - se activa cuando
## m03/m13/m23 no son 0 o m33 no es 1, y en vez de aplanar proyecta tres
## puntos (0,0) (1,0) (0,1) por la matriz 4x4 y reconstruye la afin 2x3 a
## partir de las diferencias. Adobe escribe estas matrices cuando el
## simbolo tiene rotacion 3D en la timeline.
##
## OJO con la formula: en el source el `/ z` se aplica SOLO a mat3D[12] y
## mat3D[13], no al paren entero (`mat3D[0]*x + mat3D[4]*y + mat3D[12]/z`).
## Leido literal parece un bug de precedencia upstream, pero se portea tal
## cual: la idea es que gdanimate dibuje lo mismo que flixel-animate, bug
## incluido. Si upstream lo corrige, aca hay que corregirlo igual.
func _matrix_3d_to_2d(m: Array) -> Transform2D:
	var has_perspective: bool = (
		float(m[3]) != 0.0
		or float(m[7]) != 0.0
		or float(m[11]) != 0.0
		or float(m[15]) != 1.0
	)

	if not has_perspective:
		return Transform2D(
			Vector2(m[0], m[1]), 
			Vector2(m[4], m[5]), 
			Vector2(m[12], m[13])
		)

	var points: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0)]
	var transformed: Array[Vector2] = []
	for point: Vector2 in points:
		var z: float = float(m[3]) * point.x + float(m[7]) * point.y + float(m[15])
		transformed.push_back(Vector2(
			float(m[0]) * point.x + float(m[4]) * point.y + float(m[12]) / z, 
			float(m[1]) * point.x + float(m[5]) * point.y + float(m[13]) / z
		))

	var p0: Vector2 = transformed[0]
	var p1: Vector2 = transformed[1]
	var p2: Vector2 = transformed[2]
	return Transform2D(p1 - p0, p2 - p0, p0)


## Resolucion de una clave del Animation.json que Adobe escribe con dos
## nombres: el "optimizado" (corto, ej "I") y el legacy (largo, ej "index").
##
## maru/src/animate/FlxAnimateJson.hx resuelve CADA campo por separado con
## `this.<corta> ?? this.<larga>` - FlxAnimateJson.hx:129-130:
##     inline function get_I()
##         return this.I ?? this.index;
## y lo mismo para los ~90 getters del archivo. O sea: siempre intenta la
## clave corta primero y cae a la larga si falta. NO hay un "modo" global.
##
## Este parser en cambio elegia el esquema UNA sola vez en load_animation()
## (`var optimized: bool = data.has("AN")`) y despues miraba una sola clave
## por campo. Eso rompe con cualquier Animation.json de claves mezcladas, que
## Adobe si produce: el bloque raiz puede venir optimizado (AN) mientras los
## simbolos sueltos de LIBRARY/*.json vienen en formato largo (LAYERS,
## Layer_name, Frames...). Con el esquema global, esos campos devolvian null
## y el simbolo cargaba vacio, sin ningun error.
##
## El parametro `optimized` se mantiene por compatibilidad de firma (se pasa
## posicionalmente desde ~40 llamadas y desde AdobeColorMatrix.parse), pero
## ya no decide nada.
func has_pair(_optimized: bool, dict: Dictionary, unoptim: String, optim: String) -> bool:
	return dict.get(optim) != null or dict.get(unoptim) != null


## Ver has_pair(). Devuelve la clave corta si esta presente y no es null, si
## no la larga, si no null - identico al `??` encadenado de Haxe.
func get_pair(_optimized: bool, dict: Dictionary, unoptim: String, optim: String) -> Variant:
	var short: Variant = dict.get(optim)
	if short != null:
		return short
	return dict.get(unoptim)


## F7. Port de Timeline.getWholeBounds - maru Timeline.hx:194-220.
##
## Recorre todos los frames y expande el rect con el bounds de cada frame
## (via symbol_bounds, que es el port de Timeline.getBounds). Mas fiel que
## "merge de layer.bounding_box" porque aplica el clipping frame-by-frame.
##
## Sin cache por ahora. El source cachea en `_cachedBounds` (Timeline.hx:
## 240-283) y lo invalida con clearBoundsCache; portar eso requiere hookear
## todos los puntos que invalidan (replace_frame del sprite, F13 del layer,
## etc). TODO F8.
func whole_symbol_bounds(target: AdobeSymbol, include_hidden: bool = false) -> Rect2:
	if target == null or target.length <= 0:
		return Rect2()

	var rect: Rect2 = Rect2()
	var first: bool = true

	for i in target.length:
		var fb: Rect2 = symbol_bounds(target, i, Transform2D.IDENTITY, include_hidden)
		if fb.size.x <= 0.0 or fb.size.y <= 0.0:
			continue
		if first:
			first = false
			rect = fb
		else:
			rect = rect.merge(fb)

	return rect


## F7. Port de Timeline.getBoundsOrigin - maru Timeline.hx:166-178.
## Devuelve el top-left de los bounds como Vector2. Util para replicar el
## matrix.translate(-x, -y) que hace FlxAnimate.hx:224-225 - el patron que
## usan los mods para centrar el sprite.
##
## `apply_stage_matrix` multiplica por stage_transform.x.x/y.y, que es el
## fix de "legacy bounds" del source (Timeline.hx:170-174). El port no tiene
## legacy mode, pero se mantiene el parametro por fidelidad.
func symbol_bounds_origin(target: AdobeSymbol, apply_stage_matrix: bool = false) -> Vector2:
	var rect: Rect2 = whole_symbol_bounds(target)
	var origin: Vector2 = rect.position
	if apply_stage_matrix:
		origin.x *= stage_transform.x.x
		origin.y *= stage_transform.y.y
	return origin
