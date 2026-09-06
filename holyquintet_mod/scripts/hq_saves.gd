extends Node
## HQ Saves — persistent save data for the Holy Quintet port.
## Mirrors the mod's FlxG.save.data fields used by the ported states:
## achievements, kyubey coins, gauntlet best score, story progress, setup flags.

const SAVE_PATH := "user://hq_save.json"

var unlocked_achievements: Array[String] = []
var kyubey_coins: int = 0
var best_gauntlet_score: int = 0
var first_time_setup_done: bool = false
var see_intro: bool = true
var pinpoint_accuracy_progress: int = 0
var devoted_progress: int = 0
var cur_story_progress: int = 0
var cur_story_diff: String = "hard"
var goduka_enabled: bool = false
var goduka_cooldown: int = 0
var death_counter: int = 0
var campaign_score: int = 0
var campaign_misses: int = 0
var campaign_songs_left: Array[String] = []

## Settings return (pause -> settings -> back to song)
var settings_return_scene: String = ""

## Gauntlet state
var cur_gauntlet_mods: Array[String] = []
var cur_gauntlet_multiplier: float = 1.0
var is_gauntlet_mode: bool = false
var gauntlet_ending: bool = false
var is_story_mode: bool = false


func _ready() -> void:
	load_data()


func is_achievement_locked(id: String) -> bool:
	return not unlocked_achievements.has(id)


func unlock_achievement(id: String) -> void:
	if is_achievement_locked(id):
		unlocked_achievements.append(id)
		save_data()


func achievement_progress(id: String) -> int:
	match id:
		"PinpointAccuracy":
			return pinpoint_accuracy_progress
		"Devoted":
			return devoted_progress
	return 0


func reset_run_state() -> void:
	campaign_score = 0
	campaign_misses = 0
	campaign_songs_left = []
	is_gauntlet_mode = false
	is_story_mode = false
	cur_gauntlet_mods = []
	cur_gauntlet_multiplier = 1.0


func save_data() -> void:
	var data := {
		"unlocked_achievements": unlocked_achievements,
		"kyubey_coins": kyubey_coins,
		"best_gauntlet_score": best_gauntlet_score,
		"first_time_setup_done": first_time_setup_done,
		"see_intro": see_intro,
		"pinpoint_accuracy_progress": pinpoint_accuracy_progress,
		"devoted_progress": devoted_progress,
		"cur_story_progress": cur_story_progress,
		"cur_story_diff": cur_story_diff,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))


func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		return
	var data: Dictionary = json.data
	unlocked_achievements = (data.get("unlocked_achievements", []) as Array).map(func(v): return str(v))
	kyubey_coins = int(data.get("kyubey_coins", 0))
	best_gauntlet_score = int(data.get("best_gauntlet_score", 0))
	first_time_setup_done = bool(data.get("first_time_setup_done", false))
	see_intro = bool(data.get("see_intro", true))
	pinpoint_accuracy_progress = int(data.get("pinpoint_accuracy_progress", 0))
	devoted_progress = int(data.get("devoted_progress", 0))
	cur_story_progress = int(data.get("cur_story_progress", 0))
	cur_story_diff = str(data.get("cur_story_diff", "hard"))
