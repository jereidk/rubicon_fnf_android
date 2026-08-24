extends SceneTree
func _initialize() -> void:
	var p: LullabyQualityPreset = load("res://lullaby_mod/resources/quality_presets/qol_very_low.tres")
	print("cargado: %s" % p.name)
	print("has_method('is_matching') = %s" % p.has_method("is_matching"))
	print("has_method('matches')     = %s" % p.has_method("matches"))
	print("ahora la llamada tipada...")
	print(p.matches(null))
	quit()
