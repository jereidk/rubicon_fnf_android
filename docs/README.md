# Washos Engine - Documentation

Washos Engine is a personal fork of [Rubicon](https://github.com/RubiconTeam/rubicon_fnf) with an external mod system. Any Godot 4.7 project can be loaded as a "mod" - a single script, a 2D game, a full 3D scene, or a FNF-style mod.

## Contents

- **[MODS_FORMAT.md](MODS_FORMAT.md)** - `mod.json` reference. Field by field, with gotchas and examples.
- **[GETTING_STARTED.md](GETTING_STARTED.md)** - build your first mod in 10 minutes.
- **[LUA_API.md](LUA_API.md)** - write a mod in Lua. The `washos` table, the sandbox, and the entry-point shape.
- **[mod_schema.json](../mod_schema.json)** - JSON Schema for editor autocompletion.

## Quick reference

**Where mods live:**

    /storage/emulated/0/WashosEngine/mods/

**Minimum viable mod:**

    my_mod/
      mod.json
      main.gd

**Minimum `mod.json`:**

    {
      "name": "My Mod",
      "main_scene": "res://main.gd"
    }

**Minimum `main.gd`:**

    extends Control

    func _ready() -> void:
        set_anchors_preset(Control.PRESET_FULL_RECT)
        var label := Label.new()
        label.text = "Hello"
        add_child(label)

**Debug log:**

    /storage/emulated/0/WashosEngine/debug.log
