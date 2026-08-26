extends VisibleOnScreenNotifier3D

## Drives the console SubViewport's update mode from whether the TV is on
## screen, and records every switch in the diagnostics log.
##
## The behaviour is what the scene already did through two direct
## screen_entered/screen_exited -> set_update_mode connections; this only
## takes ownership of them so the switches can be counted.
##
## Why measure instead of just changing it: the shop's periodic 70-150ms
## spikes were suspected to be this gate re-rendering a 640x480 viewport
## on each crossing, but the log does not support that on its own. Ten
## separate spikes carry byte-identical render counters
## (draw=80 prims=13389 objs=267), and a normal 30fps heartbeat carries
## those exact numbers too - so the same GPU work is present with and
## without a spike. The viewport being on only adds ~10 draw calls and
## ~700 primitives, which is far too little to explain a 4x frame.
##
## What is still plausible is FLAPPING: the notifier's AABB is 0.002 units
## thick, so while the camera pans the TV can cross the frustum edge
## repeatedly, and each DISABLED -> ALWAYS switch forces a full re-render.
## That would not show up in any per-frame counter. The MARK lines below
## make it visible: if the next log shows switches clustering around the
## spike timestamps, the gate is implicated; if switches are rare and the
## spikes continue between them, it is ruled out and the search moves on.
##
## What the log DID say, once gpu= was compared against frame=: the shop's
## spikes hold gpu at a flat 13.5ms while the frame runs 68-141ms. That
## number only covers the MAIN viewport - RenderingServer's measured render
## time is per-viewport - so every SubViewport in the scene is GPU work the
## log cannot see. The console carries the big one: console_bg's
## SubViewport is 1440x1080 with own_world_3d, a WorldEnvironment with fog
## and a DirectionalLight3D, i.e. 1.56Mpx of 3D rendered every frame
## against the main viewport's 800x360 (scale 0.50). It is authored inside
## a Control that is never hidden, so it renders for the whole shop
## session - including while the player is free-looking away from the TV
## and this gate has the OUTER viewport disabled.
##
## Hence nested_containers below. Note that setting
## render_target_update_mode on a SubViewport owned by a SubViewportContainer
## does not work: the container overwrites it from its own
## is_visible_in_tree() on every visibility notification (ALWAYS when
## visible, DISABLED when not), so an authored value is inert and a manual
## set survives only until the next visibility change. Verified against
## 4.7.1. Toggling the container's visibility is therefore the supported
## way to switch a nested viewport off, and it is what this does.
##
## This used to manage console_bg's container only, on the reasoning that
## the Home and Credits containers "are already gated correctly by the
## TabContainer hiding their tabs". The device log falsified that: sub_top=
## names Viewports/ConsoleSubViewport/Console/TabContainer/Home/
## IconSubViewport/SubViewport(720x540) as the biggest live SubViewport in
## the shop, at 2.3ms of GPU, with four of seven live. The reasoning had one
## axis too few - the TabContainer gates WHICH TAB is showing, not whether
## the TV is on screen at all, so the Home tab's six icon models kept
## rendering their own 3D world the whole time the player was free-looking
## around the room with the outer viewport already disabled.
##
## Both nested containers are managed now. Credits' is the larger of the
## two on paper (1440x1080 with no stretch_shrink, against Home's 720x540)
## though it is only live while Credits is the open tab.
##
## Restoring them is safe for the reason blanket-showing containers was not:
## visibility is a conjunction. Both of these sit under a TabContainer tab,
## so setting a container's own `visible` back to true re-enables it only if
## the TabContainer is also showing that tab - it cannot open a screen the
## player did not choose, which is what the reverted shader prewarm did.
## Both ship with no `visible` of their own, so true is what they had.

## SubViewport.UpdateMode. Named here rather than passed as the bare 4/0
## the scene connections used, which said nothing about intent.
const UPDATE_DISABLED := 0
const UPDATE_ALWAYS := 4

@export var console_viewport: SubViewport

## Every SubViewportContainer inside the console that owns a nested
## SubViewport, hidden while the TV is off screen so those viewports stop
## rendering. Setting render_target_update_mode on them directly does not
## work - see the note above - so the container's visibility is the lever.
@export var nested_containers: Array[Control] = []

## Cuanto tiene que llevar el TV fuera de pantalla antes de apagar nada.
##
## El FLAPPING que este mismo fichero predijo, confirmado por el log del
## 2026-08-25 con las MARK que se anadieron justo para verlo:
##
##     [438.98s] console viewport on   (switch #1)
##     [439.01s] console viewport off  (switch #2, 30ms since last)
##     [641.36s] console viewport on   (switch #1)
##     [641.43s] console viewport off  (switch #2, 73ms since last)
##
## Treinta y setenta y tres milisegundos. El AABB del notificador tiene 0.002
## unidades de grosor, asi que un movimiento pequeno de camara basta para que el
## TV cruce el borde del frustum varias veces seguidas.
##
## Lo que costaba son los dos sintomas que el jugador reporto juntos, y salen
## del mismo sitio: cada `off` apaga los SubViewport de los iconos y estos se
## quedan NEGROS, y cada `on` fuerza un re-render entero de 1440x1080 mas
## 720x540 de 3D, que es el CONGELON al mover la seleccion.
##
## Medio segundo sobra para un cruce accidental y se queda muy corto frente a lo
## que tarda alguien en apartar la vista de verdad. El coste de pasarse por este
## lado son unos frames de viewport encendido de mas; por el otro era la
## interfaz en negro.
const OFF_DELAY_MSEC := 500

var _switches: int = 0
var _last_switch_msec: int = 0
var _off_timer: SceneTreeTimer = null

func _ready() -> void:
	screen_entered.connect(_on_screen_entered)
	screen_exited.connect(_on_screen_exited)

## Encender va SIN retraso, y la asimetria es el punto: llegar tarde a encender
## se ve -es la interfaz en negro que el jugador esta mirando- y llegar tarde a
## apagar solo cuesta unos frames de GPU que nadie percibe.
func _on_screen_entered() -> void:
	_off_timer = null
	_set_mode(UPDATE_ALWAYS, "on")

func _on_screen_exited() -> void:
	var timer: SceneTreeTimer = get_tree().create_timer(OFF_DELAY_MSEC / 1000.0)
	_off_timer = timer
	timer.timeout.connect(_apagar_si_sigue_fuera.bind(timer))

## Solo apaga si este sigue siendo el ultimo temporizador pedido y el TV sigue
## fuera. Un `screen_entered` por el medio pone `_off_timer` a null y este
## disparo se queda en nada, que es exactamente lo que corta el parpadeo.
func _apagar_si_sigue_fuera(timer: SceneTreeTimer) -> void:
	if _off_timer != timer:
		return
	_off_timer = null
	if is_on_screen():
		return
	_set_mode(UPDATE_DISABLED, "off")

func _set_mode(mode: int, label: String) -> void:
	if console_viewport == null or not is_instance_valid(console_viewport):
		return

	console_viewport.render_target_update_mode = mode

	# The outer viewport keeps its last rendered texture while disabled, so
	# the TV screen still shows the console with the background on it; the
	# frame it comes back, the outer viewport redraws against the nested
	# texture's own last content, which is that same image. Nothing blanks.
	var live: bool = mode == UPDATE_ALWAYS
	for container in nested_containers:
		if container != null and is_instance_valid(container):
			container.visible = live

	_switches += 1
	var now: int = Time.get_ticks_msec()
	var gap: int = now - _last_switch_msec if _last_switch_msec > 0 else -1
	_last_switch_msec = now

	# Autoload, but the shop is opened directly from the editor often enough
	# that this should not hard-depend on it.
	var log_node: Node = get_node_or_null(^"/root/DiagnosticsLog")
	if log_node != null and log_node.has_method("mark"):
		log_node.call("mark", "console viewport %s (switch #%d, %s since last)" % [
			label, _switches, "%dms" % gap if gap >= 0 else "first",
		])
