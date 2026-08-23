extends SceneTree

## Un `resume_typing()` que llega antes que su `[pause]` no se puede tirar.
##
## `sequence_intro` es una pista de 78 claves - 41 `resume_typing` y 35
## `next_line` a tiempos fijos, cortados contra el audio del Collector - y el
## texto y la animacion avanzan del mismo `delta`. Eso va bien a framerate
## estable y es asimetrico en cuanto un frame se alarga:
##
##   el AnimationPlayer dispara TODAS las claves dentro de ese delta, mientras
##   `_process` teclea como mucho UNA pausa por frame (el bucle rompe en
##   cuanto `typing_paused` se pone a true).
##
## Cualquier frame lo bastante largo como para cruzar dos resumes pierde al
## menos uno, y perderlo es definitivo: la linea llega a su siguiente
## `[pause]`, se para, y no queda nada que la reanude. Se queda congelada hasta
## el siguiente `next_line`, que son segundos. Las lineas 23, 29 y 30 del tour
## tienen diez, seis y cinco pausas.
##
## La tienda es justo donde estan los frames largos - esta misma sesion
## registro frames sueltos de 17.7s dentro de su precache.
##
## Lo que este guard NO afirma: que sea un bug de la traduccion. Se simulo el
## tour entero con los tiempos reales de la pista, el `seconds_per_character`
## animado (0.025-0.07) y las 36 lineas en los dos idiomas, y **no hay ni una
## colision de `next_line` ni una pausa sin resume** en ninguno de los dos. La
## longitud del espanol no es la causa; el frame largo si.
##
##   godot --headless --path . --script tools/test_dialogue_resume.gd

const DIALOGUE := "res://lullaby_mod/scripts/lullaby/collectors_shop/dialogue/CollectorDialogue.gd"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var src: String = _read(DIALOGUE)
	_check(src != "", "el script se lee")

	_check(_has_statement(src, "if not typing_paused:")
			and _has_statement(src, "_pending_resumes += 1"),
		"un resume que llega sin pausa activa se guarda")
	_check(_has_statement(src, "if _pending_resumes > 0:")
			and _has_statement(src, "_pending_resumes -= 1"),
		"y la siguiente pausa lo gasta en vez de pararse")
	_check(src.count("_pending_resumes = 0") >= 3,
		"se limpia al empezar linea, al terminarla y al cerrar el dialogo")

	# El comportamiento, sobre el nodo real. `type_next_character()` escribe
	# en `text`, asi que hace falta el hijo que el @onready espera.
	var script: GDScript = load(DIALOGUE)
	_check(script != null, "el script carga")
	if script == null:
		_finish()
		return

	var node: Control = script.new()
	var label := RichTextLabel.new()
	label.name = "Text"
	node.add_child(label)
	var skip := RichTextLabel.new()
	skip.name = "Skip Text"
	node.add_child(skip)
	var bg := TextureRect.new()
	bg.name = "Background"
	node.add_child(bg)
	node._ready()

	# Una linea con dos pausas, y los dos resumes llegando ANTES de que el
	# tecleo alcance la primera - que es lo que hace un frame largo.
	node.dialogue_lines = ["ab[pause]cd[pause]ef"] as Array[String]
	node.current_line_index = 0
	node.show_line()

	node.resume_typing()
	node.resume_typing()
	_check(node._pending_resumes == 2, "dos resumes adelantados se acumulan")

	for _i: int in 8:
		node.type_next_character()
	_check(not node.typing_paused,
		"el tecleo atraviesa las dos pausas en vez de congelarse")
	_check(node.is_typing == false, "y la linea termina")

	# Y el caso normal, que es el que no puede cambiar: sin resume adelantado,
	# la pausa para de verdad.
	node.dialogue_lines = ["ab[pause]cd"] as Array[String]
	node.current_line_index = 0
	node.show_line()
	node.type_next_character()
	node.type_next_character()
	node.type_next_character()
	_check(node.typing_paused, "sin credito, la pausa sigue parando la linea")
	node.resume_typing()
	_check(not node.typing_paused and node._pending_resumes == 0,
		"y un resume normal la reanuda sin dejar credito suelto")

	# show_line() tiene que tirar los creditos de la linea anterior, o una
	# pausa de la siguiente se saltaria sola.
	node.resume_typing()
	node.resume_typing()
	node.dialogue_lines = ["xy[pause]z"] as Array[String]
	node.current_line_index = 0
	node.show_line()
	_check(node._pending_resumes == 0,
		"los creditos no cruzan de una linea a la siguiente")

	node.free()
	_finish()


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
