# Comprueba que la dificultad elegida en el freeplay llega al chart de la cancion.
#
# Las escenas de cancion las genera build_song_scene.gd con UNA dificultad cocida dentro y
# todas las del puerto se generaron con `normal`, asi que elegir HARD y jugar NORMAL era lo
# mismo. Quien lo arregla es el nodo `DifficultyCharts` que cuelga de cada escena; esto lo
# instancia una vez por cancion y por dificultad y ENSENA que chart acabo en cada
# controlador, que es lo unico que demuestra que el cambio se hizo.
#
#   godot --headless --path . --script res://tools/animania/harness/diff_probe.gd
extends SceneTree

const SONGS: PackedStringArray = [
	"res://songs/bopeebo/bopeebo.tscn",
	"res://songs/dadbattle/dadbattle.tscn",
	"res://songs/fresh/fresh.tscn",
	"res://songs/tutorial/tutorial.tscn",
	# phone-call y test traen un chart sin sufijo de dificultad: el nodo debe dejarlo estar.
	"res://songs/phone-call/phone_call.tscn",
	"res://songs/test/test.tscn",
]
const WANTED: PackedStringArray = ["", "easy", "hard", "standart"]


func _initialize() -> void:
	for song: String in SONGS:
		for want: String in WANTED:
			LoadingScreen.target_difficulty = want
			var root: Node = (load(song) as PackedScene).instantiate()
			get_root().add_child(root)
			await process_frame
			var out: Array[String] = []
			for n: Node in root.find_children("*", "RubiconLevelNoteController", true, false):
				var chart: Resource = n.get("chart") as Resource
				out.append("%s=%s" % [n.name, "null" if chart == null
					else chart.resource_path.get_file()])
			print("OUT %-14s %-9s %s" % [song.get_file(), "'%s'" % want, ", ".join(out)])
			root.free()
	quit()
