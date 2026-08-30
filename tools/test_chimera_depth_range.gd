extends SceneTree

## El plano lejano de Chimera esta ajustado a la escena, no al defecto de Godot.
##
## `Camera3D` no autoraba `far`, asi que corria con los 4000 por defecto sobre una
## escena cuyo origen mas lejano esta a 33.6 unidades del centro - un rango de
## profundidad 120 veces mayor del que hace falta.
##
## Hay que ser honesto con lo que esto compra: Godot 4 usa reverse-Z, y con un
## buffer de profundidad en coma flotante el plano lejano casi no afecta a la
## precision - la que manda es `near`. Donde si suma es en un buffer unorm de 24
## bits, que es lo que dan muchos moviles. O sea que esto es higiene con un
## posible beneficio en el dispositivo, no un arreglo demostrado de nada.
##
## `near` se dejo en su defecto A PROPOSITO. Es la palanca que de verdad importa
## con reverse-Z, y subirlo recorta lo que este muy cerca de la camara. Para
## saber cuanto se puede subir hace falta la distancia real de la camara a la
## geometria, y una sonda por AABB no vale: la camara esta DENTRO de la casa, asi
## que 90 de sus 107 poses caen dentro del AABB de alguna malla y la medida sale
## cero. Sin ese dato no se toca.
##
## Lo que este guard protege es la premisa, no el numero: si alguien mete en la
## escena algo lejos de verdad - un cielo, un exterior, una silueta a distancia -
## los 200 empezarian a recortarlo, y esto se entera antes que el jugador.
##
## Run with:
##   godot --headless --path . --script tools/test_chimera_depth_range.gd

const CHIMERA := "res://lullaby_mod/songs/chimera/sng_chimera.tscn"

## Con cuanto margen sobre la extension real de la escena tiene que quedarse el
## plano lejano. La escena mide 33.6 y el `far` son 200: seis veces.
const MIN_HEADROOM := 3.0

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var scene: String = _read(CHIMERA)
	if not _check(not scene.is_empty(), "sng_chimera.tscn se lee"):
		_finish()
		return

	var block: String = _node_block(scene, '[node name="Camera3D" type="Camera3D" parent="."')
	if not _check(not block.is_empty(), "la Camera3D de la cancion sigue ahi"):
		_finish()
		return
	_check(block.contains("current = true"), "y sigue siendo la camara activa")

	var far: float = _number(block, "far", -1.0)
	_check(far > 0.0, "autora un `far` en vez de heredar los 4000 por defecto (%s)" % far)

	# La extension real, del propio fichero: el origen mas lejano de cualquier
	# transform de la escena.
	var extent: float = _scene_extent(scene)
	print("       extension de la escena: %.1f unidades, far = %.1f" % [extent, far])
	_check(extent > 0.0, "se puede medir la extension de la escena")
	_check(far >= extent * MIN_HEADROOM,
		"el far deja al menos %dx de margen sobre la escena (%.1f >= %.1f)" % [
			int(MIN_HEADROOM), far, extent * MIN_HEADROOM])
	_check(far < 4000.0, "y sigue por debajo del defecto que se quiso dejar atras")

	# `near` sin autorar es deliberado - ver la cabecera. Si alguien lo pone, que
	# sea leyendo esto y no de pasada.
	_check(_number(block, "near", -1.0) < 0.0,
		"`near` sigue sin autorar: subirlo recorta y nadie ha medido cuanto se puede")

	_finish()


## El extent que usa `test`: el origen mas lejano de cualquier Transform3D del
## fichero. Es la misma medida con la que se eligio el 200.
func _scene_extent(scene: String) -> float:
	var most: float = 0.0
	for line in scene.split("\n"):
		if not line.begins_with("transform = Transform3D("):
			continue
		var inner: String = line.substr(24, line.rfind(")") - 24)
		var parts: PackedStringArray = inner.split(",")
		if parts.size() < 12:
			continue
		for i in range(9, 12):
			most = maxf(most, absf(float(parts[i].strip_edges())))
	return most


func _node_block(scene: String, header: String) -> String:
	var at: int = scene.find(header)
	if at < 0:
		return ""
	var close: int = scene.find("\n[", at + 1)
	return scene.substr(at, -1 if close < 0 else close - at)


func _number(block: String, key: String, fallback: float) -> float:
	var at: int = block.find("\n%s = " % key)
	if at < 0:
		return fallback
	var start: int = at + key.length() + 4
	var close: int = block.find("\n", start)
	return fallback if close < 0 else float(block.substr(start, close - start).strip_edges())


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - el rango de profundidad va a escala de la escena")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
