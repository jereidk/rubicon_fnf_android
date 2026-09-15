extends Control

# Mirror of HQSetup.hx
var can_control: bool = false
var step: int = 0

const MOD_PATH = "res://mods/holy_quintet/"
const DATA_PATH = MOD_PATH + "data/"
const VIDEO_PATH = MOD_PATH + "videos/"

func _ready():
	print("[HQSetup] Starting...")

	# Get boot script
	var boot = get_tree().root.get_child(0) if get_tree().root.get_child_count() > 0 else null

	# Preload videos (from global.hx HQSetup.hx line 16-32)
	preload_video("intro_start")
	preload_video("intro_yes")
	preload_video("intro_no")

	# Check if first time
	var first_time_setup_done = boot.get_save_data("gameplay", "firstTimeSetupDone", false) if boot else false
	var see_intro = boot.get_save_data("gameplay", "seeIntro", true) if boot else true

	if not first_time_setup_done:
		print("[HQSetup] First time setup needed")
		progress_setup()
	else:
		# Delay 0.5s before switching (from global.hx line 69-78)
		await get_tree().create_timer(0.5).timeout

		if see_intro:
			print("[HQSetup] Switching to HQIntro")
			get_tree().change_scene_to_file("res://scenes/boot/hq_intro.tscn")
		else:
			print("[HQSetup] Switching to HQDisclaimer")
			get_tree().change_scene_to_file("res://scenes/boot/hq_disclaimer.tscn")

func preload_video(video_name: String):
	"""Preload video without playing it"""
	var video_path = VIDEO_PATH + video_name + ".mp4"
	print("[HQSetup] Preloading video: %s" % video_path)
	# TODO: Actually preload when VideoPlayer exists

func progress_setup():
	"""Handle first-time setup progression"""
	print("[HQSetup] Showing setup UI...")
	step += 1

	# TODO: Show keybind UI
	# TODO: Show language selection
	# TODO: Save firstTimeSetupDone = true

	# For now, skip to intro
	await get_tree().create_timer(1.0).timeout

	var boot = get_tree().root.get_child(0) if get_tree().root.get_child_count() > 0 else null
	if boot:
		boot.set_save_data("gameplay", "firstTimeSetupDone", true)

	print("[HQSetup] Setup complete, switching to HQIntro")
	get_tree().change_scene_to_file("res://scenes/boot/hq_intro.tscn")
