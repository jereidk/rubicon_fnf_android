# El HUD de phone-call: mirarlo COMO SE JUEGA, sin adelantar el reloj a mano.
#
# test_phone_call_port.gd ya comprueba que el HUD entra en el beat 31, pero lo hace
# rebobinando el AnimationPlayer con `seek()` paso a paso. Eso demuestra que el evento
# existe y que la funcion hace lo que dice; NO demuestra que en una partida de verdad, con
# el reloj corriendo solo, la llamada llegue. Si el reproductor no arranca, o alguien le
# pisa la alfa despues, un arnes que rebobina no se entera.
#
# Esto deja la escena correr y va anotando: posicion del reproductor, alfa del HUD y de las
# notas del jugador. Lo que buscamos es la primera muestra en la que el HUD se ve.
#
#   godot --headless --path . --script tools/animania/harness/phone_hud_probe.gd
extends SceneTree

const LEVEL := "res://songs/phone-call/phone_call.tscn"
## `hud_in` esta en el segundo 12.24 de la pista de metodos, y su fundido dura 0.35.
const UNTIL := 15.0
const SAMPLE := 0.5

var _level: Node = null


func _init() -> void:
	root.ready.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	_level = (load(LEVEL) as PackedScene).instantiate()
	root.add_child(_level)
	await process_frame

	var player: AnimationPlayer = _level.get_node("RubiconLevelClock/AnimationPlayer")
	var hud: Control = _level.get_node("UILayer/UI")
	var lanes: Control = _level.get_node("UILayer/UI/Player")
	var opp: Control = _level.get_node("UILayer/UI/Opponent")
	var events: Node = _level.get_node("PhoneCallEvents")

	print("OUT reproductor: tocando=%s animacion=%s largo=%.2f autoplay=%s" % [
		str(player.is_playing()), player.current_animation,
		player.current_animation_length, player.autoplay])
	print("OUT anclajes: jugador %.0f, oponente %.0f (donde se dibujaron)" % [
		lanes.anchor_left * 1920.0, opp.anchor_left * 1920.0])
	print("OUT %6s  %8s  %6s  %6s" % ["reloj", "posicion", "hud", "notas"])

	var t: float = 0.0
	var next: float = 0.0
	var first_seen: float = -1.0
	while t < UNTIL:
		await process_frame
		t += root.get_process_delta_time()
		if hud.modulate.a > 0.5 and first_seen < 0.0:
			first_seen = t
		if t >= next:
			next += SAMPLE
			print("OUT %6.2f  %8.2f  %6.3f  %6.3f  jugador x=%.0f  oponente x=%.0f a=%.2f" % [
				t, player.current_animation_position, hud.modulate.a, lanes.modulate.a,
				lanes.position.x, opp.position.x, opp.modulate.a])

	await process_frame
	var image: Image = root.get_texture().get_image()
	if image != null:
		image.save_png("user://phone_hud.png")
		print("OUT %s" % ProjectSettings.globalize_path("user://phone_hud.png"))

	if first_seen < 0.0:
		print("OUT EL HUD NO APARECE en %.0f s de partida" % UNTIL)
	else:
		print("OUT el HUD aparece a los %.2f s" % first_seen)
	print("OUT first_time(hud_in) sigue libre: %s" % str(
		events.module.first_time(&"hud_in")))
	quit()
