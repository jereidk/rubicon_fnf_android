extends Node
# Verifies the Android system back button (NOTIFICATION_WM_GO_BACK_REQUEST)
# is actually intercepted on the main menu, instead of falling through to
# Godot's default quit_on_go_back=true behavior. Also verifies that if the
# dev-console popup is open, back closes the popup instead of leaving the
# menu (since that popup is a sibling of the whole scene, parented at the
# tree root the same way the popup's own backdrop is).
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/android_back_button_test.tscn

func _ready() -> void:
	var scene: PackedScene = load("res://holyquintet_mod/menus/main/main_menu.tscn")
	var screen: Control = scene.instantiate()
	# Parented straight to root and marked as current_scene, not under this
	# test node — change_scene_to_file() (what a real back-to-Title does)
	# frees whatever IS current_scene, and this test node must survive
	# that to check the result afterward.
	get_tree().root.add_child.call_deferred(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = screen
	await get_tree().create_timer(0.3).timeout

	# Case 1: dev console popup open -> back should close ONLY the popup.
	var btn: Control = screen._dev_console_btn
	btn._open_popup()
	await get_tree().process_frame
	print("BACK_TEST: popup open before back =", is_instance_valid(btn._popup))
	screen.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await get_tree().process_frame
	await get_tree().process_frame
	print("BACK_TEST: popup open after back =", is_instance_valid(btn._popup))
	print("BACK_TEST: still on main menu after popup-close back =", get_tree().current_scene == screen)

	# Case 2: nothing open -> back should navigate to Title.
	screen.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await get_tree().create_timer(2.0).timeout
	var cur := get_tree().current_scene
	print("BACK_TEST: current_scene after plain back =", cur.name if cur else "null")

	print("BACK_TEST: done")
	get_tree().quit()
