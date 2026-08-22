extends Node

## The experiment CLAUDE.md has been calling "the one that's missing" since the
## render-scale section was first written: Chimera has only ever been logged
## at scale=0.50 on a real phone, so the slope of gpu-time vs 3D pixel count is
## unmeasured. Runs the sweep here instead, on the real scene (not a synthetic
## quad+lights stand-in) via setup_render_sandbox.sh's degraded-texture
## Vulkan/mobile path - same rendering method the phone uses, same geometry,
## same lights, same shadow caster, just 128px flat-colour textures instead of
## real art (irrelevant to a fill-rate question).
##
## Freezes the song clock at one song position, then cycles
## Viewport.scaling_3d_scale through a list of values, timing actual wall-clock
## frame render time (not RenderingServer's GPU timestamp query, which
## lavapipe - software Vulkan - may not answer at all, same failure mode as
## the Mali-G76 in the real device logs). Wall time is the right instrument
## here anyway: this is a single CPU thread doing the rasterising, so frame
## wall-time already IS the render cost, with no async GPU pipeline to
## misread.
##
## Usage:
##   godot --headless --path <sandbox> --rendering-method mobile \
##     --rendering-driver vulkan res://tools/harness/render_scale_sweep.tscn \
##     -- res://lullaby_mod/songs/chimera/sng_chimera.tscn t=90 t=150
##
## One or more t= song positions; the scale list is fixed (see SCALES) so every
## run answers the same question the same way.
##
## UNVERIFIED as of this writing: parse-checks clean and setup_render_sandbox.sh
## completes the degraded-texture import, but the actual render under
## `--rendering-method mobile --rendering-driver vulkan` inside this sandboxed
## environment hangs before printing "OUT instanciada" - RSS plateaus, CPU
## drops toward 0%, and every thread sits in futex_do_wait/hrtimer_nanosleep
## (engine idle, not crunching). Killed after ~6 minutes with no output.
## Tried both with and without --headless; scene_shot.gd's own docstring
## recipe also omits --headless, which is what this now matches. Whether the
## hang is specific to Chimera's size, to this container's lavapipe build, or
## to something `--headless --import` leaves in a state the live run cannot
## use, was not narrowed down - do that first on the next attempt, or just run
## this on a real device build instead of chasing the sandbox further.
const SCALES: Array[float] = [0.35, 0.50, 0.70, 1.00]
const SETTLE_FRAMES: int = 3
const SAMPLE_FRAMES: int = 20

var _scene_path: String = "res://lullaby_mod/songs/chimera/sng_chimera.tscn"
var _at: Array[float] = [90.0]

func _ready() -> void:
	var argv: PackedStringArray = OS.get_cmdline_user_args()
	if argv.size() > 0:
		_scene_path = argv[0]
	var at: Array[float] = []
	for i in range(1, argv.size()):
		var a: String = argv[i]
		if a.begins_with("t="):
			at.append(float(a.substr(2)))
	if not at.is_empty():
		_at = at

	get_window().size = Vector2i(1600, 720)

	# Without this every note in the song is an unplayed miss (nothing here
	# simulates input), which drains health to zero and spams
	# switch_to_gameover on every note-hit callback for the rest of the run -
	# not fatal, but it buries the OUT lines and slows the sweep to a crawl.
	Settings.game_autoplay = true

	var scene: Node = (load(_scene_path) as PackedScene).instantiate()
	add_child(scene)
	_silence_gameover(scene)
	for _i in 3:
		await get_tree().process_frame
	print("OUT instanciada")

	var clock: AnimationPlayer = _find_timeline(scene)
	if clock == null:
		print("OUT sin linea de tiempo")
		get_tree().quit(1)
		return
	clock.play(&"scene")

	var vp: Viewport = get_viewport()
	var vp_rid: RID = vp.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)

	var done: float = 0.0
	for target in _at:
		while done < target:
			clock.advance(1.0 / 60.0)
			done += 1.0 / 60.0
		_pin_health(scene)
		clock.pause()

		for scale in SCALES:
			vp.scaling_3d_scale = scale
			for _i in SETTLE_FRAMES:
				await RenderingServer.frame_post_draw

			var t0: int = Time.get_ticks_usec()
			var gpu_sum: float = 0.0
			var cpu_sum: float = 0.0
			for _i in SAMPLE_FRAMES:
				await RenderingServer.frame_post_draw
				gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
				cpu_sum += RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
			var t1: int = Time.get_ticks_usec()

			var wall_ms_per_frame: float = (t1 - t0) / 1000.0 / SAMPLE_FRAMES
			var gpu_ms: float = gpu_sum / SAMPLE_FRAMES
			var cpu_ms: float = cpu_sum / SAMPLE_FRAMES

			var draw: int = RenderingServer.viewport_get_render_info(
				vp_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
				RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
			var prims: int = RenderingServer.viewport_get_render_info(
				vp_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
				RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)

			print("OUT t=%.1fs scale=%.2f wall_ms=%.3f gpu_ms=%.3f cpu_ms=%.3f draw=%d prims=%d" % [
				clock.current_animation_position, scale, wall_ms_per_frame, gpu_ms, cpu_ms, draw, prims])

		clock.play(&"scene")

	print("OUT listo")
	get_tree().quit()

func _find_timeline(scene: Node) -> AnimationPlayer:
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var p := node as AnimationPlayer
		if p != null and p.has_animation(&"scene"):
			return p
		for child in node.get_children():
			stack.append(child)
	return null

func _pin_health(scene: Node) -> void:
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if "max_health" in node and "health" in node:
			node.set("health", node.get("max_health"))
		for child in node.get_children():
			stack.append(child)

func _silence_gameover(scene: Node) -> void:
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var script: Script = node.get_script() as Script
		if script != null and "gameover" in script.resource_path.to_lower():
			node.process_mode = Node.PROCESS_MODE_DISABLED
		for child in node.get_children():
			stack.append(child)
