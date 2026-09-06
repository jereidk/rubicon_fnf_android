extends Node
## HQ Gauntlet Runtime — applies the active gauntlet mods to whichever HQ song
## scene this node is in. Mirrors the mod's GauntletHandler.hx for the mods
## the Rubicon engine can express directly:
##
## NoMechanics            - bullet/timestop notes are removed from the chart
## Bigger/SmallerWindows  - judgment windows scaled 1.25x / /1.25
## PerformanceRegen       - +0.020 health/sec once the song is running
## OpponentPerformanceDrain - CPU notes drain 0.04 (holds 0.005) health
## InstantKillMechanics   - handled by hq_note_mechanics.gd on bullet miss
## StealthNotes / ZoomingNotes - visual approximations in this script
## ComboCountRequirement, HarderMechanics, HigherScoreRequirement - pending

const WINDOW_PROPS: Array[String] = [
	"judgment_window_perfect", "judgment_window_great", "judgment_window_good",
	"judgment_window_okay", "judgment_window_bad",
]

var _zoom_boost: float = 0.0


func _ready() -> void:
	if not HQSaves.is_gauntlet_mode:
		set_process(false)
		return
	_apply_mods.call_deferred()


func _apply_mods() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var mods: Array[String] = HQSaves.cur_gauntlet_mods
	var player := scene.get_node_or_null("UILayer/UI/Player")
	var opponent := scene.get_node_or_null("UILayer/UI/Opponent")

	if mods.has("NoMechanics"):
		_remove_mechanics(player)
		_remove_mechanics(opponent)

	var window_scale := 1.0
	if mods.has("BiggerJudgementWindows"):
		window_scale = 1.25
	elif mods.has("SmallerJudgementWindows"):
		window_scale = 1.0 / 1.25
	if window_scale != 1.0:
		_scale_windows(player, window_scale)
		_scale_windows(opponent, window_scale)

	if mods.has("OpponentPerformanceDrain"):
		var health := scene.get_node_or_null("RubiconHealthModule")
		if health != null:
			for controller in [player, opponent]:
				if controller != null and controller.has_signal("note_changed"):
					controller.note_changed.connect(_on_note_changed.bind(health))


func _process(delta: float) -> void:
	if not HQSaves.is_gauntlet_mode:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var mods: Array[String] = HQSaves.cur_gauntlet_mods
	var health := scene.get_node_or_null("RubiconHealthModule")
	if health != null and mods.has("PerformanceRegen"):
		var max_value: Variant = health.get("max_health")
		health.health = minf(float(health.health) + 0.02 * delta, float(max_value) if max_value != null else 100.0)
	var player := scene.get_node_or_null("UILayer/UI/Player")
	if player == null:
		return
	if mods.has("StealthNotes"):
		_fade_stealth(player)
	if mods.has("ZoomingNotes"):
		_pulse_zoom(player, delta)
	elif _zoom_boost > 0.0:
		_zoom_boost = 0.0
		player.scroll_speed_multiplier = 1.0


func _remove_mechanics(controller: Node) -> void:
	if controller == null:
		return
	for handler: RubiconLevelNoteHandler in controller.note_handlers.values():
		var kept: Array[RubiChartNote] = []
		for note: RubiChartNote in handler.data:
			if note.type == &"Bullet Note" or note.type == &"Timestop Note":
				continue
			kept.append(note)
		handler.data = kept
		handler.update_notes()


func _scale_windows(controller: Node, scale: float) -> void:
	if controller == null:
		return
	for handler: RubiconLevelNoteHandler in controller.note_handlers.values():
		var settings := handler.settings
		if settings == null:
			continue
		for prop: String in WINDOW_PROPS:
			settings.set(prop, float(settings.get(prop)) * scale)


func _on_note_changed(result: RubiconLevelNoteHitResult, _has_ending_row: bool, health: Node) -> void:
	if result.handler == null or result.handler.get_controller().autoplay == false:
		return
	var amount := 0.04
	if result.handler.data[result.data_index].ending_row != null:
		amount = 0.005
	health.health = float(health.health) - amount


func _fade_stealth(controller: Node) -> void:
	var reveal := 720.0
	for handler: RubiconLevelNoteHandler in controller.note_handlers.values():
		for i in range(handler.note_spawn_start, handler.note_spawn_end):
			var graphic: Control = handler.graphics[i]
			if graphic == null:
				continue
			if graphic.was_hit():
				graphic.modulate.a = 1.0
				continue
			var dist := graphic.position.length()
			graphic.modulate.a = clampf((reveal - dist) / reveal, 0.0, 1.0)


func _pulse_zoom(controller: Node, delta: float) -> void:
	var near: bool = false
	for handler: RubiconLevelNoteHandler in controller.note_handlers.values():
		for i in range(handler.note_spawn_start, handler.note_spawn_end):
			var graphic: Control = handler.graphics[i]
			if graphic != null and graphic.position.length() < 620.0:
				near = true
				break
		if near:
			break
	if near:
		_zoom_boost = minf(_zoom_boost + 1.75 * delta, 1.5)
	else:
		_zoom_boost = maxf(_zoom_boost - 3.5 * delta, 0.0)
	controller.scroll_speed_multiplier = 1.0 + _zoom_boost
