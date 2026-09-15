extends Node

# Global state mirrors from HolyQuintet global.hx
var init_data: bool = false
var redirect_states: Dictionary = {
	"TitleState": "HQSetup",
	"MainMenuState": "HQMainMenu",
	"FreeplayState": "HQFreeplay",
	"StoryMenuState": "HQMainMenu"
}

var achievement_data: Dictionary = {}
var gauntlet_mods_data: Dictionary = {}
var i18n_data: Dictionary = {}

const MOD_PATH = "res://mods/holy_quintet/"
const DATA_PATH = MOD_PATH + "data/"

func _ready():
	print("=== HolyQuintet Boot ===")
	pre_state_switch()

func pre_state_switch():
	if not init_data:
		print("[Boot] Loading data...")
		load_data()
		load_translations()
		init_save_data()
		init_data = true

	# TODO: Handle state redirect (TitleState → HQSetup)
	print("[Boot] Boot complete. Starting HQSetup...")
	get_tree().change_scene_to_file("res://scenes/boot/hq_setup.tscn")

func load_data():
	"""Load achievement and gauntlet mod data from JSON"""
	print("[Boot] Loading achievement/gauntlet data...")
	# TODO: Parse data/
	pass

func load_translations():
	"""Load i18n translations"""
	print("[Boot] Loading translations...")
	var trans_path = DATA_PATH + "langs/en_US/translations.json"
	if ResourceLoader.exists(trans_path):
		var trans_json = JSON.parse_string(FileAccess.get_file_as_string(trans_path))
		if trans_json:
			i18n_data = trans_json
			print("[Boot] Translations loaded: %d keys" % len(i18n_data))

func init_save_data():
	"""Initialize save data with defaults (mirrors global.hx lines 119-153)"""
	var save_path = "user://hq_save.cfg"
	var config = ConfigFile.new()

	# Load existing or create new
	if ResourceLoader.exists(save_path):
		config.load(save_path)

	# Set defaults if not present
	if not config.has_section_key("gameplay", "firstTimeSetupDone"):
		config.set_value("gameplay", "firstTimeSetupDone", false)
	if not config.has_section_key("gameplay", "seeIntro"):
		config.set_value("gameplay", "seeIntro", true)
	if not config.has_section_key("gameplay", "tutorialCompleted"):
		config.set_value("gameplay", "tutorialCompleted", false)
	if not config.has_section_key("gameplay", "kyubeyCoins"):
		config.set_value("gameplay", "kyubeyCoins", 0)

	# Story progress
	if not config.has_section_key("story", "curStoryProgress"):
		config.set_value("story", "curStoryProgress", 0)
	if not config.has_section_key("story", "curStoryDiff"):
		config.set_value("story", "curStoryDiff", "hard")

	# GameJolt
	if not config.has_section_key("gamejolt", "curUserName"):
		config.set_value("gamejolt", "curUserName", "")
	if not config.has_section_key("gamejolt", "curUserToken"):
		config.set_value("gamejolt", "curUserToken", "")

	config.save(save_path)
	print("[Boot] Save data initialized at %s" % save_path)

func get_save_data(section: String, key: String, default_val = null):
	"""Get value from save file"""
	var config = ConfigFile.new()
	var save_path = "user://hq_save.cfg"
	if not ResourceLoader.exists(save_path):
		return default_val
	config.load(save_path)
	if config.has_section_key(section, key):
		return config.get_value(section, key)
	return default_val

func set_save_data(section: String, key: String, value):
	"""Set value in save file"""
	var config = ConfigFile.new()
	var save_path = "user://hq_save.cfg"
	if ResourceLoader.exists(save_path):
		config.load(save_path)
	config.set_value(section, key, value)
	config.save(save_path)

func translate(key: String, default_text: String = "") -> String:
	"""Get translated string or return default"""
	if key in i18n_data:
		return i18n_data[key]
	return default_text if default_text else key
