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

- `proc` high, `draw` flat -> CPU/script
- `draw`/`vram` high -> GPU
- **`frame` high but `proc` low -> engine-side work** (instantiation, texture
  upload). `TIME_PROCESS` only measures GDScript `_process`.
- `orphans` climbing then **flat** -> a pool filling, not a leak
- `SUMMARY vs_first` climbing with nothing else changing -> thermal throttling
- `LOAD` checkpoints spread out -> resource loading; bunched at the end ->
  instantiation

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

## Open problems

1. **The ~50ms floor in Chimera.** Suspect: note scenes carrying 6
   AnimationPlayers each. Needs measuring before touching - it is core
   gameplay.
2. **VRAM.** Only lowering texture *resolution* helps (target 1024-2048).
   This one fix would address VRAM, slow loads, loads-getting-slower, and
   throttling together.
3. **Multi-second `proc` stalls at cutscene starts** (`104_photographysesh`,
   `114_hexapproach`) - separate from the note pool, still unexplained. The
   now-working `SPIKE ... after X` attribution should name them.
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

## Working agreements with the user

- Spanish. Direct. They catch real problems - "el restore key no tiene la
  culpa", "revertamos ese cambio", "VSlice no aplica nada" were all correct
  and all saved time.
- They run the builds; ask before triggering one.
- They will say when something is urgent. As of this session the only urgent
  thing is Chimera stuttering.
