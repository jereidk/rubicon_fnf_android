extends SceneTree

## `lullaby_light_energy_gate.gd` hides a light exactly while it emits nothing,
## and only while it is safe to.
##
## Forward Mobile evaluates every light that reaches a fragment - measured on
## the phone's path with 8 full-screen omnis:
##
##     energy=0.35, visible=true   135.8ms
##     energy=0.0,  visible=true   135.1ms   <- same price, contributes nothing
##     energy=0.0,  visible=false   16.3ms
##
## A light at zero energy still occupies its slot in the loop; only hiding it
## removes the cost. `light_indirect_energy`/`light_volumetric_fog_energy` do
## not change that on THIS project - there is no live GI system in use
## anywhere (rendering_method.mobile is "mobile", i.e. Forward Mobile, which
## has no SDFGI/VoxelGI path, and no scene enables VoxelGI or volumetric fog) -
## confirmed by rendering a light at energy=0, indirect_energy=6.026 (the same
## combination Chimera's TvLight authors) against the light fully absent: 0/255
## worst pixel error.
##
## Deliberately opt-in per node, not an automatic scene-wide pass - see the
## script's own header for why: resolving whether an animation track writes
## this light's own `:visible` requires walking every AnimationPlayer's every
## track and resolving NodePaths, which is exactly the class of thing that has
## produced silent bugs in this project before. A human checks
## `tools/audit_light_cost.py`'s output and attaches this only where it is
## safe.
##
## First run of audit_light_cost.py flagged the shop's LightbulbLight as dead
## cost, and it was wrong to: the tool read a missing `light_energy` property
## line as 0.0, when Godot's own engine default is 1.0 - checked against the
## running binary, not assumed. LightbulbLight is an ordinary light nobody
## bothered to author an explicit energy value for. Caught before it shipped;
## this test pins the corrected default so it cannot regress silently.
##
## Run with:
##   godot --headless --path . --script tools/test_light_energy_gate.gd

const GATE_PATH := "res://lullaby_mod/scripts/lullaby/lullaby_light_energy_gate.gd"
const AUDIT_PATH := "res://tools/audit_light_cost.py"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	# 1. Structural checks on the audit tool: the corrected default, and that
	#    it still distinguishes an unauthored line from an authored zero.
	var audit: String = _read(AUDIT_PATH)
	_check(audit.contains('"energy": 1.0 if energy is None else float(energy)'),
		"el default de energia sin autorar es 1.0, el de verdad en el motor")
	_check(not audit.contains('"energy": 0.0 if energy is None else float(energy)'),
		"no queda el default viejo (0.0) en ningun sitio")

	# 2. Behavioural check on the gate script itself, live: it must hide at
	#    zero energy, show at nonzero, and never touch a BAKE_STATIC light.
	var script: GDScript = load(GATE_PATH)
	_check(script != null, "el script del gate carga")
	if script == null:
		_finish()
		return

	var light := OmniLight3D.new()
	light.light_energy = 0.0
	light.visible = true
	light.set_script(script)
	light._process(0.0)
	_check(light.visible == false, "energia 0 esconde la luz")

	light.light_energy = 1.5
	light._process(0.0)
	_check(light.visible == true, "energia > 0 la vuelve a mostrar")

	light.light_energy = 0.0
	light.light_bake_mode = Light3D.BAKE_STATIC
	light.visible = true
	light._process(0.0)
	_check(light.visible == true,
		"una luz BAKE_STATIC no se toca aunque su energia sea 0")
	light.free()

	# 3. And the same for AreaLight3D, which shares light_energy with every
	#    other Light3D subclass (confirmed via ClassDB, not assumed) - Chimera
	#    authors CrawlSpaceLight as one of these.
	var area := AreaLight3D.new()
	area.light_energy = 0.0
	area.visible = true
	area.set_script(script)
	area._process(0.0)
	_check(area.visible == false, "el gate tambien funciona en AreaLight3D")
	area.free()

	_finish()


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text
