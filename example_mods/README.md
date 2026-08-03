# Mods folder

Rubicon looks for mods in a `mods/` folder:

- **Windows/Linux/macOS (exported build):** next to the game's executable.
- **Windows/Linux/macOS (running from the Godot editor):** at the project root (`res://mods`), so it's easy to test without hunting for it.
- **Android/iOS/Web:** under the app's own data directory (`user://mods`), since those platforms don't allow writing next to the executable.

Each subfolder of `mods/` is one mod. `Mods.get_mods_root()` (autoload) tells you the exact resolved path at runtime.

## `mod.json` (optional)

Drop this at the root of your mod folder to control how it shows up in the in-game mods menu:

```json
{
	"name": "Example Mod",
	"description": "What this mod does.",
	"version": "1.0.0",
	"author": "Your Name",
	"global": false
}
```

`global: true` mirrors Psych Engine's `pack.json` → `runsGlobally`: the mod is always active and can't be turned off from the menu — useful for mods that only add shared assets/fixes rather than full content packs.

If `mod.json` is missing, the mod still loads (enabled by default), it just gets no metadata and shows up under its folder name.

## Adding content: `.pck` files

The main way to add or override content (characters, songs, stages, even new scripts) is to build it as a **Godot project that uses the Rubicon addon**, then export just your new/changed resources as a `.pck`, and drop that `.pck` anywhere inside your mod folder. At boot, Rubicon mounts every `.pck` it finds under each enabled mod folder on top of the base game (`ProjectSettings.load_resource_pack`, with override enabled).

- To **override** existing content, your resources must sit at the exact same `res://` path as the file you're replacing (e.g. a `.pck` containing `res://resources/levels/characters/bf.tscn` replaces that character everywhere it's referenced).
- To **add** new content, use a path the base game doesn't already use, and make sure whatever loads it (a song list, character list, etc.) actually scans that location.
- Packs are additive for the lifetime of the process — Godot doesn't support cleanly unmounting one. Toggling a `.pck`-based mod on/off in the mods menu only takes effect after restarting the game.

## Simple overrides: loose files

For assets that don't need the full Godot import pipeline (audio, images, JSON, etc.), you can drop loose files directly in your mod folder instead of packing them. Engine/game code that wants to support this calls:

```gdscript
Mods.get_asset_path("images/menu/background.png")
```

which checks every enabled (and every `global`) mod folder, in priority order, for `<mod>/images/menu/background.png`, and falls back to `res://images/menu/background.png` if no mod provides it — mirroring Psych Engine's `Paths.modFolders()`. This resolves live, no restart needed, but it's opt-in per feature: it only works for code paths that were written to call `Mods.get_asset_path()` instead of loading straight from `res://`.

## Mod priority / enabling

`Mods.mod_list` is ordered by priority — earlier entries win when multiple mods provide the same loose-file path. The order and each mod's enabled state persist to `user://mods_list.json` (equivalent to Psych's `modsList.txt`) and can be changed from `RubiconModsMenu` (`addons/rubicon/scenes/mods/rubicon_mods_menu.tscn`) or via `Mods.set_mod_enabled(folder, enabled)` / `Mods.set_mod_priority(folder, index)`.

## Playing a mod

Since Rubicon doesn't have a real main menu yet, the `Mods` autoload adds a small always-on-top "Mods" text button (`rubicon_mods_button.tscn`) so you can reach the menu from anywhere right now. Once a real game menu exists, call `Mods.set_entry_button_visible(false)` and have your own menu button call `Mods.open_menu()` instead — the standalone button is just a placeholder for that.

Pressing "Jugar" next to a mod calls `Mods.enter_mod(folder)`: it enables that mod, promotes it to the top of the priority list (making it [`Mods.get_current_mod()`](../addons/rubicon/scripts/mods/rubicon_mods.gd)), and reloads the current scene, mirroring Psych Engine's "the top of your enabled mods list is the mod you're currently in" behavior (`currentModDirectory`). "Jugar sin mods" (`Mods.exit_to_base()`) turns every non-global mod off and reloads, going back to the unmodded base game. The checkbox next to each mod is separate from this — it layers a mod on/off (useful for `global` add-ons) without changing which mod is "in front".
