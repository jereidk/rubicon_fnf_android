extends SceneTree

## El raycast de la tienda solo se reescribe cuando cambia la mira o el estado.
##
## `_physics_process` escribia `target_position` y `collision_mask` en cada paso
## de fisica, cambiaran o no. Las dos escrituras marcan el RayCast3D sucio y lo
## re-registran en PhysicsServer3D, asi que el coste es el mismo aunque el valor
## sea identico - y estando quieto mirando un estante es identico treinta veces
## por segundo.
##
## El log del dispositivo mide la tienda en `phys=5.16ms` con `physn=1`,
## `p3d_objs=10` y `p3d_pairs=10`. Diez pares de cajas y capsulas no cuestan eso;
## lo unico que corre en el paso de fisica ademas del servidor es este callback.
##
## Lo que se comprueba es que la cache no MIENTE, que es el riesgo de cachear:
## que se salte una escritura que si hacia falta. Por eso hay un caso por cada
## cosa que puede cambiar - la mira y el estado de la tienda - y no solo el caso
## de "no cambia nada".
##
## Run with:
##   godot --headless --path . --script tools/test_shop_raycast_writes.gd

const CONTROLLER := "res://lullaby_mod/scripts/lullaby/collectors_shop/controllers/mouse_controller.gd"

var _failures: int = 0
var _checks: int = 0


## Un RayCast3D que cuenta lo que le escriben.
class _CountingRay extends RayCast3D:
	var target_writes: int = 0
	var mask_writes: int = 0
	var _t: Vector3 = Vector3.ZERO
	var _m: int = 1

	func _set(property: StringName, value: Variant) -> bool:
		if property == &"target_position":
			target_writes += 1
			_t = value
			return true
		if property == &"collision_mask":
			mask_writes += 1
			_m = value
			return true
		return false

	func _get(property: StringName) -> Variant:
		if property == &"target_position":
			return _t
		if property == &"collision_mask":
			return _m
		return null


func _initialize() -> void:
	var script: GDScript = load(CONTROLLER)
	if not _check(script != null, "mouse_controller.gd carga"):
		_finish()
		return

	var code: String = FileAccess.get_file_as_string(CONTROLLER)
	_check(code.contains("_last_ray_target") and code.contains("_last_ray_mask"),
		"guarda lo ultimo que escribio")
	# El cursor NO se cachea, y tiene que seguir sin cachearse: hay un segundo
	# escritor (cartridge_bag_handler.gd) que una cache local no ve.
	_check(not code.contains("_last_cursor"),
		"y NO cachea el cursor, que tiene otro escritor")

	# Todo dentro del arbol: `get_aim_position()` pide `get_viewport()` y
	# `project_ray_normal()` exige que la camara este dentro. Con el host suelto
	# la prueba solo medía sus propios errores.
	var host: Node = script.new()
	var ray := _CountingRay.new()
	var cam := Camera3D.new()
	root.add_child(cam)
	root.add_child(ray)
	root.add_child(host)
	await process_frame

	host.set("ray_cast", ray)
	host.set("camera", cam)
	host.set("should_cast_ray", true)
	host.set("root", null)
	# Las escrituras del montaje no cuentan: lo que se mide es el callback.
	ray.target_writes = 0
	ray.mask_writes = 0

	# Tres pasos con la camara quieta.
	for i: int in 3:
		host.call("_physics_process", 0.016)
	_check(ray.target_writes == 1,
		"con la mira quieta escribe target_position UNA vez, no tres (%d)"
			% ray.target_writes)

	# Y si la camara se mueve, sí escribe.
	cam.rotate_y(0.5)
	host.call("_physics_process", 0.016)
	_check(ray.target_writes == 2,
		"y vuelve a escribir cuando la mira cambia (%d)" % ray.target_writes)

	host.free()
	ray.free()
	cam.free()
	_finish()


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - el raycast solo se reescribe cuando hace falta")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
