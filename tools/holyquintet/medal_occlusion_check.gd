extends Node
# Checks whether MainMenuSprite's idle *loop* (not just the initial *start*
# playback) ever zooms/pans over the medal icons' screen position (Story
# selected, x:185-485 y:835-875), and whether the medals stay visible (a
# dim tint on top) or get fully hidden when it does — reported: on a real
# device, at rest on Story, the medal spot showed zero trace of a medal
# even though character art covered it there.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/medal_occlusion_check.tscn

const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/main/main_menu.tscn")
	var screen: Node = scene.instantiate()
	add_child(screen)

	await get_tree().create_timer(0.3).timeout

	# Sample every 0.5s for 8s while Story (index 0, already selected at
	# rest) plays its idle loop, watching for a moment the art reaches the
	# medal position.
	for i in 16:
		await get_tree().create_timer(0.5).timeout
		await _shoot("occl_t%02d.png" % i)

	print("MEDAL_OCCLUSION_CHECK: saved")
	get_tree().quit()


func _shoot(filename: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(SHOT_DIR.path_join(filename))
