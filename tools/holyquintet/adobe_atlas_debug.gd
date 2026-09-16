extends Node
# Diagnostic: checks whether AdobeAtlas correctly parses AN.STI's stage
# transform (a large negative translation baked into anim_story's
# Animation.json) and whether draw_on() actually applies it — investigating
# why MainMenuSprite renders far smaller/differently positioned than the
# real reference screenshot.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/adobe_atlas_debug.tscn

func _ready() -> void:
	var atlas := AdobeAtlas.new()
	atlas.folder_path = "res://holyquintet_mod/source/images/ui/main/anim_story/"
	print("stage_symbol=", atlas.stage_symbol)
	print("stage_transform=", atlas.stage_transform)
	print("stage_transform.origin=", atlas.stage_transform.origin)
	print("symbols.has(Story_Animation)=", atlas.symbols.has(&"Story_Animation"))
	print("symbols keys sample=", Array(atlas.symbols.keys()).slice(0, 5))
	if atlas.symbols.has(atlas.stage_symbol):
		var sym = atlas.symbols[atlas.stage_symbol]
		print("stage symbol length=", sym.length)
	print("get_length_of(Story_Animation)=", atlas.get_length_of(&"Story_Animation"))
	get_tree().quit()
