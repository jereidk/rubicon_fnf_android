extends SceneTree

## El barrido del precache visita TODAS las secuencias, no solo las dos primeras.
##
## El fallo que cubre no da error, no sale en ningun contador y la linea del log
## que lo contiene parecia sana. `lullaby_preload_camera.gd` recoge poses de
## camara de la animacion `precache` y ademas de cada animacion listada en
## `extra_sweep_animations`, las concatena, y las servia EN ORDEN, una por
## fotograma revelador. El log del dispositivo:
##
##     precache finished (15840ms, 72 nodos) barrido=82 poses ... extra=30 frames
##
## `barrido` son las poses recogidas y `extra` los fotogramas que sirvieron una,
## asi que Chimera recoge 82 poses y dispone de 30 fotogramas. En orden, el
## cursor se para en el indice 29. Contando los grupos contra la escena:
##
##     precache 15 | 104_photographysesh 4 | 122_fall 13 | 107_turnaround 16
##     101_prelude 16 | 121_closetrunout 4 | 103_stroll 5 | 102_intro 2
##     114_hexapproach 7
##
## El indice 29 cae dos poses antes del final de `122_fall`. O sea que
## `107_turnaround`, `101_prelude`, `121_closetrunout`, `103_stroll`,
## `102_intro` y `114_hexapproach` no se barrian desde NINGUN punto de vista -
## seis de las ocho secuencias que estan en ese export justamente porque
## petardean, y dos de ellas (`121_closetrunout`, `114_hexapproach`) estan
## nombradas en el propio comentario del fichero como las secuencias cuyo
## petardeo este mecanismo existe para evitar.
##
## Se prueba corriendo el orden real, no leyendo el codigo, porque lo que hay que
## demostrar es una propiedad de un PREFIJO: que los primeros N servidos tocan
## las nueve secuencias para cualquier N razonable. Eso no se ve mirando.
##
## Las dos comprobaciones de la cola llegan hasta `finish_preload()`, que busca
## `/root/Settings` y `/root/DiagnosticsLog` por ruta absoluta. Con la camara
## fuera del arbol eso imprime "Can't use get_node() with absolute paths from
## outside the active scene tree" por stderr y sigue - es ruido de la prueba, no
## un fallo, y meterla en el arbol no es alternativa porque su `_ready()` se
## libera sola en cualquier ruta que no sea un cambio de escena de verdad.
##
## Run with:
##   godot --headless --path . --script tools/test_sweep_covers_every_sequence.gd

const CAMERA := "res://lullaby_mod/scripts/lullaby/lullaby_preload_camera.gd"

## Los tamaños de grupo de Chimera, contados sobre `sng_chimera.tscn`: las claves
## de `Camera3D:position` de `precache` y de cada `extra_sweep_animations`, en
## ese orden. Fijos aqui a proposito - si la escena cambia y esta prueba deja de
## describirla, lo que hay que revisar es el reparto, no el numero.
const CHIMERA_GROUPS: Array[int] = [15, 4, 13, 16, 16, 4, 5, 2, 7]

## Los fotogramas que Chimera tuvo de verdad, del log del dispositivo
## (`extra=30 frames`). El presupuesto real, no uno holgado.
const CHIMERA_FRAMES := 30

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var script: GDScript = load(CAMERA)
	if not _check(script != null, "lullaby_preload_camera.gd carga"):
		_finish()
		return

	# SIN meterlo en el arbol: su `_ready()` se libera solo en cualquier ruta que
	# no sea un cambio de escena de verdad.
	var cam: Node = script.new()

	_check(script.get_script_constant_map().has("SWEEP_TAIL_SECONDS"),
		"existe SWEEP_TAIL_SECONDS, el presupuesto de la cola")

	# --- Chimera: nueve grupos, 82 poses, 30 fotogramas ---
	_load_groups(cam, CHIMERA_GROUPS)
	cam.call("_build_sweep_order")

	var order: PackedInt32Array = cam.get("_sweep_order")
	var total: int = 0
	for n in CHIMERA_GROUPS:
		total += n

	_check(order.size() == total,
		"el orden coloca las %d poses (%d)" % [total, order.size()])

	var seen: Dictionary = {}
	for idx in order:
		_check_once(not seen.has(idx), "sin repetidos en el orden")
		seen[idx] = true
	_check(seen.size() == total, "y cada pose exactamente una vez")

	# Lo que importa: el PREFIJO que Chimera llega a servir.
	var hit: Dictionary = _groups_touched(order, CHIMERA_FRAMES, CHIMERA_GROUPS)
	_check(hit.size() == CHIMERA_GROUPS.size(),
		"en %d fotogramas se tocan las %d secuencias (%d)" % [
			CHIMERA_FRAMES, CHIMERA_GROUPS.size(), hit.size()])

	# El orden viejo, para que el fallo quede medido y no solo contado: servir
	# 0..29 tal cual dejaba seis grupos a cero.
	var straight := PackedInt32Array()
	for i in total:
		straight.append(i)
	var old_hit: Dictionary = _groups_touched(straight, CHIMERA_FRAMES, CHIMERA_GROUPS)
	_check(old_hit.size() == 3,
		"y en orden recto solo se tocaban 3 (%d) - es la regresion que esto tapa" % old_hit.size())

	# Aunque los fotogramas escaseen mucho mas, ninguna secuencia se queda fuera
	# antes que las demas: con tantos fotogramas como grupos, estan todas.
	var tight: Dictionary = _groups_touched(order, CHIMERA_GROUPS.size(), CHIMERA_GROUPS)
	_check(tight.size() == CHIMERA_GROUPS.size(),
		"con solo %d fotogramas siguen saliendo las %d" % [
			CHIMERA_GROUPS.size(), CHIMERA_GROUPS.size()])

	# --- La tienda: un solo grupo, byte a byte como antes ---
	var shop: Node = script.new()
	_load_groups(shop, [7])
	shop.call("_build_sweep_order")
	var shop_order: PackedInt32Array = shop.get("_sweep_order")
	var identity := true
	for i in shop_order.size():
		if shop_order[i] != i:
			identity = false
	_check(shop_order.size() == 7 and identity,
		"con un solo grupo el orden es el de siempre, sin tocar la tienda")
	shop.free()

	# --- La cola: revelar del todo ya no termina la pasada ---
	#
	# El otro medio del arreglo. Con el revelado completo y poses sin visitar,
	# `_try_finish()` tiene que negarse - antes entregaba ahi mismo, que es
	# exactamente como Chimera se quedaba en 30 de 82.
	var tail: Node = script.new()
	_load_groups(tail, [3, 3])
	tail.call("_build_sweep_order")
	tail.set("_hidden", [])          # nada oculto: el revelado esta "completo"
	tail.set("_revealed", 0)
	tail.set("_finished", false)
	tail.call("_try_finish")
	_check(not bool(tail.get("_finished")),
		"revelar del todo NO entrega mientras queden poses sin ver")

	# Y al revés: con todas vistas, entrega sin esperar a nada.
	tail.set("_sweep_cursor", 6)
	tail.call("_try_finish")
	_check(bool(tail.get("_finished")),
		"con las 6 poses vistas entrega en el acto")
	tail.free()

	# La cola tampoco puede quedarse: si su presupuesto ya vencio, entrega.
	var spent: Node = script.new()
	_load_groups(spent, [3, 3])
	spent.call("_build_sweep_order")
	spent.set("_hidden", [])
	spent.set("_revealed", 0)
	spent.set("_finished", false)
	var budget_ms: int = int(float(script.get_script_constant_map()["SWEEP_TAIL_SECONDS"]) * 1000.0)
	spent.set("_sweep_tail_msec", Time.get_ticks_msec() - budget_ms - 1)
	spent.call("_try_finish")
	_check(bool(spent.get("_finished")),
		"y con el presupuesto de cola agotado entrega aunque falten poses")
	spent.free()

	# --- Sin poses: no revienta ---
	var empty: Node = script.new()
	empty.call("_build_sweep_order")
	_check(PackedInt32Array(empty.get("_sweep_order")).is_empty(),
		"sin poses el orden queda vacio y no revienta")
	empty.free()

	cam.free()
	_finish()


## Rellena `_sweep_poses` y `_sweep_groups` como lo harian los dos colectores.
## Las poses son de mentira: el orden solo mira indices.
func _load_groups(cam: Node, sizes: Array) -> void:
	var poses: Array[Transform3D] = []
	var groups := PackedInt32Array()
	for n in sizes:
		groups.append(poses.size())
		for _i in int(n):
			poses.append(Transform3D.IDENTITY)
	cam.set("_sweep_poses", poses)
	cam.set("_sweep_groups", groups)


## Que grupos toca el prefijo de `frames` elementos del orden.
func _groups_touched(order: PackedInt32Array, frames: int, sizes: Array) -> Dictionary:
	var hit: Dictionary = {}
	for i in mini(frames, order.size()):
		var idx: int = order[i]
		var start: int = 0
		for g in sizes.size():
			var end: int = start + int(sizes[g])
			if idx >= start and idx < end:
				hit[g] = true
				break
			start = end
	return hit


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - el barrido llega a todas las secuencias")
	quit(1 if _failures > 0 else 0)


var _once: Dictionary = {}

## Para lo que se comprueba dentro de un bucle: cuenta una sola vez.
func _check_once(ok: bool, what: String) -> void:
	if not ok and not _once.has(what):
		_once[what] = true
		_check(false, what)


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
