extends SceneTree

## `hide_baked_lights` esconde exactamente las luces que el lightmap ya lleva,
## y ninguna otra.
##
## El motivo, medido en el g53 del usuario sobre `3d21ba99`: el frame de
## Chimera es 90% pase 3D (`gpu = 5.7ms + 90.8ms x Mpx3d`) y esos 90.8 ms/Mpx
## son lo que cuestan seis luces por fragmento en esta misma ruta - el banco
## aislado da 6 omnis a pantalla completa en 108.6ms sobre 1.152 Mpx, o sea 94
## ms/Mpx. No es geometria: el frame mas barato de la cancion dibuja 32960
## primitivas y el mas caro 9862, y `corr(gpu, prims) = +0.20`.
##
## El A/B lo hace el propio log sin que nadie se lo pida:
##
##     camara en el armario   luz=3   gpu 33.5ms   (5 muestras seguidas)
##     planos anchos de casa  luz=4   gpu 57-59ms  (11 muestras seguidas)
##
## y la cuarta luz es `MoonSpotlight`, autorada `BAKE_STATIC`. **24ms por una
## luz que el bake ya contiene.**
##
## Este guard fija las tres condiciones del pase, y cada una esta aqui por un
## bug que este proyecto ya ha enviado:
##
## 1. Sin `LightmapGI` con `light_data`, no se toca nada. Esconder las luces
##    horneadas de una escena cuyo bake no carga deja la habitacion negra, que
##    es literalmente el bug de once dias y diez builds.
## 2. Nunca una luz bajo un `RubiconCharacter`. `chr_serena_base.tscn` autora
##    la suya como BAKE_STATIC sobre la raiz del personaje, y una luz que anda
##    con el personaje no esta en el bake de la casa diga lo que diga su modo.
## 3. Solo luces visibles, y se guarda el valor anterior - `ClosetLight`
##    shipea `visible = false` y nada la enciende nunca.
##
## Y fija el hecho de datos del que depende todo: que **ninguna animacion de
## Chimera toca sus seis luces BAKE_STATIC**. Si algun dia una lo hace, este
## pase se la comeria en silencio, porque una luz escondida ignora lo que le
## escriba una pista.
##
## Correr con:
##   godot --headless --path . --script tools/test_baked_light_cull.gd

const APPLIER := "res://lullaby_mod/scripts/lullaby/settings/lullaby_light_budget_applier.gd"
const CHIMERA := "res://lullaby_mod/songs/chimera/sng_chimera.tscn"
const SERENA := "res://lullaby_mod/resources/funkin/songs/chimera/characters/chr_serena_base.tscn"

## Las seis de Chimera, por nombre, para que el fallo diga cual se movio.
const CHIMERA_BAKED: PackedStringArray = [
	"MoonSpotlight", "AmbLight", "ClosetLight",
	"CrawlSpaceLight", "OutsideGrassLight", "CrawlDoorLight",
]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var src: String = _read(APPLIER)
	_check(src != "", "el applier se lee")

	# 1. Las tres condiciones, presentes como codigo y no como comentario.
	_check(_has_statement(src, "light.light_bake_mode != Light3D.BAKE_STATIC"),
		"solo actua sobre BAKE_STATIC")
	_check(_has_statement(src, "_bake_carries_the_room(scene)"),
		"exige un LightmapGI en la escena")
	_check(_has_statement(src, "_bake_coverage(lightmap) >= BAKE_COVERAGE_FLOOR"),
		"y que el bake cubra de verdad lo que se ve, no solo que exista")
	_check(_has_statement(src, "const BAKE_COVERAGE_FLOOR := 0.75"),
		"el umbral cae entre Chimera (56/62=90%) y la tienda (44/101=44%)")
	_check(_has_statement(src, "lightmap.light_data != null"),
		"y que ese LightmapGI traiga bake cargado, no solo que exista")
	_check(_has_statement(src, "_is_under_character(light)"),
		"excluye las luces que cuelgan de un personaje")
	_check(_has_statement(src, "node is RubiconCharacter"),
		"y ese personaje se detecta por RubiconCharacter")
	_check(_has_statement(src, "if not light.visible or"),
		"no enciende una luz que shipeaba apagada")
	_check(_has_statement(src, "_restore_hidden()"),
		"y devuelve las escondidas al subir de preset")

	# 2. El dato del que depende todo: la escena de Chimera sigue autorando
	#    esas seis como BAKE_STATIC y ninguna animacion las toca.
	var scene: String = _read(CHIMERA)
	_check(scene != "", "sng_chimera.tscn se lee")
	var baked: int = scene.count("light_bake_mode = 1")
	_check(baked == 6, "Chimera sigue con 6 luces BAKE_STATIC (son %d)" % baked)

	for name: String in CHIMERA_BAKED:
		_check(scene.contains('[node name="%s"' % name),
			"%s sigue existiendo en la escena" % name)
		var driven: bool = scene.contains('/%s:' % name) or scene.contains('"%s:' % name)
		_check(not driven,
			"ninguna pista de animacion apunta a %s" % name)

	# 3. Serena autora la suya como BAKE_STATIC sobre la raiz del personaje,
	#    que es el caso concreto que la exclusion existe para cubrir.
	var serena: String = _read(SERENA)
	_check(serena.contains("light_bake_mode = 1"),
		"chr_serena_base.tscn sigue autorando su luz como BAKE_STATIC")
	_check(serena.contains("rubicon_character.gd"),
		"y su raiz sigue siendo un RubiconCharacter")

	# 4. Solo las escenas con lightmap pueden verse afectadas, y son dos.
	_check(_read("res://lullaby_mod/rooms/env_collector_shop.tscn")
			.contains('type="LightmapGI"'),
		"la tienda sigue teniendo LightmapGI")
	# Y sigue teniendo nueve luces horneadas, que es lo que la pondria en
	# riesgo si el umbral de cobertura se quitara.
	var shop_baked: int = (_read("res://lullaby_mod/rooms/env_collector_shop.tscn")
		.count("light_bake_mode = 1"))
	_check(shop_baked == 9, "la tienda sigue con 9 luces BAKE_STATIC (son %d)" % shop_baked)
	_check(scene.contains('type="LightmapGI"'),
		"Chimera sigue teniendo LightmapGI")

	# 5. Y TvLight, que si esta animada, no puede ser candidata: es
	#    BAKE_DISABLED, no BAKE_STATIC.
	var tv: int = scene.find('[node name="TvLight"')
	_check(tv >= 0, "TvLight sigue en la escena")
	if tv >= 0:
		var block: String = scene.substr(tv, 700)
		_check(block.contains("light_bake_mode = 0"),
			"TvLight sigue BAKE_DISABLED, o sea nunca candidata a esconderse")

	# 6. La fila del preset, sobre el recurso cargado.
	var low: Resource = load("res://lullaby_mod/resources/quality_presets/qol_low.tres")
	var very_low: Resource = load("res://lullaby_mod/resources/quality_presets/qol_very_low.tres")
	var medium: Resource = load("res://lullaby_mod/resources/quality_presets/qol_medium.tres")
	var high: Resource = load("res://lullaby_mod/resources/quality_presets/qol_high.tres")
	_check(low != null and very_low != null and medium != null and high != null,
		"los cuatro presets cargan")
	if low != null:
		_check(low.hide_baked_lights, "Low lo enciende")
		_check(very_low.hide_baked_lights, "Very Low lo enciende")
		_check(not medium.hide_baked_lights, "Medium no (tiene que verse bien)")
		_check(not high.hide_baked_lights, "High no")
		_check(low.cheap_shading and very_low.cheap_shading,
			"cheap_shading va en los mismos dos presets")
		_check(not medium.cheap_shading and not high.cheap_shading,
			"y no en Medium ni High")

	# 7. El segundo pase: nunca un metalico se queda sin specular, porque para
	#    un metal ese lobulo ES el material y sin el sale casi negro. La casa
	#    tiene tres asi y los tres siguen declarandose metalicos.
	_check(_has_statement(src, "_is_metallic(material)"),
		"cheap_shading exime a los materiales metalicos")
	_check(_has_statement(src, "material.metallic >= 0.5 or material.metallic_texture != null"),
		"y metalico es el escalar O la textura, no solo el escalar")
	_check(_has_statement(src, "BaseMaterial3D.SHADING_MODE_UNSHADED"),
		"y salta los unshaded, que no tienen luz que quitar")
	_check(not _has_statement(src, "SHADING_MODE_PER_VERTEX"),
		"no shipea PER_VERTEX: mide mejor pero interpola la luz por triangulo")
	_check(_has_statement(src, "_restore_shading()"),
		"y devuelve diffuse/specular al subir de preset")

	const HOUSE := "res://lullaby_mod/assets/funkin/chimera/models/house/materials/"
	for name: String in ["Material", "props1", "props2"]:
		var body: String = _read(HOUSE + name + ".tres")
		_check(body.contains("metallic = 1.0") or body.contains("metallic_texture"),
			"%s sigue siendo metalico, o sea exento" % name)

	_finish()


## `contains()` pasa sobre una linea comentada, y este fichero nombra en sus
## propios comentarios justo lo que busca. Exige una linea cuyo primer caracter
## no blanco no sea `#`.
func _has_statement(src: String, needle: String) -> bool:
	for line: String in src.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		if trimmed.contains(needle):
			return true
	return false


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text
