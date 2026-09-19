# Lua API Reference

A mod can use Lua instead of GDScript by setting `"main_scene"` to a `.lua` file. The engine runs the script in a sandboxed `LuaState`, injects the `washos` global table with the APIs below, and uses the table the script returns to build the mod's root node.

For the manifest fields (`mod.json`), see [MODS_FORMAT.md](MODS_FORMAT.md). For a walkthrough, see [GETTING_STARTED.md](GETTING_STARTED.md).

---

## The shape of a Lua mod

The entry point is a `.lua` file. It must return a table with at least these fields:

    local mod = {}

    mod.root_type = "Control"  -- optional, defaults to "Node"

    function mod.on_ready()
        -- called once after the engine creates the root node
        -- and adds it to the scene tree. Build the UI here.
    end

    return mod

- `root_type` is the class name of the root node. Accepts anything that inherits from `Node`: `Control`, `Node2D`, `Node3D`, `CanvasLayer`, `Node`, etc.
- `on_ready` is optional. When present, it runs once with the root node already in the tree.

Any other fields are stored on the mod table but not interpreted by the engine. Use them as your own module state.

---

## Sandbox

Only these Lua libraries are opened:

- `base`
- `table`
- `string`
- `math`
- `coroutine`
- `package` (only because the addon patches its searchers to resolve `res://` and `user://` paths)

Not opened: `io`, `os`, `debug`, `ffi`. A mod cannot read arbitrary files, spawn processes, or access native pointers.

Lua scripts can `require`, `dofile` and `loadfile` relative to `res://` and `user://`. The addon patches those to go through Godot's `FileAccess`, so paths inside the mod's `.pck` and paths in the app's private storage both work.

---

## The `washos` table

Every mod gets a global `washos` table. All node APIs take integer ids instead of node references, so the mod can't reach into arbitrary Node properties.

### Engine services

    washos.log(msg)

Appends a line to the engine's debug log (`/storage/emulated/0/WashosEngine/debug.log`). Prefixed with `[Lua:<mod_folder>]` so you can filter by mod.

    washos.play_confirm()
    washos.play_scroll()
    washos.play_cancel()

Play the engine's built-in UI sounds. Same as `MenuMusic.play_confirm()` in GDScript.

### Node creation

    washos.create_node(type_name)  -> id
    washos.create_label(text)      -> id
    washos.create_button(text)     -> id
    washos.create_color_rect(hex)  -> id

Return an integer id for the new node. Pass `-1` if the type is unknown or the creation fails (check `washos.log` output).

`type_name` is any class inheriting from `Node`: `"Node"`, `"Control"`, `"Node2D"`, `"Node3D"`, `"CanvasLayer"`, `"Sprite2D"`, `"Label"`, `"Button"`, etc.

`hex` is any color string accepted by `Color.html()`: `"#4a1e5a"`, `"4a1e5a"`, `"#4a1e5aff"`.

### Tree operations

    washos.add_child(parent_id, child_id)

Reparents a node. Both ids must be valid; otherwise logs a warning and does nothing.

The mod's root node id is available as `washos.root`. Add every visible node under it:

    washos.add_child(washos.root, bg)

### Common properties

    washos.set_anchors_full(node_id)
    washos.set_font_size(node_id, size)
    washos.set_text(node_id, text)
    washos.set_position(node_id, x, y)
    washos.set_size(node_id, w, h)
    washos.set_color(node_id, hex)

- `set_anchors_full` sets `PRESET_FULL_RECT` on a `Control`. Call it on every `Control` you want to fill the screen.
- `set_font_size` adds a font-size theme override.
- `set_text` works on `Label` and `Button`.
- `set_position` works on `Control` and `Node2D`. Coordinates are in pixels.
- `set_size` works on `Control`.
- `set_color` adds a `font_color` theme override on `Label`/`Button`, or sets `.color` on `ColorRect`.

Each setter is a no-op if the target node isn't compatible.

### Signals

    washos.on_button_pressed(node_id, callback)

Connects a Lua function to a `Button.pressed` signal. The callback is stored on the engine side so it doesn't get garbage-collected while the button exists.

    washos.on_button_pressed(btn, function()
        washos.set_text(titulo, "clicked")
        washos.play_confirm()
    end)

---

## A complete example

    -- main.lua
    local mod = {}
    mod.root_type = "Control"

    local title
    local counter = 0

    function mod.on_ready()
        washos.log("ready")

        local bg = washos.create_color_rect("#4a1e5a")
        washos.set_anchors_full(bg)
        washos.add_child(washos.root, bg)

        title = washos.create_label("Hola Lua")
        washos.set_anchors_full(title)
        washos.set_font_size(title, 96)
        washos.set_color(title, "#ffffff")
        washos.add_child(washos.root, title)

        local btn = washos.create_button("Tap me")
        washos.set_size(btn, 400, 90)
        washos.set_position(btn, 100, 500)
        washos.add_child(washos.root, btn)

        washos.on_button_pressed(btn, function()
            counter = counter + 1
            washos.set_text(title, "Hola Lua (" .. counter .. ")")
            washos.play_confirm()
        end)
    end

    return mod

Drop it in a folder with a `mod.json` pointing `main_scene` to `"res://main.lua"` and it runs.

---

## Gotchas

**"washos is nil"** — the entry point isn't returning a table. Make sure the file ends with `return mod`, and that `mod` was declared as a table before any use.

**Nothing is visible** — most likely forgot `washos.set_anchors_full(bg)` on the root child. A `Control` with no anchors has size zero and its children can't be seen either.

**Integer vs float ids** — LuaJIT passes integral numbers as float if they're large. The engine truncates with `int()` internally, so you can pass either form. Don't do arithmetic on ids; they're opaque.

**Errors in callbacks** — if a Lua callback errors, the error goes to the debug log with the `[Lua:<folder>]` prefix. It won't crash the engine; it just aborts that callback.

**Long-running loops** — a `while true do end` in Lua blocks the whole frame. There's no way for the engine to preempt Lua. Keep callbacks short.

---

## Coming later

Not implemented yet, but on the roadmap:

- `on_process(delta)` callback
- `on_input(event)` callback
- `washos.create_sprite(path)`, `create_audio(path)`
- Tweens (`washos.tween(node, props, duration)`)
- Signals beyond `Button.pressed`
- Reading properties back (`washos.get_text(node_id)`, etc.)

If you need one of these before it exists, use the GDScript path instead — `main_scene` to a `.gd` gives you the whole Godot API.

---

## See also

- [MODS_FORMAT.md](MODS_FORMAT.md) — the `mod.json` schema.
- [GETTING_STARTED.md](GETTING_STARTED.md) — build your first mod in 10 minutes.
- [README.md](README.md) — documentation index.
