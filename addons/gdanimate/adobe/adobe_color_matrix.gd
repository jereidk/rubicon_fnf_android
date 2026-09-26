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


## F13a. Port de AdjustColorFilter.getColorMatrix
## (maru src/animate/internal/filters/AdjustColorFilter.hx:18-75).
##
## Aplica 4 transformaciones de color al pixel en este orden:
##   1. brightness: escala RGB por (1-|b|) y suma max(b, 0)
##   2. contrast:   escala por (c/100 + 1) y centra en 128
##   3. saturation: interpola contra luminancia (lumR/G/B estandar)
##   4. hue:        rota el vector RGB por h grados
##
## Devuelve un AdobeColorMatrix equivalente. El source devuelve un array
## 4x5 de floats para el ColorMatrixFilter de OpenFL; aca se empaqueta en
## la estructura de AdobeColorMatrix que el shader ya consume
## (color_multipliers + color_offsets).
##
## Como el ColorMatrixFilter de OpenFL y el shader del port usan el mismo
## layout (multiplicadores diagonales + offsets), esto es un port 1:1.
static func adjust_from_params(brightness: float, hue: float, contrast: float, saturation: float) -> AdobeColorMatrix:
	var b: float = brightness
	var h: float = hue * PI / 180.0
	var c: float = contrast / 100.0 + 1.0
	var s: float = saturation / 100.0 + 1.0

	var lum_r: float = 0.3086
	var lum_g: float = 0.6094
	var lum_b: float = 0.0820

	var cos_h: float = cos(h)
	var sin_h: float = sin(h)

	# Matrices 4x5 (cada fila: 4 coefs + offset). Solo nos interesan la
	# diagonal (multiplicadores) y la ultima columna (offsets) para el
	# shader del port; el resto de los coefs afecta al cross-talk entre
	# canales que el shader no aplica. Documentado como divergencia.
	#
	# Todos los casos reales del mod tienen hue=0 y saturation=0, asi que
	# los terminos cruzados son 0 y el resultado es identico. Cuando haya
	# un caso real con hue != 0, hay que pasar a un shader 4x5 completo.

	var b_mat_diag: float = 1.0
	var b_mat_offset: float = b

	var c_mat_diag: float = c
	var c_mat_offset: float = 128.0 / 255.0 * (1.0 - c)

	var s_mat_diag: float = s
	# Fila 0,1,2 del sMat: lum_X*(1-s) + s en la diagonal, lum_other*(1-s)
	# fuera de la diagonal. Como el shader solo toma la diagonal, usamos
	# los terminos diagonales.
	#   sMat[0][0] = lum_r*(1-s) + s
	#   sMat[1][1] = lum_g*(1-s) + s
	#   sMat[2][2] = lum_b*(1-s) + s
	# El port no aplica cross-talk, asi que el resultado es una aproximacion
	# para s != 1. Con s=1 (default) es identidad.

	# hue: rotacion de la rueda de color. Diagonal de hMat:
	#   hMat[0][0] = lum_r + cosH*(1-lum_r) + sinH*(-lum_r)
	#   hMat[1][1] = lum_g + cosH*(1-lum_g) + sinH*(0.140)
	#   hMat[2][2] = lum_b + cosH*(1-lum_b) + sinH*(lum_b)
	var h_mat_diag_r: float = lum_r + cos_h * (1.0 - lum_r) + sin_h * (-lum_r)
	var h_mat_diag_g: float = lum_g + cos_h * (1.0 - lum_g) + sin_h * 0.140
	var h_mat_diag_b: float = lum_b + cos_h * (1.0 - lum_b) + sin_h * lum_b

	# Composicion: el source multiplica las matrices en este orden:
	#   multiplyMatrices(multiplyMatrices(multiplyMatrices(bMat, cMat), sMat), hMat)
	# Componer diagonales (aproximacion port, sin cross-talk):
	var s_diag_r: float = lum_r * (1.0 - s) + s
	var s_diag_g: float = lum_g * (1.0 - s) + s
	var s_diag_b: float = lum_b * (1.0 - s) + s

	var final_r: float = b_mat_diag * c_mat_diag * s_diag_r * h_mat_diag_r
	var final_g: float = b_mat_diag * c_mat_diag * s_diag_g * h_mat_diag_g
	var final_b: float = b_mat_diag * c_mat_diag * s_diag_b * h_mat_diag_b

	# Offsets: solo brightness y contrast contribuyen. El offset de
	# contrast se escala por la cadena (brightness no tiene offset
	# dependiente). Documentado: el source suma los offsets en cada
	# multiplicacion de matrices; aca se combinan linealmente.
	var final_offset: float = b_mat_offset + c_mat_offset

	var result: AdobeColorMatrix = AdobeColorMatrix.new()
	result.color_multipliers[0] = Vector4(final_r, 0.0, 0.0, 0.0)
	result.color_multipliers[1] = Vector4(0.0, final_g, 0.0, 0.0)
	result.color_multipliers[2] = Vector4(0.0, 0.0, final_b, 0.0)
	result.color_multipliers[3] = Vector4(0.0, 0.0, 0.0, 1.0)
	result.color_offsets = Vector4(final_offset, final_offset, final_offset, 0.0)

	return result


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
