extends Node

## Cuántas veces reconstruyen su caché los AnimationMixer de Chimera, y cuándo.
##
## La hipótesis que mide: los parones de los primeros doce segundos de Chimera
## que NO son compilación de shaders. El log del dispositivo los deja sin dueño:
##
##     t=96.06s  frame=1817ms  pipelines=+0  script_max=0.82ms  vram_delta=+0.0MB
##
## Nada de lo que el log contabiliza explica 1.8 segundos. Y el censo de ese
## mismo instante da la forma sospechosa:
##
##     anim_players=73  playing=10  anim_tracks=301  trees=14(active=14)  bones=586
##
## `AnimationMixer::_update_caches()` recorre todas las pistas de un mixer y
## resuelve cada NodePath contra el árbol. Con 73 reproductores y 586 huesos eso
## no es gratis, y se dispara solo: cambiar de animación, que un nodo entre o
## salga del árbol, o que una pista deje de resolver, invalida la caché. Los
## avisos `couldn't resolve track` del .error salen justo de esa función, y
## aparecen EN PLENO JUEGO (111.55s), no solo al cargar.
##
## No se puede llamar a `_update_caches()` desde fuera ni cronometrarla. Lo que
## sí hay es la señal `caches_cleared`, que el mixer emite al invalidar. Contar
## esas emisiones por nodo y por segundo dice si la hipótesis se sostiene: si
## catorce árboles y setenta y tres reproductores se reconstruyen una y otra vez
## durante esos doce segundos, se ve; si cada uno lo hace una vez al cargar y ya,
## la causa está en otro sitio y esto lo descarta.
##
## Se mide también el tiempo de fotograma, para poder poner las dos series una al
## lado de la otra: una reconstrucción que no cae sobre un fotograma lento no
## explica nada.
##
## Uso:
##   godot --headless --path . res://tools/harness/probe_mixer_caches.tscn
##   ... -- hasta=30

const SONG := "res://lullaby_mod/songs/chimera/sng_chimera.tscn"


func _ready() -> void:
	var until: float = 25.0
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("hasta="):
			until = a.trim_prefix("hasta=").to_float()

	var settings: Node = get_node_or_null(^"/root/Settings")
	if settings != null:
		settings.set("graphics_prefer_cutscene_video", false)

	# Colgado de root ANTES del cambio de escena, que libera la escena actual -
	# esta sonda - y con ella cualquier nodo que estuviera dentro.
	var watcher := Node.new()
	watcher.name = "MixerWatch"
	watcher.set_script(load("res://tools/harness/probe_mixer_watch.gd"))
	# Diferido: durante el _ready() de la escena principal `root` está ocupado
	# montando hijos, y add_child() falla en el sitio con "Parent node is busy
	# setting up children". La sonda se quedaba sin vigilante y la canción corría
	# sin que nadie midiera nada - se veía como "sigue cargando".
	#
	# change_scene_to_file() también se resuelve al final del fotograma y se
	# encola después, así que el vigilante ya está puesto cuando la escena cambia.
	get_tree().root.add_child.call_deferred(watcher)
	watcher.call("setup", until)

	print("OUT montando Chimera, midiendo %.0fs" % until)
	get_tree().change_scene_to_file(SONG)
