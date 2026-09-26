@tool
extends Resource
class_name AdobeFilter


## Port de FilterJson (maru dcaa33c, FlxAnimateJson.hx:260-395) + el
## dispatch de FilterJson.toBitmapFilter() (FlxAnimateJson.hx:355-410).
##
## El source tiene 7 tipos implementados para Adobe Animate:
##   BLUR (BLF)                    - BlurFilter de OpenFL
##   ADJUST_COLOR (ACF)            - AdjustColorFilter custom (matriz 4x5)
##   DROP_SHADOW (DSF)             - DropShadowFilter de OpenFL
##   GLOW (GF)                     - GlowFilter de OpenFL
##   BEVEL (BF)                    - BevelFilter de OpenFL (solo flash/openfl 9.5+)
##   GRADIENT_GLOW (GGF)           - solo flash
##   GRADIENT_BEVEL (GBF)          - solo flash
##
## Los dos "gradient*" solo se soportan en target flash, o sea N/A en Godot.
## Se mantienen en el enum para fidelidad del parseo, pero su apply es
## diferido a F13b.
##
## El port guarda los campos crudos del JSON (con fallback a los nombres
## largos legacy igual que el source: `this.BLX ?? this.blurX`).
enum AdobeFilterType {
	BLUR = 0, 
	ADJUST_COLOR = 1, 
	DROP_SHADOW = 2, 
	GLOW = 3, 
	BEVEL = 4, 
	GRADIENT_GLOW = 5, 
	GRADIENT_BEVEL = 6, 
}


@export_storage var type: AdobeFilterType = AdobeFilterType.BLUR
@export_storage var data: Dictionary = {}


## Devuelve la clave del JSON: nombre corto (optimized) o largo (legacy).
## Mismo patron que `FilterJson.get_BLX` (FlxAnimateJson.hx:281-282):
##     this.BLX ?? this.blurX
static func _pick(data: Dictionary, short: String, long: String) -> Variant:
	var v: Variant = data.get(short)
	if v != null:
		return v
	return data.get(long)


## Devuelve el valor o un default si la clave falta.
static func _pick_or(data: Dictionary, short: String, long: String, default: Variant) -> Variant:
	var v: Variant = _pick(data, short, long)
	return v if v != null else default


## Port de FilterJson.toBitmapFilter() (FlxAnimateJson.hx:355-410): dispatch
## por `N` (short) o `name` (long). Devuelve null si el filtro no es
## reconocido. El source tambien emite `FlxG.log.warn` en ese caso.
static func parse_one(raw: Dictionary) -> AdobeFilter:
	if raw == null or raw.is_empty():
		return null

	var name: Variant = _pick(raw, "N", "name")
	if name == null:
		return null

	var filter: AdobeFilter = AdobeFilter.new()
	filter.data = raw.duplicate(true)

	match String(name):
		"blurFilter", "BLF":
			filter.type = AdobeFilterType.BLUR
		"adjustColorFilter", "ACF":
			filter.type = AdobeFilterType.ADJUST_COLOR
		"dropShadowFilter", "DSF":
			filter.type = AdobeFilterType.DROP_SHADOW
		"glowFilter", "GF":
			filter.type = AdobeFilterType.GLOW
		"bevelFilter", "BF":
			filter.type = AdobeFilterType.BEVEL
		"gradientGlowFilter", "GGF":
			filter.type = AdobeFilterType.GRADIENT_GLOW
		"gradientBevelFilter", "GBF":
			filter.type = AdobeFilterType.GRADIENT_BEVEL
		_:
			# Filtro desconocido: el source tambien lo descarta.
			return null

	return filter


## Port de FilterJson.resolve (FlxAnimateJson.hx:419-440): si `input` es un
## Array se devuelve tal cual; si es un Dictionary con claves como
## "DropShadowFilter" / "GlowFilter" / etc. (formato no-optimized), se
## convierte a un Array de dicts con la clave `N` inyectada.
##
## El source lo usa en `SymbolInstanceJson.get_F`:
##     var filters = this.F ?? this.filters;
##     if (filters == null || filters is Array) return filters;
##     return this.F = FilterJson.resolve(filters);
static func parse_list(input: Variant) -> Array[AdobeFilter]:
	var result: Array[AdobeFilter] = []

	if input == null:
		return result

	var items: Array = []
	if input is Array:
		items = input as Array
	elif input is Dictionary:
		# Formato no-optimized: el dict tiene un campo por filtro
		# ("DropShadowFilter": {...}, "GlowFilter": {...}).
		for key: String in (input as Dictionary).keys():
			var raw: Variant = (input as Dictionary)[key]
			if raw is Dictionary:
				var item: Dictionary = (raw as Dictionary).duplicate(true)
				# El source inyecta el nombre corto via el `switch (filter)`.
				var short_name: String = _long_to_short(key)
				if not item.has("N"):
					item["N"] = short_name
				items.append(item)
	else:
		return result

	for raw: Variant in items:
		if raw is Dictionary:
			var filter: AdobeFilter = parse_one(raw as Dictionary)
			if filter != null:
				result.append(filter)

	return result


## Port del `switch (filter)` en FilterJson.resolve
## (FlxAnimateJson.hx:425-436): mapea el nombre del campo del dict al short.
static func _long_to_short(name: String) -> String:
	match name:
		"DropShadowFilter": return "DSF"
		"GlowFilter": return "GF"
		"BevelFilter": return "BF"
		"BlurFilter": return "BLF"
		"AdjustColorFilter": return "ACF"
		"GradientGlowFilter": return "GGF"
		"GradientBevelFilter": return "GBF"
		_: return name


## Helper para derivar el glow compat del array de filtros: primer GLOW.
## Devuelve {} si no hay ninguno. Los campos son los mismos que espera el
## shader inline actual (`atlas_shader.gdshader`), que sigue funcionando
## con estos datos hasta que F13b porte el render-to-texture real.
##
## Campos del JSON (FlxAnimateJson.hx:277-350):
##   C / color       - hex string del color
##   A / alpha       - multiplicador de alpha (default 1.0)
##   BLX / blurX     - radio horizontal del blur
##   BLY / blurY     - radio vertical
##   STR / strength  - strength / 100 en el source
##   Q / quality     - muestras del blur
##   IN / inner      - glow interno
##   KK / knockout   - oculta el sprite original
static func extract_glow_compat(filters: Array[AdobeFilter]) -> Dictionary:
	for filter: AdobeFilter in filters:
		if filter.type != AdobeFilterType.GLOW:
			continue
		var d: Dictionary = filter.data
		return {
			"color": _pick_or(d, "C", "color", "#FFFFFF"),
			"alpha": float(_pick_or(d, "A", "alpha", 1.0)),
			"blur_x": float(_pick_or(d, "BLX", "blurX", 6.0)),
			"blur_y": float(_pick_or(d, "BLY", "blurY", 6.0)),
			"strength": float(_pick_or(d, "STR", "strength", 1.0)),
			"quality": int(_pick_or(d, "Q", "quality", 1)),
			"inner": bool(_pick_or(d, "IN", "inner", false)),
			"knockout": bool(_pick_or(d, "KK", "knockout", false)),
		}
	return {}
