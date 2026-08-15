extends SceneTree

## The credits portrait sheet loads on first sight instead of with the room.
## This checks it still arrives, and that it is not arriving early.
##
## dev_portraits.png is 4096x4096 - 16.8 megapixels, 14% of every pixel the
## Collector's Shop pulls in. It used to be an ExtResource on two
## AnimatedSprite2Ds inside console.tscn, so walking into the room loaded the
## whole sheet for a screen two menus deep.
##
## The failure mode of getting the lazy version wrong is quiet: the credits
## show two blank silhouettes while the names, roles and descriptions all keep
## working, which is easy to ship and hard to notice. So both directions are
## pinned - the sheet must be gone from the scene file, and it must come back
## the moment the credits are looked at.
##
## Run with:
##   godot --headless --path . --script tools/test_credits_portraits.gd

const CONSOLE := "res://lullaby_mod/resources/console/console.tscn"
const SHEET := "res://lullaby_mod/assets/menus/console/credits/devest_portraits.tres"
const SCRIPT := "res://lullaby_mod/scripts/lullaby/collectors_shop/console/credits_container.gd"

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	_scene_case()
	_sheet_case()
	await _lazy_case()

	print("")
	if _checks < 6:
		print("FALLO: solo %d de 6 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - la hoja llega tarde pero llega")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

## The scene must no longer name the sheet. Read as text rather than through
## get_dependencies(), because that is the file the exporter walks.
func _scene_case() -> void:
	var file := FileAccess.open(CONSOLE, FileAccess.READ)
	if file == null:
		_fail("no pude leer console.tscn", true)
		return
	var text: String = file.get_as_text()
	file.close()

	_check("console.tscn ya no referencia la hoja",
		not text.contains("devest_portraits"), "")
	# Only id 42 mattered; the console has other AnimatedSprite2Ds whose sheets
	# are small and stay eager on purpose.
	_check("y no queda ninguna asignacion del id 42",
		not text.contains('ExtResource("42")'), "")

	# It must also be out of the engine's own dependency view, which is what
	# actually decides whether it loads with the room.
	var deps: PackedStringArray = ResourceLoader.get_dependencies(CONSOLE)
	var still_there: bool = false
	for dep in deps:
		if dep.contains("devest_portraits"):
			still_there = true
	_check("y tampoco esta en las dependencias del motor", not still_there, "%d deps" % deps.size())

## The sheet itself has to survive - a lazy path pointing at nothing is the
## same bug with extra steps.
##
## Only its existence is asserted. Actually loading it needs the imported
## texture, and in a fresh checkout that .res is a Git LFS pointer that was
## never pulled, so load() fails here for reasons that have nothing to do with
## this change. Reporting that as a pass would be worse than not checking it,
## so the attempt is made and its outcome printed as information.
func _sheet_case() -> void:
	_check("la hoja sigue existiendo", ResourceLoader.exists(SHEET), SHEET.get_file())

	var frames: Resource = load(SHEET)
	if frames is SpriteFrames:
		print("        (carga OK, %d retratos)" % frames.get_animation_names().size())
	else:
		print("        (no carga en este entorno - textura importada via LFS sin descargar;")
		print("         el mecanismo se prueba abajo con una hoja sintetica)")

## The lazy path itself: hidden means not loaded, visible means loaded.
func _lazy_case() -> void:
	# A stand-in sheet, written to disk so load() genuinely round-trips. The
	# real one cannot be loaded here (see _sheet_case), and the thing under
	# test is the lazy path, not the artwork.
	var stand_in := SpriteFrames.new()
	stand_in.add_animation(&"Bakyura")
	var stand_in_path := "user://test_credits_frames.tres"
	if ResourceSaver.save(stand_in, stand_in_path) != OK:
		_fail("no pude guardar la hoja de prueba", true)
		return

	var container := HBoxContainer.new()
	container.set_script(load(SCRIPT))
	container.portrait_frames_path = stand_in_path

	var sprite := AnimatedSprite2D.new()
	var player := AnimationPlayer.new()
	sprite.add_child(player)
	container.add_child(sprite)
	container.primary_portrait_animation = player
	container.secondary_portrait_animation = null

	# Hidden: _ensure_portraits() must decline.
	container.visible = false
	root.add_child(container)
	await process_frame

	container._ensure_portraits()
	_check("oculto no carga la hoja", sprite.sprite_frames == null)

	container.visible = true
	await process_frame
	container._ensure_portraits()
	_check("visible si la carga", sprite.sprite_frames != null,
		"%d retratos" % (sprite.sprite_frames.get_animation_names().size() if sprite.sprite_frames else 0))

	# Loading twice would mean the guard is not holding.
	var first: SpriteFrames = sprite.sprite_frames
	container._ensure_portraits()
	_check("no la recarga en la segunda llamada", sprite.sprite_frames == first)

	container.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(stand_in_path))

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-46s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-46s%s" % [label, "  (%s)" % detail if detail else ""])

func _fail(why: String, _hard: bool) -> void:
	_failures += 1
	print("  FALLO %s" % why)
