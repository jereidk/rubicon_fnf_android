# Pone en los dos controladores de notas el chart de la dificultad elegida en el freeplay.
#
# Las escenas de cancion las genera build_song_scene.gd con UNA dificultad cocida dentro
# -su `_build_ui(difficulty)` carga `<cancion>-<dificultad>_{Player,Opponent}.tres` y lo
# guarda en la escena-, y todas las del puerto se generaron con `normal`. El freeplay, en
# cambio, deja elegir: `changeDiff` mueve `currentDifficulty` y la cabecera lo ensena. Sin
# esto, elegir HARD y jugar NORMAL era lo mismo, y desde que el puerto arranca en `hard`
# -que es lo que hace el mod, ver 8v- la pantalla mentia siempre.
#
# En el mod esto no es un nodo: la dificultad viaja como `targetDifficulty` dentro del
# objeto que `LoadingState.loadPlayState` recibe (capsuleOnConfirmDefault, linea 653).
# Aqui viaja igual, en `LoadingScreen.target_difficulty`, y quien la aplica es este nodo
# porque la escena ya esta construida y armada cuando llega.
#
# El cambio se hace en `_ready`, que corre ANTES de que el controlador consuma su chart:
# `chart` es un @export con setter que solo marca `_chart_dirty`, y quien lo lee es el
# `NOTIFICATION_INTERNAL_PROCESS` del controlador, o sea el primer fotograma. Asignar aqui
# llega a tiempo y no hace falta reconstruir ninguna escena.
extends Node

## Las rutas se derivan del chart que la escena YA trae, no de una tabla: si el actual es
## `.../bopeebo-normal_Player.tres`, el de hard es el mismo con otro trozo en medio. Asi
## esto vale para cualquier cancion sin saber nada de ella.
const KNOWN: PackedStringArray = ["easy", "normal", "hard", "standart", "legacy"]


func _ready() -> void:
	var wanted: String = LoadingScreen.target_difficulty
	if wanted.is_empty():
		return
	# Se camina desde el padre, no desde `get_tree().current_scene`: este nodo cuelga de la
	# raiz de la escena de cancion y `current_scene` todavia puede no apuntar a ella cuando
	# la escena se instancia a mano -es lo que pasa en el banco de pruebas, y tambien
	# mientras el arbol esta a medio cambiar-.
	for node: Node in _controllers(get_parent()):
		_swap(node, wanted)


## Los RubiconLevelNoteController que cuelguen de la escena, sin importar donde esten.
func _controllers(from: Node) -> Array[Node]:
	var out: Array[Node] = []
	if from == null:
		return out
	for node: Node in from.find_children("*", "RubiconLevelNoteController", true, false):
		out.append(node)
	return out


func _swap(controller: Node, wanted: String) -> void:
	var chart: Resource = controller.get("chart") as Resource
	if chart == null or chart.resource_path.is_empty():
		return
	var path: String = chart.resource_path
	var current: String = ""
	for id: String in KNOWN:
		if path.contains("-%s_" % id):
			current = id
			break
	if current.is_empty() or current == wanted:
		return
	var target: String = path.replace("-%s_" % current, "-%s_" % wanted)
	# Una cancion puede no tener esa dificultad -phone-call trae un solo chart, sin
	# sufijo-, y en ese caso se deja el que venia en vez de romper la escena.
	if not ResourceLoader.exists(target):
		push_warning("difficulty_charts: no existe %s, se queda %s" % [target, current])
		return
	controller.set("chart", load(target))
