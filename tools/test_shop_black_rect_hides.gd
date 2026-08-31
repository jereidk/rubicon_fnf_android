extends SceneTree

## El rect de fundido de la tienda deja de dibujarse mientras es transparente.
##
## Godot NO descarta un CanvasItem por ser transparente: lo rasteriza y lo mezcla
## igual. `UI/BlackScreenThingy` es un ColorRect a pantalla completa
## (`anchors_preset = 15`) con `color = Color(1, 1, 1, 0)`, y el censo del log
## 10226-4fe0a6db lo nombra como el que mas aporta al sobredibujado en las CINCO
## muestras que hay de la tienda:
##
##     over=2.2x(n=11 top=UI/BlackScreenThingy@1.0x)
##     relleno=[UI/BlackScreenThingy@1.00x a=0.00, ...]
##
## Un relleno de pantalla entera por fotograma que no produce un pixel. Mismo
## defecto que `UILayer/NTSC@1.00x a=0.00` en Chimera, cuyo arreglo bajo el
## sobredibujado de aquella entrada de 5.1x a 2.1x.
##
## LA PREMISA, y es lo que mas importa fijar aqui: se apaga escribiendo
## `visible`, que solo es correcto porque NINGUNA pista anima esa propiedad en
## este nodo - las tres que lo tocan animan `:color`. En el NTSC pasaba lo
## contrario y escribir `visible` peleaba con cuatro pistas, que es como se metio
## un fallo que parecia verde leyendo el codigo. Si algun dia alguien anima
## `BlackScreenThingy:visible`, este enfoque deja de ser correcto y solo esta
## comprobacion se enteraria.
##
## Run with:
##   godot --headless --path . --script tools/test_shop_black_rect_hides.gd

const GATE := "res://lullaby_mod/scripts/lullaby/lullaby_transparent_rect_gate.gd"
const SHOP := "res://lullaby_mod/rooms/env_collector_shop.tscn"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var scene: String = _read(SHOP)
	if not _check(not scene.is_empty(), "la escena de la tienda se lee"):
		_finish()
		return

	# --- El cableado ---
	_check(scene.contains("lullaby_transparent_rect_gate.gd"),
		"la escena referencia el gate")
	var block: String = _node_block(scene, '[node name="BlackScreenThingy" type="ColorRect" parent="UI"')
	_check(not block.is_empty(), "BlackScreenThingy sigue en la escena")
	_check(block.contains("script = ExtResource("), "y lleva el script puesto")
	_check(block.contains("anchors_preset = 15"),
		"sigue siendo de pantalla completa - si dejara de serlo esto sobraria")

	# --- La premisa: nadie mas dispone de `visible` en este nodo ---
	var color_tracks: int = 0
	var visible_tracks: int = 0
	for line: String in scene.split("\n"):
		if not line.contains("BlackScreenThingy"):
			continue
		if line.contains(":color"):
			color_tracks += 1
		if line.contains(":visible"):
			visible_tracks += 1
	_check(color_tracks > 0, "hay pistas animando su color (%d)" % color_tracks)
	_check(visible_tracks == 0,
		"y NINGUNA anima su visible (%d) - es lo que hace correcto apagarlo asi" % visible_tracks)

	# --- El comportamiento, corriendo ---
	var script: GDScript = load(GATE)
	if not _check(script != null, "el gate carga"):
		_finish()
		return

	var rect: ColorRect = ColorRect.new()
	rect.set_script(script)
	get_root().add_child(rect)

	rect.color = Color(1, 1, 1, 0.0)
	rect.visible = true
	# Dos fotogramas en el primer caso: el nodo acaba de entrar al arbol y dentro
	# de `_initialize()` el primero no le llega a correr el `_process`. Los casos
	# siguientes van con uno porque el nodo ya lleva procesando.
	await process_frame
	await process_frame
	_check(not rect.visible, "transparente del todo -> deja de dibujarse")

	# Un fundido que arranca: tiene que encenderse YA, no tras un epsilon.
	rect.color = Color(1, 1, 1, 0.001)
	await process_frame
	_check(rect.visible, "con el alfa mas minimo vuelve, sin esperar a un umbral")

	rect.color = Color(1, 1, 1, 1.0)
	await process_frame
	_check(rect.visible, "y opaco sigue visible")

	rect.color = Color(1, 1, 1, 0.0)
	await process_frame
	_check(not rect.visible, "y al terminar el fundido se vuelve a apagar")

	rect.free()
	_finish()


func _node_block(scene: String, header: String) -> String:
	var at: int = scene.find(header)
	if at < 0:
		return ""
	var close: int = scene.find("\n[", at + 1)
	return scene.substr(at, -1 if close < 0 else close - at)


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - el rect transparente no se dibuja")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
