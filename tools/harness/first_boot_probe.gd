extends Node

## Comprueba la fila de la introduccion del Collector sobre la escena REAL,
## con los autoloads reales.
##
## Tiene que ser una escena y no un `--script`: el `_ready` de first_boot toca
## `Settings` y `SaveData`. El tema (`thm_boot_panel.tres`) no importa en este
## workspace, asi que la escena carga con errores y **no se puede juzgar el
## aspecto desde aqui** - lo que se comprueba es el cableado y las etiquetas.
##
##   godot --headless --path . res://tools/harness/first_boot_probe.tscn

const SCENE := "res://menus/first_boot/first_boot_settings.tscn"

func _ready() -> void:
	for seen: bool in [false, true]:
		var before_flag: bool = SaveData.get_flag(&"intro_seen")
		var before_force: bool = Settings.lullaby_force_shop_intro
		SaveData.set_flag(&"intro_seen", seen)

		var screen: Node = (load(SCENE) as PackedScene).instantiate()
		add_child(screen)

		var row: OptionButton = screen.intro_button
		var labels: PackedStringArray = []
		for i: int in row.item_count:
			labels.append(row.get_item_text(i))
		print("OUT intro_seen=%-5s  opciones=%s  seleccionada=%d" % [seen, labels, row.selected])

		# Y que elegir la segunda opcion escriba lo que toca en cada estado.
		SaveData.set_flag(&"intro_seen", seen)
		Settings.lullaby_force_shop_intro = false
		Settings.force_shop_intro_pending = false
		screen._on_intro_choice_changed(1)
		print("OUT   tras elegir [1]: intro_seen=%s force=%s armado=%s" % [
			SaveData.get_flag(&"intro_seen"), Settings.lullaby_force_shop_intro,
			Settings.force_shop_intro_pending])

		screen.queue_free()
		await get_tree().process_frame
		SaveData.set_flag(&"intro_seen", before_flag)
		Settings.lullaby_force_shop_intro = before_force

	SaveData.save()
	Settings.save()
	get_tree().quit()
