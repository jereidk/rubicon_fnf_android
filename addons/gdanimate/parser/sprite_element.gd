class_name SpriteElement extends Element


func _init() -> void:
	type = ElementType.SPRITE


func parse_unoptimized(input: Dictionary) -> void:
	var sprite: Dictionary = input.get('ATLAS_SPRITE_instance', {})
	name = StringName(sprite.get('name', ''))
	super(sprite.get('Matrix3D', {}))


func parse_optimized(input: Dictionary) -> void:
	var sprite: Dictionary = input.get('ASI', {})
	name = StringName(sprite.get('N', ''))

	# Some exports (e.g. Safety Lullaby's GF) use a compact 2D-only "MX"
	# affine (6 floats: a, b, c, d, tx, ty) instead of the flattened 4x4
	# "M3D" the base class expects - see SymbolElement.parse_optimized()
	# for the fuller story.
	if sprite.has('MX'):
		var mx: Array = sprite.get('MX', [])
		if mx.size() < 6:
			printerr('Invalid Matrix MX')
			return
		transform = Transform2D(Vector2(mx[0], mx[1]), Vector2(mx[2], mx[3]), Vector2(mx[4], mx[5]))
		return

	# Small conversion because inheritance yucky
	var m3d: Array = sprite.get('M3D', [])
	var m3d_dict: Dictionary = {}
	for i: int in m3d.size():
		m3d_dict.set(i, m3d[i])
	super(m3d_dict)
