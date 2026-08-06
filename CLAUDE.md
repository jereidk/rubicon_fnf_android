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

**Godot cannot open a window here** (no GPU - it hangs, Xvfb included). Only
`--headless` works. Anything visual has to be verified another way; see
"Rendering a preview" below.

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

---

## Measured facts about performance (moto g53)

- Chimera: ~30fps, `proc` 30-50ms, `draw` **21-56**, `prims` ~23000. The GPU
  is idle. **Graphics presets cannot help**; that is why Very Low changed
  nothing.
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

## Open problems

1. **The ~50ms floor in Chimera.** Suspect: note scenes carrying 6
   AnimationPlayers each. Needs measuring before touching - it is core
   gameplay.
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

Sidebar note: the settings sidebar's VBox separation is 20 (was 84) so all
six entries fit the 640x480 console viewport - measured, at 84 the 5th
button (Misc) was already mostly off-screen and a 6th would have been
unreachable.

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
