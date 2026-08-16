extends SceneTree

## A value track paints its first key over everything before that key.
##
## Chimera's master timeline - the "scene" animation on RubiconLevelClock,
## 199.875s long and running for the whole song - writes
## BlackBoxofAwesomeness:color, and its earliest key is at 181.83s with
## Color(0, 0, 0, 1). There is nothing before it. Godot does not leave the
## property alone until then: it clamps to the first key, so from the downbeat
## onwards the level clock is actively painting a full-screen rect opaque
## black, every frame, for three minutes.
##
## The rect survives that only because the same animation keeps visible false
## until 181.83 as well. Two of the Hex sequences take that away -
## 113_reaching's visible track is a single true key with nothing to turn it
## off, and approach ends on true too - and once a sequence has flipped it,
## the opaque black the clock has been holding all along is on screen. That is
## the reported bug and its shape: a black graphic tied to a character's
## sequence rather than to any moment on the timeline, and worse when a second
## one stacks on it.
##
## This measures the hold rather than reasoning about it, because reading
## Godot's interpolation is exactly how the last attempt at this bug got it
## wrong. Two identical tracks, one with a transparent key placed one frame
## ahead of the authored one, sampled where the song actually plays.
##
## The fix is that one added key and nothing else. No authored key moves, no
## update mode changes - the blanket CONTINUOUS-to-DISCRETE flip was tried in
## fce21be and reverted in b61aed2 for breaking three scenes, because the PC
## pck ships these tracks CONTINUOUS and everything else is timed against that.
##
## Run with:
##   godot --headless --path . --script tools/test_black_box_hold.gd

const SCENE := "res://lullaby_mod/songs/chimera/sng_chimera.tscn"

## The authored key, and one frame at the 24fps grid the mod is cut on.
const AUTHORED_T := 181.83333
const FRAME := 1.0 / 24.0

## Where the song actually is while the Hex sequences run.
const SAMPLES := [1.0, 30.0, 90.0, 150.0, 181.0]

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	var held: Array = await _sample(false)
	var guarded: Array = await _sample(true)

	var worst_held: float = 0.0
	for a in held:
		worst_held = maxf(worst_held, a)
	_check("sin clave previa la pista pinta negro opaco todo el rato",
		worst_held >= 0.99, "alpha %.2f a %ss" % [worst_held, SAMPLES])

	var worst_guarded: float = 0.0
	for a in guarded:
		worst_guarded = maxf(worst_guarded, a)
	_check("con una clave transparente delante, no pinta nada",
		worst_guarded <= 0.01, "alpha maximo %.4f" % worst_guarded)

	# The authored moment has to survive the guard key: it is the start of a
	# flash, and moving it would trade one visible bug for another.
	var at_key: float = await _alpha_at(true, AUTHORED_T)
	_check("y la clave original sigue llegando opaca a su hora",
		at_key >= 0.99, "alpha %.2f en %.3fs" % [at_key, AUTHORED_T])

	_scene_check()

	print("")
	if _checks < 6:
		print("FALLO: solo %d de 6 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - el reloj de Chimera ya no sostiene negro opaco")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

func _sample(guarded: bool) -> Array:
	var out: Array = []
	for t in SAMPLES:
		out.append(await _alpha_at(guarded, t))
	return out

## Drives a real AnimationPlayer over a real ColorRect, rather than asking the
## Animation resource what it thinks - the property that matters is the one
## that ends up on the node.
func _alpha_at(guarded: bool, at: float) -> float:
	var rect := ColorRect.new()
	rect.color = Color(0, 0, 0, 0)
	var player := AnimationPlayer.new()
	root.add_child(rect)
	rect.add_child(player)

	var anim := Animation.new()
	anim.length = 199.875
	var track: int = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track, NodePath(".:color"))
	anim.value_track_set_update_mode(track, Animation.UPDATE_CONTINUOUS)
	if guarded:
		anim.track_insert_key(track, AUTHORED_T - FRAME, Color(0, 0, 0, 0))
	anim.track_insert_key(track, AUTHORED_T, Color(0, 0, 0, 1))
	anim.track_insert_key(track, AUTHORED_T + FRAME, Color(1, 1, 1, 0))

	var library := AnimationLibrary.new()
	library.add_animation(&"scene", anim)
	player.add_animation_library(&"", library)

	player.play(&"scene")
	# Read before yielding. seek(update = true) applies the track there and
	# then; a process frame after it advances the animation by that frame,
	# which is invisible in the flat stretches and 40% of a one-frame ramp at
	# the key itself.
	player.seek(at, true)
	var alpha: float = rect.color.a

	rect.queue_free()
	await process_frame
	return alpha

## The measurement above only says what the shape does. This says the shipped
## scene has that shape - and it is a text check because sng_chimera.tscn
## pulls in textures and .gltf materials a headless run cannot resolve, so
## load() fails on it outright.
func _scene_check() -> void:
	var text: String = FileAccess.get_file_as_string(SCENE)
	var times: String = '"times": PackedFloat32Array(181.79167, 181.83333, 181.875,'
	_check("la escena lleva la clave de guarda", text.contains(times))

	var values: String = '"values": [Color(0, 0, 0, 0), Color(0, 0, 0, 1), Color(1, 1, 1, 0),'
	_check("y es transparente", text.contains(values))

	# Eight keys need eight transitions, or Godot drops the track on load and
	# the rect goes back to whatever last wrote it.
	var transitions: String = '"transitions": PackedFloat32Array(1, 0, 2.1435468, 1, 1, -2, 0, 1)'
	_check("con una transicion por clave", text.contains(transitions))

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-52s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-52s%s" % [label, "  (%s)" % detail if detail else ""])
