extends SceneTree

## Un rect de efecto silenciado NO vuelve a dibujarse porque una pista lo encienda.
##
## El fallo que cubre no da error de ninguna clase y se ve verde leyendo el
## codigo. `_hide_if_it_draws_nothing()` escondia el nodo una vez, al aplicar el
## ajuste, y ademas se saltaba a los que en ese instante estaban invisibles.
## Chimera's `UILayer/NTSC` esta authoreado `visible = false` y lo encienden
## CUATRO pistas de animacion a mitad de cancion, asi que el escondite no le
## llegaba a tocar: al aplicarse estaba oculto, y cuando una pista lo encendia
## ya nadie miraba.
##
## Lo que queda entonces es un ColorRect transparente SIN material dibujandose a
## pantalla completa, que no produce un pixel y cuesta un relleno entero. El log
## del dispositivo lo tiene medido en la entrada a Chimera con sha_fx=off:
##
##     over=5.1x(n=9 top=UILayer/NTSC@1.0x)
##     relleno: UILayer/NTSC@1.00x a=0.00, UILayer/RainParent/Rain@1.00x a=0.00
##
## Dos capas a 1.15 Mpx cada una en un g53, por nada.
##
## Se prueba corriendo, no leyendo, porque lo que hay que demostrar es que
## sobrevive a que OTRO escriba `visible = true` despues - que es exactamente lo
## que la version anterior no hacia y parecia que si.
##
## Run with:
##   godot --headless --path . --script tools/test_effect_rect_stays_muted.gd

const SETTINGS := "res://menus/settings.gd"
const NTSC := "res://lullaby_mod/resources/shaders/shd_ntsc_shader.gdshader"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var script: GDScript = load(SETTINGS)
	if not _check(script != null, "settings.gd carga"):
		_finish()
		return

	var paths: Variant = script.get_script_constant_map().get("EFFECT_SHADER_PATHS")
	_check(paths != null and Array(paths).has(NTSC),
		"shd_ntsc_shader sigue en EFFECT_SHADER_PATHS")

	var shader: Shader = load(NTSC) as Shader
	if not _check(shader != null, "el shader NTSC carga"):
		_finish()
		return

	# SIN meterlo en el arbol. Su `_ready` aplica los ajustes, y aplicarlos
	# llama a `_restore_effect_shaders()`, que suelta justo las conexiones que
	# esta prueba quiere observar. Con el host dentro del arbol la prueba fallaba
	# midiendo su propio montaje: `conexiones=1` tras el strip y `0` al
	# fotograma siguiente, sin que el arreglo tuviera nada que ver.
	var host: Node = script.new()

	# Un ColorRect como el de Chimera: transparente, con el shader de efecto, y
	# authoreado INVISIBLE - que es el caso que se colaba.
	var rect := ColorRect.new()
	rect.color = Color(0, 0, 0, 0)
	rect.visible = false
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	root.add_child(rect)

	host.call("_strip_shader_material_property", rect, &"material")

	_check(rect.material == null, "el material se quita")
	_check(is_zero_approx(rect.size.x) and is_zero_approx(rect.size.y),
		"y el rect queda sin tamaño, o sea sin rasterizar nada (%s)" % rect.size)

	# Lo que hace la pista de animacion a mitad de cancion. Ya no hay que
	# reponer nada: encenderlo no le devuelve el tamaño.
	rect.visible = true
	await process_frame
	_check(is_zero_approx(rect.size.x) and is_zero_approx(rect.size.y),
		"encenderlo NO le devuelve el tamaño (%s)" % rect.size)
	_check(rect.visible,
		"y no le peleamos el `visible` a la pista: sigue como ella lo dejo")

	# Al volver a encender los efectos, recupera su geometria exacta.
	host.call("_restore_effect_shaders")
	_check(rect.material != null, "restaurar devuelve el material")
	await process_frame
	_check(rect.size.x > 0.0 and rect.size.y > 0.0,
		"y le devuelve el tamaño que tenia (%s)" % rect.size)

	rect.free()
	host.free()
	_finish()


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - un rect de efecto silenciado no vuelve solo")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
