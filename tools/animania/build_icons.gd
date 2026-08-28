# Builds komi's and tadano's animated health icons.
#
# Rubicon's health bar has no icon logic at all: RubiconHealthBar moves a PathFollow2D and
# nothing ever changes the two AnimatedSprite2Ds hanging off it - bf_icon.tres carries a
# `neutral` and a `lose` animation and no code switches between them. Animania's icons are
# state machines with transition animations, and komi's sings along with her, so the
# behaviour is a script (animania_mod/scripts/animated_health_icon.gd) and this builds the
# frames it plays.
#
# The names here are Rubicon-side (`sing_left`, `to_losing`) rather than Funkin-side
# (`singLEFT`, `toLosing`), because everything else in this port already speaks that
# dialect and one translation table beats two.
#
#   godot --headless --path . --script tools/animania/build_icons.gd
extends SceneTree

const SOURCE := "res://animania_mod/source/images/icons"
const OUT := "res://animania_mod/characters"

# komi.hx's initHealthIcon, transcribed. LEFT takes the "right" art and vice versa because
# the icon is drawn flipped - flipX = true in the same function - so the mirrored "right"
# pose is what reads as left on screen.
const KOMI_ANIMATIONS := {
	"basic": ["idle", 1.0, true],
	"lose": ["losing", 1.0, true],
	"basic-to-lose": ["to_losing", 24.0, false],
	"lose-to-basic": ["from_losing", 24.0, false],
	"right": ["sing_left", 24.0, false],
	"left": ["sing_right", 24.0, false],
	"up": ["sing_up", 24.0, false],
	"down": ["sing_down", 24.0, false],
	"alt right": ["sing_left_alt", 24.0, false],
	"alt left": ["sing_right_alt", 24.0, false],
	"alt up": ["sing_up_alt", 24.0, false],
	"alt down": ["sing_down_alt", 24.0, false],
}

# tadano's icon is built by AnimaniaStuff.makeAmTakeAnimatedIcon, a module this slice does
# not carry, so what the win and predeath states are FOR is unknown. The frames are built
# anyway - they are in the atlas and dropping them would mean re-deriving this later - but
# only idle/losing and their two transitions are wired up.
const TADANO_ANIMATIONS := {
	"basic": ["idle", 1.0, true],
	"lose": ["losing", 1.0, true],
	"win": ["winning", 1.0, true],
	"predeath": ["predeath", 1.0, true],
	"basic-to-lose": ["to_losing", 24.0, false],
	"lose-to-basic": ["from_losing", 24.0, false],
	"basic-to-win": ["to_winning", 24.0, false],
	"win-to-basic": ["from_winning", 24.0, false],
	"lose-to-predeath": ["to_predeath", 24.0, false],
	"predeath-to-lose": ["from_predeath", 24.0, false],
}


func _init() -> void:
	_build("icon-komi", "komi_icon", KOMI_ANIMATIONS)
	_build("icon-tadano", "tadano_icon", TADANO_ANIMATIONS)
	quit(0)


func _build(source_name: String, basename: String, mapping: Dictionary) -> void:
	var data := SparrowImporterSpriteData.new()
	data.texture = load("%s/%s.png" % [SOURCE, source_name])
	data.atlas_path = "%s/%s.xml" % [SOURCE, source_name]
	data.fps = 24
	data.loop = false
	# sparrow.gd CRASHES with frame durations on: it carries `last_frame` across animation
	# boundaries, so when an animation's first frame has the same region as the previous
	# animation's last frame it does frame_list[anim][find(last_frame)] with find() == -1
	# on a still-empty array. The icon atlases are full of duplicate frames, so both of
	# them hit it. Turning durations off takes the other branch, and for these animations
	# it loses nothing: they are authored at a flat 24fps, unlike the character sheets
	# where held frames carry real timing.
	data.use_frame_duration = false

	var importer: SpriteImporter = load("res://addons/sprite_importer/importers/sparrow.gd").new()
	var frames: SpriteFrames = importer.convert_sprite([data])

	for prefix: String in mapping:
		if not frames.has_animation(prefix):
			push_error("%s no tiene la animacion %s" % [source_name, prefix])
			quit(1)
			return
		var entry: Array = mapping[prefix]
		# tadano's atlas already spells `predeath` the way this port wants it, and renaming
		# an animation to its own name is a collision, not a no-op.
		if prefix != entry[0]:
			frames.rename_animation(prefix, entry[0])
		frames.set_animation_speed(entry[0], entry[1])
		frames.set_animation_loop(entry[0], entry[2])

	# Anything the mapping did not name is art the port has no use for; leaving it in a
	# shipped resource would just be weight nobody can explain later.
	for anim: String in frames.get_animation_names():
		var wanted: bool = false
		for prefix: String in mapping:
			if (mapping[prefix] as Array)[0] == anim:
				wanted = true
				break
		if not wanted:
			print("OUT %s: descartada %s" % [basename, anim])
			frames.remove_animation(anim)

	var path: String = "%s/%s.tres" % [OUT, basename]
	var err: int = ResourceSaver.save(frames, path)
	if err != OK:
		push_error("no se pudo guardar %s (%d)" % [path, err])
		quit(1)
		return

	for anim: String in frames.get_animation_names():
		print("OUT %-16s %-18s %2d fotogramas  %.0f fps  bucle=%s" % [
			basename, anim, frames.get_frame_count(anim),
			frames.get_animation_speed(anim), frames.get_animation_loop(anim)])
	print("OUT guardado %s" % path)
