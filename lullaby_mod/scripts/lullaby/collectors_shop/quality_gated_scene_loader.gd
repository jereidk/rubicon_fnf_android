class_name QualityGatedSceneLoader extends Node3D

## Only loads and instantiates [member optional_scene_path] once the current
## graphics quality is at or above [member min_post_processing] - and frees
## it again if the setting drops back below that. Deliberately uses
## @export_file (a plain path string) rather than a PackedScene export: a
## PackedScene export is resolved as an ext_resource and gets loaded from
## disk the moment THIS node's own parent scene loads, regardless of the
## current setting. A path string doesn't - the referenced .tscn is only
## ever touched by the load() call below, so on presets that don't want it
## the extra nodes are never parsed, instantiated, or paid for at all
## (not merely hidden, which still costs the full creation time).

@export_file("*.tscn") var optional_scene_path: String
@export var min_post_processing: LullabySettings.PostProcessing = LullabySettings.PostProcessing.LOW

var _instance: Node = null

func _ready() -> void:
	_update()
	Settings.applied.connect(_update)

func _update() -> void:
	var should_exist: bool = Settings.graphics_post_processing >= min_post_processing
	if should_exist and _instance == null:
		_instance = load(optional_scene_path).instantiate()
		add_child(_instance)
	elif not should_exist and _instance != null:
		_instance.queue_free()
		_instance = null
