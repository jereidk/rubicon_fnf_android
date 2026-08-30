extends SceneTree

## Reproduce las animaciones de Hex sobre el modelo SOLO, sin la canción.
##
## Por qué separado: la sonda sobre la canción tarda noventa segundos de reloj
## real en llegar al jumpscare, y mezcla dos preguntas en una. Aquí se responde
## la primera sola - ¿las animaciones de Hex funcionan? - cargando `hex.tscn` y
## reproduciéndolas a mano. Si aquí salen bien, el fallo está en el despacho de
## clips de la canción y no en Hex; si salen mal, no hace falta mirar la canción.
##
## Lo que se comprueba no es "¿existe la animación?" - eso ya se sabía leyendo la
## librería - sino si de verdad MUEVE algo. Una animación puede existir, tener
## pistas, y no mover un solo hueso porque sus rutas no resuelven contra este
## árbol: es exactamente el fallo que este port ha tenido media docena de veces,
## y no se ve en la lista de nombres.
##
## Así que se muestrea la pose real: se guarda la transformada de cada hueso del
## Skeleton3D en t=0, se avanza la animación a la mitad y al final, y se cuenta
## cuántos huesos cambiaron. Cero huesos movidos con la animación reproduciéndose
## es el síntoma que describe el reporte - el modelo congelado.
##
## Run with:
##   godot --headless --path . --script tools/harness/probe_hex_model.gd

const HEX := "res://lullaby_mod/assets/funkin/chimera/models/hex/hex.tscn"

## Las que dibujan el jumpscare, más una de control que se sabe que se usa.
const WANTED := ["misc/jumpscare_short", "misc/closeup", "misc/reveal",
	"misc/rest", "misc/walk"]


func _initialize() -> void:
	var packed: PackedScene = load(HEX)
	if packed == null:
		printerr("no carga %s" % HEX)
		quit(1)
		return

	var hex: Node = packed.instantiate()
	root.add_child(hex)

	var player := hex.get_node_or_null(^"AnimationPlayer") as AnimationPlayer
	if player == null:
		printerr("hex.tscn no trae AnimationPlayer en la raiz")
		quit(1)
		return

	print("OUT librerias: %s" % ", ".join(player.get_animation_library_list()))
	var names: PackedStringArray = player.get_animation_list()
	print("OUT %d animaciones" % names.size())

	var skel := _find_skeleton(hex)
	print("OUT skeleton=%s huesos=%d" % [
		skel.name if skel != null else "(ninguno)",
		skel.get_bone_count() if skel != null else 0])

	for name: String in WANTED:
		_check_animation(player, skel, name)

	hex.free()
	quit(0)


## ¿Esta animación mueve huesos de verdad?
func _check_animation(player: AnimationPlayer, skel: Skeleton3D, name: String) -> void:
	if not player.has_animation(name):
		printerr("  FALTA   %s" % name)
		return

	var anim: Animation = player.get_animation(name)
	var tracks: int = anim.get_track_count()

	# Cuántas de sus pistas resuelven contra este árbol. Es la pregunta que
	# separa "existe" de "hace algo".
	var unresolved: int = 0
	for i: int in tracks:
		var path: NodePath = anim.track_get_path(i)
		if player.get_node_or_null(player.root_node) == null:
			continue
		var host: Node = player.get_node(player.root_node)
		if host.get_node_or_null(NodePath(String(path).get_slice(":", 0))) == null:
			unresolved += 1

	# Muestreo a lo largo del TIEMPO, no contra una pose de referencia.
	#
	# La primera version comparaba cada animacion contra la pose que habia
	# dejado la anterior, asi que las medidas no eran independientes y la
	# primera de la lista se comparaba contra la pose de importacion. Daba
	# `jumpscare_short = 7 huesos` y parecia el hallazgo; podia ser solo que
	# esa animacion empiece cerca de la pose por defecto.
	#
	# La pregunta de verdad es si la pose CAMBIA mientras la animacion corre.
	# Eso no depende de contra que se compare.
	var changes: PackedInt32Array = []
	if skel != null:
		player.play(name)
		var prev: Array[Transform3D] = []
		for step: int in 5:
			var at: float = anim.length * (float(step) / 4.0)
			player.seek(at, true)
			player.advance(0.0)
			var pose: Array[Transform3D] = []
			for b: int in skel.get_bone_count():
				pose.append(skel.get_bone_pose(b))
			if step > 0:
				var diff: int = 0
				for b: int in skel.get_bone_count():
					if not pose[b].is_equal_approx(prev[b]):
						diff += 1
				changes.append(diff)
			prev = pose
		player.stop()

	var total: int = 0
	for c: int in changes:
		total += c
	print("OUT  %-22s len=%6.2fs pistas=%3d sin_resolver=%2d  cambios por tramo: %s  (total %d)" % [
		name, anim.length, tracks, unresolved,
		str(changes), total])


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null
