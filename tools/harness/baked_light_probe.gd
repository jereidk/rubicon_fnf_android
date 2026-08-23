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

	var character := RubiconCharacter.new()
	scene.add_child(character)
	var serena_light: OmniLight3D = _light(Light3D.BAKE_STATIC, true)
	character.add_child(serena_light)
	add_child(scene)

	var before: bool = Settings.graphics_hide_baked_lights

	# 1. Con el ajuste puesto pero SIN bake cargado no se toca nada. Es la
	#    condicion que impide repetir la casa negra de once dias.
	Settings.graphics_hide_baked_lights = true
	print("OUT lightmap_sin_datos_vivo=%s" % applier._has_live_lightmap(scene))
	applier._apply_baked_light_cull(scene)
	_report("sin_bake", baked, tv_like, dynamic, ships_hidden, serena_light)

	# 2. Con bake cargado esconde la horneada y solo la horneada.
	lightmap.light_data = LightmapGIData.new()
	applier._applied_hide_baked = false
	print("OUT lightmap_con_datos_vivo=%s" % applier._has_live_lightmap(scene))
	applier._apply_baked_light_cull(scene)
	_report("con_bake", baked, tv_like, dynamic, ships_hidden, serena_light)

	# 3. Y al subir de preset devuelve lo que habia, sin encender la que
	#    shipeaba apagada.
	Settings.graphics_hide_baked_lights = false
	applier._apply_baked_light_cull(scene)
	_report("restaurado", baked, tv_like, dynamic, ships_hidden, serena_light)

	Settings.graphics_hide_baked_lights = before

	_check_cheap_shading(applier)

	applier.free()
	get_tree().quit()


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
	for pair: Array in [["_sintetico_mate", matte], ["_sintetico_metal", metal],
			["_sintetico_metal_tex", metal_tex]]:
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
		print("OUT barato    %-22s metallic=%.2f tex=%s diffuse=%d specular=%d shading=%d" % [
			name, material.metallic, material.metallic_texture != null,
			material.diffuse_mode, material.specular_mode, material.shading_mode])

	Settings.graphics_cheap_shading = false
	applier._apply_cheap_shading(holder)
	for name: String in loaded:
		var material: BaseMaterial3D = loaded[name]
		print("OUT restaurado %-21s diffuse=%d specular=%d" % [
			name, material.diffuse_mode, material.specular_mode])
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
