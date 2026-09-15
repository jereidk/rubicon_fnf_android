extends Control

func _ready():
	print("[HQMainMenu] Starting...")
	
	# TODO: Show main menu options
	# - Freeplay
	# - Story
	# - Gauntlet
	# - Settings
	# - Gallery
	
	await get_tree().create_timer(2.0).timeout
	print("[HQMainMenu] Menu loaded")
