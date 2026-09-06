extends Node
## HQ Song Completion — detects when the song animation ends and
## transitions to the results screen with real score data.

var _clock: Node
var _song_module: Node
var _has_finished: bool = false

var results_scene: PackedScene = preload("res://holyquintet_mod/menus/results/results_screen.tscn")


var _resonance_health_below_060: bool = false

func _ready() -> void:
	await get_tree().process_frame
	var scene = get_tree().current_scene
	if scene == null:
		return
	HQSaves.hq_bullet_note_missed = false
	HQSaves.hq_timestop_note_hit = false
	_clock = scene.get_node_or_null("RubiconLevelClock")
	_song_module = scene.get_node_or_null("RubiconLevelSongModule")
	var health = scene.get_node_or_null("RubiconHealthModule")
	if health != null and health.has_signal("health_changed"):
		health.health_changed.connect(_on_health_changed.bind(health))
	if _clock == null:
		push_warning("HQSongCompletion: no RubiconLevelClock found")
		return
	var anim_player = _clock.get_node_or_null("AnimationPlayer")
	if anim_player != null:
		anim_player.animation_finished.connect(_on_song_finished)


func _on_health_changed(health: Node) -> void:
	if float(health.health) <= 0.6:
		_resonance_health_below_060 = true


func _on_song_finished(_anim_name: StringName) -> void:
	if _has_finished:
		return
	_has_finished = true
	_try_achievements()

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
	var dest := "res://holyquintet_mod/menus/results/results_screen.tscn"
	if HQSaves.is_gauntlet_mode:
		var pl = scene.get_node_or_null("UILayer/UI/Player") if scene != null else null
		if pl != null:
			HQSaves.campaign_score += pl.performance_score_value
			HQSaves.campaign_misses += pl.performance_hits_miss
		if HQSaves.campaign_songs_left.size() > 0:
			HQSaves.campaign_songs_left.pop_front()
		HQSaves.gauntlet_ending = HQSaves.campaign_songs_left.is_empty()
		dest = "res://holyquintet_mod/menus/gauntlet/gauntlet_transition.tscn"
	var tw := create_tween()
	tw.tween_property(fade, "modulate:a", 1.0, 0.5).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		get_tree().change_scene_to_file(dest)
	)



## Achievement unlocks, mirroring the mod's AchievementHandler.onSongEnd.
func _try_achievements() -> void:
	var scene = get_tree().current_scene
	if scene == null or HQSaves.is_gauntlet_mode or HQSaves.goduka_enabled:
		return
	var player = scene.get_node_or_null("UILayer/UI/Player")
	if player == null:
		return
	var misses := player.performance_hits_miss
	var song := _normalize_song_name(scene.name)
	var hard_clear := misses == 0 and HQSaves.cur_story_diff == "hard"
	if hard_clear:
		match song:
			"initium": HQSaves.unlock_achievement("FCInitium")
			"resonance": HQSaves.unlock_achievement("FCResonance")
			"partea": HQSaves.unlock_achievement("FCPartea")
			"eternalstar": HQSaves.unlock_achievement("FCEternalStar")
			"vexation": HQSaves.unlock_achievement("FCVexation")
			"out-of-time": HQSaves.unlock_achievement("FCOutOfTime")
			"meguca": HQSaves.unlock_achievement("FCMeguca")
			"reconnect": HQSaves.unlock_achievement("FCReconnect")
			"stardom": HQSaves.unlock_achievement("FCStardom")
	# ResOutheal: completed resonance without health dropping to 60%.
	if song == "resonance" and not _resonance_health_below_060:
		HQSaves.unlock_achievement("ResOutheal")
	# YoureOnMyTime: out-of-time without pressing timestop or missing bullets.
	if song == "out-of-time" 		and not HQSaves.hq_timestop_note_hit and not HQSaves.hq_bullet_note_missed:
		HQSaves.unlock_achievement("YoureOnMyTime")
	# CompleteAct1: story mode clear of out-of-time.
	if song == "out-of-time" and HQSaves.is_story_mode:
		HQSaves.unlock_achievement("CompleteAct1")
	# Tenacious: died 15+ times (mod: DeathCounter >= 15 at song end).
	if HQSaves.death_counter >= 15:
		HQSaves.unlock_achievement("Tenacious")
	# Devoted progress
	HQSaves.devoted_progress += 1
	if HQSaves.devoted_progress >= 25:
		HQSaves.unlock_achievement("Devoted")
	# Pinpoint accuracy progress: count perfect hits
	HQSaves.pinpoint_accuracy_progress += player.performance_hits_perfect
	if HQSaves.pinpoint_accuracy_progress >= 5000:
		HQSaves.unlock_achievement("PinpointAccuracy")
	HQSaves.save_data()


func _normalize_song_name(raw: String) -> String:
	var lowered := raw.to_lower()
	if lowered == "outoftime":
		return "out-of-time"
	return lowered
