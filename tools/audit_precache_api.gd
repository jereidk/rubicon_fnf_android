extends SceneTree

## What Godot 4.7 actually offers for warming pipelines and GPU uploads
## without blocking a frame.
##
## The shop's precache spends 35.6 seconds on a single frame: res and nodes
## are flat across it, RAM moves 9MB, but VRAM climbs 71MB and 154 pipelines
## compile. So it is GPU upload plus pipeline creation, both synchronous on
## the draw that first needs them, and both happening for the whole scene at
## once because the precache camera reveals all 487 objects in one go.
##
## Before proposing to hand-roll a progressive reveal, check whether the
## engine already exposes something for this. Guessing at an API that does not
## exist has cost this investigation real time already.
##
## Run with:
##   godot --headless --path . --script tools/audit_precache_api.gd

const WORDS: PackedStringArray = [
	"pipeline", "precompil", "prewarm", "warm", "compil", "async", "barrier",
	"sync", "frame_drawn", "call_on_render", "shader",
]

func _initialize() -> void:
	print("Godot %s" % Engine.get_version_info()["string"])
	print("")

	_methods("RenderingServer", RenderingServer)
	_methods("RenderingDevice", RenderingServer.get_rendering_device())

	print("== ClassDB: metodos de Mesh/Material que suenan a precalentar ==")
	for klass in ["Mesh", "BaseMaterial3D", "Material", "ShaderMaterial", "GeometryInstance3D",
			"MeshInstance3D", "Viewport", "SubViewport"]:
		for m in ClassDB.class_get_method_list(klass, true):
			var name: String = m["name"]
			var lower: String = name.to_lower()
			for word in ["precompil", "prewarm", "warm", "pipeline", "surface_get_material"]:
				if lower.contains(word):
					print("  %s.%s()" % [klass, name])
					break
	print("")

	# The one thing that definitely exists and is worth confirming: a callback
	# after a frame is actually presented, which is what a progressive reveal
	# would have to pace itself on.
	print("RenderingServer.has_method('request_frame_drawn_callback') = %s"
		% RenderingServer.has_method("request_frame_drawn_callback"))
	print("RenderingServer.has_method('call_on_render_thread')        = %s"
		% RenderingServer.has_method("call_on_render_thread"))

	quit(0)

func _methods(label: String, obj: Object) -> void:
	print("== %s ==" % label)
	if obj == null:
		print("  (no disponible en headless)")
		print("")
		return

	var hits: Array[String] = []
	for m in obj.get_method_list():
		var name: String = m["name"]
		var lower: String = name.to_lower()
		for word in WORDS:
			if lower.contains(word):
				hits.append(name)
				break
	hits.sort()
	for name in hits:
		print("  %s()" % name)
	print("")
