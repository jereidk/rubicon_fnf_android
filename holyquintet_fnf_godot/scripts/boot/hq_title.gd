extends Control

# Mirror of HQTitle.hx (stub for now)

func _ready():
	print("[HQTitle] Starting...")

	# TODO: Show title screen with animation
	# TODO: Wait for input
	# TODO: Go to HQMainMenu

	# For now, skip after 3 seconds
	await get_tree().create_timer(3.0).timeout
	print("[HQTitle] Going to HQMainMenu")
	get_tree().change_scene_to_file("res://scenes/boot/hq_main_menu.tscn")
