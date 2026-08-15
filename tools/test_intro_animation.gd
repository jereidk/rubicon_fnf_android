extends SceneTree

## The Collector's intro animation is added at runtime instead of living in the
## scene's AnimationLibrary. This checks it still gets there.
##
## sequence_intro.tres is 4.17MB, a 152-second baked animation, thirteen times
## the size of anything else in the same library. It plays once in a save's
## lifetime and the flag is set immediately afterwards, so on every visit after
## the first it was loaded for an animation that could not run.
##
## The failure mode is the meanest one yet: the intro cutscene plays with the
## Collector standing frozen, and only on a save that has never seen it. A
## tester with an existing save would never hit it, and the log would say
## nothing. So the wiring is pinned here rather than trusted.
##
## Run with:
##   godot --headless --path . --script tools/test_intro_animation.gd

const SHOP := "res://lullaby_mod/rooms/env_collector_shop.tscn"
const ANIM := "res://lullaby_mod/resources/animations/collector/sequence_intro.tres"
const SHOP_SCRIPT := "res://lullaby_mod/scripts/lullaby/collectors_shop/env_collector_shop.gd"
const NAME := &"sequence_intro"

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	_scene_case()
	_asset_case()
	await _wiring_case()

	print("")
	if _checks < 8:
		print("FALLO: solo %d de 8 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - la animacion de intro llega a su libreria")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

## The scene must not carry it any more.
func _scene_case() -> void:
	var file := FileAccess.open(SHOP, FileAccess.READ)
	if file == null:
		_check("se puede leer la escena", false)
		return
	var text: String = file.get_as_text()
	file.close()

	_check("la escena ya no referencia sequence_intro.tres",
		not text.contains("animations/collector/sequence_intro.tres"))

	var deps: PackedStringArray = ResourceLoader.get_dependencies(SHOP)
	var found: bool = false
	for dep in deps:
		if dep.contains("collector/sequence_intro.tres"):
			found = true
	_check("ni el motor la ve como dependencia", not found, "%d deps" % deps.size())

## The file has to survive, and be a real Animation - a runtime add pointing at
## nothing is the same bug wearing a hat.
func _asset_case() -> void:
	_check("la animacion sigue existiendo", ResourceLoader.exists(ANIM), ANIM.get_file())

	var anim: Resource = load(ANIM)
	var ok: bool = anim is Animation
	_check("y carga como Animation", ok,
		"%.1fs, %d pistas" % [anim.length, anim.get_track_count()] if ok else "no")

## The wiring: _add_intro_animation() must put it in the default library under
## the name play() will ask for.
func _wiring_case() -> void:
	var shop := Node3D.new()
	shop.set_script(load(SHOP_SCRIPT))

	# Stand-in for the Collector. The property has to be declared in a real
	# script: set() on an object that has no such property fails silently, and
	# the first version of this test did exactly that - _add_intro_animation()
	# then saw a null animation_player and returned early, which read as the
	# code being broken rather than the double being empty.
	var stub := GDScript.new()
	stub.source_code = "extends Node3D\nvar animation_player: AnimationPlayer\n"
	stub.reload()

	var collector := Node3D.new()
	var player := AnimationPlayer.new()
	collector.add_child(player)
	collector.set_script(stub)
	collector.animation_player = player
	shop.add_child(collector)
	root.add_child(shop)
	await process_frame

	_check("el doble expone animation_player", collector.animation_player == player)

	_check("empieza sin la animacion", not player.has_animation(NAME))

	shop._add_intro_animation(player)
	_check("_add_intro_animation la anade", player.has_animation(NAME),
		",".join(player.get_animation_list()))

	# Called twice - _ready() is not the only path that could reach it.
	shop._add_intro_animation(player)
	_check("y llamarla otra vez no duplica nada",
		player.get_animation_list().size() == 1,
		"%d animaciones" % player.get_animation_list().size())

	shop.queue_free()
	await process_frame

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-46s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-46s%s" % [label, "  (%s)" % detail if detail else ""])
