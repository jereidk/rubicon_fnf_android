extends Control

# Mirror of HQIntro.hx
var can_control: bool = false
var intro_video_player: VideoPlayer
var selecting_yes: bool = false
var has_moved: bool = false

const MOD_PATH = "res://mods/holy_quintet/"
const VIDEO_PATH = MOD_PATH + "videos/"

func _ready():
	print("[HQIntro] Starting...")

	# Preload sounds (from HQIntro.hx line 18-20)
	# TODO: Preload sounds

	# Setup intro video
	intro_video_player = $VideoPlayer
	if intro_video_player:
		intro_video_player.stream = VideoStream.new() if false else null  # TODO: Load video
		intro_video_player.finished.connect(_on_intro_finished)
		# intro_video_player.play()

	print("[HQIntro] Ready (video playback TODO)")

	# Temporary: skip to disclaimer
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://scenes/boot/hq_disclaimer.tscn")

func _on_intro_finished():
	"""When intro_start.mp4 ends, show Yes/No prompt"""
	print("[HQIntro] Video finished, showing prompt...")
	can_control = true
	# TODO: Show Yes/No selector

func _on_yes_selected():
	"""User selected Yes"""
	print("[HQIntro] User selected Yes")
	# Play intro_yes.mp4
	# On finish: go to HQDisclaimer
	get_tree().change_scene_to_file("res://scenes/boot/hq_disclaimer.tscn")

func _on_no_selected():
	"""User selected No"""
	print("[HQIntro] User selected No")
	# Play intro_no.mp4
	# On finish: go to ???
	get_tree().change_scene_to_file("res://scenes/boot/hq_disclaimer.tscn")
