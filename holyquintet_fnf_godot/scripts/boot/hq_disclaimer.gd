extends Control

# Mirror of HQDisclaimer.hx (stub for now)

func _ready():
	print("[HQDisclaimer] Starting...")

	# TODO: Show disclaimer text
	# TODO: Wait for user input
	# TODO: Go to HQTitle

	# For now, skip after 2 seconds
	await get_tree().create_timer(2.0).timeout
	print("[HQDisclaimer] Skipping to HQTitle")
	get_tree().change_scene_to_file("res://scenes/boot/hq_title.tscn")
