# mod.json - Format Reference

Everything a mod needs is a folder and a `mod.json` at its root. The engine scans a few known locations, reads each folder's manifest, and shows the mod in the selector. When the user plays it, the engine packages the folder into a `.pck`, mounts it, and runs the entry point.

This document is the reference for the manifest itself. For a guided tutorial, see [GETTING_STARTED.md](GETTING_STARTED.md).

---

## Where mods live

The engine scans three roots in order of priority. If the same folder name exists in more than one root, the first one wins.

| Root | Notes |
|---|---|
| `user://mods` | App-private. Always readable and writable. |
| `/storage/emulated/0/WashosEngine/mods` | Shared storage. Requires `MANAGE_EXTERNAL_STORAGE`. Recommended for user-installed mods. |
| `/storage/emulated/0/.WashosEngine/mods` | Historically supported. Hidden folders can fail on Android 11+ scoped storage. |

The second one (without the leading dot) is the recommended location. It's visible in any file manager and works on all Android versions the engine supports.

Each mod is its own folder. The manifest must be named `mod.json` and live directly inside:

    WashosEngine/mods/
      my_mod/
        mod.json          <- required
        main.gd           <- example entry point
        Icon.png          <- optional
        ...anything else

---

## Full schema

    {
      "name": "My Mod",
      "version": "1.0.0",
      "author": "your_name",
      "description": "Short description for the mod manager.",
      "icon": "Icon.png",
      "background_color": "#3a1a4a",
      "main_scene": "res://main.gd",
      "autoloads": {
        "MyGlobal": "res://globals/my_global.gd"
      },
      "settings": {
        "display/window/stretch/mode": "canvas_items",
        "display/window/stretch/aspect": "keep"
      }
    }

### `name` (string, required)

Display name shown in the mod selector and mod manager. Any string.

### `version` (string, optional)

Free-form. Shown in the mod manager next to the name. Convention is semantic versioning (`"1.0.0"`), but nothing enforces it.

### `author` (string, optional)

Your name or handle. Shown in the mod manager.

### `description` (string, optional)

One or two sentences for the mod manager list. Longer text is truncated with ellipsis. Use a literal `\n` for a line break in the details popup.

### `icon` (string, optional)

Path to a PNG used as the preview in the mod selector's right panel. Two forms accepted:

- `"Icon.png"` - relative to the mod's folder.
- `"res://path/to/file.png"` - also resolved relative to the mod's folder.

If you don't set `icon`, the engine looks for these in order:

1. `Icon.png` (capital I) at the mod root.
2. `icon.png` at the mod root.
3. `icon.ktx`, `icon.webp`, `icon.svg` at the mod root.
4. Nothing - falls back to the animated logoBumpin in the selector's preview panel.

The file is read directly from disk (not via `res://`), so it works even for mods that aren't currently loaded.

### `background_color` (string, optional)

Hex color used to tint the selector's background when this mod is selected. Accepted formats:

- `"#RRGGBB"`
- `"RRGGBB"`
- `"#RRGGBBAA"`
- `"RRGGBBAA"`

The selector applies it via a duotone shader that preserves the brush texture and dark strokes. The transition between two mods' colors is a smooth 0.35s tween.

If unset, the default yellow (`#f5d24a`) is used.

### `main_scene` (string, required)

The entry point. Two forms:

- `"res://path/to/scene.tscn"` - a Godot scene, loaded via `change_scene_to_file`.
- `"res://path/to/script.gd"` - a GDScript, compiled and instantiated as the scene root. The script must extend something that inherits from `Node` (`Control`, `Node2D`, `Node3D`, etc.).

Paths are relative to the mod folder. The `res://` prefix is required even though the file lives outside the APK - the engine maps it at load time.

If the mod has no `mod.json` at all, the engine tries `res://main.gd` first, then `res://main.tscn`.

### `autoloads` (object, optional)

Named globals the mod wants available everywhere, like Godot's own autoloads. Each key is the name to expose; each value is the script's `res://` path.

    "autoloads": {
      "MyGlobal": "res://globals/my_global.gd",
      "MyPlayer": "res://globals/player_state.gd"
    }

Each script must extend `Node` (or a subclass). The engine:

1. Sets `ProjectSettings["autoload/<name>"]` so the identifier is resolvable by scripts.
2. Compiles the script from disk.
3. Creates a node and adds it to `/root`.

Once installed, any script in the mod can reference `MyGlobal` directly:

    func _ready() -> void:
        MyGlobal.do_something()
        print(MyGlobal.some_property)

**Notes:**

- If the name is already taken (by the engine or by another mod), the autoload is skipped with a warning. First mod wins.
- Uninstalling a mod removes its autoloads. Toggling a mod off does **not** - the `.pck` stays mounted until restart, so removing the nodes would leave the mod in an inconsistent state.

### `settings` (object, optional)

ProjectSettings overrides the mod wants applied when the user launches it. **Only a whitelist is honored.** Anything else logs a warning and is ignored.

| Setting | Value type | Effect |
|---|---|---|
| `display/window/stretch/mode` | `"disabled"`, `"canvas_items"`, `"viewport"` | Content scaling mode of the root Window |
| `display/window/stretch/aspect` | `"ignore"`, `"keep"`, `"keep_width"`, `"keep_height"`, `"expand"` | How the aspect ratio is handled |

Example:

    "settings": {
      "display/window/stretch/mode": "canvas_items",
      "display/window/stretch/aspect": "keep"
    }

The settings apply just before the scene change in `ModSelector._launch()`, and are restored to their original values when the user returns to the selector or opens the mod manager. One mod's settings don't leak into another's.

**Why only these two:** most Godot project settings are read once at startup and never again. Changing them at runtime with `ProjectSettings.set_setting()` has no effect on the already-initialized subsystem. The two above map to live `Window` properties (`content_scale_mode` and `content_scale_aspect`), so they can be changed on the fly. More settings may be added to the whitelist in future versions.

---

## Optional fields, briefly

The manifest is parsed as a plain dictionary - the engine doesn't reject unknown keys. If you add `"homepage": "https://..."` or similar, it's stored on the mod's metadata and shown in the mod manager's details popup (if a UI for it exists). Use this for anything you want; nothing engine-side depends on it.

---

## Reserved names

- `mod.json` - the manifest. Don't use this name for anything else.
- `config/` - at the root of a mods root, not inside a mod. Reserved for the engine's own state.

---

## What the engine packages

When a mod is launched, the engine walks the mod folder and packages every file into a `.pck`. Two groups of extensions are treated differently:

**Read via a custom runtime loader** (raw from disk, not from the pck):

- `.png`, `.jpg`, `.jpeg`, `.webp`, `.svg` - textures
- `.ttf`, `.otf` - fonts
- `.ogv` - Theora video
- `.ktx`, `.astc` - compressed textures
- `.glb`, `.gltf` - 3D models
- `.gdshader` - shaders
- `.ogg`, `.mp3`, `.wav` - audio

**Everything else goes into the `.pck`**, including `.gd`, `.tscn`, `.tres`, `.scn`, `.res`, `.json`, `.xml`, `.cfg`, and any other format. The `.pck` is mounted via `load_resource_pack()` and its contents become visible as `res://<original path>`.

You don't need to know this unless you're debugging loader issues. In practice it works transparently.

---

## Common gotchas

**The mod doesn't appear in the list.**
- Folder path is wrong. Check that `mod.json` is directly inside the mod folder, not one level deeper.
- Invalid JSON. A trailing comma or missing quote silently drops the mod. Validate with `jq . mod.json` on a desktop or any online JSON validator.

**`No loader found for res://...`.**
- `main_scene` points to a file that doesn't exist. Check case sensitivity - Godot treats paths as case-sensitive even if the underlying filesystem doesn't.

**The mod loads but nothing is visible.**
- If the main scene is a `.gd`, it must extend something under `Node` and add a visible subtree in `_ready()`.
- If using a `Control`, call `set_anchors_preset(Control.PRESET_FULL_RECT)` first - otherwise the node has size 0.
- If using a `Node2D`, coordinates are absolute (no anchors). Use `get_viewport_rect().size` for the screen size.

**`Cannot infer the type of "x"`.**
- Known Godot 4.7 limitation with autoloads installed at runtime. Prefer explicit types (`var x: bool = ...`) over `:=` when the right-hand side calls into an autoload.

**Autoloads don't exist.**
- Another mod or the engine already claimed that name. Check the debug log for `[autoload] <name> ya existe en /root, skip`.
- The script for the autoload has a compile error. Look for `no compila`.

**Settings are ignored.**
- The key isn't in the whitelist. The engine logs `[ModLoader] <mod>: setting no soportado (whitelist): <key>`.
- The value isn't in the accepted list (see the table above).

---

## See also

- [GETTING_STARTED.md](GETTING_STARTED.md) - build your first mod in 10 minutes.
- [mod_schema.json](../mod_schema.json) - JSON Schema for editor autocompletion.
