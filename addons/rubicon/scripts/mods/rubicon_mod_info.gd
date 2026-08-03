class_name RubiconModInfo extends RefCounted
## Metadata describing a single mod folder found under [method RubiconMods.get_mods_root].
## Populated from the mod's "mod.json" manifest, if present.

## Name of the mod's folder on disk. Used as its unique identifier.
var folder_name: String = ""
## Human-readable name shown in the mods menu. Defaults to [member folder_name].
var display_name: String = ""
var description: String = ""
var version: String = ""
var author: String = ""
## If true, this mod's packs/overrides are always active, regardless of [member enabled].
## Mirrors Psych Engine's "runsGlobally" pack.json field.
var global: bool = false
## Whether the user has this mod turned on. Ignored when [member global] is true.
var enabled: bool = true

func get_root_path() -> String:
	return Mods.get_mods_root().path_join(folder_name)
