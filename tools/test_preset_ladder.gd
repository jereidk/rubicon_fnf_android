extends SceneTree

## La escalera de calidad tiene que bajar de coste en cada peldaño.
##
## Este fichero existe porque no lo hacía. `qol_very_low.tres` shipeaba
## `render_scale = 0.7` contra el `0.65` de Low: el preset de emergencia
## renderizaba MÁS píxeles de 3D que el que va justo encima, o sea que bajar
## de Low a Very Low empeoraba el frame en la única mitad que este proyecto
## tiene medida como dominante.
##
## El modelo medido en el g53 del usuario (Adreno 619, 1600x720, dos pasadas
## de Chimera a 0.50 y a 0.70 con `bench=` de control):
##
##     gpu = 5.7ms + 90.8ms x Mpx del pase 3D
##
##     scale 0.70 -> 0.564 Mpx -> 57.0ms   (17.6 fps)   <- lo que shipeaba
##     scale 0.65 -> 0.487 Mpx -> 49.9ms   (20.0 fps)   <- Low
##     scale 0.55 -> 0.348 Mpx -> 37.3ms   (26.8 fps)   <- Very Low ahora
##     scale 0.50 -> 0.288 Mpx -> 31.9ms   (31.4 fps)
##
## (Control del ajuste: a 0.50 el modelo predice 31.9ms y el histórico medido
## de Chimera son 31.85ms.)
##
## Es la cuarta vez que un preset no baja lo que dice bajar - las tres
## anteriores están escritas en CLAUDE.md (render scale existiendo sólo en
## Very Low, el atlas de sombras de Medium idéntico al de High,
## `anisotropic_filtering` y `mesh_lod_threshold` sin cablear). Las tres se
## encontraron leyendo código meses tarde. Esta puerta las convierte en un
## fallo de build.
##
## La regla que fija: para cada campo de la escalera, High >= Medium >= Low >=
## Very Low en COSTE. Un campo omitido en un `.tres` toma el default del
## `@export`, así que la comparación se hace sobre el recurso cargado y no
## sobre el texto - que es exactamente el fallo que dejó a Medium con el atlas
## de High.
##
## Correr con:
##   godot --headless --path . --script tools/test_preset_ladder.gd

const PRESETS: Array[String] = [
	"res://lullaby_mod/resources/quality_presets/qol_high.tres",
	"res://lullaby_mod/resources/quality_presets/qol_medium.tres",
	"res://lullaby_mod/resources/quality_presets/qol_low.tres",
	"res://lullaby_mod/resources/quality_presets/qol_very_low.tres",
]

## Campos en los que un número MAYOR cuesta más GPU. Se exige no creciente.
const COSTLIER_WHEN_HIGHER: Array[StringName] = [
	&"render_scale",
	&"positional_shadow_atlas_size",
	&"positional_shadow_filter_quality",
	&"msaa_3d_quality",
	&"screen_space_aa_quality",
	&"post_processing",
	&"anisotropic_filtering",
	&"physics_ticks_per_second",
]

## Campos en los que un número MAYOR cuesta menos - son recortes, no calidad.
## `mesh_lod_threshold` tira detalle antes cuanto más alto; `atlas_frame_step`
## salta más fotogramas de atlas.
const CHEAPER_WHEN_HIGHER: Array[StringName] = [
	&"mesh_lod_threshold",
	&"atlas_frame_step",
]

## Booleanos que sólo pueden apagarse según se baja, nunca volver a encenderse.
const OFF_ONLY: Array[StringName] = [
	&"shadows_enabled",
	&"ssao",
	&"ssil",
]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var loaded: Array[LullabyQualityPreset] = []
	for path: String in PRESETS:
		var preset: Resource = load(path)
		_check(preset != null, "carga %s" % path.get_file())
		if preset == null:
			_finish()
			return
		loaded.append(preset)

	for field: StringName in COSTLIER_WHEN_HIGHER:
		_ladder(loaded, field, false)
	for field: StringName in CHEAPER_WHEN_HIGHER:
		_ladder(loaded, field, true)

	for field: StringName in OFF_ONLY:
		for i: int in range(1, loaded.size()):
			var above: bool = loaded[i - 1].get(field)
			var here: bool = loaded[i].get(field)
			_check(not (here and not above),
				"%s: %s no lo reenciende despues de %s" %
				[field, loaded[i].name, loaded[i - 1].name])

	# `light_distance_fade` es un multiplicador sobre el alcance de cada luz
	# pasado el cual deja de renderizarse, y 0 desactiva el pase entero. O sea
	# que 0 es "sin recorte" y un numero positivo mas pequeño recorta antes.
	for i: int in range(1, loaded.size()):
		var above: float = loaded[i - 1].light_distance_fade
		var here: float = loaded[i].light_distance_fade
		var above_cost: float = INF if is_zero_approx(above) else above
		var here_cost: float = INF if is_zero_approx(here) else here
		_check(here_cost <= above_cost,
			"light_distance_fade: %s (%.1f) no recorta menos que %s (%.1f)" %
			[loaded[i].name, here, loaded[i - 1].name, above])

	# Y los dos recortes que son booleanos "una vez puesto, no se quita".
	for field: StringName in [&"disable_shader_effects", &"hide_baked_lights"]:
		for i: int in range(1, loaded.size()):
			_check(not (loaded[i - 1].get(field) and not loaded[i].get(field)),
				"%s: %s no lo desactiva tras %s" %
				[field, loaded[i].name, loaded[i - 1].name])

	# El peldaño concreto que motivó este fichero, fijado por su nombre para
	# que el fallo diga de que iba en vez de solo "render_scale sube".
	var low: LullabyQualityPreset = loaded[2]
	var very_low: LullabyQualityPreset = loaded[3]
	_check(very_low.render_scale < low.render_scale,
		"Very Low (%.2f) renderiza menos pixeles de 3D que Low (%.2f)" %
		[very_low.render_scale, low.render_scale])

	# Very Low existe para que el juego corra, no para que se vea: capar el
	# frame a algo que el telefono sostiene es lo que quita el tartamudeo, y
	# es su propia fila del preset desde siempre sin que nadie la moviera.
	_check(very_low.target_fps > 0 and very_low.target_fps <= 30,
		"Very Low capa el frame (target_fps=%d)" % very_low.target_fps)

	_finish()


func _ladder(loaded: Array[LullabyQualityPreset], field: StringName,
		higher_is_cheaper: bool) -> void:
	for i: int in range(1, loaded.size()):
		var above: float = float(loaded[i - 1].get(field))
		var here: float = float(loaded[i].get(field))
		var ok: bool = here >= above if higher_is_cheaper else here <= above
		_check(ok, "%s: %s (%s) no cuesta menos que %s (%s)" %
			[field, loaded[i].name, str(loaded[i].get(field)),
			loaded[i - 1].name, str(loaded[i - 1].get(field))])


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
