extends Node

## Que corre en la tienda cada fotograma, en el lado UPDATE y en el lado DRAW.
##
## De donde sale la pregunta y como se lee el log
## ----------------------------------------------
## Dos campos del contador se leen mal con facilidad, y estan explicados en
## lullaby_diagnostics_log.gd:
##
##   proc=  es Performance.TIME_PROCESS, que Godot reinicia una vez por segundo.
##          Es el PEOR fotograma de ese segundo, no el de cada uno ni una media.
##          En la tienda va de 18 a 34ms y eso NO quiere decir 30fps: el
##          fotograma tipico lo dice `median=`, y la tienda mide median=16.6ms,
##          o sea 60fps clavados.
##   script= si es el pase de actualizacion entero - cada `_process` mas el
##          procesado interno de AnimationPlayer y AnimationTree - y en la
##          tienda vale 2 a 4ms.
##
## Y `gpu=` es una marca de tiempo de hardware de verdad: 13,5 a 15ms, constante.
## O sea que el fotograma de la tienda es GPU al 82% del presupuesto de 16,67ms
## y update al 15%. Cualquier trabajo en el lado CPU rinde poco; el que rinde
## esta en el pase de dibujo.
##
## Esta sonda enumera las dos mitades sobre el arbol VIVO, que es la unica forma
## de saber cuales de los 1533 nodos estan realmente activos - `_process` se
## puede apagar con set_process(false) y muchos lo hacen.
##
## Necesita la cache de importacion (.godot/imported); sin ella la tienda no
## carga y la sonda lo dice en vez de fingir.
##
## Uso:
##   godot --headless --path . res://tools/harness/probe_shop_frame.tscn
##   ... -- espera=120

const SHOP := "res://lullaby_mod/rooms/env_collector_shop.tscn"

var _deadline_msec: int = 0
var _shop: Node = null
var _done: bool = false
var _settle_frames: int = 0


func _ready() -> void:
	if _deadline_msec != 0:
		return                      # el vigilante, ver probe_console_deferred.gd

	var wait: float = 120.0
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("espera="):
			wait = a.trim_prefix("espera=").to_float()

	var watcher := Node.new()
	watcher.name = "ShopFrameProbe"
	watcher.set_script(get_script())
	watcher.set("_deadline_msec", Time.get_ticks_msec() + int(wait * 1000.0))
	get_tree().root.add_child.call_deferred(watcher)
	get_tree().change_scene_to_file.call_deferred(SHOP)


func _process(_delta: float) -> void:
	if _deadline_msec == 0 or _done:
		return
	if _shop == null:
		for child in get_tree().root.get_children():
			if child.has_node(NodePath("Environment/Areas")) \
					and child.has_node(NodePath("Viewports")):
				_shop = child
				break
		if _shop == null:
			if Time.get_ticks_msec() > _deadline_msec:
				_done = true
				printerr("OUT la tienda no llego a montarse")
				get_tree().quit(1)
			return

	# Unos fotogramas para que los cargadores diferidos monten y los `_ready()`
	# se hayan apagado a si mismos donde toque. Medir en el primer fotograma
	# contaria como activos nodos que se desactivan al arrancar.
	_settle_frames += 1
	if _settle_frames < 30:
		return
	_done = true
	_report()
	get_tree().quit(0)


func _report() -> void:
	var all: Array[Node] = []
	_collect(_shop, all)
	print("OUT arbol de la tienda: %d nodos" % all.size())

	_update_side(all)
	_draw_side(all)
	_animation_side(all)
	_viewport_side(all)


## Lo que corre cada fotograma en la CPU, por script y contado.
func _update_side(all: Array[Node]) -> void:
	var proc: Dictionary = {}
	var phys: Dictionary = {}
	var inp: Dictionary = {}
	var unh: Dictionary = {}
	for n: Node in all:
		if n.is_processing():
			_bump(proc, _who(n))
		if n.is_physics_processing():
			_bump(phys, _who(n))
		if n.is_processing_input():
			_bump(inp, _who(n))
		if n.is_processing_unhandled_input():
			_bump(unh, _who(n))

	_dump("_process        (cada fotograma)", proc)
	_dump("_physics_process(cada paso fisico, 30Hz)", phys)
	_dump("_input          (por evento)", inp)
	_dump("_unhandled_input(por evento)", unh)


## Lo que se dibuja: el pase 3D, el 2D y de que se componen.
func _draw_side(all: Array[Node]) -> void:
	var vis3d_on: int = 0
	var vis3d_off: int = 0
	var by_class3d: Dictionary = {}
	var surfaces: int = 0
	var canvas_on: int = 0
	var canvas_off: int = 0
	var by_class2d: Dictionary = {}
	var lights: int = 0
	var lights_on: int = 0

	for n: Node in all:
		if n is VisualInstance3D:
			var vis: bool = (n as Node3D).is_visible_in_tree()
			if vis:
				vis3d_on += 1
				_bump(by_class3d, n.get_class())
			else:
				vis3d_off += 1
			if n is MeshInstance3D:
				var m: Mesh = (n as MeshInstance3D).mesh
				if m != null and vis:
					surfaces += m.get_surface_count()
			if n is Light3D:
				lights += 1
				if vis:
					lights_on += 1
		elif n is CanvasItem:
			if (n as CanvasItem).is_visible_in_tree():
				canvas_on += 1
				_bump(by_class2d, n.get_class())
			else:
				canvas_off += 1

	print("\nOUT === DIBUJO ===")
	print("  3D visibles: %d (ocultos %d)   superficies: %d   luces: %d/%d encendidas"
		% [vis3d_on, vis3d_off, surfaces, lights_on, lights])
	_dump("  3D por clase", by_class3d)
	print("  2D visibles: %d (ocultos %d)" % [canvas_on, canvas_off])
	_dump("  2D por clase", by_class2d)


## Los AnimationPlayer/AnimationTree, que corren DENTRO del mismo pase que
## `_process` y por eso entran en `script=` del log.
func _animation_side(all: Array[Node]) -> void:
	var players: int = 0
	var playing: int = 0
	var trees: int = 0
	var trees_active: int = 0
	var tracks_playing: int = 0
	var who_plays: Dictionary = {}
	for n: Node in all:
		if n is AnimationPlayer:
			players += 1
			var ap := n as AnimationPlayer
			if ap.is_playing():
				playing += 1
				_bump(who_plays, "%s : %s" % [_shop.get_path_to(n), ap.current_animation])
				var anim: Animation = ap.get_animation(ap.current_animation)
				if anim != null:
					tracks_playing += anim.get_track_count()
		elif n is AnimationTree:
			trees += 1
			if (n as AnimationTree).active:
				trees_active += 1

	print("\nOUT === ANIMACION (dentro del pase de update) ===")
	print("  AnimationPlayer: %d, reproduciendo %d (%d pistas en curso)"
		% [players, playing, tracks_playing])
	print("  AnimationTree:   %d, activos %d" % [trees, trees_active])
	_dump("  reproduciendo ahora", who_plays)


## Los SubViewport, que son un pase de dibujo entero cada uno.
func _viewport_side(all: Array[Node]) -> void:
	print("\nOUT === SUBVIEWPORTS (cada uno es otro pase de dibujo) ===")
	var total_px: int = 0
	var always: int = 0
	for n: Node in all:
		if n is SubViewport:
			var sv := n as SubViewport
			var px: int = sv.size.x * sv.size.y
			var mode: String = ["DISABLED", "ONCE", "WHEN_VISIBLE", "WHEN_PARENT_VISIBLE", "ALWAYS"][sv.render_target_update_mode]
			if sv.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
				always += 1
				total_px += px
			elif sv.render_target_update_mode == SubViewport.UPDATE_WHEN_VISIBLE \
					or sv.render_target_update_mode == SubViewport.UPDATE_WHEN_PARENT_VISIBLE:
				total_px += px
			print("  %-52s %5dx%-5d %8.2f Mpx  %s  3d=%s"
				% [_shop.get_path_to(n), sv.size.x, sv.size.y, px / 1e6, mode,
					"off" if sv.disable_3d else "ON"])
	print("  suma de los que se redibujan: %.2f Mpx  (%d en ALWAYS)"
		% [total_px / 1e6, always])


func _who(n: Node) -> String:
	var s: Script = n.get_script() as Script
	if s == null:
		return "(sin script) %s" % n.get_class()
	return s.resource_path.get_file()


func _bump(d: Dictionary, k: String) -> void:
	d[k] = int(d.get(k, 0)) + 1


func _dump(title: String, d: Dictionary) -> void:
	var keys: Array = d.keys()
	keys.sort_custom(func(a, b): return d[a] > d[b])
	var total: int = 0
	for k: String in keys:
		total += int(d[k])
	print("\nOUT %s: %d nodos" % [title, total])
	for k: String in keys:
		print("    x%-3d %s" % [int(d[k]), k])


func _collect(node: Node, out: Array[Node]) -> void:
	out.append(node)
	for child in node.get_children():
		_collect(child, out)
