extends SceneTree

## apply_settings() must not re-send shadow state that has not changed.
##
## Every settings row calls apply_settings() the moment it is touched, and the
## reported symptom is a hitch on changing anything at all, "sin importar
## magnitud" - the shape of a cost that belongs to the re-apply and not to the
## setting. The device log names it: a settings change compiles 35 render
## pipelines with an identical breakdown every time, surf+6 draw+13 spec+16, so
## the same shaders are being thrown away and rebuilt. That session compiled 790.
##
## Every other assignment in that function goes through a Godot setter that
## returns early when the value has not moved. The four shadow writes did not:
## a bare RenderingServer call has no such check, and shadow filter quality is
## a shader define, so writing it at all invalidates the shaders reading it.
##
## The pipeline counters themselves cannot settle this here -
## RENDERING_INFO_PIPELINE_COMPILATIONS_* is Vulkan-only and reads zero under
## the OpenGL3 renderer a headless runner gets - so what this pins is the thing
## that is checkable: the guard opens for a real change and stays shut for a
## repeat, and the first apply always writes.
##
## Run with:
##   godot --headless --path . --script tools/test_settings_shadow_reapply.gd

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	var settings: Node = root.get_node_or_null(^"Settings")
	if settings == null:
		print("FALLO: no existe el autoload Settings")
		quit(1)
		return

	_check("arranca sin nada aplicado todavia",
		settings._applied_shadow_atlas_size == -1 or settings._applied_shadow_filter_quality == -1
			or settings._applied_shadow_atlas_size >= 0,
		"atlas=%d calidad=%d" % [settings._applied_shadow_atlas_size,
			settings._applied_shadow_filter_quality])

	# A value that cannot be what is already applied, so the first apply below
	# has to write it whatever the project's defaults are.
	settings.graphics_shadows_enabled = true
	settings.graphics_positional_shadow_atlas_size = 2048
	settings.graphics_positional_shadow_filter_quality = 1
	settings.apply_settings()

	_check("el primer apply escribe el estado",
		settings._applied_shadow_atlas_size == 2048
			and settings._applied_shadow_filter_quality == 1,
		"atlas=%d calidad=%d" % [settings._applied_shadow_atlas_size,
			settings._applied_shadow_filter_quality])

	# Repeating it must not re-send anything. Poking the cache would be the
	# wrong probe - the guard compares against it, so moving it is itself a
	# change and would force the write it is meant to detect. The window is
	# the observable: the branch writes positional_shadow_atlas_size, so a
	# skipped branch leaves whatever was put there.
	root.positional_shadow_atlas_size = 77
	settings.apply_settings()
	_check("repetir el mismo valor no vuelve a escribir",
		root.positional_shadow_atlas_size == 77,
		"la ventana quedo en %d" % root.positional_shadow_atlas_size)

	# And a real change does reach the window.
	settings.graphics_positional_shadow_atlas_size = 1024
	settings.apply_settings()
	_check("cambiar el tamano si escribe",
		settings._applied_shadow_atlas_size == 1024
			and root.positional_shadow_atlas_size == 1024,
		"atlas=%d ventana=%d" % [settings._applied_shadow_atlas_size,
			root.positional_shadow_atlas_size])

	# And the filter quality on its own, which is the shader define.
	root.positional_shadow_atlas_size = 77
	settings.graphics_positional_shadow_filter_quality = 3
	settings.apply_settings()
	_check("cambiar solo la calidad del filtro tambien escribe",
		settings._applied_shadow_filter_quality == 3
			and root.positional_shadow_atlas_size == 1024,
		"calidad=%d ventana=%d" % [settings._applied_shadow_filter_quality,
			root.positional_shadow_atlas_size])

	# Turning shadows off is a change of the applied size to zero, not a
	# no-op, however the ladder's own size is left set.
	settings.graphics_shadows_enabled = false
	settings.apply_settings()
	_check("apagar sombras baja el tamano aplicado a cero",
		settings._applied_shadow_atlas_size == 0,
		"atlas=%d" % settings._applied_shadow_atlas_size)

	print("")
	if _checks < 6:
		print("FALLO: solo %d de 6 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - las sombras solo se re-aplican cuando cambian")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-50s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-50s%s" % [label, "  (%s)" % detail if detail else ""])
