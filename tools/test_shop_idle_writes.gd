extends SceneTree

## La tienda quieta no reescribe cada fotograma lo que no ha cambiado.
##
## Por que existe
## -------------
## La tienda va a GPU, no a script: `gpu=12.53-13.38ms` contra `script=2.59-
## 3.47ms` en el log del 14-09. Eso NO deja al codigo fuera - el codigo decide
## cuanto se ensucia cada fotograma, y lo sucio es lo que el renderizador tiene
## que rehacer. Tres sitios lo hacian sin condicion:
##
##   prp_notepad.gd    set_shader_parameter("appear_progress", ...)
##                     sube un uniforme y marca el material sucio. `_appear_mult`
##                     arranca en 0 y la pinza clava el valor al terminar la
##                     aparicion, asi que el caso NORMAL era subir el mismo
##                     numero sesenta veces por segundo.
##
##   prp_notepad.gd    child.label_settings.font_color = ...
##                     por cada hijo del SubViewport y en cada fotograma. Escribir
##                     un LabelSettings emite `changed`, lo que marca la Label
##                     sucia y obliga a redibujar el SubViewport entero - por unos
##                     colores que solo cambian al leer una entrada nueva.
##
##   touch_aim_reticle queue_redraw() incondicional, rehaciendo un arco de 24
##                     segmentos y un circulo cada fotograma. Y es el caso peor:
##                     en FREE_LOOK `get_aim_position()` devuelve el centro de la
##                     pantalla, o sea que la mira esta quieta.
##
## Ninguna de las tres da error al volver: el juego se ve exactamente igual y
## solo cuesta mas. Por eso hay guard.
##
## Run with:
##   godot --headless --path . --script tools/test_shop_idle_writes.gd

const NOTEPAD := "res://lullaby_mod/scripts/lullaby/collectors_shop/props/prp_notepad.gd"
const RETICLE := "res://lullaby_mod/scripts/lullaby/collectors_shop/controllers/touch_aim_reticle.gd"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var notepad: String = FileAccess.get_file_as_string(NOTEPAD)
	var reticle: String = FileAccess.get_file_as_string(RETICLE)
	if not _check(not notepad.is_empty() and not reticle.is_empty(),
			"los dos ficheros se leen"):
		_finish()
		return

	# --- El uniforme -------------------------------------------------------
	_check(notepad.contains("if not is_equal_approx(next_progress, appear_progress):\n\t\tshader_mat.set_shader_parameter(\"appear_progress\", next_progress)"),
		"el uniforme de aparicion solo se sube cuando cambia")

	# --- El color de las etiquetas -----------------------------------------
	_check(notepad.contains("if child.label_settings.font_color != want:"),
		"el color de cada etiqueta solo se escribe cuando es otro")
	# Y que no quede ninguna escritura suelta al lado de la guardada.
	_check(notepad.count("label_settings.font_color = ") == 1,
		"y no queda ninguna escritura sin condicion (%d)"
			% notepad.count("label_settings.font_color = "))

	# --- El redibujado de la mira ------------------------------------------
	var at: int = reticle.find("func _process")
	if _check(at > 0, "la mira tiene _process()"):
		# Sin comentarios. La busqueda es textual y el comentario que EXPLICA
		# por que el redibujado va guardado nombra `queue_redraw()` varias
		# lineas antes de la guarda - asi que sobre el fichero crudo esta
		# comprobacion fallaba por su propia prosa. Ya paso una vez en
		# test_teardown_before_load.gd, con la misma forma.
		var body: String = _strip_comments(reticle.substr(at, 1800))
		_check(body.contains("if hovering != _drawn_hover:"),
			"la mira solo se redibuja cuando cambia el hover")
		var redraw: int = body.find("queue_redraw()")
		var guard: int = body.find("if hovering != _drawn_hover:")
		_check(guard > 0 and redraw > guard,
			"y el queue_redraw() esta dentro de esa condicion")

	# Mover no pide redibujar, pero cambiar de tamaño si: `_draw()` mide desde
	# `size`. Sin esto la mira se quedaria dibujada al tamaño viejo tras un
	# cambio de resolucion, que es el fallo que una optimizacion asi introduce.
	_check(reticle.contains("resized.connect(queue_redraw)"),
		"pero un cambio de tamaño si lo pide")

	# El centinela necesita un tercer estado: "aun no se ha dibujado" no es ni
	# hover ni no-hover, y con un bool el primer dibujado se puede perder.
	_check(reticle.contains("var _drawn_hover: int = -1"),
		"el centinela del hover tiene estado 'aun no'")

	_finish()


## Quita las lineas de comentario enteras y lo que va tras un `#` suelto.
##
## Basta con eso: aqui no hay ningun `#` dentro de una cadena, y un stripper que
## entienda cadenas seria mas codigo del que esta prueba comprueba.
func _strip_comments(code: String) -> String:
	var out: PackedStringArray = []
	for line: String in code.split("\n"):
		var hash_at: int = line.find("#")
		out.append(line if hash_at < 0 else line.substr(0, hash_at))
	return "\n".join(out)


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - la tienda quieta no reescribe lo que no cambia")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
