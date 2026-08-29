class_name ChimeraGameoverModule
extends Node


static var deaths: int = 0

@export var ignore_for_skips: bool = false
@export var health_module: RubiconHealthModule
@export var track_deaths: bool = false

@export var paths: Dictionary[StringName, String] = {}

@onready var timer: Timer = $Timer

var path_key: StringName = &""


func _ready() -> void :
	if health_module:
		health_module.health_depleted.connect(switch_to_gameover, CONNECT_ONE_SHOT)


func switch_to_gameover() -> void :
	if ignore_for_skips:
		return

	LullabyGameoverModule.has_died = true

	if track_deaths:
		deaths += 1
		path_key = &"step_%d" % clampi(deaths, 1, 4)
	else:
		path_key = &"step_0"

	# Con ruido, porque el fallo que esto cubre fue mudo durante todo el port.
	#
	# Las cinco escenas de gameover no se portaron y los cinco uid de `paths` no
	# resolvian contra nada. Leer una clave que no esta en un Dictionary tipado
	# aborta la funcion; y aunque estuviera, change_scene_to_file() con un uid
	# muerto no cambia nada y no lanza nada que se vea jugando. Las dos ramas
	# daban lo mismo desde el sofa: te quedabas sin vida en Chimera y la cancion
	# seguia, sin gameover y sin reintento, hasta que terminara.
	#
	# Que no exista una escena de gameover es un fallo de contenido y tiene que
	# leerse como tal en el .error, no como "no pasa nada".
	if not paths.has(path_key):
		push_error("ChimeraGameoverModule: no hay ruta para %s (muertes=%d)" % [
			path_key, deaths])
		return

	var scene_path: String = paths[path_key]
	if scene_path.is_empty():
		return

	if not ResourceLoader.exists(scene_path):
		push_error("ChimeraGameoverModule: %s = %s no resuelve" % [path_key, scene_path])
		return

	get_tree().change_scene_to_file(scene_path)
