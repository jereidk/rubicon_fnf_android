extends SceneTree

## `luz=Nalcanzan` is the one counter that prices Chimera's frame.
##
## Forward Mobile evaluates every light that reaches a fragment in that
## fragment's shader, and this project measured the cost in isolation at
## about 15ms per light over a full 1600x720. Two device logs then measured
## Chimera's slope at 90.8 ms/Mpx of 3D pass, which is where that curve puts
## five or six lights - so this number IS the frame.
##
## And it was reading 6 when the truth is 4. Both extras were lights the GPU
## never draws:
##
##   editor_only is dropped from the render at runtime while the node stays
##   in the tree, so is_visible_in_tree() is still true. Chimera's
##   EditorMoonDoNotDelete is one, and this file already records that it
##   "would otherwise look like the worst offender in the project".
##
##   And a light under a SubViewport lights that viewport's world, not this
##   one. Every song instances lullaby_results_screen.tscn, which carries a
##   shadow-casting DirectionalLight3D inside its own SubViewport - and the
##   logs show that viewport is not even rendering during play (sub=0/1 on
##   41 of 43 Chimera heartbeats).
##
## Run with:
##   godot --headless --path . --script tools/test_light_reach_counter.gd

const LOG := "res://lullaby_mod/scripts/lullaby/debug/lullaby_diagnostics_log.gd"
const RESULTS := "res://lullaby_mod/resources/funkin/ui/results/lullaby_results_screen.tscn"
const CHIMERA := "res://lullaby_mod/songs/chimera/sng_chimera.tscn"

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	var text: String = FileAccess.get_file_as_string(LOG)
	_check(not text.is_empty(), "the diagnostics log is readable")

	var body: String = _func_body(text, "_light_reach")
	_check(_has_statement(body, "light\\.editor_only"),
		"lights the runtime drops are not counted (editor_only)")
	_check(_has_statement(body, "light\\.get_viewport\\(\\) != main"),
		"lights belonging to another viewport's world are not counted")
	_check(_has_statement(body, "names\\.append"),
		"the lights that DO reach are named, not only counted")
	_check(body.contains("fant="),
		"and the skipped ones are reported rather than silently dropped")

	# Both rules exist because of a real node. If either stops being true the
	# check above is pinning nothing, so say so instead of passing quietly.
	var chimera: String = FileAccess.get_file_as_string(CHIMERA)
	_check(chimera.contains("editor_only = true"),
		"Chimera still ships an editor_only light (why the first rule exists)")

	var results: String = FileAccess.get_file_as_string(RESULTS)
	var head: int = results.find("[node name=\"DirectionalLight3D\"")
	_check(head >= 0 and results.substr(head, 200).contains("parent=\"SubViewport\""),
		"the results screen still puts its directional inside a SubViewport (why the second exists)")

	print("light reach counter: %d/%d checks passed" % [_checks - _failures, _checks])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)

func _has_statement(body: String, pattern: String) -> bool:
	var re := RegEx.new()
	re.compile("(?m)^[\\t ]*[^#\\n]*" + pattern)
	return re.search(body) != null

func _func_body(text: String, name: String) -> String:
	var head: int = text.find("func %s(" % name)
	if head < 0:
		_check(false, "%s() exists" % name)
		return ""
	var tail: int = text.find("\nfunc ", head + 1)
	return text.substr(head, tail - head if tail > head else -1)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  OK  ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
