extends SceneTree

## Golden-image tests con assets REALES del mod holyquintet (menu principal,
## 8 items). Los .Animation.json + spritemap*.json/png NO estan en el repo -
## se extraen de la branch origin/holyquintet-port a res://.test_assets/
## (gitignorado localmente via .git/info/exclude, ver FIDELITY.md/DESIGN.md).
##
## Para regenerar los assets de prueba:
##   git fetch origin holyquintet-port
##   mkdir -p .test_assets/hq_menu && cd .test_assets/hq_menu
##   git --git-dir=<repo>/.git archive origin/holyquintet-port \
##     holyquintet_mod/source/images/ui/main/anim_story \
##     holyquintet_mod/source/images/ui/main/anim_freeplay \
##     holyquintet_mod/source/images/ui/main/anim_gauntlet \
##     holyquintet_mod/source/images/ui/main/anim_credits \
##     holyquintet_mod/source/images/ui/main/anim_accolades \
##     holyquintet_mod/source/images/ui/main/anim_gallery \
##     holyquintet_mod/source/images/ui/main/anim_settings \
##     holyquintet_mod/source/images/ui/main/anim_shop \
##     | tar -x
##   # despues mover holyquintet_mod/source/images/ui/main/anim_* a
##   # res://.test_assets/hq_menu/
##
## Uso:
##   xvfb-run -a <Godot> --rendering-driver opengl3 --path <repo> \
##     -s res://addons/gdanimate/tests/visual/run_visual_tests.gd
##
## Posicion/escala/symbol por item calcados de
## holyquintet_mod/ui/main_menu_sprite.gd:ITEM_DATA (mod real, NO se toca -
## solo se lee para reproducir el mismo setup). offset = stage_transform.origin
## replica el workaround que ese mismo archivo ya documenta: draw_on() solo
## aplica stage_transform cuando el symbol NO esta en el diccionario, y estos
## simbolos raiz SI estan, asi que main_menu_sprite.gd lo compensa a mano en
## vez de usar apply_stage_matrix (que ademas nunca prende para estos nodos -
## no hay conflicto con el fix de apply_stage_matrix de la sesion anterior,
## simplemente no se usa aca).

const ASSET_ROOT := "res://.test_assets/hq_menu/"
const OUTPUT_DIR := "res://addons/gdanimate/tests/visual/output/"

const ITEMS := {
	"story": {"folder": "anim_story", "symbol": "Story_Animation", "position": Vector2(1300, 1000), "scale": Vector2(1.15, 1.15)},
	"freeplay": {"folder": "anim_freeplay", "symbol": "Freeplay_Animation", "position": Vector2(-2325, -250), "scale": Vector2(1.15, 1.15)},
	"gauntlet": {"folder": "anim_gauntlet", "symbol": "Gauntlet_Animation", "position": Vector2(-1250, -1100), "scale": Vector2(1.1, 1.1)},
	"credits": {"folder": "anim_credits", "symbol": "Credits_Animation", "position": Vector2(675, 675), "scale": Vector2(1.15, 1.15)},
	"accolades": {"folder": "anim_accolades", "symbol": "Accolades_Animation", "position": Vector2(-1300, 370), "scale": Vector2(1.2, 1.2)},
	"gallery": {"folder": "anim_gallery", "symbol": "Gallery_Animation", "position": Vector2(850, 750), "scale": Vector2(1.35, 1.35)},
	"settings": {"folder": "anim_settings", "symbol": "Settings_Animation", "position": Vector2(850, 700), "scale": Vector2(1.2, 1.2)},
	"shop": {"folder": "anim_shop", "symbol": "Shop_Animation", "position": Vector2(800, 500), "scale": Vector2(1.0, 1.0)},
}

const KEY_FRAMES := [0, 30, 90, 179]

var _started: bool = false


func _process(_delta: float) -> bool:
	# Mismo gotcha que run_tests.gd: _go() usa await, asi que NO hay que
	# devolver true apenas la arrancamos o el SceneTree se cierra a mitad
	# de camino. quit() la corta cuando termina de verdad.
	if not _started:
		_started = true
		_go()
	return false


func _go() -> void:
	if not DirAccess.dir_exists_absolute(ASSET_ROOT):
		printerr("No existe %s - correr el paso de extraccion del docstring de este archivo primero." % ASSET_ROOT)
		quit(1)
		return

	# Warm-up: ResourceLoader.list_directory() (lo que AdobeAtlas.load_spritemaps
	# usa para encontrar spritemap*.json/png) devolvio listados incompletos
	# (le faltaba el .png) la primera vez que se lo llamo sobre una carpeta
	# recien creada en esta sesion (.test_assets/, fuera del scan normal del
	# editor) - confirmado reproduciendo a mano: la MISMA carpeta, llamada
	# de nuevo unos frames despues, devuelve el listado completo. No es un
	# bug de gdanimate (el parser en si funciono perfecto una vez que el
	# listado vino completo) - es cache del resource filesystem de Godot
	# poniendose al dia. Tocar cada carpeta una vez y dejar pasar unos
	# frames antes de parsear de verdad evita el problema.
	var item_names: Array = ITEMS.keys()
	item_names.sort()

	for item_name: String in item_names:
		ResourceLoader.list_directory(ASSET_ROOT + ITEMS[item_name]["folder"] + "/")
	for i in 10:
		await process_frame

	for item_name: String in item_names:
		var d: Dictionary = ITEMS[item_name]
		var atlas: AdobeAtlas = AdobeAtlas.new()
		atlas.folder_path = ASSET_ROOT + d["folder"] + "/"

		var node: AnimateSymbol = AnimateSymbol.new()
		node.atlases = [atlas]
		node.position = d["position"]
		node.scale = d["scale"]
		node.centered = false
		node.symbol = d["symbol"]
		node.apply_stage_matrix = true

		root.add_child(node)

		var length: int = node.get_animation_length()
		print("%s: symbol=%s length=%d" % [item_name, d["symbol"], length])

		if length <= 0:
			printerr("  %s: get_animation_length() dio 0 - Animation.json no cargo bien?" % item_name)

		for kf: int in KEY_FRAMES:
			var f: int = mini(kf, maxi(length - 1, 0))
			node.frame = f
			for i in 3:
				await process_frame

			var img: Image = root.get_texture().get_image()
			var path: String = "%sanim_%s_f%d.png" % [OUTPUT_DIR, item_name, kf]
			var err: Error = img.save_png(path)
			print("  f%d (real %d): %s (err=%d)" % [kf, f, path, err])

		node.queue_free()
		await process_frame

	print("listo")
	quit(0)
