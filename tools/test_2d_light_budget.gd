extends SceneTree

## The 2D light budget: the only quality lever that reaches a song with no 3D.
##
## Safety Lullaby runs at 30fps and none of the presets touched it. It has no 3D
## at all - `rend=[3d=0/0/0]`, 592 primitives, 38 draw calls - so shadows, LOD,
## cheap shading and hide_baked_lights all apply to nothing, and the render
## scale scales the 3D buffer only, so every pixel of the song is drawn at the
## full 1600x720.
##
## What is left is 2D fill, and lights multiply it: Godot's canvas renderer
## draws each affected CanvasItem **again, once per light**. The alley authors
## four PointLight2D, `BG/BgLight` covering 1.000 of the frame by the census's
## own measurement, against nine parallax sprites that share a mask bit with
## them. `over=` counts items once and cannot see any of it - which is why the
## two pure-2D scenes in log d67addb8 sit 2.5x apart in items and 4.4x apart in
## GPU.
##
## Two groups, because the cost has two sides and the fix has to reach both:
## `quality_optional_2d_light` on the lights, `quality_unlit_2d` on items whose
## being lit is not worth a second pass. Groups rather than a heuristic, same
## reason SUBVIEWPORT_NATIVE_GROUP is a group - which lights carry the look is
## an authoring decision.
##
## What this pins, beyond the wiring: that it writes `enabled` and never
## `visible` (Safety animates visibility all over the scene and a walk fighting
## an animation track loses), that it restores rather than latching off, and
## that the alley is really marked - a preset that reaches an empty group is the
## failure mode this whole file exists to catch.
##
## Run with:
##   godot --headless --path . --script tools/test_2d_light_budget.gd

const SETTINGS_PATH := "res://menus/settings.gd"
const PRESET_PATH := "res://lullaby_mod/scripts/lullaby/settings/lullaby_quality_preset.gd"
const VERY_LOW := "res://lullaby_mod/resources/quality_presets/qol_very_low.tres"
const ALLEY := "res://lullaby_mod/resources/funkin/songs/safety_lullaby/alley.tscn"
const LIGHT_GROUP := "quality_optional_2d_light"
const UNLIT_GROUP := "quality_unlit_2d"

var _failures: int = 0
var _checks: int = 0
var _frames: int = 0


func _initialize() -> void:
	_source_checks()
	_preset_checks()
	_scene_checks()


var _alley_node: Node = null


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false

	# La escena se monta un frame antes de mirarla: los grupos authoreados se
	# registran al entrar al arbol, no al instanciar.
	if _frames == 2:
		var packed: PackedScene = load(ALLEY) as PackedScene
		_check(packed != null, "alley.tscn carga como escena")
		if packed != null:
			_alley_node = packed.instantiate()
			root.add_child(_alley_node)
		return false

	_authored_group_checks()
	_behavioural_checks()

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)
	return true


func _source_checks() -> void:
	var code: String = _strip_comments(_read(SETTINGS_PATH))
	_check(code.contains('const OPTIONAL_2D_LIGHT_GROUP := &"%s"' % LIGHT_GROUP),
		"el grupo de luces opcionales existe con ese nombre")
	_check(code.contains('const UNLIT_2D_GROUP := &"%s"' % UNLIT_GROUP),
		"y el de items sin iluminar")
	_check(code.contains("_apply_2d_light_budget()"),
		"apply_settings lo aplica")

	var at: int = code.find("func _budget_2d_light(")
	_check(at >= 0, "_budget_2d_light existe")
	if at < 0:
		return
	var body: String = code.substr(at)
	body = body.substr(0, body.find("\nfunc "))

	_check(body.contains("light.enabled = not graphics_disable_optional_2d_lights"),
		"escribe `enabled`, que es la propiedad que nadie anima")
	_check(not body.contains(".visible"),
		"y NUNCA `visible`: Safety anima visibilidad por todas partes")
	_check(body.contains("item.get_meta(AUTHORED_LIGHT_MASK"),
		"guarda el light_mask autorado antes de pisarlo")
	_check(body.contains("else authored"),
		"...y lo restaura, en vez de dejar un 1 a mano")


func _preset_checks() -> void:
	var preset: String = _read(PRESET_PATH)
	_check(preset.contains("var disable_optional_2d_lights: bool = false"),
		"el preset tiene el campo, apagado por defecto")
	_check(preset.contains("settings.graphics_disable_optional_2d_lights = disable_optional_2d_lights"),
		"y lo aplica a Settings")
	_check(preset.contains("settings.graphics_disable_optional_2d_lights == disable_optional_2d_lights"),
		"y entra en la comparacion, o la fila de la consola no diria 'Custom'")

	# Solo Very Low, que es el preset al que se le permite cambiar el aspecto.
	var on: int = 0
	for path: String in ["qol_very_low", "qol_low", "qol_medium", "qol_high"]:
		var text: String = FileAccess.get_file_as_string(
			"res://lullaby_mod/resources/quality_presets/%s.tres" % path)
		var enabled: bool = text.contains("disable_optional_2d_lights = true")
		if path == "qol_very_low":
			_check(enabled, "Very Low lo enciende")
		else:
			_check(not enabled, "%s lo deja apagado" % path)
		on += 1 if enabled else 0
	_check(on == 1, "y solo un preset lo enciende (son %d)" % on)


## The group has to have members, or the whole thing is a preset that reaches
## nothing - which is exactly how hide_baked_lights shipped broken once.
func _scene_checks() -> void:
	var alley: String = _read(ALLEY)
	var lights: int = alley.count('"%s"' % LIGHT_GROUP)
	var unlit: int = alley.count('"%s"' % UNLIT_GROUP)
	_check(lights >= 4, "el callejon marca sus luces 2D (%d)" % lights)
	_check(unlit >= 1, "y al menos una capa lejana como no iluminada (%d)" % unlit)

	# Y las marcas van en las luces, no en cualquier nodo.
	for name: String in ["BgLight", "Pole", "PoleLight", "PoleLight2"]:
		var at: int = alley.find('[node name="%s" type="PointLight2D"' % name)
		_check(at >= 0 and alley.find(LIGHT_GROUP, at) - at < 200,
			"%s esta en el grupo" % name)

	# Mountain es la unica capa lejana que segula iluminada: Sky y Clouds ya
	# traian light_mask = 0 del autor, y marcarlas no aportaria nada.
	var mountain: int = alley.find('[node name="Mountain"')
	_check(mountain >= 0 and alley.find(UNLIT_GROUP, mountain) - mountain < 200,
		"Mountain esta en el grupo de no iluminados")


## Y ahora INSTANCIANDO la escena, que es lo unico que prueba que las marcas
## sirvan de algo.
##
## Todo lo de arriba cuenta cadenas en el fichero, y todo lo de abajo crea nodos
## y les hace add_to_group() en codigo. Ninguna de las dos cosas ve el unico
## fallo que importa: que la marca este ESCRITA EN EL SITIO EQUIVOCADO.
##
## Godot escribe los grupos DENTRO de la cabecera del nodo:
##
##     [node name="Luz" type="PointLight2D" parent="." groups=["mi_grupo"]]
##
## y no como una linea de propiedad `groups = [...]` debajo. Las seis marcas de
## este proyecto estaban en la forma de abajo, o sea que `get_nodes_in_group()`
## devolvia cero y las dos palancas -disable_optional_2d_lights y UNLIT_2D_GROUP-
## nunca hicieron nada en el telefono. Este fichero paso con 32 checks en verde
## todo ese tiempo, y su propio docstring ya advertia del riesgo: "a preset that
## reaches an empty group is exactly how hide_baked_lights shipped broken once".
##
## El log del dispositivo del 2026-08-24 lo confirmaba a la vista: `luz2d=7/13
## suma=3.37x` con preset Very Low, que es el preset que supuestamente las apaga.
func _authored_group_checks() -> void:
	if _alley_node == null:
		return

	var luces: Array = get_nodes_in_group(LIGHT_GROUP)
	var no_iluminados: Array = get_nodes_in_group(UNLIT_GROUP)

	# Que el grupo REGISTRE de verdad se sigue comprobando - es lo que arreglo
	# mover las marcas a la cabecera del nodo, y sin esta linea volveriamos a
	# una palanca que no hace nada sin que nadie se entere. Ahora lo sostiene
	# `Mountain`, que es el que queda marcado.
	_check(no_iluminados.size() >= 1,
		"las marcas del callejon REGISTRAN de verdad: %d item no iluminado"
			% no_iluminados.size())

	# Y las CUATRO LUCES YA NO ESTAN EN EL GRUPO, a proposito.
	#
	# Quien authoreo la escena las marco como opcionales, pero esa intencion
	# nunca llego a ejecutarse: las marcas estaban escritas donde Godot no las
	# lee, el grupo devolvia cero, y las luces se quedaban encendidas pasara lo
	# que pasara. El arte que todo el mundo ha visto siempre las tuvo.
	#
	# Arreglar el grupo hizo que Very Low por fin las apagase, y ahi se vio que
	# no son opcionales. `BgLight` es `blend_mode = 2` - BLEND_MODE_MIX, leido
	# en scene/2d/light_2d.h del 4.7.1 - con `texture_scale = 4.0` y
	# `range_item_cull_mask = 257`: no ilumina, OSCURECE, y alcanza a los
	# personajes. Sin ella Hypno sale entero a plena luz cuando el original lo
	# tiene tapado de sombra. Las otras tres son el halo de las farolas junto a
	# GF, y sin ellas ese rincon queda plano.
	#
	# O sea que el mecanismo no estaba mal: su lista de miembros nunca se pudo
	# validar porque nunca funciono. Un grupo roto no solo deja de ahorrar,
	# tambien esconde que lo que hay dentro estaba mal elegido.
	var nombres: PackedStringArray = []
	for n: Node in luces:
		nombres.append(n.name)
	for critica: String in ["BgLight", "Pole", "PoleLight", "PoleLight2"]:
		_check(not nombres.has(critica),
			"  %s NO es opcional: es arte, no adorno" % critica)

	_alley_node.queue_free()
	_alley_node = null


func _behavioural_checks() -> void:
	var settings: Node = root.get_node_or_null(^"Settings")
	if settings == null:
		_check(false, "existe el autoload Settings")
		return

	var light := PointLight2D.new()
	light.add_to_group(LIGHT_GROUP)
	var plain := PointLight2D.new()
	var item := Sprite2D.new()
	item.light_mask = 3
	item.add_to_group(UNLIT_GROUP)
	var plain_item := Sprite2D.new()
	plain_item.light_mask = 3
	for node in [light, plain, item, plain_item]:
		root.add_child(node)

	var previous: bool = settings.graphics_disable_optional_2d_lights

	settings.graphics_disable_optional_2d_lights = true
	settings.call("_budget_2d_lights_under", root)
	_check(not light.enabled, "con el presupuesto activo la luz marcada se apaga")
	_check(plain.enabled, "y una luz sin marcar sigue encendida")
	_check(item.light_mask == 0, "el item marcado deja de recibir luz")
	_check(plain_item.light_mask == 3, "y uno sin marcar conserva su mascara")

	settings.graphics_disable_optional_2d_lights = false
	settings.call("_budget_2d_lights_under", root)
	_check(light.enabled, "y al subir la calidad la luz vuelve")
	_check(item.light_mask == 3, "y el item recupera SU mascara, no un 1 a mano")

	settings.graphics_disable_optional_2d_lights = previous
	for node in [light, plain, item, plain_item]:
		node.queue_free()


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	_check(not text.is_empty(), "%s se lee" % path.get_file())
	return text


func _strip_comments(source: String) -> String:
	var out: PackedStringArray = []
	for line in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		var hash_at: int = line.find("#")
		out.append(line.substr(0, hash_at) if hash_at >= 0 else line)
	return "\n".join(out)
