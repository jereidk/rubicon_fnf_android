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
  caster** - two, `MoonSpotlight` and `TvLight`. Every other scene has none,
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
- `frame` is clamped at 150ms, so `proc` is the only field that shows a real
  freeze's true size - `122_fall` reads `frame=150ms` but `proc=1878ms`.
- `orphans` climbing then **flat** -> a pool filling, not a leak
- `SUMMARY vs_first` climbing with nothing else changing -> thermal throttling
- `LOAD` checkpoints spread out -> resource loading; bunched at the end ->
  instantiation
- **`gpu=`/`cpu_render=`** are Godot's own GPU timestamp queries
  (`RenderingServer.viewport_get_measured_render_time_gpu/cpu`, one frame
  behind - not a `Viewport` instance method, confirmed the hard way against
  4.7.1). `proc` cannot tell "CPU busy building draw commands" from "CPU
  blocked waiting on the GPU" from "GDScript was slow"; a stall with `proc`
  and `gpu` both high is a real GPU-side cost (shadow atlas repack, a
  pipeline compiling), `proc` high with `gpu` flat points back at the CPU
  (skinning, culling/octree inserts, instancing).
- **`p3d_objs=`/`p3d_pairs=`** are `Performance.PHYSICS_3D_ACTIVE_OBJECTS`/
  `PHYSICS_3D_COLLISION_PAIRS` - added for the shop's physics cost (10-25x
  Chimera's, suspected `enable_object_picking`) which was flagged and never
  actually measured.
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

`frame=150.0ms` recurs because Godot **clamps delta** - real stalls can be
much worse than the log can show.

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
| `vis3d=N/M` | how much of the scene's 3D is on screen, against its total. `objs=` is the whole frame including SubViewports and cannot answer this |
| `cam=fov75@x,y,z` | where the active Camera3D is. Chimera's cost tracks the shot and no log ever recorded the shot |
| `env=glow+fog` | which per-pixel environment features are actually on. `preset=Very Low` is not evidence any of them is off |
| `mat3d=N/M` | unique 3D materials against surface count - the Peepers bug asked about 3D |
| `bones=` / `parts=N/M` | skinning load; particle systems visible and emitting |
| `psteps=N` | physics ticks *inside* this frame. 6ms across one tick is a heavy world, 6ms across four is a frame already late |
| `vp=[...]` | scaling mode/scale, msaa, aniso, mesh LOD, shadow atlas, **read back off the viewport** |
| `eng=[ts fps hz steps]` | `time_scale`, `max_fps`, physics rate, max steps |
| `focus=LineEdit:X` | the focused Control |
| `tweens=` / `msgq=` | active tweens; message-queue high-water (a `call_deferred` flood) |
| `alat=X/Yms` | audio output latency and time to next mix |

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
- VRAM: 625MB in the Collector's Shop, ~410MB in Chimera. Very high for this
  device and the likely reason loads get *slower* over a session (the same
  scene went 11.9s -> 26.6s).
- Loads: 50%->75% is where almost all the time goes, and VRAM climbs from
  ~100MB to ~540MB across it. It is texture loading.
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
(`proc=1882ms` and `373ms`, both on `122_fall`), the ~30fps ceiling from
`proc` sitting near 50ms, and loads that keep growing within a session
(shop: 13.6s first, 25.6s second) under VRAM pressure.

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

**That prewarm exists now** - `PreloadCamera` (`lullaby_preload_camera.gd`),
a `Camera3D` that makes itself current during the loading screen and plays a
`precache` animation which reveals things and sweeps 15 positions at
`fov = 120` before handing over to the real camera. It costs ~2.2s and
compiles ~90 pipelines on Chimera.

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
| Very Low | 0.50 | shadows off | 0 | off | 8.0 | x2 |

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

## Open problems

1. **Chimera's 30fps ceiling is GPU-bound** (`gpu` 38.8ms against a 38.1ms
   frame). Measured, see the performance section. The note scenes' 6
   AnimationPlayers each are a CPU cost and were the old suspect here; with
   `cpu_render` at 2.1ms and `proc` no longer the limiting number, they are not
   what holds the frame. Next step is the two-run shadows / visual-effects A/B
   described in that section - not a code change.
2. **VRAM.** Only lowering texture *resolution* helps (target 1024-2048).
   This one fix would address VRAM, slow loads, loads-getting-slower, and
   throttling together.
3. **Multi-second `proc` stalls at cutscene starts** (`104_photographysesh`,
   `114_hexapproach`, `122_fall`). Narrowed to first-draw pipeline compilation
   - texture upload, resource loading and the AnimationMixer track cache are
   all ruled out, see the `122_fall` section. The untried fix is a prewarm
   that puts just that cutscene's cast in front of an off-screen camera.
4. A **CI gate** running the `get_dependencies` sweep and failing when a
   dependency resolves by neither path nor UID. It would have caught both
   Chimera-breaking bugs before they reached an APK.
5. The **Mobile settings section** (Gameplay Control Hitbox/Touch, hitbox
   hint/gradient/opacity, mechanic hitbox direction, note layout, show pause
   button) - specified but not built. "Touch" is a whole new input mode, not
   a setting; scope it separately.
6. VSlice **y-nudge per scroll direction** - the reference distinguishes
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
