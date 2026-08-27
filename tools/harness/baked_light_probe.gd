extends Node3D

## Comprueba el pase `hide_baked_lights` sobre el applier REAL, con los
## autoloads reales, contra un arbol sintetico que reproduce los cinco casos
## que existen en este proyecto.
##
## Tiene que ser una escena y no un `--script`: el applier toca `Settings` y
## `SceneChanger`, y bajo `--script` los autoloads no existen, asi que ni
## siquiera compila. Es la misma razon por la que existe `training_probe.tscn`.
##
##   godot --headless --path . res://tools/harness/baked_light_probe.tscn

const APPLIER := "res://lullaby_mod/scripts/lullaby/settings/lullaby_light_budget_applier.gd"

func _ready() -> void:
	var applier: Node = load(APPLIER).new()   # sin add_child: su _ready no corre

	var scene := Node3D.new()
	var lightmap := LightmapGI.new()
	scene.add_child(lightmap)

	var baked: OmniLight3D = _light(Light3D.BAKE_STATIC, true)
	var tv_like: OmniLight3D = _light(Light3D.BAKE_DISABLED, true)
	var dynamic: OmniLight3D = _light(Light3D.BAKE_DYNAMIC, true)
	var ships_hidden: OmniLight3D = _light(Light3D.BAKE_STATIC, false)
	for light: OmniLight3D in [baked, tv_like, dynamic, ships_hidden]:
		scene.add_child(light)

	# El pase de luces horneadas ya no decide sobre una escena sin geometria
	# visible - el precache la esconde entera y medir ahi contesta 0/0. Asi que
	# la sonda tiene que traer mallas de verdad, y las registra en el bake para
	# reproducir los dos casos reales: Chimera (el bake lleva la habitacion) y
	# la tienda (no la lleva).
	var meshes: Array[MeshInstance3D] = []
	for i: int in 25:
		var mesh_node := MeshInstance3D.new()
		mesh_node.name = "Baked%d" % i
		mesh_node.mesh = BoxMesh.new()
		scene.add_child(mesh_node)
		meshes.append(mesh_node)

	var character := RubiconCharacter.new()
	scene.add_child(character)
	var serena_light: OmniLight3D = _light(Light3D.BAKE_STATIC, true)
	character.add_child(serena_light)
	add_child(scene)

	var before: bool = Settings.graphics_hide_baked_lights

	# 1. Con el ajuste puesto pero SIN bake cargado no se toca nada. Es la
	#    condicion que impide repetir la casa negra de once dias.
	Settings.graphics_hide_baked_lights = true
	print("OUT sin_datos_sirve=%s" % applier._bake_carries_the_room(scene))
	applier._apply_baked_light_cull(scene)
	_report("sin_bake", baked, tv_like, dynamic, ships_hidden, serena_light)

	# 2. Con bake cargado pero cubriendo poco - el caso de la tienda, 44/101 -
	#    el pase se planta y no toca nada.
	var data := LightmapGIData.new()
	for i: int in 5:
		data.add_user(lightmap.get_path_to(meshes[i]), Rect2(0, 0, 1, 1), 0, -1)
	lightmap.light_data = data
	applier._applied_hide_baked = false
	applier._bake_decided = false
	print("OUT cobertura_baja_sirve=%s (%d/25)" %
		[applier._bake_carries_the_room(scene), 5])
	applier._apply_baked_light_cull(scene)
	_report("poca_cobert", baked, tv_like, dynamic, ships_hidden, serena_light)

	# 3. Y con el bake llevando la habitacion - el caso de Chimera, 56/62 -
	#    esconde la horneada y solo la horneada.
	for i: int in range(5, 24):
		data.add_user(lightmap.get_path_to(meshes[i]), Rect2(0, 0, 1, 1), 0, -1)
	applier._applied_hide_baked = false
	applier._bake_decided = false
	print("OUT cobertura_alta_sirve=%s (%d/25)" %
		[applier._bake_carries_the_room(scene), 24])
	applier._apply_baked_light_cull(scene)
	_report("con_bake", baked, tv_like, dynamic, ships_hidden, serena_light)

	# 3. Y al subir de preset devuelve lo que habia, sin encender la que
	#    shipeaba apagada.
	Settings.graphics_hide_baked_lights = false
	applier._apply_baked_light_cull(scene)
	_report("restaurado", baked, tv_like, dynamic, ships_hidden, serena_light)

	Settings.graphics_hide_baked_lights = before

	_check_cheap_shading(applier)
	_check_dark_cull(applier)

	applier.free()
	get_tree().quit()


## Y el tercer pase, `_cull_dark_lights`, con su holdoff.
##
## Cada configuracion de "estas superficies a este numero de luces" cuesta un
## juego de pipelines de especializacion, asi que una luz que cruza el cero
## mientras se revela geometria nueva la hace compilar dos veces. Es el
## congelado de dos segundos de la sesion de fotos de Chimera: `flash` y
## `PhoneGlow` cruzan el cero siete veces cada una en 8.5s.
##
## Lo que el arreglo NO puede hacer es dejar de cullear una luz aparcada a
## cero: `TvLight` lo esta los 78 segundos de `prelude` con radio 43.9 sobre
## una casa de diez unidades. Por eso es un holdoff y no una exencion, y por
## eso la sonda comprueba los dos lados.
func _check_dark_cull(applier: Node) -> void:
	var scene := Node3D.new()
	scene.name = "DarkCullScene"

	var parked := OmniLight3D.new()      # el caso TvLight-en-prelude
	parked.name = "parked"
	parked.light_energy = 0.0
	scene.add_child(parked)

	var blinking := OmniLight3D.new()    # el caso flash
	blinking.name = "blinking"
	blinking.light_energy = 0.0
	scene.add_child(blinking)

	add_child(scene)

	var authored: int = parked.light_cull_mask
	applier._watched = applier._lights_of(scene)
	applier._dark_masks.clear()
	applier._dark_since.clear()

	# Primer paso: las dos acaban de ponerse a cero, asi que ninguna se toca.
	applier._cull_dark_lights()
	print("OUT primer_paso parked=%d blinking=%d (autorada=%d)" % [
		parked.light_cull_mask, blinking.light_cull_mask, authored])

	# La que parpadea vuelve antes del holdoff: se le olvida el reloj, que es
	# lo que impide que el siguiente cero la cullee por acumulacion.
	blinking.light_energy = 4.858
	applier._cull_dark_lights()
	blinking.light_energy = 0.0
	applier._cull_dark_lights()

	# Y ahora se adelanta el reloj de la aparcada mas alla del holdoff. La que
	# parpadeo lleva a cero solo desde su ultimo cruce, asi que sigue intacta.
	var hold_ms: int = int(applier.DARK_HOLD_SECONDS * 1000.0)
	applier._dark_since[parked.get_instance_id()] = Time.get_ticks_msec() - hold_ms - 1
	applier._cull_dark_lights()
	print("OUT tras_hold  parked=%d blinking=%d" % [
		parked.light_cull_mask, blinking.light_cull_mask])

	# Y al volver, la mascara autorada vuelve exacta y de inmediato.
	parked.light_energy = 1.0
	applier._cull_dark_lights()
	print("OUT al_volver  parked=%d exacta=%s" % [
		parked.light_cull_mask, parked.light_cull_mask == authored])

	scene.queue_free()


## Y el segundo pase, contra los materiales REALES de la casa de Chimera, que
## es donde el "nunca un metalico" tiene que demostrarse.
func _check_cheap_shading(applier: Node) -> void:
	const HOUSE := "res://lullaby_mod/assets/funkin/chimera/models/house/materials/"
	var names: PackedStringArray = ["wall", "floor", "foliage", "grars", "wood",
		"props1", "props2", "Material", "outside"]

	var holder := Node3D.new()
	var loaded: Dictionary = {}

	# Los materiales de la casa que llevan textura no cargan en este workspace
	# (no estan importados), asi que los tres casos que deciden la regla van
	# tambien como sinteticos: mate, metalico por escalar, metalico por textura.
	var matte := StandardMaterial3D.new(); matte.metallic = 0.0
	var metal := StandardMaterial3D.new(); metal.metallic = 1.0
	var metal_tex := StandardMaterial3D.new()
	metal_tex.metallic = 0.0
	metal_tex.metallic_texture = PlaceholderTexture2D.new()
	var bumped := StandardMaterial3D.new()
	bumped.normal_enabled = true
	bumped.normal_texture = PlaceholderTexture2D.new()
	for pair: Array in [["_sintetico_mate", matte], ["_sintetico_metal", metal],
			["_sintetico_metal_tex", metal_tex], ["_sintetico_normal", bumped]]:
		loaded[pair[0]] = pair[1]
		var synthetic := MeshInstance3D.new()
		synthetic.mesh = BoxMesh.new()
		synthetic.material_override = pair[1]
		holder.add_child(synthetic)
	for name: String in names:
		var material: Material = load(HOUSE + name + ".tres")
		if material == null:
			continue
		loaded[name] = material
		var mesh_node := MeshInstance3D.new()
		mesh_node.mesh = BoxMesh.new()
		mesh_node.material_override = material
		holder.add_child(mesh_node)
	add_child(holder)

	var before: bool = Settings.graphics_cheap_shading
	Settings.graphics_cheap_shading = true
	applier._apply_cheap_shading(holder)
	for name: String in loaded:
		var material: BaseMaterial3D = loaded[name]
		print("OUT barato    %-22s metallic=%.2f tex=%s diffuse=%d specular=%d shading=%d normal=%s" % [
			name, material.metallic, material.metallic_texture != null,
			material.diffuse_mode, material.specular_mode, material.shading_mode,
			material.normal_enabled])

	Settings.graphics_cheap_shading = false
	applier._apply_cheap_shading(holder)
	for name: String in loaded:
		var material: BaseMaterial3D = loaded[name]
		print("OUT restaurado %-21s diffuse=%d specular=%d normal=%s" % [
			name, material.diffuse_mode, material.specular_mode,
			material.normal_enabled])
	Settings.graphics_cheap_shading = before

func _light(bake: int, visible_now: bool) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_bake_mode = bake
	light.visible = visible_now
	return light

func _report(label: String, baked: Light3D, tv_like: Light3D, dynamic: Light3D,
		ships_hidden: Light3D, serena: Light3D) -> void:
	print("OUT %-11s horneada=%s tv=%s dinamica=%s ya_oculta=%s serena=%s" % [
		label, baked.visible, tv_like.visible, dynamic.visible,
		ships_hidden.visible, serena.visible])
