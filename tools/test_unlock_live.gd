extends SceneTree

## Checks that a locked settings row appears the moment its code is accepted,
## without the console being rebuilt.
##
## The bug this covers is not a crash and not a wrong pixel: LullabyHideIfLocked
## read its flag once at _ready, so entering the code in the Codes tab set the
## flag, saved it, said "Code accepted" - and the row it unlocked stayed
## hidden. It only turned up after loading a song and coming back, which from
## the player's side looks exactly like the code not having worked.
##
## Run with:
##   godot --headless --path . --script tools/test_unlock_live.gd

const FLAG := &"speed_hack_unlocked"

var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	await process_frame

	var save: Node = root.get_node_or_null("SaveData")
	if save == null:
		print("FALLO: no encontre el autoload SaveData")
		quit(1)
		return

	var was: bool = save.get_flag(FLAG)
	save.set_flag(FLAG, false)

	var row := Control.new()
	row.name = "SpeedHack"
	root.add_child(row)

	var gate: Node = load(
		"res://lullaby_mod/scripts/lullaby/collectors_shop/console/buttons/settings/hide_if_locked.gd").new()
	gate.unlock_flag = FLAG
	row.add_child(gate)
	await process_frame

	_check("bloqueada, la fila arranca oculta", not row.visible)

	# What the Codes tab does, with the console still on screen.
	save.set_flag(FLAG, true)
	await process_frame
	_check("al aceptar el codigo aparece sin recargar nada", row.visible)

	save.set_flag(FLAG, false)
	await process_frame
	_check("y vuelve a ocultarse si se revoca", not row.visible)

	var hacks: GDScript = load(
		"res://lullaby_mod/scripts/lullaby/collectors_shop/console/hacks_tab.gd")
	var codes: Dictionary = hacks.CODES
	_check("existe el codigo SPEEDHACK", codes.has("SPEEDHACK"),
		"codigos: %s" % ", ".join(codes.keys()))
	if codes.has("SPEEDHACK"):
		_check("SPEEDHACK apunta al flag correcto",
			StringName("%s_unlocked" % codes["SPEEDHACK"]) == FLAG,
			"-> %s_unlocked" % codes["SPEEDHACK"])

	# A write that changes nothing must not wake listeners; load_from()
	# rewrites every flag it reads.
	var woke: Array[bool] = [false]
	save.flag_changed.connect(func(_f: StringName, _v: bool) -> void: woke[0] = true)
	save.set_flag(FLAG, false)
	await process_frame
	_check("reescribir el mismo valor no emite nada", not woke[0])

	save.set_flag(FLAG, was)
	row.queue_free()

	print("")
	if _failures == 0:
		print("todo OK")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok    %s%s" % [name, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %s%s" % [name, "  (%s)" % detail if detail else ""])
