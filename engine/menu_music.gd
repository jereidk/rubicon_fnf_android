extends Node
## Musica del menu y sonidos de UI del engine, como autoload global.
##
## Reproduce dos canciones en rotacion aleatoria mientras el usuario esta
## en una pantalla de gestion (ModSelector o ModManager). Cada una se
## reproduce completa y al terminar arranca la otra, elegida al azar pero
## nunca la misma dos veces seguidas. Al entrar a un mod, ambas se
## silencian. Al volver al menu, la rotacion continua.
##
## Sobrevive a los change_scene_to_file() porque es un autoload - un nodo
## puesto en cada escena se reiniciaria en cada cambio.
##
## Para que el signal `finished` del AudioStreamPlayer se dispare, hay
## que desactivar el loop de cada stream: los .ogg exportados por defecto
## loopearian y nunca terminarian. Lo hacemos en _prepare_stream().

const TRACKS: Array[String] = [
	"res://resources/music/teatime.ogg",
	"res://resources/music/menu.ogg",
]
const SFX_CONFIRM := "res://resources/sounds/ui/confirm.ogg"
const SFX_CANCEL := "res://resources/sounds/ui/cancel.ogg"
const SFX_SCROLL := "res://resources/sounds/ui/scroll.ogg"

const MUSIC_VOLUME_DB := -6.0
const SFX_VOLUME_DB := -3.0

## Escenas donde la musica debe sonar. Cualquier otra la silencia.
const MENU_SCENES: Array[String] = [
	"mod_selector.tscn",
	"mod_manager.tscn",
]

## Streams ya preparados (loop desactivado). Se cargan una sola vez.
var _tracks: Array[AudioStream] = []
## El que esta sonando ahora, para no repetirlo en la eleccion siguiente.
var _current_track: AudioStream = null

var _confirm_stream: AudioStream
var _cancel_stream: AudioStream
var _scroll_stream: AudioStream

var _music_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next: int = 0

var _last_scene: Node = null
## True cuando el usuario pidio silenciar la musica explicitamente (por
## ejemplo, al entrar a un mod). Distinto de "esta en una escena no-menu":
## en ese caso la musica se pausa pero al volver al menu continua desde
## donde estaba.
var _muted_by_user: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	for path in TRACKS:
		var stream := _try_load(path)
		if stream != null:
			_prepare_stream(stream)
			_tracks.append(stream)

	_confirm_stream = _try_load(SFX_CONFIRM)
	_cancel_stream = _try_load(SFX_CANCEL)
	_scroll_stream = _try_load(SFX_SCROLL)

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = &"Master"
	_music_player.volume_db = MUSIC_VOLUME_DB
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_music_player.finished.connect(_on_track_finished)
	add_child(_music_player)

	for i in 3:
		var p := AudioStreamPlayer.new()
		p.bus = &"Master"
		p.volume_db = SFX_VOLUME_DB
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_sfx_players.append(p)

	call_deferred("_update_for_scene")


## Desactiva el loop de un stream para que `finished` se dispare al
## terminar la cancion. Cada tipo de AudioStream tiene su propia
## propiedad de loop en Godot 4:
##   AudioStreamOggVorbis: loop (bool)
##   AudioStreamMP3:       loop (bool)
##   AudioStreamWAV:       loop_mode (enum)
func _prepare_stream(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = false
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED


func _try_load(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("[MenuMusic] no existe %s" % path)
		return null
	return load(path)


func _process(_delta: float) -> void:
	var current := get_tree().current_scene
	if current != _last_scene:
		_last_scene = current
		_update_for_scene()


## Reproduce o pausa la musica segun la escena actual. Al entrar a un mod
## (cualquier escena que no sea de menu) la silencia; al volver a una de
## menu, arranca la rotacion otra vez.
func _update_for_scene() -> void:
	var current := get_tree().current_scene
	if current == null:
		return
	var path: String = current.scene_file_path
	var in_menu := false
	for s in MENU_SCENES:
		if path.ends_with(s):
			in_menu = true
			break

	if in_menu:
		# Salir del modo "silenciado por el usuario": volvio al menu.
		_muted_by_user = false
		if not _music_player.playing:
			_start_random_track()
		elif _music_player.stream_paused:
			_music_player.stream_paused = false
	else:
		# Entro a un mod. Silenciar de verdad: no pausa.
		stop_music()


## Arranca una cancion al azar, nunca la misma que sono la ultima vez.
func _start_random_track() -> void:
	if _tracks.is_empty():
		return
	var pick: AudioStream = null
	if _tracks.size() == 1:
		pick = _tracks[0]
	else:
		var candidates: Array[AudioStream] = []
		for t in _tracks:
			if t != _current_track:
				candidates.append(t)
		pick = candidates[randi() % candidates.size()]

	_current_track = pick
	_music_player.stream = pick
	_music_player.play()


## Cuando una cancion termina, arranca la otra.
func _on_track_finished() -> void:
	# Si el usuario salio del menu mientras sonaba, no arrancar la
	# siguiente: ya esta silenciado y va a reanudar cuando vuelva.
	if _muted_by_user:
		return
	_start_random_track()


## Fade out y stop. La llama el ModSelector antes de cargar un mod, para
## que el menu no siga sonando encima de la cancion del mod.
func fade_out_music(duration: float = 0.5) -> void:
	if _music_player == null or not _music_player.playing:
		return
	_muted_by_user = true
	var start_db: float = _music_player.volume_db
	var tw := create_tween()
	tw.tween_method(_apply_music_volume, start_db, -60.0, duration)
	tw.tween_callback(_finish_fade_out)


func stop_music() -> void:
	if _music_player == null:
		return
	_music_player.stop()
	_music_player.stream = null
	_music_player.volume_db = MUSIC_VOLUME_DB
	_muted_by_user = true


## Vuelve a subir la musica y arranca la rotacion. Util para pantallas
## que abren un popup encima del menu sin cambiar de escena.
func restore_music() -> void:
	if _music_player == null or _tracks.is_empty():
		return
	_muted_by_user = false
	_music_player.volume_db = MUSIC_VOLUME_DB
	if not _music_player.playing:
		_start_random_track()
	else:
		_music_player.stream_paused = false


func _play_sfx(stream: AudioStream) -> void:
	if stream == null or _sfx_players.is_empty():
		return
	var p := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	p.stream = stream
	p.play()


func play_confirm() -> void:
	_play_sfx(_confirm_stream)


func play_cancel() -> void:
	_play_sfx(_cancel_stream)


func play_scroll() -> void:
	_play_sfx(_scroll_stream)


## Helpers usados por fade_out_music(). Metodos en vez de lambdas
## porque la lambda capturaba _music_player en su closure, y si el
## tween se cancelaba por un cambio de escena la captura quedaba
## freed (Lambda capture at index 0 was freed).
func _apply_music_volume(v: float) -> void:
	if is_instance_valid(_music_player):
		_music_player.volume_db = v


func _finish_fade_out() -> void:
	if is_instance_valid(_music_player):
		_music_player.stop()
		_music_player.stream = null
		_music_player.volume_db = MUSIC_VOLUME_DB
