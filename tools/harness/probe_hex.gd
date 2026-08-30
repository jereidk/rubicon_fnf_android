extends Node

## Corre Chimera de verdad y pregunta, cada dos segundos, si el jumpscare pasa.
##
## No renderiza nada, y esa es la idea. La duda es "¿se reproduce el clip?", y
## eso se contesta leyendo el estado del árbol. Rasterizar la casa para
## averiguarlo cuesta ~1.9 segundos por fotograma bajo el rasterizador por
## software de esta máquina - cuatro horas y media para los 145s que harían
## falta - y no diría nada que no diga esto.
##
## Lo que se mira, y por qué cada cosa:
##
##   * qué clip tiene puesto `Sequences/SequencePlayer`. Si nunca pasa a
##     `116_hexstare`, el fallo está en el despacho de clips y Hex es inocente.
##   * qué animación tiene `hex/AnimationPlayer`. Debería pasar a
##     `misc/jumpscare_short` en 114 y a `misc/closeup` en 116.
##   * dónde está `Camera3D`. Es el dato que separa las dos hipótesis: si la
##     cámara se mueve pero Hex no se anima, el problema es de Hex; si no se
##     mueve ninguno de los dos, el clip entero no está corriendo.
##
## `graphics_prefer_cutscene_video` se apaga para que el vídeo del preludio no
## tape la escena viva - aquí interesa lo que hace la escena, no lo que se ve.
##
## Uso:
##   godot --headless --path . res://tools/harness/probe_hex.tscn

var _clock: AnimationPlayer = null
var _seq: AnimationPlayer = null
var _hex: AnimationPlayer = null
var _cam: Node3D = null
var _next: float = 95.0
var _ready_done: bool = false


func _ready() -> void:
	set_process(false)
	var settings: Node = get_node_or_null(^"/root/Settings")
	if settings != null:
		settings.set("graphics_prefer_cutscene_video", false)
	get_tree().change_scene_to_file(
		"res://lullaby_mod/songs/chimera/sng_chimera.tscn")
	_grab.call_deferred()


func _grab() -> void:
	# Dos fotogramas: uno para que el cambio de escena ocurra, otro para que los
	# _ready() de la canción hayan corrido.
	await get_tree().process_frame
	await get_tree().process_frame
	var root: Node = get_tree().current_scene
	if root == null:
		printerr("no hay escena")
		get_tree().quit(1)
		return
	_clock = root.get_node_or_null(^"RubiconLevelClock/AnimationPlayer")
	_seq = root.get_node_or_null(^"Sequences/SequencePlayer")
	_hex = root.get_node_or_null(^"hex/AnimationPlayer")
	_cam = root.get_node_or_null(^"Camera3D")
	print("OUT encontrados: clock=%s seq=%s hex=%s cam=%s"
		% [_clock != null, _seq != null, _hex != null, _cam != null])
	_ready_done = true
	set_process(true)


func _process(_delta: float) -> void:
	if not _ready_done or _clock == null:
		return
	var t: float = _clock.current_animation_position
	if t < _next:
		return
	_next = t + 2.0

	var cam: String = "-"
	if _cam != null:
		var p: Vector3 = _cam.global_position
		cam = "(%7.2f,%6.2f,%7.2f)" % [p.x, p.y, p.z]
	print("OUT t=%6.2f  clip=%-22s hex=%-26s cam=%s" % [
		t,
		_seq.current_animation if _seq != null else "-",
		_hex.current_animation if _hex != null else "-",
		cam])

	if t > 145.0:
		get_tree().quit()
