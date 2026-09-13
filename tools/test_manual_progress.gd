extends SceneTree

## La barra de carga cubre TAMBIEN la precarga, no solo la carga.
##
## Por que existe
## -------------
## Con `end_manually` la pantalla de carga no se cierra cuando termina la carga:
## se queda puesta hasta que la camara de precarga acaba su barrido. Entrando a
## Chimera en el log 10252-5c5c1817 eso son:
##
##   [ 79.36s] SCENE_OUT                          (sube la pantalla)
##   [126.81s] SCENE_IN   took=47467ms            (carga lista)
##   [166.47s] preload camera finished (38871ms)  (barrido listo)
##   [~167.3s] baja la pantalla
##
## Cuarenta segundos entre la carga y el cierre, a `fps_now=1`, con fotogramas
## sueltos de 251ms y 1138ms. Si la carga se lleva la barra ENTERA, esos cuarenta
## segundos son una barra al 100% que no se mueve delante de un sprite que
## tampoco se mueve, y eso se reporto como cuelgue: "tiene la barra ya casi
## completa ... el Sprite de pantalla sigue ahi ... se queda congelado".
##
## Es una propiedad facil de romper sin notarlo, porque romperla no da ningun
## error: basta con que alguien devuelva el `update_progress(1.0)` de
## `_complete()`, o que la camara deje de llamar a `report_manual_progress()`.
## En los dos casos el juego funciona exactamente igual y la barra vuelve a
## mentir durante cuarenta segundos.
##
## Lee el fuente en vez de ejecutar, por lo mismo que test_gpu_split_turns.gd:
## `SceneChanger` es un autoload y `--script` no da autoloads, y la camara de
## precarga necesita una escena 3D con pipelines de verdad para llegar a
## `_process`.
##
## Run with:
##   godot --headless --path . --script tools/test_manual_progress.gd

const CHANGER := "res://menus/scene_changer.gd"
const CAMERA := "res://lullaby_mod/scripts/lullaby/lullaby_preload_camera.gd"
const SONG := "res://lullaby_mod/scripts/lullaby/lullaby_level_song.gd"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var changer: String = FileAccess.get_file_as_string(CHANGER)
	var camera: String = FileAccess.get_file_as_string(CAMERA)
	var song: String = FileAccess.get_file_as_string(SONG)

	if not _check(not changer.is_empty() and not camera.is_empty()
			and not song.is_empty(), "se leen los tres ficheros"):
		_finish()
		return

	# --- El reparto ---------------------------------------------------------
	_check(changer.contains("const MANUAL_LOAD_SHARE := "),
		"scene_changer declara el reparto de la barra")

	# La carga NO puede escribir 1.0 cuando la pantalla sigue puesta. Esta es la
	# linea concreta que se rompio y la que se volveria a romper.
	_check(not changer.contains("_current_loader.update_progress(1.0)"),
		"la carga ya no escribe 1.0 a pelo")
	_check(changer.contains("var share: float = MANUAL_LOAD_SHARE if awaiting_manual_end else 1.0"),
		"el reparto sale de awaiting_manual_end")
	_check(changer.contains("_blended_progress(progress[0]) * share"),
		"la fase de carga se escala con el reparto")
	_check(changer.contains("_current_loader.update_progress(share)"),
		"y al terminar la carga la barra se queda en el reparto, no llena")

	# --- La segunda mitad ---------------------------------------------------
	var at: int = changer.find("func report_manual_progress")
	if _check(at > 0, "existe report_manual_progress()"):
		var body: String = changer.substr(at, 600)
		_check(body.contains("not awaiting_manual_end"),
			"que no pinta nada fuera de una espera manual")
		_check(body.contains("_current_loader == null"),
			"ni con la pantalla ya cerrada")
		_check(body.contains("MANUAL_LOAD_SHARE\n\t\t+ clampf(fraction, 0.0, 1.0) * (1.0 - MANUAL_LOAD_SHARE)"),
			"y que mapea 0..1 sobre el tramo que queda")

	# --- Quien la alimenta --------------------------------------------------
	_check(camera.contains("_reveal(_batch)\n\t_report_progress()"),
		"la camara reporta en cada lote revelado")
	_check(camera.contains("float(_revealed) / float(_hidden.size())"),
		"y reporta nodos revelados, no tiempo")
	_check(camera.contains("_hidden.is_empty()"),
		"sin dividir entre cero cuando no hay nada que revelar")

	# El orden importa: finish_loading_screen() baja awaiting_manual_end, asi que
	# un 1.0 posterior no se pintaria nunca.
	var tope: int = camera.find("SceneChanger.report_manual_progress(1.0)")
	var cierre: int = camera.find("SceneChanger.finish_loading_screen()")
	_check(tope > 0 and cierre > tope,
		"la barra llega a tope ANTES de cerrar la pantalla")

	# --- Y el audio que sonaba detras ---------------------------------------
	# Misma ventana, mismo reporte: la pantalla sigue puesta y la cancion ya
	# suena. Vive aqui porque es la otra mitad de lo que el jugador vio.
	_check(song.contains("player.stream_paused = get_tree().paused"),
		"la cancion no arranca sonando con el arbol pausado")
	var play_at: int = song.find("player.play(start_time)")
	var pause_at: int = song.find("player.stream_paused = get_tree().paused")
	_check(play_at > 0 and pause_at > play_at,
		"y se retiene justo despues del play(), no antes")

	_finish()


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - la barra cubre carga y precarga, y el audio respeta la pausa")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
