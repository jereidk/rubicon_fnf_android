extends SceneTree

## Un mesh cuyo unico material es un shader de efecto tiene que esconderse con
## "Reduce Visual Effects" - y volver cuando se apaga.
##
## `_strip_surface_shader_material()` lee `get_surface_override_material()` y
## `_strip_shader_material_property()` lee `material_override`, asi que entre
## los dos cubren todo material que sea del **nodo**. Un material puesto en el
## recurso de malla no es de ninguno de los dos y no lo veia nadie.
##
## Chimera's `Environment/Lights/Ray` es justo eso: un BoxMesh cuyo propio
## `material` es `shd_godrays`, que lleva en `EFFECT_SHADER_PATHS` desde
## siempre sin que el ajuste lo tocara una sola vez. Y no es poca cosa - el
## shader es `unshaded, blend_add, cull_disabled, depth_test_disabled`, o sea
## las dos caras sin rechazo por profundidad con una lectura de profundidad por
## fragmento. Medido en aislado a 800x360, que es lo que mide el pase 3D del
## moto g53 a `scale=0.50`, con la caja real de 4.97x13.57x6.6 sobre 49 mallas:
##
##     sin Ray   3.88ms / 4.13ms   draws=49  prims=588
##     con Ray   8.05ms / 8.64ms   draws=50  prims=600
##
## **Un draw call y doce primitivas duplican el frame.** Es el ejemplo mas
## limpio que tiene el proyecto de por que `draw=`/`prims=`/`objs=` no pueden
## ver un coste por pixel.
##
## ALCANCE, y hay que decirlo cada vez que se cite: **esto es inerte en los
## cuatro presets.** `Ray:visible = true` sale solo del estado `high` del
## PostProcessingTree, o sea `graphics_post_processing == 2`, y
## `disable_shader_effects` lo pone solo Very Low, que va a `post=0`. La unica
## combinacion que lo alcanza es Custom con post en High y "Reduce Visual
## Effects" marcado - reachable desde la consola, porque son dos filas
## independientes, pero no es una ganancia para nadie que use un preset. Es un
## arreglo de correccion: el ajuste que se llama "reducir efectos visuales"
## dejaba corriendo el objeto por pixel mas caro de la escena.
##
## Run with:
##   godot --headless --path . --script tools/test_effect_mesh_hide.gd

const SETTINGS_PATH := "res://menus/settings.gd"
const CHIMERA_PATH := "res://lullaby_mod/songs/chimera/sng_chimera.tscn"
const GODRAYS := "res://lullaby_mod/resources/shaders/shd_godrays.gdshader"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var source: String = _read(SETTINGS_PATH)
	var code: String = _strip_comments(source)

	_check(code.contains("func _hide_mesh_that_only_draws_an_effect("),
		"_hide_mesh_that_only_draws_an_effect existe")
	_check(code.contains("_hide_mesh_that_only_draws_an_effect(node)"),
		"y se llama desde el recorrido")

	# Cae despues del bucle de superficies: si una superficie tiene override
	# propio, ese ya se anulo y la comprobacion de "todo es efecto" tiene que
	# ver el estado de despues, no el de antes.
	var loop_at: int = code.find("_strip_surface_shader_material(node, surface)")
	var hide_at: int = code.find("_hide_mesh_that_only_draws_an_effect(node)")
	_check(loop_at >= 0 and hide_at > loop_at,
		"se llama despues de anular los overrides de superficie")

	# Las dos guardas que impiden que esto revele algo. Un nodo ya oculto se
	# deja en paz - revelar nodos escondidos es lo que hizo el prewarm
	# revertido, que dio el foco a la pestaña Codes y abrio el teclado de
	# Android en una pantalla que el jugador no eligio.
	var body: String = code.substr(hide_at)
	body = body.substr(body.find("func _hide_mesh_that_only_draws_an_effect("))
	body = body.substr(0, body.find("\nfunc "))
	_check(body.contains("if not node.visible:"),
		"no toca un nodo que ya venia oculto")
	_check(body.contains("node.material_override != null"),
		"deja el caso de material_override a quien ya lo lleva")
	_check(body.contains("surfaces == 0"),
		"una malla sin superficies no cuenta como 'solo efecto'")
	# El return dentro del bucle es lo que exige que **todas** las superficies
	# sean efecto. Sin el, una sola superficie de efecto escondería arte.
	_check(body.count("return") >= 4,
		"basta una superficie con material real para no esconder nada")
	_check(body.contains("EFFECT_SHADER_PATHS.has("),
		"solo shaders de la lista de efectos")
	_check(body.contains("_stashed_visibility[node.get_instance_id()] = true"),
		"apunta lo que escondio para poder devolverlo")

	# Y el restore tiene que cubrir MeshInstance3D, o la caja se queda oculta
	# para siempre al desmarcar el ajuste. Antes solo miraba CanvasItem.
	var restore: String = code.substr(code.find("for id: int in _stashed_visibility:"))
	restore = restore.substr(0, restore.find("_stashed_visibility.clear()"))
	_check(restore.contains("MeshInstance3D"),
		"el restore devuelve tambien las mallas, no solo los CanvasItem")

	# Y el sujeto sigue siendo el que era: shd_godrays en la lista, y en el
	# material del recurso de malla de Ray, no en un override del nodo.
	_check(code.contains(GODRAYS), "shd_godrays sigue en EFFECT_SHADER_PATHS")
	var scene: String = _read(CHIMERA_PATH)
	_check(scene.contains('[sub_resource type="BoxMesh" id="BoxMesh_vsneh"]'),
		"el BoxMesh de Ray sigue ahi")
	var mesh_block: String = _block(scene, '[sub_resource type="BoxMesh" id="BoxMesh_vsneh"]')
	_check(mesh_block.contains("material = SubResource("),
		"y su material sigue viviendo en el recurso de malla, no en el nodo")

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


func _block(text: String, header: String) -> String:
	var at: int = text.find(header)
	if at < 0:
		return ""
	var rest: String = text.substr(at + header.length())
	var end: int = rest.find("\n[")
	return rest if end < 0 else rest.substr(0, end)


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _strip_comments(text: String) -> String:
	var out: String = ""
	for line in text.split("\n"):
		var quote: String = ""
		var cut: int = -1
		for i in line.length():
			var c: String = line[i]
			if quote != "":
				if c == quote:
					quote = ""
			elif c == "\"" or c == "'":
				quote = c
			elif c == "#":
				cut = i
				break
		out += (line if cut < 0 else line.substr(0, cut)) + "\n"
	return out
