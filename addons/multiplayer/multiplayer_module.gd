extends Node
class_name MultiplayerModule
## Red P2P 1v1 para escenas con RubiconLevel. Un lado hace de host y el otro
## de cliente; cada uno controla UN controller local y recibe los hits del
## otro en el controller remoto.
##
## Arquitectura verificada contra el source:
##   - RubiconLevelNoteHandler es @abstract; la implementacion concreta del
##     test es RubiconLevelManiaNoteHandler, cuyo get_unique_id() devuelve
##     "mania_lane<N>". Por eso HANDLER_ID_FMT = "mania_lane%d".
##   - _press(event) hace toda la logica de hit local (avanza note_hit_index
##     sobre notas ya pasadas, encuentra el proximo dentro de la ventana,
##     llama hit_note() y emite just_pressed / handler_just_pressed).
##     Por eso el lado remoto simula un _press(fake_event): replica el
##     comportamiento sin reimplementar la seleccion de nota.
##   - El "índice de la nota" no viaja por RPC: cada lado lo recalcula con
##     SU propio clock. Funciona mientras los AnimationPlayers esten
##     arrancados al mismo tiempo (que coordinamos abajo).
##
## Como sincronizamos el arranque:
##   - El .tscn de multiplayer tiene autoplay = "" en el AnimationPlayer.
##   - Los dos clientes se conectan y esperan.
##   - El host manda un RPC con un timestamp ABSOLUTO (unix time) en el que
##     arranca la cancion. Los dos usan Time.get_unix_time_from_system(),
##     que es comun a los dos procesos.
##   - Cada lado espera hasta ese timestamp y llama play("scene"). Drift
##     tipico: pocos ms, dentro del judgment window.

# ============================================================================
# Configuracion (todas las props exportadas para editar desde el editor)
# ============================================================================

@export var controller_local : RubiconLevelNoteController
@export var controller_remote : RubiconLevelNoteController

## Formato del id del handler dentro del controller. Default para el addon
## rubicon_mania: "mania_lane0", "mania_lane1", ...
@export var handler_id_fmt : String = "mania_lane%d"

## Cantidad de lanes.
@export var lane_count : int = 4

## Puerto UDP de ENet.
@export var port : int = 12345

## IP del host (solo cliente).
@export var host_address : String = "127.0.0.1"

## True = host, false = cliente.
@export var is_host : bool = false

## Delay antes de arrancar la cancion (segundos). Da tiempo a que el
## cliente establezca el peer y termine de cargar la escena.
@export var start_delay_sec : float = 3.0

## Acciones de input mapeadas a lane index. ui_left → 0, ui_down → 1,
## ui_up → 2, ui_right → 3. Mismo orden que las lanes del chart de test.
const LANE_ACTIONS : Array[StringName] = [
	&"ui_left", &"ui_down", &"ui_up", &"ui_right",
]

# ============================================================================
# Estado
# ============================================================================

signal peer_connected()
signal peer_disconnected()
signal song_started()

var _peer : ENetMultiplayerPeer
var _remote_peer_id : int = 0
var _started : bool = false
var _song_target_unix : float = 0.0


func _ready() -> void:
	# Override de is_host por cmdline. Util para lanzar dos instancias
	# locales desde el mismo .tscn sin duplicar escenas:
	#   godot --path . -- --host
	#   godot --path . -- --client
	# Sin args, usa el valor exportado en la escena.
	var args := OS.get_cmdline_user_args()
	if "--host" in args:
		is_host = true
	elif "--client" in args:
		is_host = false

	# Auto-detectar controllers por nombre si no fueron asignados. En el
	# test son "Player" (derecha) y "Opponent" (izquierda).
	if controller_local == null:
		controller_local = find_child("Player", true, false) as RubiconLevelNoteController
	if controller_remote == null:
		controller_remote = find_child("Opponent", true, false) as RubiconLevelNoteController

	if controller_local == null or controller_remote == null:
		push_error("[Multiplayer] no encontre los controllers (Player / Opponent)")
		set_process_input(false)
		return

	# Desactivar autoplay y inputs en los dos. El modulo es el unico que
	# toca input.
	controller_local.autoplay = false
	controller_local.disable_inputs = true
	controller_remote.autoplay = false
	controller_remote.disable_inputs = true

	# Frenar el AnimationPlayer si arranco por autoplay (por si el .tscn
	# no lo tenia desactivado). El .tscn de multiplayer ya lo trae en "".
	var clock := controller_local.get_level_clock()
	if clock != null and clock.animation_player != null and clock.animation_player.is_playing():
		clock.animation_player.stop()
		clock.animation_player.autoplay = ""

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	if is_host:
		_start_host()
	else:
		_start_client()


# ============================================================================
# Setup de red
# ============================================================================

func _start_host() -> void:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, 1)
	if err != OK:
		push_error("[Multiplayer] create_server(%d) fallo: %d" % [port, err])
		return
	multiplayer.multiplayer_peer = _peer
	# En ENet el server tiene id 1.
	_remote_peer_id = 0  # todavia no hay cliente
	print("[Multiplayer] HOST escuchando en puerto %d (mi id = %d)" % [port, multiplayer.get_unique_id()])


func _start_client() -> void:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(host_address, port)
	if err != OK:
		push_error("[Multiplayer] create_client(%s:%d) fallo: %d" % [host_address, port, err])
		return
	multiplayer.multiplayer_peer = _peer
	# En ENet el server siempre es 1. Este cliente no conoce su id hasta
	# conectarse, pero el server siempre es 1.
	_remote_peer_id = 1
	print("[Multiplayer] CLIENTE conectando a %s:%d" % [host_address, port])


func _on_connected_to_server() -> void:
	print("[Multiplayer] conectado al servidor (mi id = %d)" % multiplayer.get_unique_id())
	peer_connected.emit()


func _on_connection_failed() -> void:
	push_error("[Multiplayer] conexion fallida")


func _on_server_disconnected() -> void:
	print("[Multiplayer] servidor desconectado")
	peer_disconnected.emit()


func _on_peer_connected(id: int) -> void:
	print("[Multiplayer] peer %d conectado" % id)
	_remote_peer_id = id
	peer_connected.emit()
	if is_host:
		_schedule_start()


func _on_peer_disconnected(id: int) -> void:
	print("[Multiplayer] peer %d desconectado" % id)
	peer_disconnected.emit()


# ============================================================================
# Sincronizacion de arranque
# ============================================================================

## El host espera start_delay_sec y manda la orden de arranque a todos con
## un timestamp absoluto de unix time. Los dos lados esperan hasta ese
## timestamp y arrancan el AnimationPlayer en el mismo momento.
func _schedule_start() -> void:
	await get_tree().create_timer(start_delay_sec).timeout
	# 0.5s extra de margen para que el RPC llegue y el cliente procese.
	var target_unix := Time.get_unix_time_from_system() + 0.5
	_rpc_start_song.rpc(target_unix)
	_do_start(target_unix)


@rpc("authority", "call_local", "reliable")
func _rpc_start_song(target_unix: float) -> void:
	_do_start(target_unix)


func _do_start(target_unix: float) -> void:
	if _started:
		return
	_started = true
	_song_target_unix = target_unix

	var wait := target_unix - Time.get_unix_time_from_system()
	if wait > 0.0:
		await get_tree().create_timer(wait).timeout

	var clock := controller_local.get_level_clock()
	if clock == null or clock.animation_player == null:
		push_error("[Multiplayer] controller local sin level clock")
		return

	clock.animation_player.play(&"scene")
	print("[Multiplayer] cancion arrancada en unix=%.3f" % Time.get_unix_time_from_system())
	song_started.emit()


# ============================================================================
# Input local
# ============================================================================

func _input(event: InputEvent) -> void:
	if not _started or event.is_echo():
		return
	for lane in mini(lane_count, LANE_ACTIONS.size()):
		var action : StringName = LANE_ACTIONS[lane]
		if event.is_action_pressed(action):
			_on_local_press(lane, event)
		elif event.is_action_released(action):
			_on_local_release(lane, event)


func _on_local_press(lane: int, event: InputEvent) -> void:
	var handler := _get_handler(controller_local, lane)
	if handler == null or not handler._should_process():
		return
	# Aplicar el hit local. _press hace toda la logica de hit_note.
	handler._press(event)
	# Mandar al otro lado. El otro rehace el mismo _press con un event
	# sintetico, y va a calcular el mismo índice si los clocks estan
	# sincronizados.
	_rpc_remote_press.rpc_id(_remote_peer_id, lane)


func _on_local_release(lane: int, event: InputEvent) -> void:
	var handler := _get_handler(controller_local, lane)
	if handler == null or not handler._should_process():
		return
	handler._release(event)
	_rpc_remote_release.rpc_id(_remote_peer_id, lane)


## Id del handler segun el formato. El handler del test es
## RubiconLevelManiaNoteHandler y su get_unique_id() devuelve
## "mania_lane<N>", asi que con handler_id_fmt = "mania_lane%d" matchea.
func _get_handler(controller: RubiconLevelNoteController, lane: int) -> RubiconLevelNoteHandler:
	if controller == null:
		return null
	var handler_id : StringName = StringName(handler_id_fmt % lane)
	if not controller.note_handlers.has(handler_id):
		return null
	return controller.note_handlers[handler_id]


# ============================================================================
# Recepcion de hits remotos
# ============================================================================

@rpc("any_peer", "call_remote", "reliable")
func _rpc_remote_press(lane: int) -> void:
	var handler := _get_handler(controller_remote, lane)
	if handler == null or not handler._should_process():
		return
	var fake := InputEventAction.new()
	fake.action = LANE_ACTIONS[lane]
	fake.pressed = true
	handler._press(fake)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_remote_release(lane: int) -> void:
	var handler := _get_handler(controller_remote, lane)
	if handler == null or not handler._should_process():
		return
	var fake := InputEventAction.new()
	fake.action = LANE_ACTIONS[lane]
	fake.pressed = false
	handler._release(fake)
