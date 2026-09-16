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

## HQMainMenu.hx: freeplayUnlocked/gauntletUnlocked/accoladesUnlocked/
## galleryUnlocked gate the corresponding menu button's locked state — all
## default false (a fresh save), same as the real mod, and nothing in this
## port unlocks them yet since the story-mode progression that would
## unlock them for real isn't built.
##
## viewedMenu (badly named — it's really "menu indices still owed a new-
## badge") defaults to [1,2,3,4] in the real global.hx: HQMainMenu only
## shows a badge when BOTH the index is in this list AND that button is
## unlocked, so on a fresh save every badge stays hidden (everything in
## the list starts locked) until something unlocks one of them, at which
## point its already-pending entry makes the badge appear immediately —
## no separate "just unlocked" flag needed. Each destination screen
## removes its own index once actually visited (HQFreeplay/HQGauntlet/
## HQAchievements/HQGallery); this port does that removal from
## HQMainMenu's own confirm handler instead, since those destination
## screens are still early stubs with no such hook of their own yet.
var freeplay_unlocked: bool = false
var gauntlet_unlocked: bool = false
var accolades_unlocked: bool = false
var gallery_unlocked: bool = false
var viewed_menu: Array[int] = [1, 2, 3, 4]

## Not a real FlxG.save.data field — global.hx's newsText is session-only,
## always blank with no fallback when HttpUtil.hasInternet() is false. This
## caches the last successfully-fetched ticker text/version so the main
## menu can show *something* offline instead of going blank every time,
## per user request (a deliberate improvement over the real mod's behavior,
## not a fidelity gap).
var cached_news_text: String = ""
var cached_news_version: String = ""

## Per-run mechanic flags (not persisted), read by HQAchievements.
## Mirrors the mod's bulletNoteMissed / timeStopNoteHit for YoureOnMyTime.
var hq_bullet_note_missed: bool = false
var hq_timestop_note_hit: bool = false
var hq_atks_sustained: bool = false
var hq_dodge_perfects: int = 0


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
	hq_atks_sustained = false
	hq_dodge_perfects = 0


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
		"freeplay_unlocked": freeplay_unlocked,
		"gauntlet_unlocked": gauntlet_unlocked,
		"accolades_unlocked": accolades_unlocked,
		"gallery_unlocked": gallery_unlocked,
		"viewed_menu": viewed_menu,
		"cached_news_text": cached_news_text,
		"cached_news_version": cached_news_version,
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
	unlocked_achievements.assign((data.get("unlocked_achievements", []) as Array).map(func(v): return str(v)))
	kyubey_coins = int(data.get("kyubey_coins", 0))
	best_gauntlet_score = int(data.get("best_gauntlet_score", 0))
	first_time_setup_done = bool(data.get("first_time_setup_done", false))
	see_intro = bool(data.get("see_intro", true))
	pinpoint_accuracy_progress = int(data.get("pinpoint_accuracy_progress", 0))
	devoted_progress = int(data.get("devoted_progress", 0))
	cur_story_progress = int(data.get("cur_story_progress", 0))
	cur_story_diff = str(data.get("cur_story_diff", "hard"))
	freeplay_unlocked = bool(data.get("freeplay_unlocked", false))
	gauntlet_unlocked = bool(data.get("gauntlet_unlocked", false))
	accolades_unlocked = bool(data.get("accolades_unlocked", false))
	gallery_unlocked = bool(data.get("gallery_unlocked", false))
	viewed_menu.assign((data.get("viewed_menu", [1, 2, 3, 4]) as Array).map(func(v): return int(v)))
	cached_news_text = str(data.get("cached_news_text", ""))
	cached_news_version = str(data.get("cached_news_version", ""))
