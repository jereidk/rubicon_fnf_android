class_name LullabyShaderPrewarm

## Forces a scene's materials to compile while the loading screen is still
## covering the screen, instead of mid-song when they first appear.
##
## Godot compiles a shader the first time its material is actually drawn, on
## the main thread. On an Adreno 619 that costs between half a second and
## three seconds per material - which is exactly what Chimera's diagnostics
## log shows: proc spikes of 473ms, 1117ms and 2837ms, each landing on the
## frame a SequencePlayer cutscene starts (114_hexapproach, 122_fall) and
## reveals 3D models that had not been drawn yet. Draw calls at that moment
## are in the twenties, so nothing is struggling to render; the frame is
## simply blocked compiling.
##
## The work cannot be avoided, only moved. Making the hidden nodes visible
## for a couple of frames gets every material drawn once, paying the whole
## cost during a load the player is already waiting through.
##
## Only nodes that are currently HIDDEN are touched, and each one's flag is
## restored afterwards. Visible nodes are left alone - their shaders compile
## on the first frame regardless, and reaching into them risks disturbing a
## scene that is already set up correctly.

## Frames to wait with everything shown. One to submit the draw, one more for
## the renderer to have actually consumed it.
const RENDER_FRAMES := 2

## Runs the prewarm and returns how many nodes it revealed. Awaits, so call
## it with await from somewhere that can wait - between change_scene_to_packed
## and hiding the loading screen.
static func prewarm(tree: SceneTree, scene: Node) -> int:
	if tree == null or scene == null:
		return 0

	var hidden: Array[Node] = []
	_collect_hidden(scene, hidden)
	if hidden.is_empty():
		return 0

	for node in hidden:
		node.set("visible", true)

	for i in RENDER_FRAMES:
		await tree.process_frame

	# Restored in reverse so a parent is re-hidden after its children, which
	# keeps the intermediate states from ever showing a half-revealed subtree.
	for i in range(hidden.size() - 1, -1, -1):
		if is_instance_valid(hidden[i]):
			hidden[i].set("visible", false)

	return hidden.size()

## Walks the whole tree rather than stopping at the first hidden ancestor:
## a hidden parent's children still hold their own materials, and they are
## exactly the ones a cutscene reveals later.
static func _collect_hidden(node: Node, out: Array[Node]) -> void:
	if (node is CanvasItem or node is Node3D) and not node.visible:
		out.append(node)

	for child in node.get_children():
		_collect_hidden(child, out)
