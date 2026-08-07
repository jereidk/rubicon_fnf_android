extends SceneTree

## Dumps a raw file out of Lullaby.pck next to the port's copy, so gdanimate
## atlas data (Animation.json / spritemap*.json) can be compared - those are
## read with FileAccess at runtime, not through the resource loader, so
## get_dependencies() and SceneState say nothing about them.
##
##   godot --headless --script tools/diff_pck_file.gd -- <pc_path> <out_path>

const PCK := "res://lullaby_mod/original_pck/Lullaby.pck"

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("OUT usage: -- <pc_path> <out_path>")
		quit()
		return

	if not ProjectSettings.load_resource_pack(PCK, false):
		print("OUT could not mount pck")
		quit()
		return

	var src: String = args[0]
	if not FileAccess.file_exists(src):
		print("OUT missing in pck: ", src)
		quit()
		return

	var data: PackedByteArray = FileAccess.get_file_as_bytes(src)
	var out := FileAccess.open(args[1], FileAccess.WRITE)
	if out == null:
		print("OUT cannot write ", args[1])
		quit()
		return
	out.store_buffer(data)
	out.close()
	print("OUT wrote ", data.size(), " bytes to ", args[1])
	quit()
