@tool
class_name AdobeColorMatrix
extends Resource


@export_storage var color_multipliers: Array[Vector4]
@export_storage var color_offsets: Vector4 = Vector4.ZERO


func _init() -> void :
	color_multipliers = [
		Vector4(1.0, 0.0, 0.0, 0.0), 
		Vector4(0.0, 1.0, 0.0, 0.0), 
		Vector4(0.0, 0.0, 1.0, 0.0), 
		Vector4(0.0, 0.0, 0.0, 1.0), 
	]


func concat(another: AdobeColorMatrix) -> AdobeColorMatrix:
	var matrix: AdobeColorMatrix = AdobeColorMatrix.new()
	matrix.color_multipliers = color_multipliers.duplicate()
	matrix.color_offsets = color_offsets + another.color_offsets

	for i: int in color_multipliers.size():
		matrix.color_multipliers[i] *= another.color_multipliers[i]

	return matrix


## Resuelve una clave del bloque color probando primero el nombre corto y
## cayendo al largo, igual que los getters de ColorJson en
## maru/src/animate/FlxAnimateJson.hx:646-700 (`this.RM ?? this.RedMultiplier`,
## etc). Antes esto elegia el esquema con un flag global heredado del parser,
## asi que un bloque color en formato largo dentro de un Animation.json
## optimizado (o al reves) devolvia null en TODOS los campos y el tint se
## perdia sin aviso. Ver adobe_atlas.gd:get_pair para el detalle.
static func _pair(data: Dictionary, optim: String, unoptim: String) -> Variant:
	var short: Variant = data.get(optim)
	if short != null:
		return short
	return data.get(unoptim)


static func parse(_optimized: bool, data: Dictionary) -> AdobeColorMatrix:
	var matrix: AdobeColorMatrix = AdobeColorMatrix.new()
	var mode: Variant = _pair(data, "M", "mode")
	if mode == null or mode is not String:
		return matrix

	var rm: Variant = _pair(data, "RM", "RedMultiplier")
	var ro: Variant = _pair(data, "RO", "redOffset")

	var gm: Variant = _pair(data, "GM", "greenMultiplier")
	var go: Variant = _pair(data, "GO", "greenOffset")

	var bm: Variant = _pair(data, "BM", "blueMultiplier")
	var bo: Variant = _pair(data, "BO", "blueOffset")

	var am: Variant = _pair(data, "AM", "alphaMultiplier")
	var ao: Variant = _pair(data, "AO", "AlphaOffset")

	match mode:
		"AD", "Advanced":
			matrix.color_multipliers[0] *= float(rm)
			matrix.color_multipliers[1] *= float(gm)
			matrix.color_multipliers[2] *= float(bm)
			matrix.color_multipliers[3] *= float(am)
			matrix.color_offsets = Vector4(
				float(ro) / 255.0, 
				float(go) / 255.0, 
				float(bo) / 255.0, 
				float(ao) / 255.0, 
			)
		"CA", "Alpha":
			matrix.color_multipliers[3] *= float(am)
		"CBRT", "Brightness":
			var brt: Variant = _pair(data, "BRT", "brightness")
			var brightness: float = float(brt)

			var color_mult: float = 1.0 - absf(brightness)
			matrix.color_multipliers[0] *= float(color_mult)
			matrix.color_multipliers[1] *= float(color_mult)
			matrix.color_multipliers[2] *= float(color_mult)

			var color_offset: float = maxf(brightness, 0.0)
			matrix.color_offsets += Vector4(
				color_offset, color_offset, color_offset, 0.0, 
			)
		"T", "Tint":
			var tc: Variant = _pair(data, "TC", "tintColor")
			var tm: Variant = _pair(data, "TM", "tintMultiplier")

			var tint: Color = Color.from_string(String(tc), Color.WHITE)
			var tint_mult: float = float(tm)
			var mult: float = 1.0 - tint_mult
			matrix.color_multipliers[0] *= mult
			matrix.color_multipliers[1] *= mult
			matrix.color_multipliers[2] *= mult
			matrix.color_offsets = Vector4(
				tint.r * tint_mult, 
				tint.g * tint_mult, 
				tint.b * tint_mult, 
				0.0, 
			)

	return matrix
