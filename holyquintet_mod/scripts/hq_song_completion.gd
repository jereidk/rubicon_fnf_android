extends Node
## HQ Song Completion — detects when the song animation ends and
## transitions to the results screen with real score data.

var _clock: Node
var _song_module: Node
var _has_finished: bool = false

var results_scene: PackedScene = preload("res://holyquintet_mod/menus/results/results_screen.tscn")


func _ready() -> void:
	await get_tree().process_frame
	var scene = get_tree().current_scene
	if scene == null:
		return
	_clock = scene.get_node_or_null("RubiconLevelClock")
	_song_module = scene.get_node_or_null("RubiconLevelSongModule")
	if _clock == null:
		push_warning("HQSongCompletion: no RubiconLevelClock found")
		return
	var anim_player = _clock.get_node_or_null("AnimationPlayer")
	if anim_player != null:
		anim_player.animation_finished.connect(_on_song_finished)


func _on_song_finished(_anim_name: StringName) -> void:
	if _has_finished:
		return
	_has_finished = true

	# Collect score data from the player note controller.
	var scene = get_tree().current_scene
	if scene != null:
		var player = scene.get_node_or_null("UILayer/UI/Player")
		if player != null:
			var total_hits = player.performance_hits_perfect + player.performance_hits_great \
				+ player.performance_hits_good + player.performance_hits_okay \
				+ player.performance_hits_bad + player.performance_hits_miss
			var acc = player.performance_accuracy_percent
			if total_hits > 0:
				acc = (float(player.performance_hits_perfect * 300 + player.performance_hits_great * 200 \
					+ player.performance_hits_good * 100 + player.performance_hits_okay * 50 \
					- player.performance_hits_bad * 50 - player.performance_hits_miss * 100) \
					/ float(maxi(total_hits, 1)) / 3.0)

			# Set static data for results screen
			ResultsData.song_name = scene.name
			ResultsData.score = player.performance_score_value
			ResultsData.accuracy = acc
			ResultsData.hits_perfect = player.performance_hits_perfect
			ResultsData.hits_great = player.performance_hits_great
			ResultsData.hits_good = player.performance_hits_good
			ResultsData.hits_okay = player.performance_hits_okay
			ResultsData.hits_bad = player.performance_hits_bad
			ResultsData.hits_miss = player.performance_hits_miss

	# Stop audio
	if _song_module != null:
		for child in _song_module.get_children():
			if child is AudioStreamPlayer:
				child.stop()

	# Wait a beat then fade
	await get_tree().create_timer(1.5).timeout
	var layer := CanvasLayer.new()
	layer.layer = 100
	scene.add_child(layer)
	var fade := ColorRect.new()
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.color = Color.BLACK
	fade.modulate.a = 0.0
	layer.add_child(fade)
	var tw := create_tween()
	tw.tween_property(fade, "modulate:a", 1.0, 0.5).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		get_tree().change_scene_to_file("res://holyquintet_mod/menus/results/results_screen.tscn")
	)
