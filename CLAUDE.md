# Lullaby Android port - working notes

Notes for whoever picks this up next. This is a port of the PC/Godot mod
*Lullaby* to Android, on the Rubicon engine. Everything below was learned by
being wrong about it first; the point of writing it down is that the next
session does not have to be.

Target device for every measurement here: **moto g53 5G, Adreno 619,
1600x720**. It is a mid-range phone and it is the thing to optimise for.

---

## Environment

| | |
|---|---|
| Working checkout | `/tmp/api_audit` (a real git checkout, branch `add-lullaby-mod`) |
| Godot | `/tmp/Godot_v4.7.1-stable_linux.x86_64` |
| Original PC mod | `lullaby_mod/original_pck/Lullaby.pck` (852MB, Git LFS, hydrated) |
| NightmareVision reference | clone of `jereidk/NightmareVision-Android-Support`, branch `impostor-legacy-android` |

`/home/user/rubicon_fnf_android` is a *different* checkout on another branch
and does not have the mod. Do not confuse them.

**Godot renders here now, under Xvfb.** This note used to say it could not -
"no GPU, it hangs, Xvfb included" - and that was true for months and shaped
everything below it. It is no longer true: Xvfb and xvfb-run are installed,
Mesa gives a software GL, and the engine exits cleanly.

```bash
timeout 90 xvfb-run -a --server-args="-screen 0 800x600x24" \
  godot --rendering-driver opengl3 --path $D m.tscn
```

Inside the scene, wait two `RenderingServer.frame_post_draw` and then
`get_viewport().get_texture().get_image().save_png(...)`. Verified: a
300x200 ColorRect at (50,50) comes out at exactly that size and position.
`--headless` still has no framebuffer, so the driver flag is what matters,
not the display alone.

What this does NOT unlock is loading the real project - its resources are
still unimported here and the autoloads still do not exist under `--script`,
so `sng_chimera.tscn` will not open any more than it did before. What it
unlocks is rendering *isolated* scenes for real instead of reproducing their
maths in PIL, which is what the section below had to settle for.

---

## The single most useful technique: isolated test projects

The full project cannot be loaded in this workspace - most resources are not
imported, and the autoloads (`Settings`, `Debugger`, `ErrorHandler`,
`SaveData`) do not exist under `--script`, so anything touching them fails to
compile. That is a pre-existing limitation, **not** a symptom of your change.

So: verify a change by rebuilding the smallest possible project around it.

```bash
D=$SCRATCH/test; mkdir -p $D; cd $D
cat > project.godot <<'EOF'
config_version=5
[application]
config/name="test"
config/features=PackedStringArray("4.4")
EOF
# copy in only the script under test, stub whatever it needs, run it
timeout 40 /tmp/Godot_v4.7.1-stable_linux.x86_64 --headless --path $D m.tscn 2>&1 | grep -E "^OUT|SCRIPT ERROR"
```

This caught real bugs every time it was used: a `NOTIFICATION_PREDELETE`
crash, an indentation error that stopped a whole autoload from parsing, and
the fact that hand-written `node_paths` serialisation actually resolves.

`class_name` is **not** registered in a fresh project - use
`preload("res://x.gd")` instead of the global name.

### Reading the real project without loading it

`ResourceLoader.get_dependencies(path)` works without instantiating and
without the dependencies being importable. It is how the shop crash and the
Hex animation bug were both found.

`PackedScene.get_state()` (`SceneState`) reads authored node properties -
names, types, `visible`, exported values, animation libraries - without ever
instantiating the scene. This is the workhorse for comparing port vs pck.

### Rendering a preview

Godot cannot render here, so mock-ups were built with **PIL**, reproducing the
same maths the game will use, and sent with `SendUserFile`. Useful, but say
clearly that it is a render of the maths and not a screenshot of the game.
When slicing sprites out of an atlas, get the regions from the atlas's
`SpriteFrames`/`.tres` - slicing "into equal quarters" by eye produces
garbage (learned the hard way).

---

## Reading the original PC pck

The pck mounts read-only and is the ground truth for "was this a porting
mistake or was it always like this":

```gdscript
ProjectSettings.load_resource_pack("res://lullaby_mod/original_pck/Lullaby.pck", false)
```

`false` = do not replace project files, so colliding paths resolve to the
port's own copy.

PC layout roots are `res://assets/...`, `res://resources/...`,
`res://songs/...`. The port moved everything under `res://lullaby_mod/...`.
Scenes inside are `.tscn.remap` -> compiled `.scn`; `ResourceLoader.exists()`
and `load()` both work on the original path.

**`.gdc` scripts are readable.** Since Godot 4.3 they are binary *tokens*,
not bytecode: zstd-compressed behind a `GDSC` header, with identifiers XOR'd
by `0xb6` and string constants stored plainly. `tools/read_pck_scripts.gd`
recovers the strings:

```bash
godot --headless --script tools/read_pck_scripts.gd -- backshot spe_
```

It does not reconstruct source, but "nothing in 260 scripts mentions X" is
often the answer you need.

---

## Landmines in this repo

**A value track painting its first key backwards can be load-bearing.** The
rule itself is real - a value track applies its first key over all time before
that key - but "the earliest key is opaque black, therefore this rect is
accidentally black for three minutes" does not follow, and `bc32b05` shipped a
guard key and a CI gate on exactly that reasoning.

Chimera's `BlackBoxofAwesomeness` is a full-rect `ColorRect` authored
`color = Color(0, 0, 0, 0)`. The clock's `scene` track has its first `:color`
key at 181.83s and opaque, so the colour reads opaque black from the downbeat.
That is not an accident: the SequencePlayer's own `RESET` **also** sets
`color = Color(0, 0, 0, 1)`, and `113_reaching` then flickers `:modulate`
between opaque and transparent black to black the screen out while Serena
reaches. A ColorRect multiplies `modulate` by `color`, so that flicker only
shows anything *because* the colour underneath is opaque. A transparent guard
key at t=0 fights the RESET and can silently delete an authored blackout - the
exact "black graphics that used to appear correctly and now do not" the user
reported after that build.

Every one of those tracks is byte-identical to the pck's. The check that
settles this class of question is that diff, not the arithmetic: **before
"fixing" a value track, confirm the mod does not depend on the value it is
painting.** The gate is gone and so is `tools/test_black_box_hold.gd`.

`e77bed1` attacked the same rect from the other side and was also wrong.
`flashing_check.gd` reads `visible = Settings.get(&"game_flashing_lights")`,
which reveals as readily as it hides; that commit made it a suppressor only,
on the premise that switching those rects on at `_ready` "is the black
graphic covering Chimera". The premise is false - the cause was five precache
tracks - and the change was also **inert**, which is the part worth keeping:

| nodo | por qué no cambiaba nada |
|---|---|
| `BlackBoxofAwesomeness` | el reloj `scene` **y** el RESET escriben `visible = false` en t=0, así que la asignación del `_ready` dura como mucho un frame |
| `UIBlack` | el RESET escribe `false` en t=0, y además es `modulate = (1,1,1,0)` **y** `color = (0,0,0,0)` |
| `Black2` | transparente en los dos niveles y **ninguna** animación lo toca - no pinta nunca, con `visible` o sin él |
| `UIBlackFG`, `Pulse`, `Cover` | shipean visibles, así que original y suppressor dan lo mismo |

Revertido para volver al pck, que es literalmente esas cuatro líneas.
`flashing_check_3d.gd` nunca se tocó. La lección es la de siempre en este
fichero: **un nodo cuyo `visible` lo escribe una animación en t=0 no puede
ser explicado por lo que haga un `_ready`** - mirar las pistas antes que el
script.

**Never delete an asset because it looks orphaned.** This repo has been
broken by that at least three times (`8878770`, `5ee950a`, and a lightmap
`.exr`). Two known blind spots where nothing textually references a file that
is nonetheless required:

- textures extracted as a side effect of `.gltf` import - a cold build
  regenerates them, a cached build does not
- `spritemap*.png`, loaded at runtime by `gdanimate/animate_symbol.gd:129`,
  which scans the directory for `spritemap*.json`

**Resources extracted from the pck keep the PC path roots.** They reference
`res://resources/...` while the file now lives under `res://lullaby_mod/...`.
This is systemic - it broke Hex's animations and the shop's jar. It only
works when the local file declares the UID the binary expects, so the fix is
usually to add `uid="uid://..."` to the local `.tres` header, not to move
files. A sweep of `get_dependencies` over all resources finds them.

**Godot silently drops animation tracks it cannot resolve.** Blender exports
bone names with dots, the `.gltf` importer writes underscores; 86% of the
Collector's and Hex's tracks were being discarded without a warning. Fixed
across ~3305 tracks in `15fa53c`.

**Our Rubicon fork is not the mod's Rubicon, and the scenes were authored
against theirs.** The extracted scenes set properties and animate tracks
that only exist on the original engine; where our fork renamed or dropped
one, the authored value and every track targeting it are discarded in
silence. This is how Monochrome stayed broken for months: our
`rubicon_character.gd` had replaced the original's `dancing_measure_step`
(a per-measure rate, turned into steps via the song's time signature) with
a fixed `dancing_step_interval = 8`. 4x4x0.5 = 8, so 4/4 songs were right
by coincidence and Chimera looked fine - but Monochrome and Safety Lullaby
are **3/4**, where the interval should be 6, so their characters danced on
the wrong beats and cut off whatever animation was running. On top of that
`chr_serena_base.tscn` and `chr_hypno_safety.tscn` both author
`dancing_measure_step = 0.25`, and Hypno's scene *animates* it across three
tracks - all silently dropped. Restored in the same commit as this note.

**Diff the whole engine, not just the script you suspect.** Decompiling all
80 of the pck's addon scripts and comparing `@export`/`func`/`signal` sets
against ours found four more live gaps in one pass: `offset_input` /
`offset_note_position` (the console's Offset and Visual Offset rows drove
nothing), and the entire misplay subsystem - `allow_misplays`, the
`misplayed` signal, `break_combo_indexes`, `note_controller_connected`, and
two whole scripts (`RubiconCharacterManiaMisplay`,
`RubiconHealthModuleManiaMisplay`). **All three songs** depend on the
health-module one (`get_dependencies` confirms it), so ghost tapping cost
nothing anywhere in the port. Restored alongside the dance-interval fix.

The tell for this class of bug is a defensive guard in our own code: a
`if "x" in node:` or `has_signal(&"y")` around something the mod's scenes
already reference usually means someone hit the gap, worked around it, and
moved on.

**`gdanimate` used to be a different version too. It is not any more** - the
addon now matches the mod's, `adobe/` + `sparrow/`, with `atlases`,
`atlas_index` and `use_backbuffer_cache` all present. The table below is kept
because the *reasons* in it still explain why `offset` was restored and
`centered` was not, but do not use it as a list of what is missing. What
follows it about the stage instance matrix is still true.

The version that mattered when this was written:

| mod | ours |
|---|---|
| `symbol` (name **or prefix**) | `symbol` (exact name) |
| `speed_scale`, `autoplay`, `loop` | `loop_mode` (enum string) |
| `centered`, **`offset`** | *(offset restored; centered deliberately not - see below)* |
| `atlases: Array[AnimateAtlas]` + `atlas_index` | `atlas: String` (directory) |

`offset` was authored on two nodes and silently dropped by our fork, which is
what put Gold's back-turned intro pose in the wrong place in Monochrome. The
mod applies it as the seed of the draw transform - `Transform2D.IDENTITY
.translated(draw_info.offset)` in its `adobe_atlas.gd` - so ours now does the
same in `_draw()`. `centered` is only read on the sparrow path, which we do
not have, and all nine atlases here are adobe, so it is a no-op and was left
out on purpose rather than added as dead API.

Our parser also never reads the stage instance matrix (`AN.SI...MX/M3D`) that
the mod's `stage_transform` applies when a `symbol` does not resolve. All nine
`Animation.json` files in this project have no stage matrix, so it costs
nothing today - but a new atlas that has one would be drawn untransformed.

### The full API sweep, and where it now stands

Decompiling **all 87** of the pck's addon scripts (not just `addons/rubicon/**`,
which is all the earlier sweep covered) and diffing top-level member
declarations against ours leaves exactly **two** scripts with anything missing,
out of 80 in common:

- `gdanimate/animate_symbol.gd` - the whole rewrite. `offset` is restored;
  `centered` is a deliberate no-op here; `speed_scale`, `autoplay`, `loop`,
  `atlases`/`atlas_index` and the backbuffer-cache internals are API this fork
  does not have and no scene in this project authors.
- `rubicon_level_note_controller.gd` - `_get_result_count_of_rating`, a private
  helper. Not a gap: ours computes the same six `performance_hits_*` counters
  in one pass instead of six.

Do not trust a regex that keys on `@export` for this. An earlier pass flagged
`mania_directions` as missing from `rubicon_character.gd` when it is right
there at line 425 - the multiline `@export_storage` above it fooled the
pattern. Match top-level `var`/`const`/`func`/`signal` declarations instead and
ignore decorators.

Seven scripts exist in the pck and not here: gdanimate's `sparrow/` pair (no
asset uses the sparrow format - all nine atlases are adobe) and the
`camera_preview`, `parallax2d_preview` and `model_to_atlas` editor plugins,
which nothing references.

### The sweep that actually catches this class of bug

An API diff only finds what the *mod's* engine had. The sharper question is
which authored values are being dropped **right now**, whatever the cause:

```bash
python3 tools/collect_authored_properties.py > authored.json
godot --headless --script tools/audit_authored_properties.gd -- authored.json
```

Across 3536 nodes in every `.tscn` in the project this is down to a single
finding, the known-harmless `centered`. It found `AnimateSymbol.offset` and one
stale line of our own (`visible_property` on the shop's `TouchAimReticle`, left
behind when that script was rewritten).

Two things to know before reading its output:

- **Filter dynamic properties or the real findings drown.** Names built at
  runtime through `_get_property_list()` - `popup/item_N/*`, `item_N/*`,
  `joint_constraints/*`, `parameters/*`, `bone_name`, `blend_times` - are
  invisible to `ClassDB` and were 40 of the first run's 46 "findings".
- **A node whose class cannot be pinned down must be excluded, not guessed.**
  Scripts stored inline as `script = SubResource("GDScript_...")`, and instance
  chains that bottom out in a `.gltf`, have no readable class. Falling back to
  the script's own base type is worse than skipping: `RubiconCharacter extends
  Node`, so Chimera's `hex` had its perfectly valid Node3D `transform`
  reported missing. 128 nodes are skipped this way and the count is printed.

### The animation-track sweep

Authored properties are only half of it - Godot drops a **track** whose
NodePath does not resolve, or whose property the target does not have, just as
silently:

```bash
python3 tools/collect_animation_tracks.py > tracks.json
godot --headless --script tools/audit_animation_tracks.gd -- tracks.json
```

**7747 tracks across 62 scenes, and every finding is present in the pck too -
no port regression exists here.** What is left, all of it dead in the original
mod as well:

- `Console:input_active` (3 tracks) - `console.gd` has no such property, in the
  pck either.
- `HeartbeatController:path_mode` (4) and Chimera's `Camera3D:follow_enabled` /
  `:path_follow` (2) - same, and that Camera3D is a plain scriptless `Camera3D`
  on both sides.

Getting from 197 raw hits to 9 was almost entirely fixing the tool, and the
four corrections are the reusable part:

1. **Key the scene root `"."`, never by its own name.** A child of the root is
   written `parent="."`, so its path is just its name - and this project really
   does give a child the root's name (`cut_boyfriend_scream`, every pause
   menu). Keying both the same way merges them and 24 tracks aimed at the child
   resolve to nothing.
2. **Mark `.gltf`/`.scn` instances opaque.** 304 tracks aim into a skeleton
   that came from a glTF. Their subtree is unreadable from text, so they are
   unchecked - reporting them as broken buries everything else.
3. **A script with its own `_get_property_list()` cannot be checked.**
   `RubiconCharacter` builds `sing_left`/`miss_up`/... from
   `mania_anim_aliases` that way; 99 tracks drive them and they are correct on
   both engines. Detect the method via `get_script_method_list()` and skip.
4. **`%Name` is a unique-name lookup** resolved against the scene owner at
   runtime and cannot be followed from text (6 tracks).

And one thing the sweep genuinely cannot know: **a track aimed at a node
created at runtime looks identical to a dead one.** Monochrome's `scene`
animation drives `../BloodCutscene/...`, `../BoyfriendScream` and
`../MonoCloseup` - 16 tracks, none of those nodes in the .tscn, all three
instantiated by `BloodCutsceneLoader` from uid paths. Read the output; do not
turn it into a build gate.

### The string-pool sweep (the one that catches re-typed code)

The two sweeps above check *data* - authored properties and animation tracks.
Neither can see a script that was retyped by hand and drifted while doing it,
because the drifted version still parses and still refers to real nodes.

An exported `.gdc` is a binary token stream whose identifier and constant
tables survive intact, so for anything the port carried over, the pck holds
every node name, property name, animation name, path and literal the original
used. Anything in that list absent from our source is a drift point:

```bash
godot --headless --script tools/sweep_pck_strings.gd                 # summary
godot --headless --script tools/sweep_pck_strings.gd -- monochrome   # detail
```

At the time it was written: 249 scripts compared, 46 with at least one missing
string, 92 total. That low number is the useful part - the port is faithful,
so the hits are worth reading one at a time.

**It found two real bugs on its first run**, both the same root cause: hex
colours converted by hand instead of kept as hex.

- `heartbeat_controller.gd` faded Chimera's ECG line to `Color.DARK_GRAY`
  where the original used `Color("333333")`. Godot's `DARK_GRAY` is CSS
  `darkgray`, `#a9a9a9` - **3.31x brighter** than `#333333`, and a light grey
  despite the name. Two occurrences, success and miss.
- `typing_challenge.gd` dimmed Celebi with `Color(0.247, 0.247, 0.247)` where
  the original used `Color("333333")`. `0x33/255` is `0.2`; `0.247` is `0x3F`.
  1.23x. Two occurrences.

Prefer `Color("rrggbb")` over both float triples and the named constants when
porting - it keeps the literal comparable to the pck and this sweep can then
see it. `Color.DARK_GRAY` in particular should be treated as a porting smell.

Caveats: a miss can be legitimate - the port may have moved a value into the
scene (Peepers' colours are authored on its ColorRect, correctly), renamed
something deliberately, or split one script into two. The `_is_meaningful`
filter drops mostly-punctuation runs from the token bytes, but admits 6/8-digit
hex outright, since hex literals carry no letters and are exactly the
high-value case. Read the hits; do not bulk-fix them.

### `gpu=` only ever measured the main viewport

`RenderingServer.viewport_get_measured_render_time_gpu()` takes a viewport
RID, and the log passed the root window's. **Every SubViewport in the scene
was outside that number.** This is what made the Collector's Shop read as a
CPU problem: thirteen spikes at `frame=68-141ms` with `gpu` pinned at
13.48-13.75ms and byte-identical `draw=80 prims=13389 objs=267`. Subtract
`proc` (a per-second maximum, 34.6ms) and `gpu` (13.5ms) from a 141ms frame
and ~90ms is unaccounted - it was rendering the log could not see.

The console carried it. `console_bg`'s SubViewport is **1440x1080 with
`own_world_3d`, a WorldEnvironment with fog and a DirectionalLight3D** -
1.56 Mpx of 3D against the main viewport's 800x360 at `scale=0.50` - and it
lives inside a `Control` that is never hidden, so it rendered for the whole
shop session, *including* while the player free-looks away from the TV and
`TvViewportDisabler` has the outer viewport disabled. The Home tab's
`IconSubViewport` is another 1440x1080 with six icon models.

Both now render at 720x540 (`stretch_shrink = 2`; the console ends up inside
a 640x480 viewport scaled 0.45/0.41, so 1440x1080 was ~2.2x oversampled to
begin with), and the gate hides `console_bg`'s container along with the
outer viewport.

**Setting `render_target_update_mode` on a SubViewport owned by a
`SubViewportContainer` does nothing.** The container overwrites it from its
own `is_visible_in_tree()` on every visibility notification - `ALWAYS` when
visible, `DISABLED` when not. An authored value in the `.tscn` is inert and
a manual set survives only until the next visibility change (verified
against 4.7.1). Toggling the container's `visible` is the supported way.
Do **not** blanket-show containers to switch them back on: restore what each
one had, or only manage the one you can prove is always visible. Revealing
hidden containers is exactly what made the reverted shader prewarm open the
console on a screen the player never chose.

Since this, every log line carries `sub=live/total sub_gpu=Xms sub_px=YM`.
Per-viewport timing is off by default, so the collection walk enables it.

### What each scene actually asks the GPU for

```bash
python3 tools/audit_gpu_cost.py
```

Lists per scene the always-on shadow casters and the full-frame CanvasItems
carrying a shader, split by whether the node ships visible. That split is the
whole point: a node authored `visible = false` is switched on by a sequence for
a few seconds and is **not** part of the steady-state frame cost.

The result explains the shop-vs-Chimera gap exactly:

- **Chimera is the only gameplay scene in the project with an always-on shadow
  caster** - **one**, `MoonSpotlight`. This used to say two and name `TvLight`
  as the second; `TvLight` is authored `shadow_enabled = false` and that note
  was stale. Sweeping all 26 scenes in Chimera's dependency tree finds exactly
  three `shadow_enabled = true`, and the other two are `EditorMoonDoNotDelete`
  (`editor_only = true`, so it never renders) and `PhoneGlow`, whose ancestor
  `Sequences/SerenaTakingPictures/SerenaCinematics` ships hidden. Every other
  scene has none,
  and the shop, with more lights and more draw calls, costs 17.3ms against
  Chimera's 38.8ms.
- Chimera's `Rain`, `NTSC` and the `Ray` godray box all ship `visible = false`.
  **What they ship as is not what they run as, and this bullet used to conclude
  the opposite.** Running the scene and reading the tree back (`scene_probe`,
  below) says NTSC is on from `_ready` for the whole song at
  `graphics_post_processing = HIGH`, because `Settings/PostProcessingTree`
  holds it there - and `Environment/Lights/Ray` is on during gameplay, at
  1738x1080 of screen at `scene@60` and 1210x1080 at `scene@100`. Only `Rain`
  is really cutscene-only. Both survivors are full-screen per-pixel work on a
  scene whose problem is per-pixel, and `shd_godrays` sits on the `Ray`
  BoxMesh's own material, so "Reduce Visual Effects" never strips it.
- **The shadow atlas does not scale with `graphics_render_scale`.** That is why
  dropping render scale to 0.50 did not help: the colour pass halved to
  800x360, the shadow maps kept rendering at the full atlas size.

Two things the tool has to get right, and got wrong first:

- **`editor_only = true` lights do not render at runtime.** Chimera's
  `EditorMoonDoNotDelete` is a shadow-casting DirectionalLight3D and would
  otherwise look like the worst offender in the project.
- **Ancestor visibility.** `PhoneGlow` sets no `visible` of its own but lives
  under a cutscene group that ships hidden.

**`intro.tscn`'s 20.6ms is five framebuffer copies, not drawing.** It has 40
objects, 13 draw calls and **168 primitives** - it is barely drawing anything.
What it does is copy the screen five times: `shd_blend_modes` samples
`hint_screen_texture`, so each of the four overlay-blended 3283x1046 fog
sprites needs a `BackBufferCopy`, and there are five in the scene
(`scn_game_intro.tscn` has five too). A full framebuffer copy forces a
tile-based GPU to resolve out to memory, which is the most expensive single
thing you can ask it for.

Nulling the material did **not** stop this: a `BackBufferCopy` copies whether
or not anything still samples the result, so "Reduce Visual Effects" removed
the shader maths and kept the whole cost. `_strip_backbuffer_copy()` now
disables the copy too, which is free once the materials that read it are gone.

The same "the setting removes the shader but not the cost" shape is worth
checking for elsewhere. `shd_godrays` is in `EFFECT_SHADER_PATHS` but sits on
Chimera's `Ray` **BoxMesh resource**, not on the node, so the stripper never
sees it - harmless today only because `Ray` ships `visible = false`.

This does not explain Chimera. It has one `BackBufferCopy` and it is inside
`UILayer/RainParent/Rain`, which is hidden; its other large canvas items are
empty `Control`s that draw nothing.

Worth knowing and deliberately not changed here: `TvLight` has
`light_energy = 0` with `shadow_enabled = true` and `omni_range = 43.9`, so it
emits nothing while still rendering a shadow cubemap over the whole scene.
`122_fall` animates its energy, so switching its shadow off is a look decision,
not a free win - measure it before touching it.

### El mundo 3D de Chimera: lo que hay, y por qué no es ahí

Auditado entero, porque la pregunta se hace sola cada vez que se mira el frame
de Chimera. El resultado corrige dos cosas escritas aquí y no aporta una
optimización para el preset que la gente usa.

**Proyectores de sombra: uno, no dos.** Barriendo las 26 escenas del árbol de
dependencias de Chimera hay exactamente tres `shadow_enabled = true`, y sólo
`MoonSpotlight` está vivo en régimen (`EditorMoonDoNotDelete` es
`editor_only`, `PhoneGlow` cuelga de un padre que shipea oculto). Y a Very Low
las sombras salen apagadas de todas formas, así que en el teléfono del usuario
son **cero**.

**El pase 3D es el 8% de los píxeles.** A `scale=0.50` sobre 1600x720 el 3D
dibuja 800x360 = 0.29 Mpx; el canvas 2D no escala y el censo da `over=3.0x`
sobre 1.15 Mpx por capa, o sea 3.46 Mpx. El dato independiente que lo enmarca
está en `228f4636`, un A17 a 2340x1080, con `rend=` partido:

| canción | 3D (draws/prims) | 2D (draws/prims) | `gpu` p50 |
|---|---|---|---|
| **safety_lullaby** | **0 / 0** | 8 / 92 | **25.93ms** |
| monochrome | 0 / 0 | 42 / 334 | 13.23ms |
| chimera (g53, 1600x720) | 21 / 16106 | 10 / 306 | 31.85ms |

**Safety Lullaby no dibuja un solo triángulo de 3D y cuesta 25.93ms.** Y
cuesta el doble que Monochrome dibujando cinco veces menos. Quitar el mundo 3D
entero de Chimera no la llevaría por debajo de ese suelo.

**El experimento que lo cierra sigue sin hacerse, y ahora se sabe leer.**
`graphics_render_scale` sólo toca el pase 3D, así que dos pasadas de Chimera a
0.35 y a 0.75 -moviendo esa fila sola- dicen qué fracción del frame es el 3D.
El barrido de la tienda (arriba) demuestra que el método funciona y que en un
frame limitado por GPU `bench` no confunde nada.

#### Las 58 mallas de la casa: ninguna fuera de cámara en toda la canción

La pregunta obvia después de medir que el 3D es sólo el 8% de los píxeles:
¿hay geometría de la casa que nunca entra en cuadro y sigue `visible = true`
todo el rato? El patrón de Peepers (256 `_process` corriendo oculto) sugiere
que sí podría haberlo. La respuesta, con geometría real y no con suposición:
**no, ninguna de las 58 mallas de `chimera.gltf` queda nunca fuera del
frustum de cámara en toda la canción.**

Y llegar a esa respuesta necesitó rodear un bloqueo real. Las mallas
individuales de la casa (`window_001`, `floorfucked`, `Cube_022`...) viven
dentro de `chimera.gltf`, un recurso importado - opaco a un barrido de texto,
como ya se sabía. El camino habitual para esto sin autoloads,
`PackedScene.get_state()`, tampoco sirvió aquí: el `.scn` cacheado de este
checkout (`.godot/imported/chimera.gltf-*.scn`) no parsea, y reimportarlo
puso a Godot a escanear los 875 pasos del proyecto entero - horas, por el
mismo motivo que el ASTC EXHAUSTIVE. Se abortó antes de que hiciera nada.

La salida: **`.gltf`, a diferencia de `.glb`, es JSON de texto plano.** Nada
de pipeline de importación de por medio. `nodes[].translation/rotation/scale`
más `meshes[].primitives[].attributes.POSITION` -> `accessors[].min/max` da
una AABB local por malla, compuesta a mano con la matriz de rotación del
cuaternión. Confirmado que la matemática cuaternión->matriz coincide con
`Basis.from_euler` real del motor a 8+ decimales, en cuatro casos con
rotaciones combinadas en los tres ejes - no se dio por buena de memoria.

Con eso y el camino de cámara completo de la canción (las 26 secuencias con
pista propia de `Camera3D:position/:rotation/:fov`, interpoladas cada 0.5s -
377 muestras sobre 199.9s), cada una de las 58 mallas se probó contra un cono
de visión con 15° de margen extra. **Cero mallas nunca encuadradas**, y no por
poco: la peor (`Circle`) despeja el borde del cuadro por 29° en su mejor
momento. Repetido con margen cero, incluso con un cono artificialmente
estrecho de 0.001° -que sí encuentra diez mallas cuando se prueba así, así que
el mecanismo detecta de verdad casos negativos- las 58 siguen dentro con los
parámetros reales. La casa mide unos 10 metros y son 26 planos distintos
barriéndola durante tres minutos: no hay rincón que la cámara no toque nunca.

**Veredicto: no hay nada que ocultar por encuadre en la casa.** Y aunque lo
hubiera, esta sesión ya midió que `draw`/`prims`/`objs` no correlacionan con
el coste de GPU de Chimera - el techo son las luces por fragmento, no los
vértices. `tools/audit_house_mesh_visibility.py` deja la técnica completa
(lectura de `.gltf` en crudo, matemática de cámara verificada, camino de
cámara por secuencia) como herramienta para la próxima pregunta de "¿esto se
ve alguna vez?", que si no se habría vuelto a pagar desde cero.

#### El nodo `Ray`, medido - y por qué el arreglo es inerte

`Environment/Lights/Ray` es un BoxMesh de 4.97x13.57x6.6 cuyo material vive en
el **recurso de malla**, no en el nodo. Su shader es

    render_mode unshaded, blend_add, cull_disabled, depth_test_disabled

o sea las dos caras rasterizadas sin rechazo por profundidad, con una lectura
de `hint_depth_texture` por fragmento, sobre 1738x1080 de pantalla a
`scene@60`. Medido en aislado a 800x360 -que es lo que mide el pase 3D del g53
a `scale=0.50`- con la caja real sobre 49 mallas:

    sin Ray   3.88ms / 4.13ms   draws=49  prims=588
    con Ray   8.05ms / 8.64ms   draws=50  prims=600

**Un draw call y doce primitivas duplican el frame.** Es el ejemplo más limpio
que tiene el proyecto de por qué `draw=`/`prims=`/`objs=` no pueden ver un
coste por píxel.

Y `shd_godrays` lleva en `EFFECT_SHADER_PATHS` desde siempre sin que "Reduce
Visual Effects" lo tocara una sola vez, porque el stripper leía
`material_override` y `get_surface_override_material()` - los dos materiales
del *nodo*- y nunca el del recurso de malla.
`_hide_mesh_that_only_draws_an_effect()` cierra ese hueco escondiendo el nodo
(anular no vale: el material es de un recurso compartido y la caja saldría
blanca, que es el fallo que puso blancos los cubos de la tienda).

**Pero es inerte en los cuatro presets, y hay que decirlo cada vez que se
cite.** `Ray:visible = true` sale sólo del estado `high` del
`PostProcessingTree`, o sea `graphics_post_processing == 2`, y
`disable_shader_effects` lo pone sólo Very Low, que va a `post=0`:

| preset | post | Ray | stripper |
|---|---|---|---|
| High | 2 | **encendido** | no |
| Medium | 1 | apagado | no |
| Low | 0 | apagado | no |
| Very Low | 0 | apagado | sí (nada que esconder) |

La única combinación que lo alcanza es **Custom con post en High y "Reduce
Visual Effects" marcado** - dos filas independientes de la consola. Es un
arreglo de corrección, no una ganancia: el ajuste que se llama "reducir
efectos visuales" dejaba corriendo el objeto por píxel más caro de la escena.

Lo que sí queda apuntado como decisión de aspecto, no como bug: **a High,
`Ray` va en el mismo paquete que NTSC y la lluvia.** Un jugador que quiera
quitar los godrays tiene que bajar el post-proceso entero.

### El depth pre-pass de la casa: medido de verdad, y vuelto a poner

**La medida que faltaba, en la ruta del teléfono** (Vulkan, Forward Mobile), 24
quads con máscara solapados, geometría idéntica en los cuatro casos:

| modo | gpu | draws | prims | objs |
|---|---|---|---|---|
| OPAQUE | 35.6ms | 24 | 48 | 24 |
| **ALPHA_SCISSOR (2)** | **103.5ms** | 24 | 48 | 24 |
| **DEPTH_PRE_PASS (4)** | **399.0ms** | 24 | 48 | 24 |
| ALPHA (1) | 404.1ms | 24 | 48 | 24 |

**3.86x contra scissor - y los tres contadores son idénticos en los cuatro
modos.** Esa segunda mitad es la importante: `draw=`, `prims=` y `objs=` **no
pueden ver** que una superficie se dibuja dos veces. Por eso todas las lecturas
por recuento del log acababan en "no es geometría" -correcto- y ahí se
quedaban sin salida.

**Lo que lo señaló fueron dos logs de otros dos teléfonos**, misma build.
Chimera cuesta el doble que la tienda en las **dos** GPUs:

| | Adreno 619 | Mali-G52 |
|---|---|---|
| Chimera | 31.85ms | 24.22ms |
| tienda | 15.49ms | 14.68ms |

…teniendo Chimera menos luces alcanzando la cámara (4 contra 6), menos mallas
horneadas (62 contra 102), sin niebla (`env=limpio` contra `fog`) y menos draw
calls (21 contra 39). La única diferencia estructural: la casa tenía cinco
materiales en modo 4 y **la tienda no tiene ninguno** - sus trece son opacos.

Puesto otra vez, con `alpha_scissor_threshold = 0.214` explícito -el mismo que
`grars`, que conserva más borde que el 0.5 por defecto- y con
`tools/audit_house_transparency.py` como puerta de CI, que lleva la medida
dentro para que no haya que repetirla.

Fuera de alcance a propósito: `models/hex/materials/HexBroeknArms.tres`, un
gradiente de verdad, en otra carpeta, donde la regla no lo alcanza por error.

#### Por qué se revirtió la primera vez, y por qué ya no aplica

Cinco materiales de la casa de Chimera (`Material.001`, `foliage`, `props1`,
`props2`, `propruhhhhhoneofthem`) están en `transparency = 4`,
`ALPHA_DEPTH_PRE_PASS`, que dibuja el objeto dos veces - una pasada opaca de
profundidad y luego la transparente. Godot lo documenta como caro y es peor en
una GPU de tiles, que es todo lo de aquí. Además mantiene la superficie en la
cola transparente, donde nada detrás se puede rechazar por profundidad.

`869b1af` los pasó a `ALPHA_SCISSOR` (2) con este dato detrás - el porcentaje
de téxeles con alfa entre 8 y 247, o sea los bordes suavizados, que son los
únicos píxeles que scissor dibuja distinto:

    props1     38.4% opaco   0.29% parcial
    props2     36.9% opaco   0.26% parcial
    plantt     21.2% opaco   0.64% parcial
    FUKC       37.2% opaco   1.23% parcial
    foliage     8.0% opaco   3.96% parcial

Son máscaras binarias, y `grars` y `trash` en esa misma carpeta ya estaban en
scissor, así que era la convención de la propia carpeta.

`0eb5c69` lo revirtió y tenía razón entonces: la ganancia nunca se había
medido, y el cambio se hizo **en medio de la caza del gráfico negro**, sobre la
única escena que el usuario reportaba como rota. Ese bug se cerró en la build
152, y la medida ya está arriba. Los dos reparos han caducado.

### Tres materiales más en el modo caro, fuera de la casa - y esta vez sin decisión de calidad

El barrido de `transparency = 4` de la casa se limitó a esa carpeta a
propósito. Repetido sobre **todo** el proyecto (`tools/audit_opaque_transparency_modes.py`,
nueva) encuentra tres más: `mat_console_inactive/select/idle.tres`, las
placas de los seis modelos de icono del `IconSubViewport` del Home de la
consola - el SubViewport que este mismo fichero ya documenta como el más caro
de la tienda.

Y aquí no hay que decidir nada de calidad: las dos texturas que usan
(`uigradient_tex.png`, `uigradientSELECT_tex.png`) son opacas en la práctica -
el peor texel de las dos es un 254/255 aislado, ruido de redondeo, no un
borde suave real (un borde suave de verdad deja una franja de texeles, no uno
suelto). `transparency = 0` es matemáticamente idéntico en píxeles a lo que
había, así que no hace falta ajustar ningún `alpha_scissor_threshold` como sí
hizo falta en la casa.

Medido en la ruta del teléfono, seis placas a la resolución real del
SubViewport (720x540) en vez de las paredes grandes de la casa:

    OPAQUE (0)          4.07ms
    ALPHA_SCISSOR (2)   4.38ms
    DEPTH_PRE_PASS (4)  4.33ms  <- lo que shipeaba

Real pero modesto a este tamaño de pantalla - nada que ver con el 3.86x de la
casa, porque seis placas de icono no tienen tanto que duplicar por píxel. Aun
así es dinero gratis: cero coste de calidad, cero umbral que ajustar.

`tools/audit_console_icon_materials.py` (sin dependencias, en CI) fija que
los tres sigan en `transparency=0`. El barrido con Pillow que encontró esto
(`audit_opaque_transparency_modes.py`) es herramienta de descubrimiento, igual
que el análisis de texeles de la casa - no está en CI, sólo su resultado.

### HexBroeknArms: el cuarto material caro, medido y cerrado sin arreglo

La nota que dejó fuera del barrido de la casa a
`models/hex/materials/HexBroeknArms.tres` (`transparency=4`,
`ALPHA_DEPTH_PRE_PASS`) decía "un gradiente de verdad, en otra carpeta" sin
haberlo medido nunca con la misma regla que decidió la casa. Medido ahora:

    opaco (>=254/255)        69.4%
    transparente (<=1/255)   20.3%
    banda parcial             10.2%   (media 86/255 dentro de la banda)

10.2% de banda parcial es 3-40x lo que tenían las cinco superficies de la casa
(0.26%-3.96%), así que la nota tenía razón, y ahora con un número: no es una
máscara binaria con el borde suavizado, tiene una fracción real de píxeles a
medio camino. Renderizado en Python contra dos fondos (gris neutro y uno
saturado, para forzar el peor caso de fringing) comparando alpha real contra
`ALPHA_SCISSOR` a threshold=0.5: **PSNR 33.3dB, error de píxel hasta 93/255,
10.1% de los píxeles cambiados** - muy por debajo de cualquier cosa que se
haya enviado este proyecto (los 337 ASTC van de 18.9 a 45.9dB de PSNR, y esto
es un borde de personaje, no una textura de fondo).

Y no hay un modo intermedio gratis: el banco de la casa midió `ALPHA` (modo 1)
a 404.1ms contra `ALPHA_DEPTH_PRE_PASS` (modo 4) a 399.0ms - prácticamente
idénticos, los dos ~11x más caros que `OPAQUE`. Cambiar de modo sin pasar a
scissor no ahorra nada.

Es además una superficie que dibuja siempre que Hex está en pantalla, no un
evento raro: `hex.gltf` tiene una única malla (`Plane_001`) con cuatro
superficies - Head, Body, Hair, BroeknArms - las cuatro se dibujan juntas, sin
condición de visibilidad propia, y `hex.tscn` autora
`blend_shapes/ArmGo(Broken) = 1.0` fijo, o sea el estado "brazo roto" es el
estado por defecto del personaje, no una pose transitoria.

**Cerrado sin arreglo.** La única vía sin pérdida de calidad sería partir la
malla por región de UV (opaco aparte de la banda de borde), que es un cambio
de modelado real y no algo que se pueda hacer aquí sin Blender. Escrito para
que nadie vuelva a marcarlo "gradiente real, no tocar" sin el número detrás,
y para que nadie intente el canje a scissor pensando que es gratis como lo
fue en la casa - aquí no lo es.

### El barrido de escala de render, por fin medido - y sale lineal


Este fichero lleva toda la sesión pidiendo el experimento: *"Chimera solo se ha
registrado **jamás** a `scale=0.50`. Dos pasadas seguidas a 0.35 y a 0.75 dicen
de una vez si el techo es por píxel."* Nunca se hizo. Y resulta que **ya estaba
hecho**, en un log que nadie había abierto: `dcb37c09`, un **sexto dispositivo**
- moto g(60)s, **Mali-G76 MC4, 2460x1080**, driver 1.1.131, build `10123`.

Un jugador se metió en la pestaña de Gráficos de la consola, dentro de la
tienda, y barrió las filas **de una en una** durante ochenta segundos. Es
exactamente el protocolo que este fichero pide ("two runs toggling one row at a
time... do not change the preset") y lo hizo un amigo sin saberlo.

Escena congelada durante todo el tramo - `draw=92`, `prims≈16100`,
`vis3d=120/140`, `mat3d=83/135`, `sub=4/7`, los mismos en las diez muestras -
así que todo lo que se mueve es por píxel o por estado. Sólo las muestras
asentadas (≥4s tras el cambio; `median=` es una ventana móvil y una lectura a
2.4s todavía promedia el ajuste anterior):

| escala | msaa | ssaa | vram | `median` | `bench` |
|---|---|---|---|---|---|
| 1.10 | 4x | SMAA | 418MB | 92.9 / 92.7 | 1316 / 199 |
| 1.00 | 4x | SMAA | 346MB | 78.4 / 77.5 | 484 / 1045 |
| 1.00 | 2x | SMAA | 288MB | 76.1 | 443 |
| 1.00 | 2x | FXAA | 249MB | 72.7 / 71.7 / 71.5 / 71.2 | 1094 / 1138 / 1092 / 1316 |

**El modelo de relleno, ajustado con las dos primeras filas:** la pantalla son
2.657 Mpx, el pase 3D es `2.657·s²`.

    pendiente = (92.8 - 77.95) / (3.215 - 2.657) = 26.6 ms por Mpx de 3D
    suelo     = 77.95 - 26.6 x 2.657            =  7.3 ms

Y el tercer punto, que no entró en el ajuste: a `scale=0.50` el modelo predice
`7.3 + 26.6 x 0.664 = 25.0ms`. El mismo teléfono, veinte segundos antes, en
Very Low: **`median=25.2ms`**. Un 1% de error a lo largo de un rango de 4.8x de
píxeles de 3D.

**La tienda es fill-rate puro y lineal en píxeles de 3D, con 7.3ms de suelo.**
Bajar la escala de render paga exactamente lo que dice la aritmética, sin
rodillas ni saturación. (Very Low además apaga sombras y post, así que ese 25.2
debería quedar algo *por debajo* de 25.0 - el clavo es un poco de suerte. La
pendiente sí se apoya en cuatro muestras asentadas.)

### Y el gobernador **no** toca este frame

`bench` va de 199us a 1316us dentro de esta misma tabla - **6.6x de reloj de
CPU** - y el frame no se entera:

    scale=1.10   92.9ms @ bench=1316      92.7ms @ bench= 199     0.2% de diferencia
    scale=1.00   78.4ms @ bench= 484      77.5ms @ bench=1045     1.2%
    2x + FXAA    72.7 / 71.7 / 71.5 / 71.2  con bench 1092..1316  2.1%

O sea que el aviso de este fichero -"lee `bench` antes que cualquier otro
número"- hay que leerlo con su alcance: vale para los **tiempos de carga** (la
tienda 4763ms vs 17420ms es el gobernador) y para **ordenar secuencias por
`gpu`**, donde el frame tiene holgura. En un frame profundamente limitado por
la GPU, `bench` no explica nada y no hay que descontarlo. Los dos regímenes
existen en este proyecto y son distinguibles justo así: mueve el reloj 6x y mira
si el frame se mueve.

### El atlas de sombras es gratis cuando nada proyecta - medido dos veces

Lectura tentadora y **falsa**, que casi se convierte en una optimización: entre
150.86s y 157.27s el frame cae de 91.8 a 78.4 y lo único que dice la línea
`SETTINGS` es que el atlas pasó de 4096 a 1024. Catorce milisegundos por una fila
sola, en una escena que el censo registra como `lights=18(shadow=0)` con
`shadows=[]` en las cinco muestras del tramo.

No es eso. Dos comprobaciones independientes:

- **`vram` no se mueve** en ese paso: 346MB antes y 346MB después. Un atlas de
  4096 a 16 bits son 32MB; si estuviera reservado, liberarlo se vería. Godot no
  lo reserva porque ninguna luz pide hueco. Las otras dos filas del barrido sí
  mueven VRAM (msaa 4x->2x, −58MB; SMAA->FXAA, −39MB), así que el contador
  funciona.
- **En aislado, en la ruta del teléfono** (Vulkan, Forward Mobile), 81 mallas y
  18 omnis, barriendo sólo `positional_shadow_atlas_size`:

  | atlas | sin proyectores | con 4 proyectores |
  |---|---|---|
  | 0 | 14.91ms | 15.32ms |
  | 512 | 14.09 | 16.65 |
  | 1024 | 14.32 | 16.65 |
  | 2048 | 14.44 | 16.98 |
  | 4096 | **13.45** | **17.12** |

  Sin proyectores es ruido plano y el 4096 sale el más rápido; con cuatro es
  monótono y creciente. El control funciona y el caso de cero es plano.

Lo que de verdad pasó es la ventana: el 91.8 de 150.86s se tomó **2.4s** después
de bajar la escala de 1.10 a 1.00, y `median=` todavía promediaba frames de
1.10. El valor asentado de `scale=1.00` es el 78.4 de 157.27s. O sea que esos
catorce milisegundos son **el cambio de escala**, no el atlas, y encajan con la
pendiente de arriba.

**Regla:** bajar `positional_shadow_atlas_size` en una escena sin proyectores no
compra nada. La tienda es exactamente ese caso. Chimera no - tiene tres
`shadow_enabled = true`.

### `screen_space_aa` no estaba en la línea `SETTINGS`, y valía 4ms

La quinta vez que una fila del preset no se puede atribuir porque el log no la
imprime. A los 171.72s el `vp=` pasa de `ssaa2 aniso2` a `ssaa1 aniso1` de
golpe, mientras `SETTINGS` sólo puede informar de `aniso=4x -> 2x`. El frame
baja 3.4ms y la VRAM 39MB.

**Los 39MB delatan cuál de las dos fue.** El filtrado anisotrópico es estado de
muestreador: no reserva nada. SMAA reserva búferes a pantalla completa. Así que
el paso es SMAA->FXAA y atribuirlo al anisotrópico habría sido exactamente el
error que este fichero documenta cuatro veces. `ssaa=off/fxaa/smaa` está ahora
en `_graphics_summary()`.

### Tres sospechas más, comprobadas contra código y cerradas

Ninguna de las tres era un problema real. Se dejan escritas para que nadie
vuelva a gastar una sesión en ellas.

**El bus de audio `"Radio"` con cinco efectos no cuesta nada, comprobado en el
código fuente de Godot.** `default_bus_layout.tres` lleva un bus `Radio` con
Distortion+HighPass+LowPass+BandPass+Amplify siempre presentes, y nada en el
proyecto envía audio ahí (`grep` de `"Radio"` y de `get_bus_index` no encuentra
ni una referencia, ni literal ni dinámica). Parecía trabajo de mezcla gratis
por descubrir, pero `servers/audio/audio_server.cpp:578` salta el efecto
entero cuando el canal no tiene audio activo, salvo que el efecto override
`process_silence()` - y de los built-in sólo `AudioEffectCapture` y
`AudioEffectRecord` lo hacen. Un bus sin nada sonando cuesta cero, verificado
contra el código, no supuesto.

**El glow del `PostProcessingTree` de la tienda ya está bien enganchado.**
`Environment` shipea `glow_enabled = true` como valor autorado base, que
parecía un candidato a "el preset no lo alcanza" (la clase de bug que ya
salió cuatro veces con `screen_space_aa`, el atlas de sombras direccional,
etc). No lo es: el estado `off` del árbol (post=0, o sea Low y Very Low) lo
apaga, `low` y `high` (post=1/2) lo dejan encendido - exactamente lo que
debería.

**"El coste de física de la tienda corre 10-25x el de Chimera" no está en los
datos.** Contado sobre los 33 logs del proyecto: `p3d_objs=0` de mediana en
**las dos** escenas (`env_collector_shop.tscn` y `sng_chimera.tscn`), y
`p3d_pairs` comparable (tienda mediana 10/máx 52, Chimera mediana 0/máx 31).
La causa sospechada tampoco era real: el apuntado de la tienda es un solo
`RayCast3D` en `mouse_controller.gd`, no picking por `Area3D`, y
`enable_object_picking` ni siquiera es una propiedad real de `Viewport` (la
que existe es `physics_object_picking`, sin usar en ningún sitio del
proyecto). Corregido también el comentario que originó la sospecha en
`lullaby_diagnostics_log.gd`.

### Cómo se lee un A/B de gráficos, y por qué los anteriores no valieron

```bash
python3 tools/compare_gpu_by_sequence.py A.log B.log
```

Empareja los latidos de las dos pasadas **por nombre de secuencia** y saca
`gpu` de cada una con su razón. Dos motivos, y los dos han invalidado antes
algún intento:

- **Chimera no es lenta de forma uniforme.** En `10152-665dedd4` la misma
  canción va a 14.8ms en `113_reaching` y a 48.7ms en `104_photographysesh` -
  3.3x de diferencia dentro de una partida. Una media sobre eso la domina
  cuánto se entretuvo el jugador en cada tramo, así que dos pasadas de la
  **misma** build ya difieren más que la mayoría de los ajustes.
- **El teléfono cambia por debajo.** La herramienta imprime `bench=` **antes**
  que cualquier `gpu`, y avisa si se movió más de un 25%. No es un reparo
  teórico: en ese log `bench` va de 187us a 960us *dentro de una sola sesión*.

El veredicto se calcula contra la razón de píxeles que la escala implica, leída
de `vp=` y no de `scale=` -que es lo pedido, no lo aplicado, y `186e17f` existe
porque discreparon-. Si el coste por píxel explica ≥60% es fill-rate; si ≤25%,
el techo es geometría o estado y hay que tachar lo escrito sobre fill-rate.

**El experimento que falta, y que esta herramienta existe para leer:** Chimera
solo se ha registrado **jamás** a `scale=0.50`. Dos pasadas seguidas a 0.35 y a
0.75 -moviendo esa fila sola, sin tocar el preset- dicen de una vez si el techo
es por píxel. Es más barato y más informativo que el A/B de sombras, que además
ya no procede: a Very Low las sombras salen apagadas, `post=0` deja el NTSC y
los godrays de `Ray` fuera, y `env=limpio` en los 42 latidos.

**Intento de correrlo aquí en frío, sin teléfono: se atasca, no se resuelve.**
`tools/harness/render_scale_sweep.gd` (nuevo) hace exactamente esto - congela
el reloj de Chimera en un `t=` y cicla `Viewport.scaling_3d_scale` por
0.35/0.50/0.70/1.00, midiendo tiempo de pared real por frame (no
`viewport_get_measured_render_time_gpu`, que en un renderer software puede no
contestar igual que el Mali-G76 del log real). Parsea limpio contra el
analizador real. Pero `setup_render_sandbox.sh` -degrada las 503 texturas a
128px sin compresión para que lavapipe no se atasque decodificando ASTC, ya
descrito en la sección de renderizado más abajo- tenía un bug real que se
arregló de paso: el segundo `find` (copias reales de `.tscn`/`.tres`/`.gd`/
`.cfg`...) no excluía `.godot/`, así que un `.cfg` de estado de plegado del
editor dentro de `.godot/editor/` rompía el `cp` porque el directorio destino
no existía (`.godot` está excluido a propósito del hardlink inicial). Arreglado
con `-not -path './.godot/*'` en ese find.

Con eso el import del sandbox termina (unos minutos, no horas - las texturas
ya no son EXHAUSTIVE). Pero **correr la escena de verdad bajo
`--rendering-method mobile --rendering-driver vulkan` se cuelga antes de
`_ready()` terminar** - RAM en el proceso se estabiliza en ~670MB, CPU cae
hacia 0%, y los 23 hilos están todos en `futex_do_wait`/`hrtimer_nanosleep`
(motor inactivo, no calculando). Matado a los ~6 minutos sin una sola línea
`OUT`. Probado con y sin `--headless` - la receta de `scene_shot.gd` tampoco
lleva `--headless`, así que el intento final ya coincidía con eso. No se llegó
a averiguar si el atasco es el tamaño de Chimera, esta build concreta de
lavapipe del contenedor, o algo que `--headless --import` deja en un estado
que la ejecución en vivo no puede usar - lo primero que hay que acotar la
próxima vez, o directamente correr esto en una build de teléfono real en vez
de seguir peleando con el sandbox.

### Tools for this: diff the port against the pck directly

Three scripts, all mounting the pck read-only:

```bash
godot --headless --script tools/diff_pck_scene.gd -- <port_path> <pc_path>
godot --headless --script tools/diff_pck_file.gd  -- <pc_path> <out_path>
godot --headless --script tools/diff_pck_texture.gd -- <pc_path> <port_path>
```

`diff_pck_scene.gd` dumps every authored node property and expands any
`AnimationLibrary` to per-animation track paths, without instantiating - it is
what proved `chr_goldp1.tscn` and `sng_monochrome.tscn` are byte-equivalent to
the mod's (18 nodes / 198 animations and 138 nodes / 125 animations, identical
track counts and paths), which is what narrowed Monochrome's remaining bugs
down to the engine instead of the data. `diff_pck_file.gd` is for the things
the resource loader never sees - gdanimate reads `Animation.json` and
`spritemap*.json` with `FileAccess`, so `get_dependencies()` says nothing
about them.

**A cropped spritemap is not automatically a bug.** `8b0e901` cropped dead
transparent padding from 11 atlases, and the sizes no longer match the
`meta.size` their `spritemap*.json` declares (goldp1/turnaround is 4068x2598
against a declared 4096x4096). That looks alarming and is fine: regions are
absolute pixel rects from the top-left, and every region still fits inside
every cropped texture. The check that matters is `max(x+w), max(y+h)` over
`ATLAS.SPRITES` versus the real PNG size, not the declared size.

**When a port bug survives every data check, decompile the pck's engine and
diff it.** `/tmp/gdre_tools/gdre_tools.x86_64` (GDRE 2.6.3) does it
properly - `tools/read_pck_scripts.gd` recovers only *string constants*,
not identifiers, so "nothing mentions X" is worthless for function and
property names (verified: `singing_hold_type` returns zero hits even though
the pck's own scenes assign it). The real recipe:

```bash
cd /tmp/gdre_tools
./gdre_tools.x86_64 --headless --extract=<pck> --include="res://addons/rubicon/**" --output=<dir>
./gdre_tools.x86_64 --headless --decompile=<dir>/path/to/file.gdc --bytecode=4.5.0
```

`--scripts-only` and `--include` are mutually exclusive. The decompiler
*infers* type annotations that the real source cannot have had - it
annotated a handler as `RubiconLevelNoteHandler` and then read `lane_state`
off it, which only exists on the mania subclass and would not parse. Treat
its types as hints, not truth.

`gdre_tools.x86_64 --headless --compile=<file.gd> --bytecode=4.5.0` is the
fastest syntax check for an engine script - but **it only tokenises. It does
not run the type analyser, and it will happily accept code Godot refuses to
load.** Do not use it as the only check on a script you are about to ship.

That gap shipped a broken build. `lullaby_fps_display.gd` said `extends Node`
while sitting on a `CanvasLayer` (legal - a script may extend any ancestor of
its node's type), and reaching the layer's own `offset` through
`self as CanvasLayer` is an *invalid cast* at analysis time. GDRE compiled it
without complaint; on device the whole script failed to parse, the node ran
with no script at all, and the debug overlay drew every container it was
authored with, frozen, with nothing ever calling `update_visibility()`.

The check that catches it is Godot's own analyser against a throwaway project:

```bash
mkdir -p /tmp/parsecheck
printf 'config_version=5\n[application]\nconfig/name="p"\n' > /tmp/parsecheck/project.godot
godot --headless --path /tmp/parsecheck --check-only --script <abs path to file.gd> 2>&1 \
  | grep "Parse Error" | grep -vE 'not declared in the current scope|Could not find type|Preload file'
```

The filter drops exactly the noise an isolated project always produces -
autoloads (`Settings`, `SceneChanger`), `class_name`s and `preload()` targets
it cannot see. Anything that survives the filter is real. Compare against the
same file at `HEAD` before believing a leftover: some scripts (gdanimate's
`animate_symbol.gd`) already emit "Cannot infer the type of X" from the
unresolvable `class_name`s and always have.

**`git push` for LFS is blocked** - `lfs.github.com` gets a 403 at CONNECT
from the environment proxy (org policy, do not retry or work around it).
`github.com` itself is fine. Anything under `precompiled_astc_imports/*.res`
therefore has to be pushed by the user from their own machine.

---

## Texture pipeline

Custom importer `lullaby.astc_sprite` (`addons/astc_sprite_import/`), block
size 8, calling `tools/astc_compress`. Output is `.res`, **not** `.ctex` -
which matters, because a scene with a hardcoded `load_path` to a `.ctex` will
fail to load once its texture moves to this importer. That is what made
Chimera fail to load entirely.

**ASTC 8x8 costs exactly `ceil(w/8)*ceil(h/8)*16` bytes - resolution only.**
Basis Universal (`compress/mode=4`) tracks content instead. So:

- on a dense texture ASTC is much smaller (4096² dense: 9.01MB -> 4.00MB)
- on a sparse one Basis is *smaller than ASTC's flat floor*, and converting
  makes it bigger
- converting all 397 Basis textures blindly would have **added 11.8MB**

Always measure per texture before converting. The 66 textures on
`compress/mode=0` (Lossless) are 4.5MB as PNGs and 9.1MB as ASTC - leave
them.

**ASTC does not reduce VRAM here.** Basis was already transcoded to a
compressed GPU format on device. Only *resolution* reduces VRAM.

**But `compress/mode=0` (Lossless) does, and it is the worst offender in the
project.** Lossless is not compressed on the GPU at all - it is RGBA8, four
bytes per pixel. The earlier note here said to leave the 66 mode=0 textures
alone because they are 4.5MB as PNGs and 9.1MB as ASTC; that was about **APK
size** and is still true, but as **VRAM** they were catastrophic:

| | | RGBA8 | compressed |
|---|---|---|---|
| `settings_icons.png` | 4096x2048 | 33.6 MB | 8.4 MB |
| `OptionsBox.png` | 2048x2048 | 16.8 MB | 4.2 MB |
| `training_icons.png` | 4096x512 | 8.4 MB | 2.1 MB |
| `ConsoleStartup.png` | 2048x1024 | 8.4 MB | 2.1 MB |
| `lil_ector.png` | 256x2048 | 2.1 MB | 0.5 MB |

Five console UI textures, 69.2MB of VRAM between them, 1.7MB of PNG on disk.
Moved to Basis (mode 4) rather than VRAM Compressed (mode 2): both land at the
same ~1 byte/pixel on device, but Basis is content-aware so these mostly-flat
UI sheets stay small in the APK instead of adding ~15MB of ASTC.

### All Basis textures moved to ASTC 8x8

337 textures moved from `compress/mode=4` to the project's own
`lullaby.astc_sprite` importer at block size 8, EXHAUSTIVE quality. Basis
transcodes to about 1 byte/pixel on device, ASTC 8x8 is 0.25, so:

**VRAM 510MB -> 128MB, and the ASTC payload totals 128MB against 203MB of PNG
sources.** By a wide margin the biggest change in the port.

This was the user's call, made against a quality measurement that argued the
other way, and the measurement is left here rather than deleted because the
numbers are still the numbers - `tools/measure_astc_quality.gd`:

| | PSNR | worst channel error |
|---|---|---|
| `grass.png` | 18.9 dB | 255/255 |
| `hypnobald.png` | 23.4 dB | 255/255 |
| `rock.png` | 26.9 dB | 255/255 |
| `spritemap1.png` | 36.0 dB | 255/255 |
| `front_trees.png` | 45.9 dB | 84/255 |
| `end_bg.png` | 51.9 dB | 15/255 |

The worst-case errors are in the **alpha channel** - this art is hard-edged
cutout, and 8x8 fringes every boundary; `end_bg.png`, the one opaque
background, is the only clean result. Two caveats on those numbers: the tool
uses Godot's encoder rather than EXHAUSTIVE, and `sprite_importer.gd`'s own
header records that the two measured **~0.4dB apart** at the same block size,
so EXHAUSTIVE is not a large reprieve. If fringing shows up on device, this
commit is the thing to revert.

Things this touched that are easy to miss:

- **The importer pads, it does not resize** (`9b07a65`), blitting into a
  transparent canvas at (0,0). Regions therefore stay valid - 41 of the
  converted textures are region-sliced and are unaffected. But the texture's
  *reported size* grows to the next multiple of 8, so **82 textures used whole
  get up to 7px of transparent padding** on the right and bottom. 375 were
  already a multiple of 8.
- **UIDs and output hashes are unchanged** - only the extension moves, `.ctex`
  to `.res`, because the hash is the md5 of the `res://` source path.
- **A stale precompiled pair had to go.** `FucknoBack.png` was in
  `precompiled_texture_imports/` as a `.ctex`, which its `.import` no longer
  expects. Deleting it emptied that directory, and the workflow's
  `cp precompiled_texture_imports/*.ctex` had no guard - an empty glob would
  have failed the build. It is `nullglob`-guarded now.
- **CI will pay for this once.** EXHAUSTIVE 8x8 measured 5.2s for 4096x1170 on
  8 threads here, so ~9 minutes for all 510 Mpx locally and proportionally
  more on a smaller runner. `precompiled_astc_imports/*.res` is Git LFS, which
  this environment cannot push, so the outputs have to be generated and pushed
  from a real machine to make it a one-off.

**Changing the compression mode cannot break an atlas.** It does not touch the
texture's dimensions, so every `AtlasTexture` region and every
`spritemap*.json` rect still lands where it did. That is what makes this safe
where rescaling a sheet is not - the 129 region-sliced sheets above 2048 would
each need every region rewritten in lockstep, and this repo has been broken by
exactly that class of change before.

`tex_static_noise.png` and the app icons stay lossless on purpose: the first is
sampled as data by `shd_shop_static_spatial`, and lossy noise is artefacts.

**The importer used to `img.resize()` to reach a multiple of the block size**,
which rescales rather than pads and shifted every pixel a few thousandths.
Invisible on a standalone sprite, fatal on an atlas whose regions come from a
`spritemapN.json` in exact source pixels. It silently distorted 28 textures
and was why Gold's back-turned intro never appeared. Fixed to pad in
`9b07a65`.

**Precompiled imports** (`precompiled_astc_imports/`) hold pre-run importer
output so CI does not spend an hour on EXHAUSTIVE ASTC. Godot decides whether
to reimport by comparing **content hashes**, not timestamps - so changing the
*importer* does not invalidate them, and stale output will be restored over a
fix. Delete the affected pairs when the importer changes.

Filenames are `<basename>-<md5 of the res:// source path>.res`. You can
generate them in a mirror project that uses the identical `res://` paths.

---

## The diagnostics log

`lullaby_mod/scripts/lullaby/debug/lullaby_diagnostics_log.gd`, autoload
`DiagnosticsLog`, on by default (`Settings.lullaby_diagnostics_log`).

Writes to the first writable of:
1. `/storage/emulated/0/.HypnosLullaby/logs` (needs All-files-access;
   `permissions/manage_external_storage=true` is in `export_presets.cfg`
   **for debugging only** and should come back out)
2. `/storage/emulated/0/Android/data/com.rubicon.fnf/files/logs`
3. `user://logs` - which on Android is *internal* storage and unreachable
   without root. This is why the log first appeared not to exist.

The header records `dir_used`, so a log always says where it ended up.

Entry types: `HEARTBEAT` `SPIKE` `MEMORY` `SCENE_OUT` `SCENE_IN` `LOAD`
`CENSUS` `SUMMARY` `WARNING` `ERROR` `MARK`. Every line carries the full
counter set so one line answers "what was happening".

How to read it:

- `proc` high, `draw` flat -> CPU-side
- `draw`/`vram` high -> GPU
- **`pipe=N(+D)`** is the running count of GPU pipelines the engine has had to
  compile, with this entry's delta. A non-zero `+D` on a stall frame means the
  engine stopped to build shader pipelines - the one cause the log was blind
  to before 4.7 exposed `RENDERING_INFO_PIPELINE_COMPILATIONS_*`.
- `proc` is **not** GDScript-only. `TIME_PROCESS` covers the whole process
  step, including engine-side node and animation work, and it also picks up
  main-thread waits (it sits at 95-322ms during threaded scene loads, when
  almost no script is running). So "proc high" does not mean "your script is
  slow"; it means the frame's process step blocked, whatever on.
- **`frame` is the wall clock and `proc` is the stale one - this used to say
  the opposite.** `473788e` stopped deriving `frame` from `delta`, which Godot
  clamps, and timed it with `Time` instead, so `frame` now reports the true
  size of a freeze. `proc` is `TIME_PROCESS`, a **per-second maximum**, so on a
  frame longer than a second it reports the previous second's number and reads
  low. In `10152-665dedd4`, `122_fall@6.8s` logs `frame=1911.7ms` with
  `proc=34.7ms` - read `frame`, and treat a low `proc` on a long frame as an
  artefact of the monitor rather than evidence the CPU was idle.
- `orphans` climbing then **flat** -> a pool filling, not a leak
- `SUMMARY vs_first` climbing with nothing else changing -> thermal throttling
- `LOAD` checkpoints spread out -> resource loading; bunched at the end ->
  instantiation
- **`gpu=n/d` significa que el driver no contesta, no que la GPU estuviera
  ociosa.** El moto g(60)s (Mali-G76 MC4, driver 1.1.131) devuelve 0.00 en las
  492 entradas de `dcb37c09`, con `cpu_render` variando normalmente al lado.
  Contada sobre los 33 logs del proyecto, la racha máxima de entradas seguidas
  con `gpu == 0` y `cpu_render > 0` es **492 en ese modelo y 0 en los otros
  cinco**, así que la pareja separa los dos casos sin margen de duda. El log
  echa el pestillo a las 12 entradas, lo dice con una línea `GPUTIMING`, y a
  partir de ahí `gpu=` y `sub_gpu=` salen `n/d` en vez de `0.00`. En ese
  dispositivo **el frame hay que leerlo de `median=`**, no de `gpu=`.
- **`gpu=`/`cpu_render=`** are Godot's own GPU timestamp queries
  (`RenderingServer.viewport_get_measured_render_time_gpu/cpu`, one frame
  behind - not a `Viewport` instance method, confirmed the hard way against
  4.7.1). `proc` cannot tell "CPU busy building draw commands" from "CPU
  blocked waiting on the GPU" from "GDScript was slow"; a stall with `proc`
  and `gpu` both high is a real GPU-side cost (shadow atlas repack, a
  pipeline compiling), `proc` high with `gpu` flat points back at the CPU
  (skinning, culling/octree inserts, instancing).
- **`p3d_objs=`/`p3d_pairs=`** are `Performance.PHYSICS_3D_ACTIVE_OBJECTS`/
  `PHYSICS_3D_COLLISION_PAIRS` - added for a suspected "shop's physics cost
  10-25x Chimera's" that was flagged and never actually measured. Now it has
  been, across the project's 33 logs: median `p3d_objs=0` in **both**
  `env_collector_shop.tscn` and `sng_chimera.tscn`, and pairs comparable (shop
  median 10/max 52, Chimera median 0/max 31). The suspected cause was also
  never real - `mouse_controller.gd`'s aim is one `RayCast3D` in
  `_physics_process`, not per-`Area3D` picking, and `enable_object_picking`
  is not a real property (`Viewport.physics_object_picking` is, and nothing
  in this project sets it). Closed: not a lever.
- **CENSUS `lights=N(shadow=M)`** counts currently-visible `Light3D` nodes
  and how many of those have `shadow_enabled` - Godot exposes no shadow-atlas
  counter directly, so this is the closest indirect read on whether a new
  shadow caster lines up with a stall.
- **CENSUS `trees=N(active=M)` / `notes=N(visible=M)`** - added because every
  prior Chimera census happened to land during a cutscene, where `playing`
  AnimationPlayers sat at 5-17, nowhere near the ~240 the "40 notes on screen
  x 6 AnimationPlayers each" theory (see the note-scene section below)
  implies. That theory was never actually tested, not ruled out: `Note.tscn`
  drives 4 of its 6 AnimationPlayers through an `AnimationTree` state
  machine, which never calls `.play()` on them, so they read
  `is_playing()==false` no matter how much per-frame blend work the tree is
  doing. `trees_active`/`notes_visible` are the counters that were missing to
  actually catch a dense-note moment instead of another cutscene.
- **CENSUS `top_anims` now carries `@Ns`** - the playing animation's position
  within itself (e.g. `SequencePlayer/122_fall@7.5s`), not a timestamp. Turns
  "122_fall was playing" into "7.5s into 122_fall", which is what actually
  locates a stall against one of its 31 tracks' keyframes instead of
  reconstructing it from wall-clock arithmetic across log lines.

`DiagnosticsLog.mark("text")` drops a labelled line from anywhere.

### The fields added so this stops needing a build per question

Every one of these is on every entry, and each exists because something
specific was once impossible to answer without another device session. Read
this table before adding a counter - the odds are it is already there.

| field | answers |
|---|---|
| `seq=122_fall@7.5s` | where in the song this line was written. Position *within* the sequence, so a stall lands against one of its tracks |
| `anim=N/M` | AnimationPlayers running / AnimationTrees active. Counted separately: a tree never calls `play()` on the players under it |
| `procn=` / `physn=` | nodes running `_process` / `_physics_process`. Bounds on what the main loop can possibly be doing |
| `self=` | this log's own `_process`, **subtracted from `rest=`** so the instrument is not inside its own number |
| `bench=Nus` | fixed arithmetic, timed. **The one that makes every other number trustworthy** - see below |
| `vis3d=N/M` | how many of the scene's `VisualInstance3D` are **switched on**, against its total. This row used to say "on screen" and that is **wrong**: `_visual3d_load()` is `is_visible_in_tree()`, which knows nothing about the frustum. Two shots costing 32.0ms and 14.8ms both read `vis3d=74/96`, so this cannot tell them apart and nothing in the log can |
| `cam=fov75@x,y,z` | where the active Camera3D is. Chimera's cost tracks the shot and no log ever recorded the shot |
| `env=glow+fog` | which per-pixel environment features are actually on. `preset=Very Low` is not evidence any of them is off |
| `rend=[3d=d/p/o sha=... 2d=...]` | the frame's draw calls, primitives and objects **split between the 3D pass, shadow rendering and the 2D canvas** (`viewport_get_render_info`, free). The one field that answers "is it the 2D or the 3D": the 3D runs at `scaling_3d_scale` and the canvas does **not**, so at 0.50 one full-screen 2D layer covers 4x the pixels of the entire 3D pass. `draw`/`prims`/`objs` are totals and correlate with `gpu` at +0.24/+0.26/+0.16 - a 3D pass shrinking while a 2D overlay grows reads as "no change" in all three |
| `mat3d=N/M` | unique 3D materials against surface count - the Peepers bug asked about 3D |
| `bones=` / `parts=N/M` | skinning load; particle systems visible and emitting |
| `psteps=N` | physics ticks *inside* this frame. 6ms across one tick is a heavy world, 6ms across four is a frame already late |
| `vp=[...]` | scaling mode/scale, msaa, aniso, mesh LOD, shadow atlas, **read back off the viewport** |
| `eng=[ts fps hz steps]` | `time_scale`, `max_fps`, physics rate, max steps |
| `focus=LineEdit:X` | the focused Control |
| `tweens=` / `msgq=` | active tweens; message-queue high-water (a `call_deferred` flood) |
| `alat=X/Yms` | audio output latency and time to next mix |
| `probe=Nms(graph= prog= res=) sweep=Nms` | on `SCENE_IN`, what the log itself spent measuring that load, **split by which walk** - plus the RETAINED sweep, which was never inside `probe=` at all. See below |

### `probe=` no dice lo que parece, y por eso ahora va partido

`SCENE_IN` de Chimera trae `took=17588ms probe=1507.3ms`, y la lectura obvia
-"el 8.6% de la carga son los diagnósticos"- **no está apoyada en nada**. Tres
recorridos distintos alimentan ese número y el barrido de `RETAINED`, otros
597ms en la misma carga, ni siquiera estaba dentro. El total honesto nunca se
había impreso: 2104ms, no 1507.

Y hay un motivo para dudar de la lectura entera: los cuatro recorridos van en
`_process`, o sea **en el hilo principal**, mientras `load_threaded_request`
trabaja en un hilo del `WorkerThreadPool`, en un teléfono de 8 núcleos. Lo que
gastan es el presupuesto de frame de la pantalla de carga, que es un coste
real y **distinto** de alargar la carga. Los números del propio log apuntan a
que no la alargan: la tienda carga dos veces en la misma sesión, `took` va de
4763ms a 17420ms (3.7x) y `probe` solo de 623ms a 1145ms (1.8x). Si `probe`
fuera el que manda, crecerían juntos.

Capar el total sobre esa lectura habría sido optimizar contra un número que
nadie había desglosado - y la nota sobre `PROBE_BUDGET_USEC` ya registra qué
pasa cuando este recorrido se capa sin cuidado: `deps=111/112` sobre un grafo
de 512, con todo lo que quedaba por debajo del corte sin contar ni nombrar.

Así que en vez de capar, se partió:

| | qué es |
|---|---|
| `graph=` | el recorrido en anchura sobre `get_dependencies()` que construye el denominador de `deps=N/M` |
| `prog=` | la pasada de `has_cached()` una vez por segundo sobre lo que falta |
| `res=` | el recorrido de residuo de la escena que sale |
| `sweep=` | `_continue_retained_sweep`, que informaba aparte en `RETAINED` y por eso se leía como gratis |

El siguiente log lo decidió, a la primera:

| escena | `took` | `probe` | **`graph`** | `prog` | `res` | `sweep` |
|---|---|---|---|---|---|---|
| chimera | 18883ms | 1758 | **1692** | 56 | 10 | 579 |
| tienda #2 | 18055ms | 1070 | **980** | 79 | 11 | 629 |
| tienda #1 | 4746ms | 789 | **765** | 16 | 8 | 107 |

**El BFS sobre `get_dependencies()` es el 92-96% del `probe`.** La pasada de
`has_cached()` por muestra no cuesta nada y no hay que tocarla. Si algún día
hay que acotar esto, es el BFS y solo el BFS - y la nota sobre
`PROBE_BUDGET_USEC` dice cómo se hace mal.

### El instrumento se callaba justo en los frames que existe para medir

Escrito aparte porque es la clase de fallo que invalida conclusiones sin dejar
rastro: **no produce una línea equivocada, produce ninguna línea.**

`473788e` movió `frame_ms` al reloj de pared porque el `delta` de Godot deja
de describir el frame por encima de ~50ms - 300ms llegan como 53.1ms, 1200ms
como 80.9ms y 5000ms como 66.7ms, o sea que ni siquiera es un techo. Lo que
ese commit no tocó son los cuatro temporizadores que deciden **si se escribe
una entrada**: `_time_since_spike`, `_time_since_heartbeat`,
`_time_since_census` y `_time_since_summary`. Los cuatro seguían sumando
`delta`, así que en un frame atascado apenas avanzan y sus puertas se quedan
cerradas.

Lo que costó, en `10152-665dedd4`:

- el frame de **7787.6ms** del precache de la tienda **no tiene línea
  `SPIKE`**. `_time_since_spike` había ganado unos 66ms de crédito por 7.8
  segundos de reloj y seguía dentro de `SPIKE_COOLDOWN_SECONDS`. Solo lo
  recogió `SUMMARY worst=`, que se alimenta de `frame_ms`.
- el latido se saltó **13.5s** (30.57 -> 44.09) y **11.5s** (84.19 -> 95.68),
  con `HEARTBEAT_SECONDS` en 5. Los dos huecos son precisamente los dos
  precache.

O sea que los dos tramos más largos que este log ha mirado nunca salieron en
él, y por eso ninguno de los dos estaba en este fichero. Arreglado: los cuatro
van por `frame_ms`, y `tools/test_frame_clock.gd` lo fija (9 comprobaciones).

**La regla general:** si añades un contador de tiempo a este fichero, aliméntalo
de `frame_ms`, nunca de `delta`. `delta` solo es correcto en el primer frame,
donde todavía no hay `_last_frame_usec`.

**Y había una segunda puerta, que sobrevivió a ese arreglo.** El log siguiente,
`10154-8d1ee1ac`, ya con los cuatro temporizadores al reloj, trae un frame de
**7391.8ms** dentro del primer precache de la tienda y **sigue sin línea
`SPIKE`**. Solo lo recoge `SUMMARY`.

La causa es `_frames_seen`, que se pone a 0 en cada `SCENE_IN` -a propósito, el
buffer de frames no significa nada al cruzar una carga- alimentando una
condición `_frames_seen > WINDOW_SIZE` con `WINDOW_SIZE = 120`. El precache
corre justo después de la carga y a pocos frames por segundo: el de la tienda
gasta 8.6 segundos y nunca se acerca a 120 frames. **El detector duerme
exactamente el tramo que existe para medir**, y lo hizo en dos builds seguidas.

Ahora hay dos formas de entrar. La prueba de razón sigue necesitando la ventana
llena, que es lo correcto para un pico moderado; un frame por encima de
`SPIKE_ALWAYS_MS` (250ms) se reporta pase lo que pase, marcado `(sin ventana)`
porque en ese caso la `median=` de al lado es el 16.6 de reserva y no una
medida.

Three of them are worth knowing *why*:

**`bench=` kills the confound that poisons every other measurement here.**
Two effects drop the clocks in the same direction - the touch-boost governor
when nobody is touching the screen, and thermal throttling across a session -
and `SUMMARY vs_first` cannot tell either from a scene that got heavier. If
`bench=` rises by the same factor as `script=`, the device changed and the
scene did not. It compares only within one template (debug runs GDScript
arithmetic ~1.24x slower), which is what the header's `template :` is for. It
is 2000 iterations because 20000 measured 1.08ms a run and would have put a
spike on one frame per second - the instrument perturbing the measurement,
which is the thing it exists to expose.

**`vp=` is the preset-ladder bug class made visible.** Four separate times a
preset did not lower what it claimed to, each found by reading code months
late. Reading the viewport back turns that into one line.

**`focus=` is the shop keyboard bug.** The reverted prewarm revealed hidden
nodes, gave focus to the Codes tab's `LineEdit` and opened the Android
keyboard on a screen the player never chose. That cost a device session; this
field would have said it immediately.

All of it comes out of the walk `_collect_blackout_watch` already ran one
second after the scene settles, so **no new tree walk was added**. The
per-frame cost is a visibility check per particle system and about a hundred
`is_playing()` calls off a cached list. `BLACKWATCH` prints the static
inventory once per scene - rects, mixers, visuals, particles, process nodes,
surfaces, unique materials, skeletons, bones - and names which player it
picked as the sequence driver, so a wrong pick is visible rather than
silently producing `seq=-`.

Two habits when adding to this file. Check property names against the running
binary (`ClassDB.class_get_property_list`) rather than writing them from
memory - the iOS preset work found half a dozen plausible names that do not
exist. And check the format string's arity against `HEAD` rather than by eye:
the parser in `git log` for these commits undercounts specifiers by a
constant 7, so what matters is that the delta is unchanged, not that the two
numbers match. The stub project cannot run this file - its `class_name`
dependencies hang a fresh project - so that check is structural.

---

## Reemplazar el 74.6% de Chimera por vídeo: investigado y descartado

El usuario propuso reemplazar los tramos de Chimera sin Serena en pantalla por
vídeo pre-renderizado sin HUD. La idea pasó por tres rondas y vale la pena
dejarlas todas, porque cada una cambió el veredicto.

### Ronda 1: ¿hay algo reactivo en esos tramos? Sí - los dos personajes, se pensó

Chimera tiene exactamente dos instancias de `RubiconCharacter` con
`level_note_controller` conectado: `hex` (carril Opponent) y
`Sequences/SerenaBase/SerenaBase` (carril Player). Cualquiera de los dos
cantando o fallando en vivo según el jugador rompería un vídeo horneado.
Primer veredicto (equivocado): sólo el 5.1% de la canción está libre de
**ambos** - un solo tramo, `105_headingout`+`106_cameracheck`, 62.33s-72.50s,
y ni siquiera es de los planos ya identificados como caros.

### Ronda 2: el error estaba en tratar a `hex` como reactivo

No lo es. `UILayer/GameUI/Opponent` (el controlador de `hex`) lleva
**`autoplay = true`** - nunca recibe input real, siempre toca el chart
perfecto. Y sus animaciones `miss_up/down/left/right` están *todas* alias a
`hex_misc_anim_library/idle_anim` - no existe visualmente un "fallo" para él.
`UILayer/GameUI/Player` (Serena) no tiene esa línea, lleva `inputs` conectado
a las pulsaciones reales, y sus `miss_*` son clips propios y distintos.

Recalculando con Serena como único límite real: recorriendo el reloj de la
canción (`RubiconLevelClock`, 27 secuencias despachadas, animación "scene" de
199.875s) y simulando cada pista `:visible` de Serena, ella sólo está en
pantalla entre **3.00s y 53.78s** (`101_prelude`, `102_intro`, `103_stroll`).
Todo lo demás - **149.1 de 199.9 segundos, 74.6%** - está libre. Casi
exactamente la estimación original del usuario. La lección: comprobar
`autoplay` y si las animaciones `miss_*` son distintas de `idle`, no sólo si
un nodo está atado a un `level_note_controller` - eso solo, sin más, no basta
para decir que algo es reactivo.

### Ronda 3: el vídeo en sí, medido, y por qué se descarta igual

Con la mitad del problema resuelta, la otra mitad decide todo. Tres hechos,
medidos:

**No hay descodificación por hardware, confirmado contra el APK real del
proyecto.** `android_debug.apk` desempaquetado, `strings` sobre
`libgodot_android.so`: sólo símbolos de `VideoStreamTheora`/`libtheora`. Nada
de MediaCodec, nada de ExoPlayer. Software puro sin añadir un plugin nativo -
que rompería la limpieza que hizo trivial el port a iOS.

**El coste de decodificar es real y no se solapa gratis con la GPU.** Medido
con `ffmpeg -benchmark` aislado (un hilo, sin Godot ni Xvfb de por medio),
1600x720: 4.7-5.1ms/frame en el peor caso (alto detalle), 2.3ms/frame en
contenido más comprimible, en una CPU de escritorio x86_64. Y dentro de Godot
mismo el coste **escala con la resolución del vídeo** - evidencia de que no
se esconde en el hueco de CPU que ya tiene Chimera (`script` 8ms contra `gpu`
31ms): aterriza como coste añadido al frame, no como relleno gratis. Sin
dispositivo real no hay número exacto para el Adreno 619, pero el patrón de
toda la sesión (el móvil siempre más lento que cualquier x86 de escritorio)
apunta a 5-20ms por fotograma sólo en decodificar - entre un tercio y la
totalidad del presupuesto de 16.7ms a 60fps, antes de que la CPU haga nada
más.

**El peso, para los 149s candidatos:** 219-305MB a 1600x720 según calidad,
71-96MB incluso en el mejor caso probado (contenido comprimible u
horneado a media resolución). Más del doble de los 33MB que ganó toda la
conversión a ASTC de esta sesión - por una sola canción.

**Y no hay precedente en este proyecto.** Ni el port ni el pck original en PC
usan vídeo en ningún sitio - cero `.ogv`, cero `VideoStreamPlayer`, en
ninguna escena, comprobado por texto y por `get_dependencies()`. El "vídeo"
del intro de Safety Lullaby que parece justificar la idea no es un vídeo:
`intro.tscn` es una escena 2D normal (`AnimatedSprite2D` + `AnimationPlayer`,
la misma arquitectura de siempre) con cinco capas de niebla en `shd_blend_modes`
copiando el framebuffer cinco veces - por eso cuesta 20.6ms, y por eso *parece*
cinemático sin serlo. No hay ningún caso en este proyecto donde la
descodificación de vídeo se haya probado, ni bien ni mal.

**Veredicto: no compensa.** Cambiaría un cuello de botella de GPU que ya se
sabe atacar (luces, relleno 2D, escala) por uno de CPU sin garantía de
aguantar 60fps en el Adreno 619, con más del doble de peso de APK por una sola
canción, y sin poder verificar la calidad visual real aquí - este entorno no
renderiza Chimera con su iluminación correcta, así que "se ve prácticamente
igual" no se pudo comprobar. Si algún día se quiere cerrar la duda del todo,
el experimento que falta es en el teléfono real: un `.ogv` de 10-15s grabado
de Chimera, reproducido solo, leyendo `gpu=`/`proc=` del log.

## Lo que NO hay que optimizar en Chimera, medido

Escrito para que nadie vuelva a gastar una sesión donde ya está contestado. Todo
de `10152-665dedd4`, 42 latidos:

| candidato | por qué no |
|---|---|
| **La CPU en general** | `script` p50 = **8.06ms** contra `gpu` p50 = **31.43ms**. El frame lo tiene la GPU con casi 4x de margen |
| **El sistema de notas** | `notes=36 ms/s` (≈1ms/frame) y **sin correlación con gpu**: hay `notes=84 ms/s` con `gpu=14.8ms` y `notes=57` con `gpu=48.7ms` |
| **Instanciar notas en canción** | `inst=0` en los 42 latidos. El prewarm del pool funciona y no vuelve a tocarse |
| **gdanimate** | `anim2d=0.00 ms/s` en toda la canción - **pero solo en Chimera, ver abajo** |
| **Post-proceso, NTSC y godrays** | `post=0` a Very Low, y el estado `off` del `PostProcessingTree` pone `Ray:visible = false`. `env=limpio` en los 42 |
| **Sombras** | `shadows=off` ya viene en Very Low |
| **Overdraw 2D** | `over=3.0x` con `gpu=33.4ms` **y** `over=3.1x` con `gpu=18.2ms`. No correlaciona |

Y el dato que lo resume: el frame **más caro** de la canción (60.2ms) dibuja
**menos** que el más barato (11.8ms) - 20 objetos y 19657 primitivas contra 41
y 23046. El coste sigue al plano de cámara y a nada más.

**Chimera no es lenta de forma uniforme; lo son cuatro o cinco planos.**
`113_reaching` va a 14.8ms y `116_hexstare` a 15.1ms - los dos a 60fps - contra
`104_photographysesh` a 44.2ms y `112_disorientidle` a 39.6ms. Cualquier
optimización que suba la media sin tocar esos planos no se nota.

**Pero *cuáles* son esos planos no sale de este log, y esta tabla lleva meses
usándose como si sí.** Cada secuencia aparece 1-3 veces en los 42 latidos, así
que cada una se midió al reloj que hubiera en ese instante - y el reloj se
mueve 12x dentro de la sesión (ver la sección del gobernador). Sacando `bench`
al lado, los cuatro "planos caros" son exactamente los cuatro medidos más
despacio:

    104_photographysesh  44.2ms  bench=1094us
    112_disorientidle    39.6ms  bench=1214us
    114_hexapproach      35.3ms  bench=1434us
    115_runningaway      30.4ms  bench=1883us
    103_stroll           31.5ms  bench= 240us   <- reloj alto, y aun asi 31.5ms

Ordenar secuencias por `gpu` crudo es ordenarlas por cuánto estaba acelerado
el teléfono. Lo que **sí** sobrevive es `103_stroll`: 31.5ms a `bench=240us`,
o sea con el reloj arriba, cuatro latidos y 162 toques. Ese plano es caro de
verdad. El resto del ranking hay que rehacerlo con `bench` al lado, o con dos
pasadas seguidas, que es para lo que existe `compare_gpu_by_sequence.py` -
protege **entre** pasadas y nada protegía **dentro** de una.

### Dos subsistemas dados por gratis midiendo la canción equivocada

`notes=` y `anim2d=` se descartaron arriba, y las dos medidas son de Chimera.
El log del A17 (`10154-8d1ee1ac`, Mali-G57) trae por primera vez Monochrome y
Safety Lullaby, que son canciones **2D puras** - `rend=[3d=0/0/0 ...]`, 334 y 92
primitivas - y ahí los números son otros:

| | Chimera | **Monochrome** | **Safety Lullaby** |
|---|---|---|---|
| `gpu` p50 | 31.85ms | 13.23ms | 25.93ms |
| `draw` | 21 (3D) + 10 (2D) | 41.5, todo 2D | **8.5**, todo 2D |
| `prims` | 16106 | 334 | **92** |
| **`notes`** | 14.85 ms/s | **69.12** (max 118.6) | 34.23 |
| **`anim2d`** | **0.00** | **56.80** (max 153.4) | 38.17 (max 52.1) |

**gdanimate no es gratis, es gratis en Chimera** - que es la única canción que
no usa atlas de Adobe en escena. En Monochrome cuesta 56.8 ms/s de mediana y
pica a 153.4. Y el sistema de notas cuesta ahí 4.7x lo que cuesta en Chimera.

Entre los dos son ~126 ms/s en Monochrome, o sea ~2.5ms por frame a 50fps, más
`script` 6.18ms. Monochrome es una canción **de CPU**; Chimera es de GPU. La
tabla de arriba solo vale para Chimera y hay que decirlo cada vez que se cite.

Y el otro dato de esa tanda: **Safety Lullaby cuesta 25.93ms de GPU con 8.5
draw calls y 92 primitivas**, en una pantalla de 2340x1080. Eso es relleno puro
y nada más - el canvas 2D no baja con `graphics_render_scale`, así que en un
teléfono 1080p una canción que no dibuja nada cuesta 26ms.

### Tres intentos de optimizar gdanimate y las notas, y por qué fallaron

Escritos para que la próxima sesión no los repita. Los tres parecían buenos
leyendo el código y los tres se cayeron al medirlos, **antes** de enviarlos.

**1. "La caché de gdanimate no se rehabilita tras reconstruir."** Es verdad:
`_use_backbuffer_cache` se pone a `false` en cada avance de frame y sólo vuelve
a `true` desde `_notification(TRANSFORM_CHANGED)`, nunca al final de un
rebuild. Parece que el rebuild rellena la caché y el siguiente dibujo la tira.

Medido con el atlas real de Gold, cuatro símbolos, en un proyecto aislado:

| | avances | rebuilds | con caché | rebuild ms/s |
|---|---|---|---|---|
| quietos, código actual | 416 | 412 | 4 | 71.0 |
| moviéndose, código actual | 428 | 424 | 428 | 77.5 |
| moviéndose, **con el arreglo** | 416 | **412** | 424 | **70.7** |

**Inerte.** El ratio rebuild/avance es 0.99 en los tres: ya hay exactamente una
reconstrucción por avance de frame, que es lo correcto. Lo único que encola un
redibujado sin avance es un cambio de transform, y ése ya rehabilita la caché.

Lo que sí queda establecido: los ~57 ms/s de `anim2d` en Monochrome son **el
addon funcionando como está diseñado**, no un fallo. Bajarlos exige menos
símbolos, menos framerate de atlas, o reescribir el rebuild para reusar los RID
en vez de liberarlos y recrearlos - y eso es código vendorizado que la build de
PC tiene byte a byte.

**2. "Los tres bucles de churn recorren el chart entero cada frame."** También
es verdad - `range(0, note_spawn_start)` y `range(note_spawn_end, data.size())`
caminan todo lo que hay a los dos lados de la ventana, por carril y por frame.
Pero están dentro del cronómetro `churn=`, y en Monochrome **`churn` son 9
ms/s**. Son comprobaciones de null y salen baratas. No es ahí.

**3. `get_controller()` llamado cuatro veces por `_process`.** Devuelve un
campo. No es nada.

Con lo cual el reparto de `lanes=52 ms/s` queda: `bounds` 8.6 + `pump` 8.5 +
`churn` 9.0 = 26, y los otros ~26 repartidos por un `_process` que es
aritmética barata. **0.13 ms por carril y frame**, ocho carriles, sesenta veces
por segundo. No hay un dueño; es coste de GDScript esparcido. Atacarlo sería
reescribir el bucle de carril, no cambiar una línea.

### Dos leads que se caen al mirarlos, y por qué

Los dos parecen hallazgos en una lectura rápida del log. No lo son, y quedan
escritos para que la próxima lectura rápida no los redescubra:

- **`self=5.34ms` no es coste por frame.** Sale dentro del grupo de
  `script_max`, que es el peor frame de *cada segundo* - y ese es justo el
  frame en que el log escribe su línea. Es ~5ms una vez por segundo, no 5ms
  cada frame. `settings.gd:277` dice que el log "is quiet", y con esa lectura
  lo es.
- **La barra de carga no marca 50% clavado.** Eso es el log, que informa de
  `progress[0]` crudo de `load_threaded_get_status`. El jugador ve
  `_blended_progress()` (`68e33a6`), que toma el máximo con la ratio de
  dependencias en caché. Lo que sí es cierto es que **la barra se congela unos
  diez segundos igual**, porque en ese tramo no se completa ninguna
  dependencia de primer nivel - ver abajo.

### Los diez segundos ciegos de cada carga

El tramo más largo sin información de todo el log, y está en las dos escenas
grandes:

| | congelado | qué llega al salir |
|---|---|---|
| Chimera | `deps=188/351` durante **11s** | `chimera_house.tscn`, `mdl_chimera_camera.gltf` |
| Tienda (2ª visita) | `deps=329/522` durante **9s** | `mdl_shop_base.gltf`, `prp_tv.gltf`, `prp_sign.gltf` |

Un glTF grande bloquea el hilo de carga y **ni la fracción del motor ni el
recuento de dependencias se mueven** mientras dura, así que ninguna de las dos
mitades de `_blended_progress()` puede informar. De los ~13s de carga de
Chimera, once son ese bloque.

`DEPCOST` no lo ve: solo cobra cuando algo llega, así que carga los once
segundos a lo siguiente que aparece.

**Y en `10154-8d1ee1ac` ese bloque por fin tiene firma.** Durante los once
segundos de Chimera (97.86s -> 108.82s):

| | |
|---|---|
| `ram` | **plana**, 129-131 MB |
| `vram` | **plana**, 138 MB |
| `deps` | **plana**, 188/351 |
| `pipe` | **293 -> 367**, o sea **74 pipelines `mesh`**, a 4-6 por segundo |
| `SPIKE` | uno cada ~0.8s, de 40 a 70ms |

La tienda hace lo mismo: `ram` plana en 137MB, `vram` plana en 85MB, y `pipe`
de 590 a 634 en ocho segundos.

RAM y VRAM planas durante once segundos **descartan a la vez cargar y subir**.
El único contador que se mueve es el de pipelines de malla, que el motor
compila al crear cada superficie. Eso no dice que sea *toda* la causa - lo que
llega al final del bloque es `chimera_house.tscn` y su `.gltf`, y deserializar
eso también cuesta - pero sí que las dos explicaciones que este fichero tenía
escritas (I/O y subida de texturas) están medidas y son falsas.

Y se paga otra vez en cada visita: la tienda compila ~53 `mesh` en su primera
carga y ~130 en la segunda, con la escena idéntica. Los 291 `mesh` de la
sesión entera son todos de pantallas de carga.

**Y sí sobrevive a cerrar la app.** Dos logs del mismo Redmi (Mali-G52), misma
build, dos arranques distintos, misma escena:

| | arranque 1 | arranque 2 |
|---|---|---|
| carga de la tienda | **52014ms** | **5998ms** |
| precache de la tienda | **30089ms** | **1270ms** |
| **total antes de jugar** | **82 segundos** | **7 segundos** |

`bench` durante los dos tramos es comparable (mediana ~640us contra ~605us), o
sea que no es el gobernador. **12x, y es la caché de pipelines del driver.**

**Lo que corrige, y es importante:** los pipelines compilados son **los mismos**
en los dos arranques - 2 can, 53 mesh, 120 surf, y 58 contra 68 spec, 233
contra 243 en total. O sea que `RENDERING_INFO_PIPELINE_COMPILATIONS_*` cuenta
**creaciones, no fallos de caché**. El recuento no es un proxy del coste, y
toda lectura que lo use como tal -incluidas varias de este fichero- hay que
leerla con eso delante. Lo que reducir variantes distintas sí ahorra es el
**primer** arranque, donde cada una se compila de verdad.

Así que todo el dolor de carga y precache de este proyecto es **coste de
primera ejecución**. Un jugador nuevo espera 82 segundos antes de entrar a la
tienda; el mismo jugador, la segunda vez que abre el juego, espera 7.

#### El desglose completo de un arranque en frío

De `b53011f7`, un ZTE 8550 (Mali-G57) con **la misma ventana que el moto g53**,
1600x720, en su primerísima ejecución. Es la medida de arranque en frío más
limpia que tiene el proyecto:

| | |
|---|---|
| carga de la tienda | **41 639ms** (`STALL 50.0% for 39.2s`) |
| instanciar | 1 395ms |
| `SCENE_UP ready+drawn` | **8 670ms**, y **90 pipelines `surf`** en ese paso |
| precache | **23 867ms** |
| **total hasta poder jugar** | **~66 segundos** |

Dos cosas que ese desglose nombra y que no se veían antes:

- **`ready+drawn after=8670ms`** es *antes* de que el revelado empiece. Es el
  motor creando las mallas de la escena, y compila 90 `surf` de una. En el
  moto ese mismo paso son 927ms. No lo toca ningún código de este repo.
- **La primera tanda ciega del revelado cuesta ~10.7 segundos.** `SUMMARY`
  registra `worst=10686.2ms`, y el hueco entre `primer _process` (168.90s) y
  el censo siguiente (181.45s) son 12.5 segundos en los que compilan 53
  pipelines - 30 `surf` y 23 `spec`. Eso es exactamente un frame de revelado,
  y con el código de entonces revelaba **cinco** nodos nunca dibujados a la
  vez. Es el frame que `FIRST_BATCH = 1` acota, y este log es la evidencia más
  fuerte que hay de que hacía falta.

Y durante los 39 segundos de `STALL`: quince picos de 428-828ms, `deps`
congelado en 101/522 durante ocho segundos y luego en 283/522 durante diez,
compilando entre 0 y 8 pipelines `mesh` cada uno. Uno de 578.0ms compila
**cero**, con RAM, VRAM y `res` planos. Los pipelines explican parte del tramo,
no todo.

Térmico en cuatro minutos: `vs_first=+74%`.

### Las texturas Lossless que quedan, contadas bien

`compress/mode=0` no se comprime en la GPU - es RGBA8, cuatro bytes por píxel -
y esta sección del fichero ya movió cinco hojas de la consola por eso. Quedan
más, pero **la cifra hay que sacarla contando solo lo referenciado**, o sale
mal por un factor de cuatro:

| | texturas | VRAM | PNG en disco |
|---|---|---|---|
| referenciadas | 51 | **26.1 MB** | 1.38 MB |
| sin referencia | 14 | 68.2 MB | 2.12 MB |

Casi todo el segundo grupo es **un solo fichero**:
`assets/funkin/chimera/textures/serena/intro/serena_cinematics-2.png`, 4096x4096
en `mode=0`, 64 MB. Parece la peor textura del proyecto y **no la carga nadie**:
es la copia con raíz de ruta de PC, y el `.tres` del sprite usa la de
`lullaby_mod/`, que mide 3352x4005 -recortada por `8b0e901`- y ya va por
`lullaby.astc_sprite`. Dos ficheros con el mismo nombre y distinto importador.
Por la regla de este fichero no se borra; solo hay que no contarla.

De las 51 reales, dos son el 77%:

    loading.png        2048x2048   16.0 MB   (0.41 MB de PNG)
    nte_default.png    1024x1024    4.0 MB   (0.40 MB de PNG)

Y `tex_static_noise.png` se queda en Lossless a propósito -
`shd_shop_static_spatial` la muestrea como datos y un ruido con pérdida son
artefactos.

**`loading.png` ya está movida, y a 4x4, no a 8x8 ni a Basis.** Es el único
sitio de este fichero donde se deja de seguir la convención de las cinco hojas
de consola (`mode=4`), y el motivo está medido:

| | VRAM | disco | PSNR | peor alfa |
|---|---|---|---|---|
| Lossless (antes) | 16.00 MB | 0.41 MB | - | 0 |
| ASTC 8x8 | 1.00 MB | 1.00 MB | 43.2 dB | **121/255** |
| Basis -> ETC2 en device | 4.00 MB | ~0.3 MB | 44.1 dB | 27/255 |
| **ASTC 4x4** | **4.00 MB** | 4.00 MB | **68.3 dB** | **5/255** |

La imagen es una **silueta blanca plana sobre transparencia** - Hypno y los
niños recortados, sin un solo detalle de color. El borde es lo único que hay,
así que un error de alfa es el error. `tools/render_astc_ab.gd` lo enseña sin
discusión a 8x8: el diagonal limpio del original sale escalonado y la
diferencia roja traza el contorno entero. Basis va por ETC1S, que guarda el
alfa en un plano aparte y es justo lo arriesgado en un recorte binario; los
27/255 de la tabla son además un *proxy* del destino de transcodificación, no
la pérdida real de ETC1S, así que el número verdadero puede ser peor.

4x4 cuesta 3.6 MB más de APK que Basis y ahorra los mismos 12 MB de VRAM, con
la calidad **medida** en vez de supuesta. Si algún día el APK aprieta, cambiar
a `mode=4` es una línea.

**`nte_default.png` fue detrás, también a 4x4, y con más margen de duda.** Es
el sprite más dibujado del proyecto -lo usan once ficheros, entre ellos
`Note.tscn` y `Lane.tscn`- y mide peor que `loading.png`:

    ASTC 8x8   34.3 dB   peor 255/255   alfa 223/255   <- descartado
    ASTC 4x4   50.4 dB   peor  73/255   alfa  71/255   <- puesto

El motivo de que mida peor está en el atlas: las 32 regiones de
`nte_default.tres` -y las 52 de `nte_default_hypno.tres`, que es la piel que
suena de verdad- **no están alineadas a bloque** (x=669, 573, 585, 1...
ninguna múltiplo de 4 ni de 8), así que cada flecha monta a caballo entre
bloques. El `73/255` cae en el borde entre rojo y verde saturados de las
flechas de placeholder, que es el peor caso posible para cualquier compresor.

Lo que lo decide no es el número absoluto sino **contra qué se compara**: este
proyecto ya envía 337 texturas a 8x8 con PSNR de 18.9 a 45.9 dB - `grass.png`
18.9, `rock.png` 26.9, `spritemap1.png` 36.0. 50.4 dB a 4x4 está por encima de
todo lo que ya lleva puesto. Y mirándola con `render_astc_ab.gd`, a tamaño de
hoja son indistinguibles y la diferencia a x4 es negra con motas sueltas.

**Ahorro conjunto de las dos: 20 MB -> 5 MB de VRAM.** Y las dos necesitan
precompilado o CI paga EXHAUSTIVE en cada build - ver abajo.

### Y con esas dos, la palanca de compresión está agotada

El mapa completo, contando solo lo que algo referencia:

| importador | texturas | VRAM |
|---|---|---|
| **ASTC 8x8** | **340** | **420.7 MB** |
| Basis | 6 | 16.5 MB |
| Lossless | 49 | 6.1 MB |
| ASTC 4x4 | 2 | 5.0 MB |
| | **397** | **448.3 MB** |

(Eso es el proyecto entero. Chimera carga 224 MB de ahí y la tienda 165 MB.)

**No queda nada que convertir**, y las tres razones están medidas:

- El 94% ya está en ASTC 8x8, que es 0.25 bytes/píxel - el formato más barato
  que existe en esta GPU. No hay a dónde bajar.
- Las 49 Lossless que quedan suman **6.1 MB entre todas**; las dos que valían
  la pena eran el 77% de los 26.1 MB originales y ya están hechas.
- Las 6 en Basis (16.5 MB) son contenido de demostración de Rubicon -
  Boyfriend, `fnf_stage`, el skin de notas de Funkin - y lo único que las carga
  es `songs/test/test.tscn`, que Lullaby no abre nunca. Convertirlas ahorra
  **0 MB de VRAM en juego** y *aumenta* el APK, porque son 2.6 MB de PNG contra
  4.1 MB de ASTC.

Lo único que queda es **resolución**, y es grande pero es la clase peligrosa:

    lado >= 4096     60 texturas   193.1 MB   -> 48.3 MB si se halvan
    2048-4095       110 texturas   199.9 MB   -> 50.0 MB
    1024-2047        95 texturas    28.3 MB
    < 1024           77 texturas     4.3 MB

170 texturas de 2048 para arriba tienen 393 de los 425 MB. Halvarlas dejaría
el conjunto en 106 MB. Pero **129 de ellas están troceadas en regiones**, y
bajar la resolución obliga a reescribir cada región de cada `.tres` en
lockstep - que es exactamente la clase de cambio que ha roto este repo antes.
Cambiar el *modo* de compresión es seguro porque no toca las dimensiones;
cambiar las dimensiones no lo es.

**Trampa al hacer este recuento:** no metas los `.import` en el texto donde
buscas referencias. Cada uno declara su propio `uid=`, así que toda textura se
referencia a sí misma y el barrido da 693 MB en vez de 448 - con las copias de
raíz de PC coladas en el top. Las referencias se buscan en `.tscn`, `.tres`,
`.gd` y `project.godot`, y en nada más.

Dos cosas que hubo que comprobar antes, y que son la checklist de este cambio:

- **Ningún `load_path` apunta al `.ctex`.** El importador saca `.res`, y una
  escena con la ruta del `.ctex` escrita a mano deja de cargar - es lo que
  tumbó Chimera entera una vez. En todo el proyecto no hay ninguno.
- **Las regiones siguen cabiendo.** 8 regiones de 891x444, `max(x+w)=1792` y
  `max(y+h)=1806` contra una textura de 2048x2048. Cambiar el modo no toca las
  dimensiones, así que esto siempre se cumple, pero se comprueba igual.

Y de paso salió que `loading.tres` pide `uid://bidtt2jjjlbva` mientras el
`.import` declara `uid://bok2mx0i4qbh1`. Resuelve por ruta de texto y funciona,
pero **son 11 avisos así en todo el proyecto** (`verify_hardcoded_uids.gd` los
lista) y es exactamente la clase de desajuste que al exportar dejó a Chimera sin
lightmap. No se tocó aquí: es un arreglo sistémico con su propio riesgo, no algo
que mezclar con un cambio de compresión.

### La tienda gasta un cuarto de su GPU en SubViewports

```
sub=5/7  sub_px=1.11M  sub_gpu=3.50ms   de un gpu=13.83ms
sub_top= IconSubViewport(720x540), console_bg/SubViewport(720x540), Notepad/Page
```

1.11 megapíxeles contra los 0.29 Mpx que dibuja el juego a `scale=0.50`. Los
dos de la consola ya bajaron de 1440x1080 a 720x540 y siguen siendo el 25% del
frame. La puerta de `console_bg` existe y estaba abierta en 4 de 8 muestras.

## Measured facts about performance (moto g53)

- **Chimera's 30fps ceiling is the GPU, and the old note here saying "the GPU
  is idle, graphics presets cannot help" was wrong.** That claim came from
  reading `proc` alone, before the log measured GPU time at all, and it sent
  the whole investigation at GDScript and node counts for months. The numbers,
  from `91066500-lullaby_20260806_152409.log`, 43 Chimera heartbeats:

  | | frame | gpu | cpu_render | phys | draw | prims |
  |---|---|---|---|---|---|---|
  | Chimera | 38.1ms | **38.8ms** | 2.13 | 0.61 | 39 | 21189 |
  | Collector's Shop | 33.3ms* | 17.3ms | 1.02 | - | 72 | 17056 |

  \* the shop is *capped*, not slow - 33.3ms exactly, target_fps was 30.

  `gpu` and `frame` are the same number in Chimera. The CPU spends 2ms
  building the frame and then waits. Whatever the fix is, it is on the GPU
  side.

- **El 2D cubre 12x los píxeles del 3D, y `rend=` por sí solo no lo dice.**
  A `scale=0.50` sobre 1600x720 el pase 3D dibuja 800x360 = **0.29 Mpx**. El
  canvas 2D **no** escala: 1600x720 = 1.15 Mpx por capa a pantalla completa, y
  el censo de Chimera da `over=3.0x` en régimen (`top=UILayer/Black2@1.0x`), o
  sea **3.46 Mpx**.

  `rend=` lo hace parecer lo contrario y hay que leerlo con cuidado: el canvas
  son **10 draw calls y 306 primitivas** contra 21 y 16106 del 3D, y
  correlaciona con `gpu` a +0.12 frente a +0.44. Pero eso mide *cuenta*, no
  *relleno* - diez draw calls de rectángulos a pantalla completa siguen siendo
  diez mezclas de pantalla completa. Las dos mitades no se pueden separar
  contando.

  El dato que enmarca las dos: `gpu` p50 = 31.85ms para 0.29 Mpx de 3D son
  **9.0 Mpíxeles/s**, un número imposible para un Adreno 619 si el techo fuera
  el relleno del 3D. Sumando el 2D son 3.75 Mpx y 118 Mpíxeles/s, que ya es
  plausible. **Mover la escala de render y ver si `gpu` la sigue es lo único
  que separa las dos**, y sigue sin hacerse.

- **It is not draw calls and not geometry.** In the same session at the same
  render scale, the shop draws *more* (72 calls vs 39) with comparable
  primitives and costs less than half the GPU time. Chimera does less work by
  every count-based measure and takes 2.2x as long, so the cost is per-pixel,
  not per-object.

- **It is not 3D resolution either, or not only.** `scale=0.50` throughout that
  run - the 3D was already rendering at 800x360 - and it still cost ~39ms.

- **This GPU is expensive on fullscreen blending.** `intro.tscn` is a 2D menu
  with **13 draw calls and zero lights** and it costs **20.6ms** of GPU. 2D is
  not affected by `scaling_3d_scale`, so that is pure fill on overlapping
  full-screen layers - a third of a 60fps budget for a menu.

- **Nothing accumulates across the song, except geometry, and geometry is not
  the cost.** Chasing "do earlier cutscene stages stay on screen": `objs` and
  `draw` rise and fall all song and are back to 45 objects / 16 draw calls near
  the end, so drawn objects do not pile up. `prims` **does** - its floor goes
  from ~10.2k to ~34.5k and never returns, so something is revealed and not
  hidden again. It costs almost nothing: first 60s is 10414 prims at 38.9ms,
  last 30s is 34511 prims at 42.5ms. 3.3x the geometry for +9% GPU.

  All three counters are uncorrelated with GPU time: `objs` +0.16, `draw`
  +0.24, `prims` +0.26. And there are counter-examples in both directions -
  16671 prims at 19.5ms against 10312 prims at 38.9ms.

- **The cost tracks which sequence is on screen, at a constant shadow count.**
  This is the sharpest thing in the log and it *weakens the shadow theory
  above*, so read it before acting on that one:

  | | sequence | prims | shadows | gpu |
  |---|---|---|---|---|
  | costly | `101_prelude` | 10312 | 4 | 38.9ms |
  | costly | `107_turnaround` | 29233 | 4 | 46.5ms |
  | **cheap** | `scene@133` | 16671 | 4 | **19.5ms** |
  | **cheap** | `123_crawling` | 26390 | 4 | **24.0ms** |
  | costly | `125_outro` | 34511 | 4 | 43.0ms |

  Same four shadow casters throughout, 10-11 visible lights throughout, and the
  GPU swings 2.2x. **Chimera already runs at ~50fps for a ~40-second stretch.**
  Whatever the ceiling is, it is not a fixed per-frame cost - it is per-pixel
  work that depends on what fills the frame, which points at overdraw and at
  the mobile renderer evaluating 10-11 lights per fragment on wide shots of the
  house.

- **"Lowering the render scale did not help" was never actually measured.**
  Chimera has only ever been logged at `scale=0.50`; there is no sample of it
  at 1.0, so the slope is unknown. Running it at 0.35 and at 0.75 and seeing
  whether `gpu` tracks the pixel count is the cheapest way to confirm or kill
  the fill-rate reading, and it is a better first test than the shadows A/B.

- **What is still open, and the test that closes it.** The one structural
  difference the census shows between the two scenes is shadow casters:
  Chimera `lights=13(shadow=5)`, the shop `lights=14(shadow=0)` - more lights,
  no shadows, half the cost. That is the best current suspect, together with
  Chimera's rain/godrays layers. It is **not proven**, because
  `lights=N(shadow=M)` counts nodes with `shadow_enabled` regardless of whether
  the engine renders them (`graphics_shadows_enabled` off sets the atlas to 0),
  and that log predates `82a135b` and so does not record which graphics options
  were in force - the player was on a Custom setup, having nudged render scale
  to 0.55 and back.

  Since `82a135b` every CENSUS carries the full graphics summary and any change
  emits a `SETTINGS` line, so the attribution problem is fixed. The test is two
  Chimera runs toggling one row at a time in the console's Graphics tab -
  `Shadows` (`graphics_shadows_enabled`), then `Reduce Visual Effects`
  (`graphics_disable_shader_effects`) - and reading `gpu=` for each. Do not
  change the preset, which moves several options at once and is what made the
  earlier "Very Low changed nothing" conclusion uninterpretable.
- **VRAM: 165MB in the Collector's Shop and 224MB in Chimera** - measured on
  `10152-665dedd4`, the first log taken after the ASTC conversion and after the
  lightmap was restored. The old numbers here were 625MB and ~410MB, and they
  are what the "VRAM is the one fix that pays four times" argument was built
  on. It paid: this is a **3.8x** cut in the shop and **1.8x** in Chimera, and
  it is the ASTC 8x8 move doing exactly what its own arithmetic predicted
  (510MB -> 128MB of texture VRAM). Loads-getting-slower has not been re-tested
  under the new figure.
- **Loads are not slow because of VRAM, and this bullet used to say they
  were.** The old text - "50%->75% is where almost all the time goes, and VRAM
  climbs from ~100MB to ~540MB across it, it is texture loading" - was written
  before the ASTC conversion and is now false twice over. In
  `10152-665dedd4` the same shop scene loads twice in one session:

  | | `took` | `bench` | ram | vram |
  |---|---|---|---|---|
  | tienda 1a visita | **4763ms** | 235us | 115MB | 96MB |
  | tienda 2a visita | **17420ms** | 184->**960us** | 142MB | **91MB** |

  **VRAM is *lower* on the slow load.** What moved is `bench=`, the log's
  fixed-arithmetic control: the same arithmetic takes 4x longer. The load did
  not get heavier, the phone got slower - see the governor section below.
- Thermal: `vs_first` reached +23%.
- **Each note is a 20-node scene with 6 AnimationPlayers and a state machine
  of 24 transitions** (`addons/rubicon_mania/resources/skins/default/Note.tscn`).
  40 notes on screen means ~240 AnimationPlayers processed per frame. This is
  the likeliest source of the constant ~50ms floor.
- `spawn_note()` instantiates when the pool is empty, on the main thread,
  mid-song. The pool starts empty. `prewarm_pool()` (`0b421d2`) fills it
  during `update_notes()`.

---

## Mistakes made here, so they are not repeated

**Two hypotheses were confidently wrong**, both stated before measuring:

1. "The 3305 restored bone tracks are the cause" - the census showed only
   55-176 tracks playing.
2. "The stalls are shader compilation" - a prewarm was implemented, cost
   34 seconds of load time, removed zero spikes, and **broke the shop**: it
   revealed hidden nodes, which gave focus to the Codes tab's `LineEdit`,
   opened the Android keyboard twice and left the console on a screen the
   player never opened. Reverted in `cf5a391`.

The lesson that actually stuck: **do not change gameplay-adjacent code on a
hypothesis.** Add the measurement that would confirm or kill it, ship that,
and read the log.

**`call_deferred()` after a scene change is a trap.** `get_tree().current_scene`
is not set on the frame `change_scene_to_packed()` runs; `call_deferred` fires
at the end of *that* frame, so the callback sees the outgoing scene or null.
This silently broke two separate systems - the note layout applier (VSlice
appeared to do nothing at all) and the log's spike attribution (no `after ...`
ever appeared). `await get_tree().process_frame` twice instead.

**A commit message saying "verification deferred to CI" is a warning sign.**
One such commit shipped a `.tscn` that could not load, and it took hours to
trace. CI importing and exporting successfully does **not** mean a scene
loads - nothing loads gameplay scenes during export.

---

## What the note-pool prewarm actually did (measured)

Confirmed working on device. `orphans` starts at **2416** on the first Chimera
census instead of climbing from 1 to 589 over minutes - the pool is full
before the song starts, so `spawn_note()` never instantiates mid-song.

The win shows up in the *lows*, not the average:

| | before | after |
|---|---|---|
| typical `fps_low` | 7-20 | 20-30 |
| spikes per Chimera run | ~15 | ~9 |

Costs about 12MB of RAM (148 -> 160MB in Chimera) for the pooled nodes.
Worth it.

The spike attribution works now too, and immediately said something new:
several spikes follow **note-hit and character sing animations**
(`sturmR_NoteHit_Init`, `chr_serena_sing_library/...`), not sequences. With 6
AnimationPlayers per note that points back at the note scene's weight.

Still unfixed after this: the multi-second stalls at cutscene starts
(`proc=1882ms` and `373ms`, both on `122_fall`) and the ~30fps ceiling.

The third item that used to be on this list - "loads that keep growing within
a session (shop: 13.6s first, 25.6s second) **under VRAM pressure**" - was
half right. The growth is real and reproducible (4763ms then 17420ms for the
identical shop scene). The attribution was not: VRAM is *lower* on the slow
load, and `bench=` is 4x worse. It is the governor, not memory.

## The cutscene stalls (`122_fall`, `proc` 373-1882ms) - what is known

Read the animation directly out of the scene text rather than by loading it:
`SequencePlayer`'s library is `SubResource("AnimationLibrary_mao22")` at
`sng_chimera.tscn:10928`, whose `_data` maps each sequence name to an
`Animation` sub-resource (`122_fall` -> `Animation_pyq2i`, line 8265).

`122_fall` is only 31 tracks, and three of them matter:

```
tracks/2  ../hex:visible                                   <- reveals a 3D character
tracks/0,1 ../Camera3D:rotation, :fov
tracks/5  animation track -> SerenaFalling/Falling/AnimationPlayer
```

So the stall lands on the frame a 3D character is revealed and the camera
swings. `hex.tscn` itself is only 4 nodes - it instances the real model from
another scene - so the weight is in the glTF-derived model behind it.

**This also explains why the shader prewarm could not have worked**, which was
never understood at the time it was reverted: it set `visible = true` for two
frames, but a revealed node **outside the camera frustum is culled and never
drawn**, and a material that is never drawn never compiles. Revealing
everything at once cost 34 seconds and compiled almost nothing, because
almost none of it was on screen. Any future prewarm has to get the things in
front of a camera, not merely make them visible - which is a much bigger and
more invasive change than it first appears.

### What it is not (three candidates eliminated)

The "31 tracks, three of them matter" reading above undersold it. Listing
every track shows `122_fall` is a **mass first-draw event**: on one frame it
reveals six things that have never been rendered, and turns a light on.

```
../hex:visible                              4 unique materials, skinned, 12 blend shapes
../SerenaFalling:visible                    + its own AnimationPlayer (track 5)
SerenaBrokenArm/SerenaBrokenArm:visible
../Environment/chimera_house/floorfucked:visible     (swaps out floornormal)
../Environment/chimera_house/window_001/_004:visible
../Environment/chimera_house/mdl_chimera_camera:visible
../Camera3D/OmniLight3D:visible + :light_energy      <- a light switches ON
../Environment/Lights/TvLight:light_energy
../Camera3D:rotation, :fov                  camera swings to face all of it
```

A light appearing changes the lighting permutation every lit material has to
be compiled for, so it is not merely six new meshes - it can invalidate
pipeline variants for things already on screen.

Three of the candidates that were open are now closed:

- **Not texture upload.** The stall frames log `vram_delta=+0.0MB`, and VRAM
  sits flat at 318MB across the whole song. Nothing is being uploaded.
- **Not resource loading.** `ram` is flat at ~160MB over the same window, and
  no `LOAD` entry is anywhere near it.
- **Not the AnimationMixer track cache.** This was the best guess: Hex carries
  **2122 bone tracks across 18 animations** on a 113-bone skeleton, and
  `_update_caches()` walks every animation in the player, not just the one
  being played. Measured in a synthetic project on the real 4.7.1 binary
  (113 bones, 118 tracks/anim, timing the first `play()`): the cost does scale
  with the total - 0.13ms at 2 animations, 1.00ms at 18 (2124 tracks), 1.68ms
  at 36 - but the magnitude is off by three orders of magnitude. Even a phone
  20x slower than the build machine pays ~20ms, not 1900ms.

That leaves first-draw pipeline compilation, which now also has a size that
fits: Hex alone is four distinct skinned + morph-target pipelines, and mobile
Vulkan can spend several hundred ms on one of those.

It also explains an ordering detail that otherwise looks backwards:
`114_hexapproach` reveals Hex earlier and only costs ~140ms, while `122_fall`
costs 1900ms. The expensive frame is not the first time Hex exists, it is the
frame where six unseen models **and** a new light all land in the camera at
once.

Worth trying, and deliberately narrower than the prewarm that broke the shop:
put only this cast in front of a small off-screen SubViewport camera for a
frame during the loading screen. It touches no song-scene visibility state,
which is what made the previous attempt reveal the console's Codes tab.

### El gráfico negro de Chimera: cinco pistas del precache

Cerrado por bisección en el dispositivo, tras once días y diez builds. La
causa son las cinco pistas `:visible` que `95b9656` añadió a `precache` para
cubrir el stall de `122_fall`. Quitarlas devuelve la casa.

    1bfa45f  (18 pistas)   BUENO      f3922ec  6-ago   BUENO
    ee9f3fc  (23 pistas)   NEGRO      e304353  8-ago   BUENO
    ee9f3fc sin las 5      BUENO      76e2c5c  9-ago   NEGRO

**La premisa del commit era falsa.** Decía que `122_fall` revela seis cosas
"the precache camera never framed". Tres de las cinco -`window_001`,
`window_004` y `mdl_chimera_camera`- son `MeshInstance3D` que **shipean
visibles**, o sea exactamente lo que `_hide_everything()` esconde y
`_reveal()` enseña delante de la cámara. Ya estaban calentándose. Solo
`floorfucked` (shipea oculto) y `SerenaFalling` (Node2D) quedaban fuera.

**Y por eso rompen: las cinco tocan la casa, y la casa es lo único del
proyecto con un `LightmapGI`.** Cruzar los objetivos de cada pista contra los
nombres que registra `chimera_base.lmbake` -que es binario, así que hay que
leerlo con `re.findall(rb'[ -~]{3,}', ...)`, no con grep sobre texto- separa
los dos grupos sin una sola excepción:

| pista | nodo | ¿registrado en el bake? |
|---|---|---|
| las 18 originales | `hex`, `NTSC`, `Rain`, `flash`, las 8 Serena, `OmniLight3D`, `TvLight` | **ninguno** |
| las 5 de `95b9656` | `window_001`, `window_004`, `floorfucked` | **sí** |
| | `mdl_chimera_camera`, `SerenaFalling` | no |

Escribir `visible` desde el `precache` sobre una malla que el `LightmapGI`
tiene registrada la desengancha del bake, y como Chimera es la única canción
con luces en `light_bake_mode = 1` (`BAKE_STATIC`), lo que queda es ambiente
más las dinámicas: la casa sin luz. Por eso el síntoma era **falta de luz** y
no un rectángulo encima, por eso `sonda=` mostraba la geometría presente pero
negra, y por eso solo pasaba en Chimera.

La bisección lo confirma con la granularidad justa: el grupo "ventanas" tiene
dos usuarios del bake y el grupo "resto" tiene uno solo (`floorfucked`), **y
los dos salieron negros**. Un solo usuario basta.

**Regla nueva: antes de añadir una pista `:visible` al `precache`, cruza el
nodo contra los nombres del `.lmbake`. Si está registrado, no la añadas.**
El `PreloadCamera` ya calienta esa malla por su cuenta -`_hide_everything()`
la esconde y `_reveal()` la enseña delante de la cámara- así que la pista no
aporta nada y sí introduce la carrera.

**La regla vieja no protegía de esto, y la que se escribió al cerrar el bug
tampoco.** Este fichero decía "check the path is in RESET before adding it",
y las cinco están - pero el RESET no apaga: *restaura*, y para `window_001`,
`window_004` y `floorfucked` restaura `true`, así que comprobar la lista
confirmaba el nodo encendido en vez de descartarlo. El primer intento de
regla nueva fue "el nodo no puede ser un `VisualInstance3D` visible", y es
**falsa**: las pistas 12 y 15 de las 18 originales apuntan a
`SerenaWalkingOut` y `SerenaBrokenArm`, que son `AnimatedSprite3D` -o sea
`SpriteBase3D` -> `GeometryInstance3D` -> `VisualInstance3D`- y llevan ahí
desde siempre sin romper nada. El tipo de nodo no es el criterio; el bake sí.

Dos trampas que costaron builds en el camino:

- **`tracks/N/enabled = false` no equivale a quitar la pista.** Dos cortes
  hechos así salieron negros los dos, contradiciendo al que revertía el
  fichero entero. Para bisecar dentro de una animación, quita bloques y
  renumera, o parte del fichero bueno y añade.
- **`BLACKOUT ... (3D) cubre=1.00 negro=si` señaló a `window_004` y era
  falso.** El vigilante proyecta el AABB, no los píxeles, y esa malla mide
  28x4.4x13.4 en el mundo: con la cámara dentro cubre siempre la pantalla.
  `walls` sale igual. Es la misma trampa ya documentada para las luces.

Aquí había escrito un "hallazgo colateral" que decía que **ninguno** de los 145
pares de `precompiled_astc_imports` tenía un `dest_md5` que casara con su
`.res`, y que por tanto ese directorio no aceleraba nada. **Es falso, y se
comprobó contando:**

    dest_md5 del sidecar vs md5 real del .res     145 coinciden, 0 no
    source_md5 del sidecar vs md5 real del PNG    143 coinciden, 0 no
                                                    2 huerfanos (.res que
                                                    ningun .import pide)

El mecanismo funciona. Borrar ese directorio por creerse esa nota costaría una
hora de EXHAUSTIVE en cada build. La comprobación es de cuatro líneas de
Python -`hashlib.md5(open(res,'rb').read())` contra el `dest_md5` del sidecar-
y hay que hacerla antes de repetir la afirmación.

**That prewarm exists now** - `PreloadCamera` (`lullaby_preload_camera.gd`),
a `Camera3D` that makes itself current during the loading screen and plays a
`precache` animation which reveals things and sweeps 15 positions at
`fov = 120` before handing over to the real camera. It costs ~2.2s and
compiles ~90 pipelines on Chimera.

### El barrido corría en tiempo de animación y el revelado en frames

Dos relojes distintos para un solo trabajo, y por eso el prewarm calienta menos
de lo que parece. La cabecera del propio fichero lo diagnosticó desde el primer
día -*"only what the camera saw from its starting pose was ever warmed, which
is why pipelines keep compiling later, during play"*- pero `67c9fad` arregló
solo una de las dos mitades: pasó el **revelado** a ir por frames, con
retroceso multiplicativo, y dejó el **barrido** en la animación.

Un `AnimationPlayer` avanza por delta. Con frames de cientos de milisegundos
-que es exactamente lo que hay mientras se compilan pipelines- una animación de
0.8s se acaba en cuatro o cinco frames, mientras que el revelado que debía
acompañar dura 6737ms en Chimera. Todo lo revelado a partir del quinto frame se
dibujó desde donde la última clave dejó la cámara.

El log de `10152-665dedd4` lo mide sin ambigüedad:

    precache de Chimera   87.9s -> 95.7s   pipe 431 -> 526   (~95, 6737ms)
    toda la canción                        pipe 527 -> 600   (73 más)

y los 73 que se escapan caen justo en las cuatro secuencias cuya cámara va
donde el barrido no llega: `104_photographysesh` (21 pipelines en tres frames),
`121_closetrunout` (5), `114_hexapproach` (4) y `122_fall`, cuyo peor frame es
**1911.7ms para `spec+8`** con RAM y VRAM planas.

Arreglado sacando las poses de la propia animación (`find_track(^".:position")`)
y volviéndolas a servir desde `_process`, una por frame de revelado, ciclando.
No toca la visibilidad de ningún nodo, así que **no puede chocar con el
`LightmapGI`** - que es lo que hundió el intento anterior.

Dos cosas que hay que respetar si alguien lo vuelve a tocar:

- **Servir poses solo con la animación terminada.** Mientras suena, la
  animación es dueña de `position` y `rotation` y está autorada para serlo; dos
  escritores en un `transform` es un temblor, no un barrido.
- **Ciclar, no agotarse.** Siempre hay más frames de revelado que poses -
  Chimera autora 15 y gasta 30-40 frames en 88 nodos-, así que quedarse en la
  última al terminar el array reintroduce el bug por la puerta de atrás.

`_mark` al ceder el testigo trae ahora `revelado_al_fin_anim=N/M`, que es **el
número que dice si esto hacía falta**: si la animación termina con el revelado
ya hecho, el barrido nunca fue el problema y todo este mecanismo sobra.

### El precache escondía las luces, y compilaba el doble de pipelines

Medido, no razonado, y en la ruta exacta del teléfono (Vulkan, Forward Mobile)
con tres mallas de tres shaders distintos:

| estado | `spec` |
|---|---|
| geometría, cero luces | 3 |
| + una omni | 6 (+3, las mismas otra vez) |
| + una spot | 9 (+3) |
| quitando la omni | 12 (+3) |

**Cada configuración de luces por la que pasa la escena cuesta un juego entero
de pipelines de especialización.** Satura por número - una tercera y una cuarta
omni no añaden nada - pero no por *estado*. Y el control dice que el arreglo es
gratis: encender las luces sin nada visible compila **0**, y revelar los mismos
seis shaders sobre una escena ya iluminada compila **6 en vez de 12**.

La causa era que `_hide_everything()` escondía todo `VisualInstance3D`, y contra
`ClassDB` eso incluye `Light3D` y **`LightmapGI`** - ninguno lleva material ni
compila pipeline propio. El comentario del propio script decía que cubría "the
things that carry a material and therefore need a pipeline"; no era lo que
hacía. Como el revelado recorre luces y geometría juntas en orden de DFS, la
escena iba de cero luces, a algunas, a todas, pagando cada tramo.

Los dos que **no** se eximieron, y por qué - esto es la parte reutilizable:

| | por qué se sigue escondiendo |
|---|---|
| `VisibleOnScreenNotifier3D` (6, la tienda) | esconderlo es lo que evita que dispare `screen_entered` mientras una cámara de 109° barre la sala. Es un efecto sobre la lógica del juego, no una cuestión de pipelines |
| `ReflectionProbe` (1, la tienda) | hace captura real cuando está visible, y nada ha medido cuál de los dos costes gana |

**La trampa que queda:** `visible` es local y renderizar no lo es. Una luz que
cuelgue de una malla que sí se esconde deja de iluminar por herencia, y eso no
se puede descartar leyendo un `.tscn` para los subárboles que salen de un
`.gltf`. Por eso el `MARK` de arranque trae la pareja
`N luces/bakes exentos, encendidos A -> B`.

**Y ese contador tuvo que aprender a leerse.** La primera versión solo daba el
número de *después*, y Chimera registró `11 intactos de 16`, que se leyó como
cinco luces perdidas por el escondite. Es falso: cuatro son `flash` y
`PhoneGlow` bajo `Sequences/SerenaTakingPictures`, y `Cameralight` y un
`OmniLight3D` bajo `Environment/chimera_house/mdl_chimera_camera` - y **los dos
padres shipean `visible = false`**. Ya estaban apagadas. Un recuento tomado solo
después de esconder no separa "lo apagó mi escondite" de "venía apagado", así
que la línea que existía para delatar un problema se inventó uno. La base se
toma ahora **antes** de esconder nada, y el hueco entre los dos números sí es
atribuible.

### Lo que el arreglo dio, medido en 10154-8d1ee1ac

Los recuentos de pipelines son contabilidad del propio Godot, así que no
dependen del driver y trasladan al teléfono:

| | 152 | 154 | |
|---|---|---|---|
| PRECACHE tienda #1 | 96 spec | **68** | −29% |
| PRECACHE chimera | 90 spec | **55** | −39% |
| PRECACHE tienda #2 | 93 spec | **66** | −29% |
| total de la sesión | 375 spec | **290** | −23% |

**El tiempo de pared no se puede atribuir**, y es importante no venderlo. La
tienda va de 8954ms a 8608ms (−4%) y Chimera de 6737 a 5092 (−24%), pero esta
sesión corrió a reloj más alto: el precache de la tienda se midió a
`bench=151us`, el más rápido de toda la sesión, contra ~332us la vez anterior.
A igualdad de reloj la tienda probablemente no mejoró.

Y los `spec` **durante la canción** de Chimera no bajaron (74 -> 79). O sea que
el arreglo quitó trabajo tirado del precache pero no consiguió calentar más de
lo que la canción usa. Eso sigue abierto.

### El precache más caro no es el de Chimera, es el de la tienda

Todo el trabajo de precache de este fichero ha ido a Chimera. Los `MARK` del
mismo log dicen que la tienda cuesta más y que nadie lo había contado:

| | precache | pipelines de ese tramo |
|---|---|---|
| tienda 1a visita | **8954ms** | 120 surf + 96 spec |
| chimera | 6737ms | 90 spec |
| tienda 2a visita | **1280ms** | 93 spec |

Dentro de esos 8954ms hay **un solo frame de 7787.6ms** - el peor del
proyecto, cuatro veces el `122_fall` de 1911ms que sí lleva meses escrito
aquí. No aparecía en ningún log porque el propio log se callaba; ver la nota
de las cuatro puertas más abajo.

Y el dato que orienta el arreglo: la segunda visita compila **casi los mismos
pipelines de especialización** (96 -> 93) y tarda **7x menos**. O sea que el
coste no es el recuento, es que el driver ya tiene los binarios compilados.
Dentro de una sesión la caché funciona. Si sobrevive a cerrar la app es lo
que contesta la línea `pipe_cache:` de la cabecera, comparando el UUID entre
dos arranques.

El reparto completo de los 864 pipelines de la sesión, que dice dónde se paga:

    menus (boot->intro)         4
    carga tienda #1            53      <- durante la pantalla de carga
    PRECACHE tienda #1        218
    tienda jugando #1          20
    carga chimera             136      <- durante la pantalla de carga
    PRECACHE chimera           90
    chimera cantando           79      <- los que se escapan, en canción
    carga tienda #2           168
    PRECACHE tienda #2         93
    tienda jugando #2           3

Los 291 `mesh` que compilan **durante las pantallas de carga** son el motor
haciéndolo por su cuenta al crear cada malla, y son también los spikes de
43-112ms que se ven entre 70s y 86s. Están en el sitio menos malo posible,
pero la pantalla de carga tartamudea por eso.

**But it did not cover `122_fall`, which is the stall that is still there.**
Diff the sequence's `:visible` tracks against the precache's and five were
missing: `SerenaFalling`, `floorfucked`, `window_001`, `window_004`,
`mdl_chimera_camera` (`floornormal` ships visible and is already warm). Added
in the same commit as the SubViewport work. The general recipe when a
cutscene still stalls:

```bash
# list what a sequence reveals, then diff against Animation_pnfws (precache)
python3 - <<'PY'   # see the tracks dump in this file's git history
PY
```

Restoring afterwards is free: precache's track 0 is an `animation` track that
replays `SequencePlayer`'s `RESET` five times, and `RESET` already carries all
127 of these paths. That is why `hex:visible = true` in the precache does not
leave Hex on screen, and why anything else added there is safe the same way -
**check the path is in RESET before adding it.**

Sweeping precache's paths against every `RESET` in the scene leaves three
uncovered, and all three are fine:

| path | why it does not matter |
|---|---|
| `UILayer/NTSC:visible` | the `PostProcessingTree` owns it, not `RESET` - see below |
| `Sequences/.../SerenaCinematics/flash:visible` | the ancestor is restored hidden |
| `Environment/Lights/TvLight:visible` | it ships visible and `light_energy` is restored to 0 |

The sweep has to normalise paths before comparing or it is useless: `precache`
lives on `PreloadCamera/AnimationPlayer` and `RESET` on
`Sequences/SequencePlayer`, so the same node is `../Sequences/X` in one and `X`
in the other.

**And that is how five tracks were dead on arrival.** The five `:visible`
tracks added to cover `122_fall` were written as `SerenaTakingPictures:visible`
and friends - relative to `PreloadCamera`, whose only child is an
`AnimationPlayer`. All five resolved to nothing and were silently dropped, so
that commit warmed exactly nothing. Corrected to `../Sequences/...`. Four of the
five now duplicate tracks that were already correct; the duplication is harmless
and the diff is smaller than renumbering the track array.

### `UILayer/NTSC` is on all song by design, and it is not a leak

Worth writing down because it looks exactly like one, and a whole commit was
spent on it before it was measured. `UILayer/NTSC` is a full-rect `ColorRect`
on `shd_ntsc_shader` - 65 `hint_screen_texture` taps per fragment, alpha taken
from the same sample - authored `visible = false`, and `precache` turns it on.
No `RESET` in the scene carries it back. Every static reading of that says
"stuck on for the whole song, painting over the stage".

It is not. `Settings/PostProcessingTree` is an `AnimationTree` whose state
machine runs `Start -> off -> high` when `settings_post_processing == 2`, and
`high` holds `NTSC:visible = true` for as long as the state is active. So NTSC
is on from `_ready`, before precache touches anything, on the mod's own design
and identically in the pck. Measured:

```
OUT Settings=true post_processing=2 disable_shader_effects=false
OUT === tras _ready ===
OUT UILayer/NTSC        visible=true  en_arbol=true
```

The other half of the theory was wrong too: **Godot 4 inserts the back-buffer
copy itself** when a CanvasItem's material samples `hint_screen_texture`. The
explicit `BackBufferCopy` under `Rain` is not what feeds it, so "NTSC repaints
one frozen frame forever" has no mechanism.

`graphics_post_processing` is what actually governs this - `NONE`/`LOW` play
`off`/`low`, which `queue_free()` the node outright. So NTSC exists or does not
depending on a quality row, and any future reading of it has to say which.

Two ways the test that should have caught this got it wrong first, both worth
avoiding:

- **Take the baseline off a fresh instance that was never added to the tree.**
  `PreloadCamera` plays `precache` from its own `_ready()`, so by the first
  `process_frame` every key at `t = 0` has already applied. A baseline read
  there records NTSC as already visible and the leak compares equal to itself -
  11 false positives, and the one node being investigated invisible.
- **Drive the animation with `advance()`, never `seek()`.** Track 0 of
  `precache` is an `animation` track dispatching the SequencePlayer's `RESET`
  five times, and a dispatch is assigned when its key is crossed and then
  seeked forward by the parent every frame after. Stepping with `seek()`
  assigns the clip without ever advancing it, so none of the restores apply and
  every revealed node reads as a leak.

And the tooling lesson under both: **`--script` does not give you the
autoloads.** The probe read `Settings` as null, the scene fell into its
gameover path, and the state machine never advanced past `off` - which made
NTSC look freed. Run a scene (`--headless --path . res://tools/harness/...`),
not a `SceneTree` script, for anything that touches `Settings`.

## The quality preset ladder, and the gaps that kept being in it

Three separate times now the presets turned out not to lower the thing they
claimed to. The pattern is always the same: `LullabyQualityPreset`'s field has
a default, a `.tres` does not declare it, and the preset therefore ships the
default. Grep for what each `.tres` actually declares before assuming a preset
does anything.

A fourth variant of the same failure, and it is not a `.tres` problem:
**`positional_shadow_atlas_size` covers omni and spot lights only.** A
`DirectionalLight3D` renders into a completely separate atlas that the
Graphics tab's "Shadows" row never touched, so "off" was not fully off and
the 4096/2048/1024/512 ladder never reached it.
`RenderingServer.directional_shadow_atlas_set_size()` and
`directional_soft_shadow_filter_set_quality()` now follow the same row and
the same numbers.

**Physics is a preset field now (60 / 60 / 30 / 30 Hz).** A sweep for
`_physics_process`/`_integrate_forces` across the whole repo finds exactly
three users and none is timing-critical: Safety Lullaby's `lamp_flicker.gd`
accumulates delta, the shop's `mouse_controller.gd` re-aims the hover
raycast, and Rubicon drives notes off the audio clock in `_process`. The
shop spends 3-6ms of a 24ms frame on 19 Area3Ds and 31 collision pairs with
`p3d_objs=0` - not one active rigid body. `Engine.max_physics_steps_per_frame`
also drops 8 -> 4 everywhere: a 141ms frame was asking for eight catch-up
physics steps inside the frame that was already late, and below two ticks of
frame time the cap never engages at all.

|  | render scale | shadow atlas | shadow filter | aniso | mesh LOD | light fade |
|---|---|---|---|---|---|---|
| High | 1.00 | 4096 | 2 | 4x | 1.0 | off |
| Medium | 0.85 | 2048 | 1 | 2x | 2.0 | off |
| Low | 0.65 | 1024 | 0 | off | 4.0 | x3 |
| Very Low | 0.70 | shadows off | 0 | off | 8.0 | x2 |

**Chimera's real-time lights**, which is what "light fade" acts on. They split
cleanly into local and scene-wide, and the house is about 10 units across:

| light | range | energy | gone at x3 | gone at x2 |
|---|---|---|---|---|
| SerenaBase | 1.51 | 1.07 | 6.1 | 4.5 |
| CrawlDoorLight | 1.75 | 0.265 | 7.0 | 5.2 |
| CameraMechanic | 3.16 | 1.0 | 12.6 | 9.5 |
| OutsideGrassLight | 5.81 | 0.28 | 23.2 | 17.4 |
| Camera3D's own | 6.51 | 2.35 | 26.0 | 19.5 |
| AmbLight | 18.14 | 2.87 | 72.6 | 54.4 |
| MoonSpotlight | 21.46 | 0.37 | 85.8 | 64.4 |
| TvLight | 43.93 | 0.0 | 175.7 | 131.8 |

Only the four small dim ones ever fade; the four that light the whole scene
never reach their distance, and the camera's own light rides the camera so its
distance is always ~0. Most of these live inside instanced sub-scenes, so a
scan of `sng_chimera.tscn` alone finds four lights, not eight.

What was wrong before:

- **Render scale existed only on Very Low.** High, Medium and Low all rendered
  3D at full resolution, on a project that is provably per-pixel bound.
- **Medium's shadow cost was identical to High's** - it declared neither the
  atlas size nor the filter quality, and Low reduced the atlas while leaving
  filter quality at the most expensive setting.
- **`anisotropic_filtering` and `mesh_lod_threshold` were not wired up at
  all.** Godot exposes both on `Viewport`; the project sat on the engine
  defaults (4x anisotropic, a 1-pixel LOD threshold that means LODs never
  engage) on every preset including Very Low. Both are viewport-wide, so they
  are the two levers that help *every* scene rather than one.

`SCALING_3D_MODE_NEAREST = 5` is a real value in 4.7.1 - Low and Very Low
setting `scaling_3d_mode = 5` is correct and is the cheapest upscaler, not the
out-of-range bug it looks like. Verify enum values against the running binary
(`ClassDB.class_get_enum_constants`) rather than from memory.

`is_matching()` compares every tracked field, so a preset that omits one still
matches as long as the omitted default equals what it wants - but declare new
fields in all four files anyway, or the next person reading the table above
will draw the wrong conclusion.

## The 60/40 flip is the CPU governor, and it is a headroom readout

Reported from the device: in Monochrome, stop touching the hitbox and the
frame rate settles at 40; take your turn again and it goes back to 60. The
tester then found the tell - **it does not happen while screen recording.**

Nothing in the game does this. There is no `low_processor_usage_mode`
anywhere, in project.godot or in code; `Engine.max_fps` is the target fps
(60) and is only ever touched by lullaby_error_handler.gd, which drops it to
1 for the error screen and restores it. Screen recording keeps the SoC busy
enough that the clocks stay up, which is exactly the shape of Android's
touch-boost DVFS: touching raises the clocks, idling lets them fall.

**Do not chase it in the game.** But do read what it says: 60 -> 40 is a
1.50x slowdown, so a 16.7ms frame becomes 25ms. A frame with real headroom
never crosses the line - 8ms at boosted clocks is about 12ms at 0.65x and
still inside the budget. Crossing it means the frame was already at the
edge, which is the argument for every optimisation in the sections below.

It also puts a caveat on every log in this repo: **a heartbeat taken while
the player was not touching the screen was measured at reduced clocks.**
gpu=, script= and the rest are wall-clock milliseconds, so they all inflate
together when the governor steps down, and `SUMMARY vs_first` cannot tell
that apart from thermal throttling. Compare like with like - a quiet stretch
against a quiet stretch - and treat a spread between two runs of the same
section as suspect unless both were equally busy.

### And the size of it, measured: 12x, with a control that cannot be confounded

That caveat sat here for months as a caveat. `bench=` turns it into a number,
and the number is far bigger than "1.50x". Over the 63 heartbeats of
`10152-665dedd4`:

| | n | `bench` mediana |
|---|---|---|
| latidos con toques (`in=` > 0) | 27 | **236us** |
| latidos sin tocar (`in=0`) | 36 | **813us** |

Full range across the session: **184us to 2210us**. And the split is not
statistical - `bench=235us` appears **only** on heartbeats with input, every
single time, in five different scenes. That is Android's touch-boost DVFS
read directly, with fixed arithmetic that no scene can make heavier.

Three consequences, all of which have already misled this file:

- **The load-time growth is this, not VRAM** - the shop's two loads in that
  session are 4763ms at `bench=235us` and 17420ms at `bench` up to 960us, with
  *less* VRAM resident on the slow one.
- **A per-sequence ranking of `gpu` is a ranking of how boosted the phone
  was**, unless `bench` is printed next to it. Chimera's "four expensive
  shots" are the four slowest-clocked samples.
- **`in=0` and "cutscene" are the same stretch of song**, so the untouched
  heartbeats are also the ones with the heaviest geometry (`prims` 24107 vs
  14378, `script` 10.15ms vs 3.64ms). Splitting on `in=` alone therefore
  cannot separate governor from content, and this log cannot settle it. Two
  passes of the same section, one played and one idled, can.

The habit to build: **read `bench` before any other number on the line.** It
is already on every entry.

## Very Low pasó a `render_scale = 0.70`, y hay que decir qué compra y qué no

Decisión del usuario, correcta: **0.50 no es "el juego yendo bien", es el
juego a un cuarto de resolución escondiendo que hay lag de verdad.** Bajar la
escala tiene que ser el recurso de emergencia, no la base, y Very Low
enseñaba pixelado severo para tapar un problema que había que medir, no
esconder.

El coste, con el modelo lineal ya validado en el barrido de la tienda
(`frame = 7.3ms + 26.6ms por Mpx de pase 3D`, sobre 1600x720):

| scale | 3D | modelo |
|---|---|---|
| 0.50 | 0.288 Mpx | 15.0ms |
| **0.70** | **0.564 Mpx** | **22.3ms** |
| 1.00 | 1.152 Mpx | 37.9ms |

`(0.70/0.50)² = 1.96x` de píxeles de 3D. Es una subida real de coste, no un
cambio gratis, y no hay ningún ajuste de este fichero que la compense del
todo - el `light_distance_fade` de Very Low ya era el más agresivo de los
cuatro presets y sólo cubre las cuatro luces locales pequeñas (radio < 6),
nunca las cuatro que iluminan la casa entera. Subir la escala y dejar el
resto de la escalera igual es aceptar ese coste a cambio de que Very Low dé
una imagen reconocible en vez de un cuarto de resolución.

## Lo que hace caro un píxel de 3D son las luces, no la resolución

Y esto reencuadra todo lo demás de este fichero, así que va antes.

**`graphics_render_scale` es la palanca de emergencia, no la línea base.** Lo
normal es 1.0 y que el juego vaya bien ahí; 0.50 es el juego renderizando a un
cuarto de resolución. Chimera se ha registrado **siempre** a 0.50, o sea que
los 31.85ms de `gpu` p50 son el número *con la muleta puesta*. A 1.0 el pase 3D
pasa de 0.29 a 1.15 Mpx sobre 1600x720.

Medido en la ruta del teléfono (Vulkan, Forward Mobile, 1600x720), una sola
superficie cubriendo la pantalla entera y N omnis cuyo radio la alcanzan toda:

| luces | 0 | 1 | 2 | 4 | 6 | **8** | 10 | 12 |
|---|---|---|---|---|---|---|---|---|
| gpu | 14.6 | 32.7 | 54.6 | 80.5 | 108.6 | **134.8** | 134.0 | 134.3 |

**Cero luces son 14.6ms y ocho son 134.8 - 9x**, unos 15ms por luz y pantalla
completa. Forward Mobile no tiene pase diferido: cada luz que alcanza un
fragmento se evalúa en el shader de ese fragmento. O sea que la palanca que
conserva la estética y hace alcanzable el 1.0 es **cuántas luces llegan a cada
píxel**, no a cuántos píxeles se renderiza.

Tres cosas que esa curva dice y que no estaban escritas:

- **Satura en 8.** Forward Mobile aplica como mucho ocho luces por objeto, así
  que la novena no cuesta nada - y tampoco ilumina. Una escena cuyo censo dé
  más de 8 luces visibles está pagando el máximo **y** perdiendo algunas en
  silencio. Chimera registra `lights=10..13`.
- **`light_energy = 0` cuesta el precio completo.** Ocho luces a 0.35 y ocho a
  0.0 midieron 135.8ms y 135.1ms - idénticas. Las mismas ocho **escondidas**,
  16.3ms. Una luz que no emite nada sigue ocupando su hueco; sólo
  `visible = false` la saca.
- **`light_bake_mode = BAKE_STATIC` no la saca tampoco**, al menos sobre
  geometría sin lightmap: 33.8ms contra 32.7 a una luz, 136.7 contra 134.8 a
  ocho. Sobre geometría con bake Godot debería excluirla y eso **no está
  medido aquí** - hacerlo pide hornear un lightmap, que no se puede en este
  entorno.

```bash
python3 tools/audit_light_cost.py          # barre lullaby_mod/
```

Cuenta, por escena, las luces a energía cero que nadie sube, y muestrea una
rejilla sobre el volumen que abarcan para decir **cuántas alcanzan el mismo
punto** - que es el número que se paga.

**El primer hallazgo era un bug de la propia herramienta, no del port, y se
cogió antes de tocar una sola escena.** Leía una línea `light_energy` ausente
como 0.0; el default real del motor, comprobado contra el binario en marcha
(`OmniLight3D.new().light_energy`), es **1.0**. `LightbulbLight` de la tienda
no tiene línea `light_energy` porque nadie se molestó en autorar un valor
explícito - es una luz normal, no coste muerto. Corregido, y con
`tools/test_light_energy_gate.gd` fijando el default para que no vuelva a
pasar en silencio.

**Con el default correcto, cero hallazgos `[COSTE]` en las 88 escenas.** No
hay ninguna luz encendida a energía cero sin que algo la suba. Los tres
hallazgos que quedan son `[aviso]`: luces que legítimamente pasan por energía
cero, conducidas por animación o por script.

Dos de esos tres eran falsos positivos de otra clase, la misma que ya mordió en
el barrido 2D: una `light_energy` escrita desde GDScript es invisible a un
barrido de texto. `power_console.gd` conduce la `TVLight` de la tienda entre 0
y 0.241 y `mch_picturetaking.gd` conduce el foco del flash. La herramienta
sigue ahora los NodePath hasta el script del nodo que los exporta, igual que
`audit_canvas_fill.py`.

Y el tercero, Chimera's `TvLight`, queda anotado y sin gatear, con su motivo:
energía 0 y `omni_range = 43.927` sobre una casa de unas 10 unidades, pero su
energía la suben nueve secuencias distintas y sólo está a cero durante
`prelude`, 16.5s de una canción de tres minutos. Gating de un nodo de gameplay
por 16 segundos no compensa el riesgo.

**El arreglo, listo y probado, para la próxima luz que sí aparezca:**
`lullaby_mod/scripts/lullaby/lullaby_light_energy_gate.gd`, `@tool extends
Light3D`, esconde el nodo mientras `light_energy` está a cero. Deliberadamente
opt-in por nodo, siguiendo la misma forma que `lullaby_effect_rect_gate.gd` -
resolver si una pista de animación escribe el `:visible` de esa luz exige
recorrer cada `AnimationPlayer` y resolver NodePaths en tiempo de ejecución,
que es justo la clase de cosa que ya ha mordido en este proyecto (`%Name`,
`.` contra nombre, subárboles de `.gltf` opacos). Un humano revisa la salida
del audit y adjunta el script sólo donde dice que es seguro.

**Y `light_indirect_energy`/`light_volumetric_fog_energy` no complican el
arreglo, comprobado en vez de supuesto.** `TvLight` de Chimera tiene
`light_energy = 0.0` **y** `light_indirect_energy = 6.026` durante `prelude`,
que a primera vista parece un rebote de luz indirecta que el gate se comería.
No lo hace: este proyecto usa `rendering_method.mobile="mobile"` (Forward
Mobile), que no tiene SDFGI ni VoxelGI, y ninguna escena declara un `VoxelGI`
ni fog volumétrico - así que no hay ningún sistema de GI en vivo que consuma
esos multiplicadores en una luz dinámica. Confirmado renderizando una luz con
exactamente esa combinación (`energy=0`, `indirect_energy=6.026`) contra la
misma luz completamente ausente de la escena: **0/255 de peor error de
píxel.**

## Las cuatro reglas del relleno 2D, medidas

El canvas 2D es la mitad del frame que `graphics_render_scale` **no** toca. A
`scale=0.50` sobre 1600x720 el pase 3D entero son 0.29 Mpx; una sola capa 2D a
pantalla completa son 1.15 Mpx y el censo de Chimera llega a `over=8.4x`. Y
Safety Lullaby dibuja `3d=0/0` y cuesta 25.93ms. O sea que aquí está el techo
de las tres canciones, y hasta esta sesión no había una sola medida de él.

Todo lo de abajo sale de la ruta del teléfono (Vulkan, Forward Mobile,
1600x720), con ocho ColorRect a pantalla completa apilados salvo donde se diga.

```bash
python3 tools/audit_canvas_fill.py          # barre lullaby_mod/ y addons/
```

### 1. `modulate` descarta, `self_modulate` y `color` no

| caso | gpu | draws | prims |
|---|---|---|---|
| opaco | 28.98ms | 1 | 16 |
| **`modulate.a = 0`** | **0.93ms** | **0** | **0** |
| `self_modulate.a = 0` | 30.87ms | 1 | 16 |
| `color.a = 0` | 31.09ms | 1 | 16 |
| `visible = false` | 0.90ms | 0 | 0 |

`modulate` propaga a los hijos, así que Godot puede saltarse el subárbol
entero; los otros dos afectan sólo a ese item y se dibuja igual. Y fíjate en el
orden: **una mezcla a pantalla completa de nada cuesta un pelo MÁS que una
opaca.** `color = Color(0,0,0,0)` no es "inerte", es el caso más caro de los
cuatro.

Antes de dar por gratis un rect transparente, mirar **cuál de los tres niveles**
está a cero.

### 2. Un pase identidad cuesta casi lo que uno que hace algo

Con el shader real de Safety Lullaby (`shd_radial_blur`) sobre 40 rects:

| caso | gpu | draws |
|---|---|---|
| activo (`BLUR_STRENGTH=0.135`, 15 muestras/píxel) | 49.7ms | 2 |
| identidad (`BLUR_STRENGTH=0`) | 20.0ms | 2 |
| oculto | 6.7ms | 1 |

El `draws=2 -> 1` es la parte que no se sabía: **esconder el rect se lleva la
copia de backbuffer que el motor inserta por `hint_screen_texture`.** Es lo
contrario del `BackBufferCopy` explícito de `intro.tscn`, que copia lo lea
alguien o no. Detalle completo en la sección de Safety Lullaby.

### 3. `render_mode blend_disabled` existe en `canvas_item`

Y para una capa opaca es **idéntico píxel a píxel**:

    blend_mix           10.53ms      <- lo que hace todo CanvasItem por defecto
    blend_premul_alpha  10.15ms
    blend_disabled       2.78ms

Mismo fragment, mismo trabajo, sólo cambia el estado de mezcla.

**No aplicado a nada todavía, a propósito.** Ese 3.8x es de un rasterizador
software, donde mezclar es leer memoria; en un tiler la mezcla lee memoria de
tile, que es mucho más barata, así que la ganancia real en un Adreno está sin
medir. Y ponerlo cuesta un `ShaderMaterial` único por nodo, que es un bind
único que no batchea. Es una fila de A/B en el teléfono, no un cambio que se
manda a ciegas.

Sólo vale para **`ColorRect`**. Un `TextureRect` o un `NinePatchRect` con una
textura recortada lee como opaco en `color`/`modulate` y está lleno de agujeros
en pantalla; el `StyleBox` de un `Panel` puede ser redondeado o translúcido.

### 4. Una capa opaca NO tapa lo de abajo por sí sola

Siete capas con un fragment caro y una octava opaca encima:

| | gpu |
|---|---|
| sin tapa | 89.8ms |
| tapa opaca con `blend_mix` | **91.0ms** |
| tapa opaca con `blend_disabled` | 18.4ms |

La fila del medio es la importante: **poner una capa opaca encima no ahorra
nada.** El 2D de Godot no tiene búfer de profundidad, así que se dibuja en
orden de pintor y un draw posterior no puede cancelar el trabajo de uno
anterior.

Los 18.4ms de la tercera fila son el rasterizador software difiriendo el
sombreado por tiles y descartando lo tapado. **Un Adreno o un Mali no pueden
hacer eso sin profundidad, así que no cuentes con ello.** La versión portable
del truco es esconder tú las capas tapadas, y esos 18.4ms son la cota superior
de lo que eso daría.

### Lo que el barrido encuentra hoy

**Cero hallazgos de coste muerto en los 104 ficheros.** Los dos que había
-`%WaterEffect` y `%RadialEffect` de Safety Lullaby- están cerrados por la
regla 2. Quedan 28 candidatos a la regla 3, casi todos fondos de menús y de
arranque, más `Stage`, `BlackBG` y `Black` de Monochrome, que es la única
canción donde el frame es canvas puro.

**Dos falsos positivos que la herramienta tuvo que aprender a no dar**, y los
dos son de la clase que ha roto este repo antes:

- **Un `visible` escrito desde GDScript es invisible a un barrido de texto.**
  `LowerHealthRect` de Chimera está autorado `self_modulate.a = 0` con `color`
  opaco, o sea exactamente el patrón de la regla 1 - y no es un fallo:
  `lower_health_overlay.gd` lo tiene por un NodePath exportado y hace
  `visible = health < max_health / 2`. La herramienta sigue ahora los NodePath
  sin sufijo `:propiedad` hasta el script del nodo que los exporta.
- **`TextureRect` fuera de la regla 3**, por lo dicho arriba.

## Un pase de pantalla completa que produce la identidad cuesta lo mismo que uno que hace algo

Y este proyecto tenía dos siempre encendidos, en Safety Lullaby.

Lo primero, la regla del motor, medida - **Godot descarta un CanvasItem por su
`modulate.a`, no por el `color.a` del ColorRect.** Ocho rects a pantalla
completa apilados, 1600x720, Forward Mobile:

| caso | gpu | draws | prims |
|---|---|---|---|
| opaco | 28.8ms | 1 | 16 |
| `modulate.a = 0` | **0.79ms** | 0 | 0 |
| `color.a = 0` | **30.5ms** | 1 | 16 |
| `visible = false` | 0.90ms | 0 | 0 |

O sea que `color = Color(0,0,0,0)` con el `modulate` intacto no es que no sea
gratis: es **el caso más caro de los tres**, una mezcla a pantalla completa que
no pone nada. Antes de dar por inerte un rect transparente, mirar cuál de los
dos niveles es el que está a cero.

Y hay una segunda mitad, que es la que decide cuánto vale el arreglo: **la copia
de backbuffer que el motor inserta por `hint_screen_texture` sigue la
visibilidad del CanvasItem que la pide.** Con el shader real de Safety Lullaby
(`shd_radial_blur`) sobre 40 rects de fondo:

| caso | gpu | draws |
|---|---|---|
| activo (`BLUR_STRENGTH=0.135`, 15 muestras/píxel) | 49.7ms | 2 |
| **identidad** (`BLUR_STRENGTH=0`, copia la pantalla y la reescribe igual) | **20.0ms** | 2 |
| oculto | **6.7ms** | 1 |

El pase identidad cuesta 13.3ms de un frame de 20 - **tres veces todo lo que
hay debajo** - y el `draws=2 -> 1` dice que esconderlo se lleva la copia. Esto
es lo contrario del caso de `intro.tscn` que ya está escrito arriba, y la
diferencia importa: allí la copia es un **nodo `BackBufferCopy` explícito**, que
copia lo lea alguien o no; aquí la inserta el motor por el material.

Los dos rects de Safety Lullaby estaban exactamente ahí. `%WaterEffect`
(`shd_trance_water_hsv_contrast`) y `%RadialEffect` (`shd_radial_blur`) shipean
visibles, sin pista de animación que los toque, y sus cuatro parámetros salen
todos de `_effects_strength` en `trance_shaders.gd`, que es
`(100 - retention) / 100` - o sea **0 mientras el jugador lleve bien el
péndulo**, que es la mayor parte de una partida buena. A 0, `WAVE_STRENGTH <= 0`
y `BLUR_STRENGTH <= 0` toman las dos ramas de identidad y HSV/contraste están en
sus valores neutros.

`trance_shaders.gd` los esconde ahora por debajo de `NEUTRAL_EPSILON = 0.002`.
La cota sale de que el término que más pesa es la saturación, `1 - 0.275·e`, y
medio paso de 8 bits pide `0.275·e < 0.5/255`, o sea `e < 0.0071`. Comprobado
además renderizando una rampa de matiz/saturación/valor por los **dos** shaders
reales y diffeando contra la misma rampa sin pasar por nada:

    e = 0.0020   peor error 0/255   0 canales de 691200
    e = 0.0071   peor error 0/255   0
    e = 0.0200   peor error 0/255   0
    e = 0.1000   peor error 1/255   1658  (0.24%)

10x de margen real hasta la primera diferencia medible, y la última fila es la
que prueba que el método detecta un efecto de verdad en vez de pasar en vacío.
`tools/test_trance_gate.gd` (12 comprobaciones, en CI) fija la constante contra
su propia cota, porque el barrido de arriba necesita un framebuffer y CI no
tiene display.

Dos cosas de alcance, para no vender esto de más:

- **Monochrome ya lo tenía.** `lullaby_effect_rect_gate.gd` hace lo mismo por
  sondeo sobre `Front/RadialBlur`, cuyo `intensity` lo conduce una pista de
  animación y por tanto no hay script al que engancharse. Dos herramientas para
  dos situaciones; en Safety Lullaby el script ya tiene el número en la mano y
  sondear sería peor.
- **Los dos shaders están en `EFFECT_SHADER_PATHS`**, así que a Very Low se
  quitan enteros y ahí esto no cambia nada. Cae en Low, Medium y High - que es
  justo donde el jugador **no** pidió degradar nada.

El tercer rect a pantalla completa de esa canción, `ScuiguileLayer/SquiggleLayer`,
lleva `WAVE_STRENGTH = 2.0` autorado y nadie lo mueve: está haciendo su trabajo
todo el rato y no se toca.

## Peepers is half of Monochrome's frame

`Peepers.tscn` - the wall of eyes - is 132 nodes carrying 128 ColorRects, and
it is the single most expensive thing in the song. Measured on device across
28 heartbeats with it visible against 79 without:

| | on | off |
|---|---|---|
| draw | 270 | 32 |
| gpu | 10.84ms | 9.55ms |
| cpu_render | 1.65ms | 0.76ms |
| script | 10.14ms | 6.89ms |
| script_max | 38.28ms | 20.62ms |
| fps_low | 20.5 | 29 |

Two separate causes, both fixed, and both worth knowing as shapes:

**128 unique ShaderMaterials where 6 would do.** All 128 eyes use the same
shader; the materials differed only in `rect_size`, which the shader reads
solely as `aspect = rect_size.x / rect_size.y` - and every eye is square, so
all 126 distinct values were no-ops. A unique material per item is a unique
bind per item, so nothing batched. The parameters that actually vary are
`eye_size_variant` (3) and `eye_position` (2). **Before assuming a per-item
material is needed, check what the shader does with the parameter that
differs.**

**256 `_process` callbacks that ran while hidden.** Each eye runs its own
`_process` for the wobble and each glow runs another for scale and rotation.
Godot does not skip `_process` for an invisible node, so all 256 kept firing
through every stretch where Peepers is hidden - which is most of the song.
They were provably doing nothing: `Peepers._process` returns early when
hidden, so `_time` freezes, and every child recomputed the same position,
alpha and rotation from frozen inputs. `NOTIFICATION_VISIBILITY_CHANGED` now
gates `set_process` on all of them.

`fx=N(effect=M full=K)` in the CENSUS line is what found this: it counts
visible CanvasItems carrying a ShaderMaterial, and it tracked the song's
`Stage/Peepers:visible` keys one for one against `draw`.

## What the black graphic is not, measured rather than reasoned

`tools/harness/scene_probe.tscn` lists every visible CanvasItem that actually
paints, with its rect in base pixels, at any position of the song. Run over
Chimera at `_ready` and at 40/60/80/100/110/120/140/160s, **the whole scene
never has more than a handful**, and not one of them is near the 1440x1080 at
x=240 the screenshots were measured at:

| | | |
|---|---|---|
| `UILayer/NTSC` | 1920x1080 at 0,0 | on by design at post-processing HIGH |
| `UILayer/LowerHealthRect` | 1920x1080 at 0,0 | alpha follows health |
| `UILayer/HeartVignette` | 1464x1080 at 228,0 | alpha 0 except during the heartbeat |
| `Intro/ColorRect2` | 1957x1103 at 0,0 | the intro fade, `queue_free`d at 34.6s |

So it is not an authored 2D overlay. Every candidate that was argued about from
the scene text - the pause `AspectRatioContainer`, `CalmThineself`, `Borders`,
`HeartVignette` - is either never visible or the wrong size, and this settles
all of them at once.

`LowerHealthRect` is the only thing in the scene shaped like the report: a
full-screen opaque black `ColorRect` that sits **before** `GameUI` in
`UILayer`, so it covers the stage and not the notes, and whose alpha is
`remap(health, 0, max/2, 1, 0)` - it appears the moment health drops under half
and deepens as the player loses. Chimera starts at exactly `max/2`. It is
**byte-identical to the pck's**, so it is not a port bug, but nothing else
matches "over the stage, not the notes, worse when Hex arrives, clears again".
Worth asking whether the black tracks the health bar before looking further.

The remaining place to look is 3D: `scene_probe`'s `3d` mode projects every
visible mesh through the live camera, and a mesh in front of it covers the
stage, draws under every CanvasLayer, and is invisible to any CanvasItem walk.

### And the watcher could not see 3D at all

Two facts from the player close the search space: the black is **flat opaque
black with alpha 1**, nothing visible underneath, and it is **there during the
intro but the intro camera does not frame it** - it appears when the gameplay
camera comes in. A 2D overlay does not care where the camera points. A blend
cannot be opaque. So it is geometry.

Which the instrument built to name it could not report. `_blackout_watch` is
typed `Array[CanvasItem]` and `_can_cover_the_screen()` only admits
`ColorRect`, `TextureRect`, `Panel`, `SubViewportContainer` and `Sprite2D`.
`_visual3d_watch` held all 96 of Chimera's meshes, collected in the same walk,
and only ever fed the `vis3d=N/M` counter. `_poll_blackouts_3d()` now projects
them and reports coverage, the rect, and **the material each surface binds**.

Three things it has to get right, all of which it got wrong first:

- **Skip `Light3D`.** They are `VisualInstance3D` too and their AABB is their
  *range*: `AmbLight`, `MoonSpotlight` and `TvLight` all reported covering the
  whole screen. (`TvLight` is in that list for its 43.9-unit range, not for
  casting - it does not cast.) `GeometryInstance3D` is the set that puts pixels down.
- **`negro=` is ANY surface, not every.** The windows bind white glass on
  surface 0 and `albedo(0,0,0,1)` on surface 1; requiring all of them black
  reported both as `negro=no`.
- **Slice the list.** 96 meshes x 8 `unproject_position()` calls every frame is
  ~770 projections a frame in GDScript, on the phone being measured.
  `VISUAL3D_PER_FRAME = 16` covers the list several times a second.

And unlike the 2D half, it **closes explicitly when a node is freed** rather
than `continue`-ing past it. That guard is why a missing "deja de taparla" is
ambiguous, and it nearly convicted `Intro/OutsideDoor` off a device log when
the census (`delta=[… Sprite2D-4 Node2D-3]`, `opaque=[]`) showed `103_stroll`
had freed it on schedule.

### The two flat-black meshes, and why they are not a port bug

The sweep with materials finds exactly two: `window_001` and `window_004`, both
`albedo(0.00,0.00,0.00,1.00)` on surface 1, from
`models/house/mat/window.tres` - black albedo, emission enabled,
**`emission_energy_multiplier = 0.0`**. Next to it sits `window_glow.tres`,
byte-identical but energy `4.5`, referenced by **nothing**. And
`chimera_house.gd` is:

```gdscript
func glow():
	$window_004.set_surface_override_material(1, )
```

Which looks exactly like the smoking gun and is not. That text is **GDRE's
decompiler output committed verbatim** - it dropped the second argument, almost
certainly the `preload()` of `window_glow.tres`. It still *parses*, because
GDScript allows a trailing comma, so it is a one-argument call to a two-argument
method that would fail at runtime. But `tools/read_pck_scripts.gd -- glow` over
all 260 of the pck's scripts finds `glow` in exactly one place, `Peepers.gdc`'s
unrelated `glow_node`. **Nothing calls `glow()` in the original either**, so the
windows are black on PC too and the glow material is the mod's own dead code.
Do not "restore" it.

The landmine to carry forward: **never commit decompiler output without
reading it.** GDRE silently drops arguments, not just type annotations.

### FRAME: the log measures the picture, not the scene

Every other instrument in `lullaby_diagnostics_log.gd` describes the scene and
hopes the frame follows. Nine rounds of the black graphic have shown that hoping
is not enough - the tree has been swept, projected, diffed against the pck and
cleared on every axis, and the player still sees a black rectangle. `FRAME`
reads the rendered frame back and measures it:

```
FRAME negro 960x720 en 160,0 (cubre=0.75) borde=0px luma_media=0.088
      leido=1280x720 en 6.9ms perfil=[----                        ----]
      sin_luz=sigue(antes 960x720 ahora 960x720)
```

That line is from a validation run with a synthetic 1440x1080 rect authored at
x=240 in base coordinates - and it reports 960x720 at x=160 in the 1280x720
frame, which is the number the screenshots were measured at, to the pixel. The
instrument reproduces the report before being pointed at the bug.

Four things it has to get right, and three of them were wrong first:

- **Rows must be counted inside the column band, not across the width.** The
  first version crossed an independent x-run with an independent y-run and
  reported `negro 142x0` - height zero - for exactly the shape being hunted: a
  centred rectangle leaves every row only 75% dark, under any threshold worth
  having.
- **The letterbox is reported separately** (`borde=`). The widest run that
  touches an edge is the pillarbox and is not the bug; the widest run that
  touches neither is. That split is the player's own instruction.
- **`sin_luz=` is what decides where to look next.** On the first big dark
  region the next frame is drawn once with `DEBUG_DRAW_UNSHADED`, which throws
  away every light and lightmap and paints raw albedo. Survives it → geometry
  or a material, and the 3D blackout list names it. Vanishes → nothing is
  covering anything, the scene is simply not lit there, and no amount of
  node-hunting would ever have found that.
- It costs a GPU-to-CPU readback, 6.5-8.8ms measured, so it runs every 8s, is
  scaled to 96 columns before any arithmetic, and prints its own cost.

The `perfil=` ramp is 32 buckets of mean column luminance. Read it when the
rect looks wrong: it shows the shape of the frame directly, and a black band
that the run detector misses is still visible in it.

### What the first FRAME log actually said

`aef733a5`, moto g53, Very Low, aspect Normal. The measurement nine rounds were
missing, and it is not a rectangle:

```
[163-251s] negro 0x0 borde=1280px luma_media=0.014-0.027 perfil=[                                ]
```

**The whole frame is black**, edge to edge, for ninety seconds - from
`109_backingupback` through `121_closetrunout` - and comes back at
`123_crawling` at `luma_media=0.163`, ten times brighter, same scene. That is
the player's "todo se pone completamente negro hasta lo del botón flash",
measured instead of described.

And nothing is covering it. Across that window the census reads
`vis3d=75-78/96`, `lights=10(shadow=1)`, `fx=0`, `env=limpio`, and the 2D
blackout list is empty except for two authored flickers. Geometry is visible,
lights exist, no overlay and no shader. **The surfaces are simply not lit.**

Where the camera is during it settles which surfaces: `cam=fov80@-15.7,1.8,-1.6`
and `cam=fov90@-14.1,1.8,-0.3` - the closet, fifteen units out from a house
about ten across. `Environment/Lights/ClosetLight` sits at `-15.98,2.27,-0.90`,
is authored `visible = false`, and **nothing anywhere turns it on** - checked in
the port and in the pck, identical. So that corner has only ever been lit by
the bake, which makes `chimera_base.lmbake` the only remaining candidate and is
why every heartbeat now carries `lm=`.

The bake is intact on this side: it resolves by UID
(`uid://bha4lelasbqse::::res://songs/chimera/chimera_base.exr` - note the PC
path root, which resolves anyway because the local `.import` declares that UID),
loads as 512x512x8, and registers 58 users.

**"On this side" was the whole bug.** That sentence is true and it is also the
reason this took eleven days: the UID resolves at import, and 84d99d5 measured
that at EXPORT it does not - ~1300 invalid-UID warnings across ~227 files in a
single export step. On the APK, `res://songs/chimera/chimera_base.exr` is not a
fallback, it is the path that loads, and `e191f1e` had deleted it as an orphan.
Its twin, `res://resources/collector_shop/env_collector_shop.exr`, was deleted
by the same commit, threw `Failed loading resource` on the next build, and was
restored that night. Chimera's did not throw - a `LightmapGI` with no texture is
a legal `LightmapGI` - so the only symptom was an unlit house, which reads
exactly like the lighting question everyone was already chasing. Both files are
back and `tools/audit_lightmap_fallback_paths.py` now fails CI on the next one:
it reads the paths out of the `.lmbake` binary, which is the one place a text
grep and `ResourceLoader.get_dependencies()` both cannot see.

### Why only Chimera, and why the shape of the black changed shot by shot

The player's framing was the sharpest evidence in the whole investigation -
"solo ocurre en chimera nada mas" - and it has an exact structural answer:

- **Exactly two scenes in the project have a `LightmapGI`**: Chimera and the
  collector's shop. `grep -rl 'type="LightmapGI"' --include=*.tscn` returns
  those two and nothing else. They are precisely the two `.exr` files `e191f1e`
  deleted.
- **Chimera is the only song with baked lights at all.** `light_bake_mode = 1`
  (`BAKE_STATIC`) appears 6 times in `sng_chimera.tscn` and **0 times** in
  `sng_monochrome.tscn` and `sng_safety_lullaby.tscn`. A `BAKE_STATIC` light
  contributes to static geometry *only* through the bake, so with the bake gone
  `MoonSpotlight`, `AmbLight`, `ClosetLight`, `CrawlSpaceLight`,
  `OutsideGrassLight` and `CrawlDoorLight` all stop lighting the house. The two
  that light the *whole* house - `AmbLight` (range 18.1, energy 2.87) and
  `MoonSpotlight` (21.5) - are both in that list.
- What survives is ambient plus the **dynamic** lights, and the ones that
  matter ride the camera (`Camera3D/OmniLight3D`, the sequence spots): no
  `light_bake_mode` line, so the Godot 4 default `BAKE_DYNAMIC`.

That last point is what makes the log's shot-by-shot pattern fall out, and it
is why the black looked like a rectangle that moved rather than a stuck
overlay. From `4a6869d7`, mapping each `FRAME` through the clock's dispatch
times (`101_prelude` at 3s, `107_turnaround` at 72.5s, `122_fall` at 149.04s):

| song t | sequence | camera | frame |
|---|---|---|---|
| ~9 | `101_prelude` | `fov75@0,3.0,3.7` | luma 0.111, `borde=320px` |
| ~41 | `103_stroll` | `fov80@0,3.0,3.2` | `negro 320x720 en 160,0` |
| ~73 | `107_turnaround` | `fov75@0,2.6,6.6` | **`negro 960x720 en 160,0 cubre=0.75`** |
| 81-141 | `110` … `119` | inside the house / closet | `borde=1280px`, luma **0.015**, ninety seconds |
| ~153 | `122_fall` | `fov64@0.5,2.8,-0.6` | luma 0.118, back |
| ~168 | `123_crawling` | `fov66@8.2,-1.9,-0.5` | luma 0.156 |

Wide shots of the house are black because the house was lit by the bake. Close
shots come back because the camera's own dynamic light reaches what it is
pointed at - which is also why `122_fall` and the crawlspace, the two places
the camera is right up against the geometry, were always the moment the player
said it cleared.

**And it disposes of the "75% wide rectangle" reading for good.** At song t=73
the HUD is not even on screen: the clock fades `UILayer/GameUI:modulate` to
alpha 0 between 70.41s and 71.67s and sets `UILayer/GameUI/Player:visible =
false` at 73.17s. Nothing was bounding that run but the geometry itself - the
lit outdoors at the frame edges against an unlit interior in the middle.

### Two sweeps that say there is no second one of these

The whole class is "a resource points at a file by plain `res://` text and the
file is gone". Both halves came back clean, which is worth recording so the
next session does not re-run them on a hunch:

```bash
# every binary resource (.res .scn .lmbake .mesh .material .occ): 198 files
# every text resource's ext_resource path= (.tscn .tres): 467 files
```

The binary sweep's only hits are 7 audio `.res` naming the `.ogg`/`.wav` they
were imported from - bookkeeping, the packets are embedded, nothing loads
through it. The text sweep's only hit is
`lullaby_mod/assets/collector/hand/shop_talk_pick_hands.tscn`, whose
`pick_hands.gltf` does not exist. **Nothing references that scene**, so it
cannot break a build - but it also cannot load, so do not wire it up without
recovering the glTF first. Per the standing rule it was left in place rather
than deleted.

Two other things the log named, both worth knowing:

- `UILayer/HeartVignette` is `1464x1080 at 228,0`, `cubre=0.76`, pulsing every
  ~0.45s through the heartbeat at `alpha=0.52`. In the 1280 frame that is
  976x720 at x=152 - the closest thing in the whole session to the "75-80% of
  the width" the screenshots were measured at, and it is the mechanic working
  as authored.
- `UILayer/LowerHealthRect` covered the screen at `alpha=0.64` for **38
  seconds** (120.95-158.97). Health-driven and identical to the pck, but that
  is most of `103_stroll` through `107_turnaround` spent under a dark veil.

The one field that did not answer was `sin_luz=`. It fired once per scene, and
it spent that shot at `103_stroll` on a 413px region eighty seconds before the
real blackout. It re-arms on growth now, so it follows the worst frame instead
of the first.

### The fields added to answer "why is it black"

`FRAME` said the whole frame was black; it could not say why. Four fields did.
**Two de ellos ya no existen** - ver "Lo que se quitó del log al cerrar el bug"
más abajo - pero los cuatro se describen aquí porque el próximo que necesite
medir una pantalla negra querrá saber qué se construyó y por qué:

| field | answers | ¿sigue? |
|---|---|---|
| `sonda=[normal=L/C albedo=L/C luz=L/C]` | the same instant drawn three ways - as shipped, with `DEBUG_DRAW_UNSHADED` (every light and lightmap discarded, raw albedo), and with `DEBUG_DRAW_LIGHTING` (albedo discarded). L is mean luma, **C is the dark region's coverage**, and C is the one that decides: a region that survives raw albedo is something black being drawn, one that vanishes was never covering anything | **no** |
| `luz=NalcanzanM dir=D cerca=X@d` | how many visible lights actually **reach the camera**, not how many exist. `lights=10(shadow=1)` was true for all ninety black seconds and every one of them was back in the house | sí |
| `lm=on tex=WxHxL users=N vis=n/m sh=b` | the LightmapGI's bake: visible, texture dimensions, total users, and **how many of the meshes on screen right now are registered users**. A healthy bake that does not cover what the camera is looking at is indistinguishable from a broken one if only the total is counted | sí |
| `env=... ambS@E bgM@E` | ambient source and energy, background mode. `limpio` only ever meant "no glow, no fog", which is the less interesting half in a scene that goes dark | sí |

`FRAME` also carried `min/p50/p95/max` and a 3x3 `rejilla=` of block luminance,
because a mean of 0.015 cannot distinguish "uniformly black" from "black with
the notes still drawn on top".

Three things this cost, all found by running it rather than by reading it:

- **`light.get("spot_range")` on an AreaLight3D returns null**, and assigning
  null to a typed float aborts the function *with no error printed*. That call
  ran while building every log line, so one null silently took `HEARTBEAT`,
  `CENSUS` and `FRAME` out of the log entirely - the log looked healthy because
  `VIS` and `BLACKOUT` are emitted earlier. Chimera has exactly one AreaLight3D
  (`CrawlSpaceLight`). Cast, never `get()`. **Esta sigue viva**: el patrón es
  general, no del `FRAME`.
- **The probe's three passes must land on consecutive frames.** Gating the
  re-entry on `state == 1` instead of `state != 0` left eight seconds between
  them, comparing a frame against a scene that had moved on.
- **`|` cannot be used inside a field.** The grid used it as a row separator and
  it is the log's own message/counter separator, which breaks every reader of
  the file starting with the ones in `tools/`.

### Lo que se quitó del log al cerrar el bug

El fichero pasó de 2031 líneas el 15-ago a 3826 el 19: **+88% en cuatro días**,
casi todo para esta caza. Cerrado el bug, lo caro y de un solo uso se fue - 535
líneas, el 14% del fichero:

| se fue | por qué |
|---|---|
| `FRAME` y todo `_measure_frame()` | un readback GPU→CPU de **6.5-8.8ms cada 8s**, más dos frames enteros redibujados con `DEBUG_DRAW_UNSHADED`/`_LIGHTING` para la `sonda=`. El instrumento más caro que ha tenido este fichero |
| `BLACKOUT` en 3D (`_poll_blackouts_3d` y sus cuatro ayudantes) | 16 mallas x 8 `unproject_position()` **por frame**, en GDScript, en el teléfono que se estaba midiendo |
| `VIS` | una línea por cada transición de visibilidad de la lista vigilada. Existía porque la puerta de cobertura de `BLACKOUT` había mentido una vez; como diagnóstico permanente es ruido |
| `aj=` | los ajustes de imagen del `Environment`, construyendo la rampa del LUT en cada entrada |

**Se queda** `BLACKOUT` en 2D: es barato (una lista corta, lecturas) y es la
red de seguridad de esta clase exacta de bug. Y se quedan `lm=`, `luz=`,
`vis3d=` y todos los contadores generales de la tabla de campos.

Si hace falta volver a medir la imagen en vez de la escena, está en el
historial: `git show 1d19b3c` lo introduce, `375886c` le añade la `sonda=`.
No hay que reinventarlo, pero tampoco dejarlo puesto entre bugs.

### Rendering Chimera on the device's own renderer

`tools/harness/setup_render_sandbox.sh <dir>` builds a throwaway copy that can,
and the trick is that the blocker was never the scene:

- `--rendering-driver opengl3` loads the song but GL Compatibility has no
  `LightmapGI`, so all of Chimera renders at a mean luma of 13/255 - always
  black, whatever the bug is.
- `--rendering-method mobile --rendering-driver vulkan` is the device's exact
  path, lightmap included, but lavapipe has no ASTC: it decompresses ~500
  textures to RGBA8 on the CPU and sits inside `load()` at 5% CPU indefinitely.

So the sandbox rewrites its 503 texture imports to **uncompressed, 128px**,
which lavapipe takes natively and which does not change lighting at all. The
song then loads on the real path. Captures look like mush; they measure light,
not art.

Needs `apt-get install -y mesa-vulkan-drivers` for lavapipe, and about ten
minutes to import. **It refuses to run in place**, because it rewrites 503
`.import` files and `--import` rewrites their `uid=` lines on top of that.

Not cacheable between sessions - the container is ephemeral and the only
durable store is the git remote, where degraded 128px imports have no business
being. The script is the durable part: one command instead of a day of
rediscovering why neither renderer works.

### The renderer cannot answer lighting questions

`scene_shot` under Mesa does not apply the `LightmapGI` (`chimera_base.lmbake`),
so all of Chimera renders at a mean luminance of 13 out of 255. Hiding both
windows changed the frame by 0.1. It answers "what is on screen and where"; it
cannot answer "is this lit" or "is the stage black", and a null result from it
proves nothing about either.

That is the **GL Compatibility** renderer, which is what `--rendering-driver
opengl3` selects and which has no lightmap support. The device runs Forward
Mobile on Vulkan, so any conclusion drawn from a `scene_shot` frame about
darkness is about the harness, not the game. An A/B of the two black windows
was reported as a clean null on exactly this mistake.

**Matching the device's renderer here does not work, and the attempt is not
worth repeating.** `mesa-vulkan-drivers` gives lavapipe, and
`--rendering-method mobile --rendering-driver vulkan` really does bring up
"Vulkan 1.4.318 - Forward Mobile", lightmap and all. What it cannot do is load
the song: lavapipe has no ASTC, so every one of the ~500 textures is
decompressed to RGBA8 on the CPU, and the process sits inside `load()` at 5%
CPU indefinitely - 20 minutes in, still no first frame, on 16GB of RAM.
Stripping the scene after `instantiate()` does not help either, because the
PackedScene has already pulled every ext_resource by then. Reconstructing a
cut-down stage by hand would work but stops being the scene under test.

## Open problems

1. **Chimera's 30fps ceiling is GPU-bound**, and it moved: `gpu` p50 is now
   **31.4ms** (p90 36.6) against the 38.8ms this file recorded before, for a
   median of 30fps over 42 heartbeats on `10152-665dedd4`. The spread by
   sequence is the useful part and it is wide - `113_reaching` 14.8ms and
   `116_hexstare` 15.1ms both run at 60fps, while `104_photographysesh` costs
   44.2ms and `112_disorientidle` 39.6ms. **Chimera is not uniformly slow; four
   or five shots are.**

   **Which shots is not established, and this item used to assume it was.**
   Each sequence appears 1-3 times across those 42 heartbeats, each measured
   at whatever clock the governor happened to be at - and that spans 12x
   inside this one session. The four "expensive" shots above are exactly the
   four measured at the lowest clocks (`bench=` 1094-1883us), while
   `103_stroll` costs 31.5ms at `bench=240us`, fully boosted, over four
   heartbeats and 162 touches. `103_stroll` is the only shot in the song
   currently known to be expensive on its own merits. Redo the ranking with
   `bench` alongside before aiming anything at it - see the governor section.
2. **VRAM is no longer the top problem.** 224MB in Chimera and 165MB in the
   shop, down from ~410 and 625. Lowering texture *resolution* is still the
   only further lever and still pays twice (VRAM and APK), but the urgency is
   gone. Thermal is down with it: `vs_first` reached **+15%** here against the
   +23% recorded before.
3. **El peor frame del proyecto está en el precache de la tienda, no en la
   canción, y todavía no tiene nombre.** `SUMMARY worst=7787.6ms` en
   `10152-665dedd4` y `7391.8ms` en `10154-8d1ee1ac`, los dos dentro del primer
   precache de la tienda, los dos sin línea `SPIKE` porque el detector dormía
   (arreglado; ver la sección de las dos puertas). El siguiente log ya debería
   traerlo con `pipe=`, `vram_delta=` y la secuencia al lado. Hasta entonces no
   se sabe de qué está hecho.

   Y hay un segundo sin explicar: **un frame de 4405.6ms jugando en la tienda**
   (58.95s de ese log) con `pipe+0`, `vram_delta=+0.0MB`, RAM plana, `in=0` y
   nada en el censo. No compila ni reserva nada. Sin teoría.

4. **The multi-second stall at cutscene starts, and the first thing tried
   against it since the "untried fix" note was written.** `122_fall@6.8s`
   logged **`frame=1911.7ms`** with `pipe+8` the last time this was measured -
   before `4706758` fixed the sweep to run off the reveal instead of the
   clock, so that number needs a fresh log before it can be trusted as
   current. Three more sequences show the same shape: `121_closetrunout@0.7s`
   489ms `pipe+5`, `104_photographysesh@6.6s` 481ms `pipe+5`,
   `107_turnaround@0.1s` 350ms. Texture upload, resource loading and the
   AnimationMixer track cache are all ruled out (see the `122_fall` section).

   **Shipped, unverified on device:** `extra_sweep_player`/
   `extra_sweep_animations` on `lullaby_preload_camera.gd`, wired on
   Chimera's `PreloadCamera` to all four stalling sequences. Each sequence's
   own `Camera3D:position`/`:rotation` keys get folded into the cycling sweep
   (`tools/test_preload_extra_sweep.gd`, in CI), so the loading-screen camera
   also passes through the viewpoints those cutscenes use, not only the ones
   the precache's own animation authors. This is deliberately the narrowest
   version of "put the cast in front of a camera": it adds viewpoints to the
   reveal loop that already exists and touches nothing else - not
   `KEEP_VISIBLE`, not `_hide_everything()`, no `:visible` or light state, the
   one class of change this file has the most reason to be careful with (the
   eleven-day black house was exactly a precache `:visible` change). Caught
   during design, not after shipping: the first draft pointed
   `extra_sweep_player` at this node's own `animation_player`
   (`PreloadCamera/AnimationPlayer`, whose library holds only `precache`)
   instead of `Sequences/SequencePlayer`, where `122_fall` etc. actually live
   - would have silently collected nothing forever. The mutation-tested test
   pins that.

   **What it should move, and what would say it worked:** the total pipeline
   count and the precache's own cost should be about the same either way -
   this does not create or destroy work, it moves *when* each pipeline first
   compiles. A `pipe+N` on one of the four sequences during play, dropping to
   near zero with a corresponding rise during the precache line, is the
   result that confirms it. A device log is what settles this, not this
   note.
5. A **CI gate** running the `get_dependencies` sweep and failing when a
   dependency resolves by neither path nor UID. It would have caught both
   Chimera-breaking bugs before they reached an APK.
6. The **Mobile settings section** (Gameplay Control Hitbox/Touch, hitbox
   hint/gradient/opacity, mechanic hitbox direction, note layout, show pause
   button) - specified but not built. "Touch" is a whole new input mode, not
   a setting; scope it separately.
7. VSlice **y-nudge per scroll direction** - the reference distinguishes
   upscroll from downscroll; ours has a single value.

---

## Tooling gotchas that cost real time

**GitHub MCP results are often too large for context.** `actions_list` and
`get_job_logs` regularly exceed the limit and get written to a file instead.
That is the good path - parse it, do not retry:

```bash
python3 -c "
import json,re
d=json.loads(re.search(r'\{.*\}',open('<saved file>').read(),re.S).group(0))
r=d['workflow_runs'][0]
print(r['id'], r['status'], r.get('conclusion','(running)'), r['head_sha'][:8], r['html_url'])
"
```

Use `.get('conclusion', ...)` - the key is absent while a run is in progress.

**CI logs arrive as one enormous single line.** Splitting on `\n` yields one
segment. Split on the timestamp prefix instead:

```python
re.split(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z ', text)
```

**Godot's error string is "Failed loading resource", not "Failed to load
resource".** Grepping for the wrong one hid 72 real errors for a long stretch
and nearly sent the whole shop investigation down the wrong path.

**The Bash tool times out at ~2 minutes.** Long imports need
`nohup ... > log 2>&1 &` plus polling. Do not chain `sleep`s - that is
blocked. A full project import here takes hours (EXHAUSTIVE ASTC); it is
almost never what you actually need.

**`pkill -f <pattern>` can match and kill your own shell** (exit 144). Kill by
PID, or accept the process finishing on its own.

**Artifact downloads are blocked** (`productionresultssa*.blob.core.windows.net`,
proxy policy). Use the MCP log tools instead; do not try to work around it.

---

## CI and builds

Workflow is `.github/workflows/android-build.yml`; trigger with
`actions_run_trigger` / `run_workflow` on `add-lullaby-mod`. A normal build is
6-9 minutes. It gets much longer whenever precompiled ASTC output is missing,
because CI then recompresses at EXHAUSTIVE quality.

There is already a CI gate, `tools/verify_hardcoded_uids.gd`, which fails the
build if any bare `uid://` literal in a `.gd` does not resolve. It has caught
a real one.

The `.godot/imported` Actions cache and its `restore-keys` are **not** the
cause of anything - that was investigated at length and the user was right to
insist on it. Cached vs cold builds differed because `5ee950a` had deleted 60
textures that only a cold import regenerates. Do not remove the cache to
"fix" a symptom.

### Getting LFS objects pushed (user does this from Termux)

`lfs.github.com` is blocked from this environment, so the user pushes those.
The recipe that finally worked - the `-b` branch flag was missed twice, and
the LFS rule only exists on `add-lullaby-mod`:

```bash
pkg install -y git git-lfs gh && gh auth login && gh auth setup-git
GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 --filter=blob:none --sparse \
  -b add-lullaby-mod https://github.com/jereidk/rubicon_fnf_android.git lfs_tmp
cd lfs_tmp
GIT_LFS_SKIP_SMUDGE=1 git sparse-checkout set precompiled_astc_imports
tar xzf /sdcard/Download/<package>.tar.gz
git add precompiled_astc_imports/<specific files>
git lfs status                      # must say (LFS:), not (Git:)
```

Both `GIT_LFS_SKIP_SMUDGE=1` matter - without it on the sparse-checkout it
downloads ~420MB of existing LFS content. Never set `git lfs install
--skip-smudge` globally; it dirties the user's normal clone.

---

## Settings and presets

`Settings` (`menus/settings.gd`) persists any var whose name starts with
`lullaby_` automatically - adding one is a single line. Engine-level ones
(`game_centered`, `display_target_fps`, `graphics_*`) already exist.

`LullabyQualityPreset.is_matching()` compares **every** tracked field, so a
preset that omits one stops matching and the UI shows "Custom". When adding a
field to the preset, declare it in all four `.tres` files even where the value
does not change.

Console UI lives in `lullaby_mod/resources/console/console.tscn`. Option
scripts: `list_button.gd` (enum), toggle/incremental/input variants. Adding an
option is a node plus `property`/`display_list`/`values_list`, wired to a
`Settings` var - see the `DebugDisplay` and `NoteLayout` entries as templates.
The scene is too large to load in this workspace; validate it structurally
(undeclared/unused resource ids, dangling paths) with a regex pass instead.

---

## Scene structure worth knowing

All three songs share the layout the note-layout applier depends on:

```
UILayer/GameUI/Player      anchor 0.75, Lane0..3 at x = -225 -75 75 225 (spacing 150)
UILayer/GameUI/Opponent    anchor 0.25, same lanes
```

`Stage` is a **ColorRect**, not a 3D world - the strumlines are in screen
space at the base resolution, so pixel offsets work directly.

**Midscroll is not a setting the code can read.** It is an AnimationTree with
`centered`/`uncentered` states, and those animations drive exactly two
properties: `Player:anchor_left` and `Player:anchor_right`. Anything else
writing those will be overwritten every frame; anything writing lane
positions or scales does not conflict.

Touch controls (`addons/rubicon_mobile_controls/`) use a numbered-slot
pattern - `force_active_source1..4`, plus `reserved_controls` and paired
`hide_sources`/`hide_properties` arrays on the note hitbox. Ugly, but adding a
case is a scene edit rather than an engine change, which is deliberate.

---

## iOS

There is an iOS build now: preset `iOS` in `export_presets.cfg`,
`.github/workflows/ios-build.yml`, `workflow_dispatch` only. It produces an
**unsigned** IPA, because every sideloader (AltStore, SideStore, Sideloadly,
TrollStore) re-signs with the installing user's own Apple ID and would strip
anything signed here. So the workflow needs no Apple account, no certificate
and no secret.

The port needed no code changes at all. There is no GDExtension anywhere, no
Android native plugin, no `JavaClassWrapper`, and the only platform branch in
the repo is `OS.get_name() == "Android"` in `_pick_log_dir()`, which already
falls through to `user://logs`. `user_data/accessible_from_files_app` puts
`UIFileSharingEnabled` in the Info.plist, so that directory is reachable from
the Files app and the diagnostics log can be retrieved the same way as on
Android.

**Godot exports the Xcode project fine from Linux** - verified against the
4.7.1 binary here, producing a complete `.xcodeproj`, `.xcframework` and pck.
Only the `.ipa` step needs macOS ("`.ipa` can only be built on macOS. Leaving
Xcode project without building the package." is the exporter's own message).
The workflow still does everything on `macos-latest` rather than splitting the
job, because the alternative is shuttling an ~800MB Xcode project between two
jobs as an artifact.

Things that cost time, in the order they bit:

- **Do not write the preset from memory.** Half a dozen plausible option names
  do not exist in 4.7.1: there is no `architectures/arm64` (iOS is arm64-only
  and has no such option), no `capabilities/push_notifications`, no
  `storyboard/use_launch_screen_storyboard`, no `icons/spotlight_40x40`. Dump
  the real ones out of the binary instead:

  ```bash
  strings -n 4 godot | grep -E '^(architectures|capabilities|user_data|storyboard|icons)/[a-z0-9_@]+$' | sort -u
  ```

  All 45 keys in the preset were checked against that list.

- **`application/app_store_team_id` is required even with
  `export_project_only=true`.** Empty gives "App Store Team ID not specified."
  and no export. It is committed as the placeholder `0000000000`; xcodebuild
  runs with `CODE_SIGNING_ALLOWED=NO`, which ignores `DEVELOPMENT_TEAM`
  entirely, so nothing ever resolves it.

- **A missing `rendering/textures/vram_compression/import_etc2_astc` fails the
  export with an *empty* error message.** Literally "due to configuration
  errors:" and then nothing - `test_etc2()` has no text of its own. This
  project already sets it (project.godot:120); it only showed up in a
  throwaway test project and cost half an hour of bisecting the preset. If an
  iOS or Android export ever fails with an empty reason, check that setting
  first.

- **The destination directory has to exist.** Godot reports "Target folder
  does not exist or is inaccessible" rather than creating it, so the workflow
  runs `mkdir -p builds/ios` first.

- **macOS keeps export templates in
  `~/Library/Application Support/Godot/export_templates/<version>/`**, not the
  `~/.local/share/godot/...` the Android workflow uses. Only `ios.zip` (200MB)
  is unpacked out of the 1.2GB tpz.

The scheme, target and `PRODUCT_NAME` are all the basename of `export_path`
(`lullaby`), which is why `XCODE_SCHEME` in the workflow and the preset's
`export_path` have to change together. Configurations are `Debug` and
`Release`; the generated scheme uses `Debug`.

`tools/make_ios_icon.py` builds the required opaque 1024x1024 icon from the
Android adaptive pair. `Icon.png` is Godot's stock 205x199 default and is not
usable - iOS masks its own squircle, so the source must be square, opaque and
without pre-rounded corners.

Untested, and only a device can settle it: whether it runs. iOS is stricter
about memory than Android and the shop peaks at ~229MB RAM plus ~236MB VRAM.

## APK size

438MB -> ~405MB this session, from converting 47 textures to ASTC. Every
conversion was measured individually; see the texture pipeline section for why
that matters. Remaining levers are content decisions (texture resolution)
rather than compression - and lowering resolution is also the VRAM fix, so it
is the one change that pays twice.

---

## Working agreements with the user

- Spanish. Direct. They catch real problems - "el restore key no tiene la
  culpa", "revertamos ese cambio", "VSlice no aplica nada" were all correct
  and all saved time.
- They run the builds; ask before triggering one.
- They will say when something is urgent. As of this session the only urgent
  thing is Chimera stuttering.

---

## Mobile settings section (Rubicon)

`Settings` tab of the console has a `Mobile` sidebar entry (tab index 6,
after Audio) with the gameplay touch-control options:

- `GameplayControl` (Hitbox/Touch) shows/hides the two option groups live
  via `mobile_section_visibility.gd` (watches `Settings.applied`, same
  pattern as the Quality Preset "Custom" label).
- Hitbox group: Hint -> `show_outlines`; Gradient -> fill vs pressed
  distinction; Opacity (0-100, % of the addon's authored 0.03/0.16);
  Mechanic Hitbox Direction (Up/Bottom/Center, default Bottom).
- Touch group: `TouchNoteHitboxSize` (0.5-2.0) is the tap radius around
  each note (base 100px, scaled linearly) and also scales the round red
  mechanic button (pinned 0.75-1.5x so it never gets untappably small).
- `NoteLayout` moved here from Gameplay (same ListButton, same property).
- `ShowPauseButton` hides `UILayer/SongTouchControls/PauseButton`.

All applied live by autoload `MobileControlsApplier`
(`lullaby_mobile_controls_applier.gd`, same 2-frame pattern as
`NoteLayout`). It finds the lane hitboxes by group
`rubicon_mobile_controls` (joined in the addon's `_ready`), the pendulum
mechanic hitbox by script path, and the pause button by fixed scene path.
`RubiconMobileControls` gained `hitbox_bottom_percent` and
`hitbox_center_percent`; Center splits lanes 0-1 above / 2-3 below the
pendulum band. Only Safety Lullaby has the mechanic, so the direction
setting does nothing on Monochrome/Chimera (lanes stay full-height).

### Touch mode (Fase 2 - implemented)

In Touch mode the applier (`lullaby_mobile_controls_applier.gd`):

- Sets `gameplay_touch_mode = true` on every `RubiconMobileControls` lane
  hitbox: hidden, input disabled, holds released (`rubicon_mobile_controls.gd`
  owns the flag, restored when the mode flips back).
- Hides the pendulum `RubiconMechanicHitbox` AND stops its parent
  (`SafetyLullabyTouchControls`) `_process` - it re-shows the hitbox every
  frame otherwise. `_restore_mechanic_hitbox()` re-enables it when the mode
  switches back mid-session.
- Instantiates `LullabyTouchNoteInput` (`lullaby_touch_note_input.gd`), a
  full-screen overlay that reads the note controller at
  `UILayer/GameUI/Player`, plus `LullabyMechanicActionButton` (round red,
  right-centre, dispatches `lullaby_special` like RubiconActionButton) shown
  only while the pendulum server's `started && !autoplay` (showcase-mode
  aware). The button is a child of the overlay and scales with
  `TouchNoteHitboxSize`.

Touch gameplay rules:

- A tap selects the unhit note whose visual centre (rotated arrow
  container AABB) is nearest, within the radius; only each lane's
  `note_hit_index` note is a candidate (the engine judges lanes in order).
- It drives the SAME handler methods the hitbox drives (`_press`/`_release`
  on the mania lane handlers), so judgment windows, scoring, splash and
  character animations are untouched. Taps use a synthetic
  `InputEventScreenTouch`; the handler ignores the event object.
- Up to 4 simultaneous fingers (one per lane) cover chords; a held finger
  keeps a hold note until release; second finger on a held lane is ignored.
- Every visible `Button` in the scene is a reserved zone (pause/restart,
  Chimera's mechanic buttons, the red button) - taps there never hit notes.
- Same hide/release-all behaviour as the other overlays: pause menu,
  gameover, and cutscenes (HUD modulate alpha).
- `disable_inputs` / `should_autoplay()` block touch input exactly like the
  engine controller does; physical keys still work in Touch mode.

Sidebar note: the settings sidebar is `separation = 20`, `margin_top = 205`.
The console's own UI canvas is 1440x1080 (not the 640x480 the
`ConsoleSubViewport` renders it into - that mismatch is what made this easy
to get wrong repeatedly).

**Read the pck before guessing at this layout.** The original PC mod has
only **three** sections (Gameplay, Visuals, Misc) at `separation = 84`,
`margin_top = 338`: 3x111 + 2x84 = 501, spanning y=338..839, centred at
y≈588. Our six sections inherited a `margin_top` that was only ever
correct for three, which is why the column sat too low and MOBILE ended up
against the bottom edge. Shrinking `separation` (84 -> 20 -> 10) kept
"fixing" the overflow while leaving the column bottom-heavy and off-centre,
because separation was never the problem - the top margin was. 6x111 +
5x20 = 766 centred on the original's y≈588 gives `margin_top = 205`
(y=205..971), same visual axis as the PC layout.

The AUDIO/GRAPHICS/MOBILE wordmarks (`tools/console_art/make_wordmark.py`)
had a separate history worth not repeating: a uniform `MaxFilter` outline
read as heavier and blockier than the scanned originals, but "breaking up"
the edge with high-frequency noise was worse - ~21 isolated specks per word
against the originals' 0-1, and edges that read as splattered paint. The
originals are **not** jagged: they are soft, slightly blurred, and carry a
grey scan halo, with the unevenness in stroke *width* rather than in the
boundary. Measure it - count connected components in the alpha, and compare
against `gameplay.png`/`misc.png` - rather than judging by eye.

### Four bugs a review of the Touch mode caught

All four shipped in the same commit and none would have shown up in CI.

**`_release()` has to be dispatched unconditionally.** The engine
(`rubicon_level_note_controller.gd:263-266`) calls `_release()` on every
key-up with no guard beyond `_should_process()`, and `_release()` is the
*only* place manual play resets `lane_state` to `LANE_STATE_NEUTRAL`. The
overlay guarded its release on "is this still the lane's current note",
which is never true for a tap note (`_press` already advanced
`note_hit_index` past it), so `lane_state` stuck at `LANE_STATE_HIT`
forever. `monochrome_note_camera.gd:46-53` sums a camera offset per lane
in that state, so Monochrome's camera drifted off-centre and stayed
there. `_release()` is already self-guarding - just call it.

**A runtime Control parented to a song root is in canvas layer 0.** Song
roots are plain `Node`s, so a Control added to one sits in the default
canvas, *below* `UILayer` (a CanvasLayer: layer 1, and **6** in
Monochrome). `UILayer/GameUI` is a full-rect Control on the default
`MOUSE_FILTER_STOP`, so it swallows every GUI touch first. Note tapping
survived that (it runs off `_input()`, which precedes GUI), but the
overlay's own red mechanic `Button` is picked through GUI and so could
never be pressed - the pendulum was unplayable in Touch mode. Parent
runtime touch UI to `UILayer`, like every authored touch control already
is.

**`find_children("*", "Button")` does not see a Control.**
`ChimeraEscapeDPad extends Control`, so the overlay's "every visible
Button is reserved" sweep missed it and a tap could drive the pad and hit
a note at once. The overlay has a `reserved_controls` export for exactly
this - but nothing populated it (the song scenes set `reserved_controls`
on the *MobileControls* node, not on the overlay). The applier now copies
that array over and appends the D-pad.

**`Settings.applied` fires on every single option row.** Anything hooked
to it that walks a scene tree runs on every keypress in the console - and
the Collector's Shop tree is enormous. Guard scene-walking appliers on
"is this actually a song" (`UILayer/GameUI/Player` exists) and do one
walk, not one per node you are looking for.

---

## The Hacks tab has a joke code

`hacks_tab.gd`'s `CODES` dictionary is real cheat codes (unlock a song,
Showcase, the speed hack). `PRANK_CODE` (`"GODMODE"`) is not one of them -
checked first so it never falls into "Invalid code.", sets no `SaveData`
flag, so it can be entered over and over. The bit is typing the most
mythical cheat code in gaming and getting a fart sound instead: it plays
`sfx_wet_disguisting_fart.mp3`, already in the project and already used by
the ShittyGPU screen, and prints a random mocking line from `PRANK_LINES`.

`console.play_sound` only ever reached `sfx/shop/console/*.wav` -
`console_sfx.gd`'s handler had the folder and the extension hardcoded. Given
a name it can't find there, it now falls back to `sfx/misc/*.mp3` before
giving up, which is what let the fart code reuse the existing 3D-positioned
console speaker instead of adding a second, disconnected audio player just
for this.
