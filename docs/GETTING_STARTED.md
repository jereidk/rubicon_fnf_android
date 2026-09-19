# Getting Started - Your First Mod in 10 Minutes

This walkthrough builds a working mod from scratch and loads it on the device. No Godot editor required, no build step, no prior experience with Godot.

By the end you'll have a "Hola Washos" mod that shows a title, a counter that updates when you tap a button, and a working exit back to the engine's selector.

**Prerequisites:** the engine installed, and file manager access to `/storage/emulated/0/WashosEngine/mods/`.

---

## Step 1 - Create the folder

Open any file manager that can browse shared storage. Navigate to:

    /storage/emulated/0/WashosEngine/mods/

If the folder doesn't exist, create it. Then create a subfolder for your mod:

    /storage/emulated/0/WashosEngine/mods/holawashos/

The name of the folder doesn't matter to the engine - it's just how you identify the mod on disk. Use lowercase with no spaces to avoid surprises.

---

## Step 2 - Write the manifest

Inside `holawashos/`, create a file called `mod.json`. Open it in any text editor and paste:

    {
      "name": "Hola Washos",
      "version": "0.1",
      "author": "your_name",
      "description": "My first mod.",
      "main_scene": "res://main.gd"
    }

Save it. That's the entire manifest - four keys and a main scene path. See [MODS_FORMAT.md](MODS_FORMAT.md) for what else you can put here (icons, background colors, autoloads, settings).

**Common mistake:** the file must be exactly `mod.json`, not `mod.json.txt` or `Mod.Json`. Android file managers sometimes hide extensions. If the mod doesn't appear in the engine's selector later, this is the first thing to check.

---

## Step 3 - Write the entry point

In the same folder, create `main.gd` and paste:

    extends Control

    var _title: Label
    var _counter: int = 0

    func _ready() -> void:
        set_anchors_preset(Control.PRESET_FULL_RECT)
        DebugLog.log("[HolaWashos] _ready")

        var bg := ColorRect.new()
        bg.color = Color("#4a1e5a")
        bg.set_anchors_preset(Control.PRESET_FULL_RECT)
        bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(bg)

        var center := CenterContainer.new()
        center.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(center)

        var vbox := VBoxContainer.new()
        vbox.add_theme_constant_override("separation", 30)
        center.add_child(vbox)

        _title = Label.new()
        _title.text = "Hola Washos"
        _title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _title.add_theme_font_size_override("font_size", 96)
        _title.add_theme_color_override("font_color", Color.WHITE)
        _title.add_theme_constant_override("outline_size", 10)
        _title.add_theme_color_override("font_outline_color", Color.BLACK)
        vbox.add_child(_title)

        var btn := Button.new()
        btn.text = "Tap me"
        btn.custom_minimum_size = Vector2(400, 90)
        btn.add_theme_font_size_override("font_size", 32)
        btn.pressed.connect(_on_button_pressed)
        vbox.add_child(btn)

    func _on_button_pressed() -> void:
        _counter += 1
        DebugLog.log("[HolaWashos] tap %d" % _counter)
        MenuMusic.play_confirm()
        _title.text = "Hola Washos (%d)" % _counter

Save it. The mod is now complete.

**What each part does:**

- `extends Control` makes this a UI node. `Control` fills the screen and lets you anchor children. Other options: `Node2D` for 2D games, `Node3D` for 3D, `Node` for logic-only mods.
- `set_anchors_preset(Control.PRESET_FULL_RECT)` makes the root node cover the entire screen. Without this, the node has size zero and nothing you add is visible.
- `DebugLog.log(...)` writes to the engine's debug log, which you can read at `/storage/emulated/0/WashosEngine/debug.log`.
- `MenuMusic.play_confirm()` reuses the engine's built-in UI sound. Same for `play_scroll()`, `play_cancel()`.

---

## Step 4 - Load it in the engine

Open Washos Engine on the device. The selector screen shows the list of mods.

- If **Hola Washos** appears in the list, tap it, then tap **PLAY**.
- If it doesn't appear, tap **Administrar mods** at the bottom and then **Releer**. This forces a full rescan. Then go back to the selector.

When the mod loads, you should see:

- A dark purple background.
- The title "Hola Washos" in white with a black outline.
- A "Tap me" button.
- A round **X** button in the top-right corner of the screen.

Tap the button a few times - the title updates and each tap plays a sound. When you're done, tap the X in the top-right, confirm "Yes", and you're back in the selector.

The X button is provided by the engine itself, not by your mod. It appears whenever a mod is running so you always have a way back.

---

## Step 5 - Iterate

Edit `main.gd` in your file manager, save, then:

- Go back to the selector (via the X button).
- Tap **Administrar mods** > **Releer**, then **Volver**.
- Tap your mod and **PLAY** again.

The engine detects that the file's modification time changed and rebuilds the mod's `.pck` automatically. Rebuild takes about a second for a small mod.

To check whether your code ran, open the debug log. On Android you can view it with any text viewer app, or from Termux:

    tail -50 /storage/emulated/0/WashosEngine/debug.log

Look for lines starting with `[HolaWashos]`. Any `push_warning` or `push_error` in your code shows up here too.

---

## What to try next

**Read the manifest reference.** [MODS_FORMAT.md](MODS_FORMAT.md) covers everything else you can put in `mod.json`:

- Add an `Icon.png` to show a preview in the selector.
- Add a `background_color` to tint the selector's background while your mod is selected.
- Add `autoloads` to expose globals to every script in your mod.
- Add `settings` to override the window's stretch mode.

**Look at how other mods are built.** The engine ships with a couple of test mods. Open their `mod.json` and `main.gd` and try to modify them.

**Use Godot's API.** A mod is a Godot scene. Everything in the [Godot 4.7 documentation](https://docs.godotengine.org/en/stable/) works. That includes:

- Node types (`Control`, `Sprite2D`, `CharacterBody2D`, `Node3D`, `Camera3D`, ...)
- Signals, tween, animation
- Theming, shaders, post-processing
- Physics (2D and 3D)

**Reuse engine services.** These are available to your mod automatically:

- `DebugLog.log(msg)` - append a line to the debug log.
- `MenuMusic.play_scroll()` / `play_confirm()` / `play_cancel()` - UI sounds.
- `ErrorToast.show(msg)` - a toast notification on screen.
- `ModLoader` - access to the mod list, config, and helpers (advanced).

---

## Common problems

**The mod doesn't appear in the list.**

- `mod.json` is missing or its name is wrong (e.g. hidden `.txt`).
- `mod.json` is invalid JSON. A missing comma or quote breaks it silently. Use an online JSON validator to check.
- The mod folder is one level too deep. The engine expects `mods/<name>/mod.json`, not `mods/<name>/<somename>/mod.json`.

**The mod loads but nothing is visible.**

- You forgot `set_anchors_preset(Control.PRESET_FULL_RECT)` on the root `Control`.
- Or the root extends `Node` (no rendering). Use `Control` or `Node2D` for visible content.

**`Cannot infer the type of "x"` appears in the error log.**

- This is a known Godot 4.7 limitation when the right-hand side calls into an autoload. Fix: use explicit types instead of `:=` for those lines. Example:

      # Instead of:
      var unlocked := not HQSaves.is_achievement_locked(id)

      # Write:
      var unlocked: bool = not HQSaves.is_achievement_locked(id)

**Where is the debug log?**

    /storage/emulated/0/WashosEngine/debug.log
    /storage/emulated/0/WashosEngine/error.log

The first is normal `DebugLog.log()` output plus `push_warning`. The second collects `push_error` and engine-level errors. Both are plain text and can be read with any file viewer.

---

## See also

- [MODS_FORMAT.md](MODS_FORMAT.md) - full `mod.json` reference.
- [docs/README.md](README.md) - documentation index.
