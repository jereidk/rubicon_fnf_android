extends Node
## HQ Gameover Handler — connects RubiconHealthModule.health_depleted to
## the HQ gameover screen overlay. Add as a child of any HQ song scene.
##
## Inspired by phone_call's DeathSequence but simplified for HQ: no
## character-specific death poses, just fade to gameover overlay.

var _health_module: Node
var _gameover_scene: PackedScene = preload("res://holyquintet_mod/menus/gameover/gameover_screen.tscn")
var _is_dead: bool = false
var _gameover_layer: CanvasLayer


func _ready() -> void:
	await get_tree().process_frame
	_health_module = _find_health_module()
	if _health_module == null:
		push_warning("HQGameOverHandler: no RubiconHealthModule found in parent scene")
		return
	_health_module.health_depleted.connect(_on_health_depleted)


func _find_health_module() -> Node:
	var scene = get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("RubiconHealthModule")


func _on_health_depleted() -> void:
	if _is_dead:
		return
	_is_dead = true

	# Stop all audio players in the scene.
	_stop_audio()

	# Hide mobile controls.
	_hide_mobile_controls()

	# Fade to black briefly, then show gameover.
	_gameover_layer = CanvasLayer.new()
	_gameover_layer.layer = 100
	get_tree().current_scene.add_child(_gameover_layer)

	var fade := ColorRect.new()
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.color = Color.BLACK
	fade.modulate.a = 0.0
	_gameover_layer.add_child(fade)

	# Pause the game tree so notes stop falling.
	get_tree().paused = true

	# Fade in.
	var tw := create_tween()
	tw.tween_property(fade, "modulate:a", 1.0, 0.5).set_ease(Tween.EASE_IN)
	tw.tween_callback(_show_gameover)


func _stop_audio() -> void:
	var scene = get_tree().current_scene
	if scene == null:
		return
	# Stop the RubiconLevelSongModule's audio players.
	var song_module = scene.get_node_or_null("RubiconLevelSongModule")
	if song_module != null:
		for child in song_module.get_children():
			if child is AudioStreamPlayer:
				child.stop()
	# Also stop any other AudioStreamPlayers in the scene.
	for node in scene.get_children():
		if node is AudioStreamPlayer and node.playing:
			node.stop()


func _hide_mobile_controls() -> void:
	var scene = get_tree().current_scene
	if scene == null:
		return
	var mobile = scene.get_node_or_null("MobileControls")
	if mobile != null:
		mobile.visible = false


func _show_gameover() -> void:
	# Unpause tree so the gameover screen can receive input.
	get_tree().paused = false

	var go = _gameover_scene.instantiate()
	go.process_mode = Node.PROCESS_MODE_ALWAYS
	_gameover_layer.add_child(go)
