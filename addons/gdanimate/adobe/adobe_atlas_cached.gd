extends Resource
class_name AdobeAtlasCached


@export_storage var spritemap: Dictionary[StringName, AdobeAtlasSprite] = {}
@export_storage var symbols: Dictionary[StringName, AdobeSymbol] = {}
@export_storage var framerate: float = 24.0
@export_storage var stage_symbol: StringName = &""
@export_storage var stage_transform: Transform2D = Transform2D.IDENTITY
@export_storage var stage_rect: Rect2 = Rect2(0, 0, 1280, 720)
@export_storage var stage_color: Color = Color.WHITE
@export_storage var render_stage: bool = false
