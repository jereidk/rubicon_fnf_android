# How this port is done

This is the method, not the history. It is written for whoever picks the port up next —
including me, after a context reset. The per-piece findings live in
`animania_mod/source/README.md`; this file is *how to find them and not be wrong*.

---

## 0. The one rule

**Measure, don't derive. Then make the guard fail before believing the fix.**

Every number in this port is either read out of the mod or measured from a render. When
neither is possible, the code says so at the point of use — `NOT the mod's`, `placed by
eye`, `this is a reading`. Never launder a guess into a constant that looks measured.

And a fix is not finished when the guard passes. It is finished when you have **temporarily
reverted the fix and watched the new check fail**. The guard in this repo has agreed with a
bug at least five times, always because the check was written from the same wrong
understanding as the code. Reverting is the only thing that catches that.

```bash
cp file.gd /tmp/.../file.bak
# break it back
<run guard>          # must print FALLO
cp /tmp/.../file.bak file.gd
```

---

## 1. Where the truth lives

The mod ships three kinds of source, and they need three different tools.

| Kind | Where | How to read it |
| --- | --- | --- |
| **Data** | `assets/data/**.json`, `assets/images/**.xml` | Just read it. Exact, no work. |
| **hscript** | `assets/scripts/**.hx` | Plain text in the build. **Look here first.** |
| **Compiled Haxe** | the `Animania` binary | Disassemble. Slow. Last resort. |

The `.hx` files were missed for a long time — `tadano.hx`, `tadano-stand.hx`,
`phone-call.hx` and the song scripts are all *right there*. Before disassembling anything,
run:

```bash
find /home/user/animania_build/assets -name "*.hx" | xargs grep -ln "<thing>"
```

Only `TitleScreen`, `MainMenuScreen`, `FreeplayScreen`, `OptionsScreen`, `StoryMenu` and
their objects are compiled.

### Getting the build

The mod's Linux build is not in this repo (695 MB on disk as the tarball). The user supplies
a URL; it unpacks to `/home/user/animania_build`. **The container is ephemeral** —
`/home/user` and `/tmp` are both lost on recreation. Only committed work survives. sha256 of
`animania061-Linux.tar.gz` is
`22c804dd53b269dd3e9235ea4e2d388d39a51c1d9afe7609d48b1a950aeea677`, and the direct URL that
has worked is `https://pixeldrain.com/api/file/iq5uWdQ8`.

**pixeldrain, Google Drive and GameBanana are blocked by the default egress policy.** The
cloud environment ships at **Trusted** network access, which allows package registries and
GitHub and nothing else; every other host gets a 403 at CONNECT, recorded under
`recentRelayFailures` in `curl -sS "$HTTPS_PROXY/__agentproxy/status"`. Do not try to route
around it. Either
- have the user set the environment's **Network access** to Full or Custom — it is in the
  cloud icon above the message box at claude.ai/code, then the gear on the environment, NOT
  anywhere in Settings — and note that the network change takes effect in a RUNNING session
  while environment VARIABLES do not, because those are copied in once at startup; or
- have them attach the tarball as a GitHub release asset on this repo, which is already how
  `ref-twgusta` delivered reference material and which the Trusted list allows.

**Running the binary is not allowed** and has been refused repeatedly. Disassembling it and
reading its assets are fine and are what this port does.

---

## 2. Reading compiled Haxe (hxcpp)

The helper scripts for this live in the scratchpad, not the repo, because they are throwaway
— but they are worth rewriting each time. What they do:

```bash
nm -C --print-size Animania | grep "ClassName_obj::method("
objdump -d --start-address=0xA --stop-address=0xB -C Animania
objdump -s --start-address=0xA --stop-address=0xB Animania   # .rodata
```

`tools/animania/hxdis.py <start-hex> <size-hex>` does the filtering described below in one
step: it decodes each rip-relative load as both a NUL-terminated string and a double, prints
`call` targets demangled, and marks the `movl $0xNNN,0x..(%rsp)` Haxe line numbers. It is
committed rather than left in the scratchpad because rewriting it each session was waste.

A useful dump filters an address range for: `call` targets, rip-relative loads (decoded as
both a double and a NUL-terminated string), and stores to `(%rbp)`/`(%rsp)`. Line numbers
appear as `movl $0xNNN,0xNN(%rsp)` — those are Haxe source lines and they group statements.

### Things that will catch you out

**`Null<double>` is a 16-byte block `{flag byte, double}`.** Which stack block is which
argument is *not* visible in the caller. Read the callee: `FunkinSprite.create` does
`cmpb $0,(%rsi); jne skip; mov 0x8(%rsi),%r13` for arg 1 and the same on `%rdx` for arg 2,
and the caller loads `%rsi` from `-0x70(%rbp)` and `%rdx` from `-0x60`. So the **first block
is x**, and a flag byte of **zero** means the value is present. Getting this backwards put
freeplay's VCR in the sky.

**Strings in a static array are 16 bytes: length first, pointer second.** `_hx_array_data_*`
arrays live in `.bss` and are filled by `_GLOBAL__sub_I_<file>.cpp`. The lengths alone often
identify the names.

**Field names → offsets.** `__GetFields` pushes the names in declaration order (read each
`lea` target as a string); `__Field` returns the offsets. They do *not* zip 1:1 — inherited
fields and properties break the alignment. To name a specific offset, find the
`mov 0xOFF(%rdi),%rax` in `__Field` and read the `cmp` immediates just before it: they are
the tail bytes of the name plus its length, which is usually enough to pick one candidate
out of the `__GetFields` list.

**Read `objdump -s` output indexed by address, not by concatenating lines.** The lines start
at the containing 16-byte row, so blind concatenation is off by up to 15 bytes and silently
returns the wrong string. This misread `animania/menu/menu_switch` as
`animania/mennu_switch`.

**Eases are polynomials with their coefficients in `.rodata`.** Recovered so far:

    smootherStep(t)      = t*t*t*(t*(t*6 - 15) + 10)
    smootherStepInOut(t) = smootherStep(t)
    smootherStepOut(t)   = 2 * smootherStep(t*0.5 + 0.5) - 1
    backIn(t)            = t*t*(2.70158*t - 1.70158)
    backInOut(t)         = t2=2t; t2<1 ? t2*t2*(2.70158*t2 - 1.70158)/2
                                       : ((t2-2)^2*(2.70158*(t2-2) + 1.70158) + 2)/2
    MathUtil.smoothLerpPrecision(from, to, dt, halfLife)
                         = to + (from - to) * pow(2, -dt/halfLife)

Godot's `TRANS_BACK` matches flixel's back exactly (same 1.70158), so a Tween is fine there.
Nothing in Godot is smootherstep — write the polynomial and drive it yourself.

---

## 3. Coordinate conventions

These are settled and must not be re-litigated.

- **Funkin is 1280×720; this project is 1920×1080.** The factor is `1920.0/1280.0` = 1.5.
- **World coordinates stay verbatim. The 1.5 lives on the camera's zoom.** Anything the mod
  places against `FlxG.width/height` is a SCREEN distance and *does* get ×1.5.
- Funkin's `characterOrigin` is `(width/2, height)` — horizontal centre, vertical **bottom**.
- `Stage.applyCharacterData` adds the STAGE's `cameraOffsets` **on top of** the character
  JSON's. Forgetting this put the death camera 300px right and 150px high, twice.
- A character JSON's `frameIndices` counts the **atlas's** frames. The sparrow importer
  dedups runs of identical frames into one held longer, so those indices do not address the
  imported list. Key one frame per *atlas* frame, each showing whichever imported frame
  covers it by running duration. See `_window` in `build_character_scenes.gd`.

### Text: which face it is, and why `modulate` gives you nothing

Two kinds of lettering, and the disassembly does **not** tell them apart.

- **TTF.** `setFormat("VCR OSD Mono", 32, ...)` — the size rides in the high half of a packed
  `Null<int>`, so it reads as `movabs $0x2000000000`, never as a plain `32`. The port has
  `VCR OSD Mono Cyr.ttf`, which is a few percent narrower for the same cap height; a string
  ending 5px short of the reference is that, not a placement error.
- **Sparrow bitmap.** `assets/images/fonts/` holds `default`, `bold`, `alphabet-white` and
  `freeplay-clear` as png + xml, one SubTexture per character (punctuation spelled out:
  `-period-`, `-question mark-`). `AtlasText` in `animania_mod/scripts/` draws these.

`StoryMenuState.create()` formats the tracklist as VCR like the other two, and the capture
shows a rounded hand-drawn face instead. All 36 fonts embedded in the executable were
extracted and rendered — none of them is it; `default` matches the capture stroke for
stroke. **Trust the capture over the call.**

To tell which one you are looking at, composite the word out of the atlas at a trial scale
and stack it against the reference crop. Two words fix the scale on their own: the glyph
regions add up (`"DadBattle"` = 289px of atlas for 185px on screen, `"Bopeebo"` 223 for 144,
both 0.64), which also proves the letter spacing is zero.

**`default.png` is solid black.** Every opaque pixel is `(0,0,0)`; the mod tints it by
*adding* (`assets/scripts/shaders/AddColorShader.hx`), and Godot's `modulate` *multiplies*.
Black times pink is black, so the first run of `AtlasText` laid out twenty-one glyphs, every
check on them passed — in the tree, visible, right region, right position — and the box
stayed empty. Rebuild the sheet once with the RGB forced to white and the alpha kept, then
modulate.

### Not all of the mod is compiled

**Before reverse-engineering a screen's behaviour, look for its HScript.** The
mod ships `assets/scripts/**` AND loose `.script` files under `assets/data/`,
and the compiled state loads them by name: `LoadingState`'s constructor calls
`HScriptsHandler.getScript("data/loadingScreen")` at 0x36c6566 and then hands it
`onLoadParams`, `onCreateBG`, `onUpdate`, `onLoaded` and `onUpdatePost`. The file
is `assets/data/loadingScreen.script`, it is Haxe source, and it decides which of
the five loading backgrounds is used and what each one does. That is a table you
can read in ten seconds against an afternoon of disassembly — and the
disassembly could not have produced it, because none of it is in the binary.

The tell is in `create()`: a key built as `"loadingScreen/funkin" + this.field0x100`
where nothing in `create()` ever writes 0x100. A field the function reads but
never sets comes from somewhere, and `__construct` says where.

### The loading screen

`funkin.ui.transition.LoadingState` at 0x36c7d40 (`create`), 0x36c27a0
(`updateOnLoadingNoodlePosition`) and 0x36c2c00 (`onLoaded`), plus
`assets/data/loadingScreen.script` for everything per-song. It is a SUBSTATE in
the mod, and a scene of its own here: `animania_mod/menus/loading/`, entered
through `LoadingScreen.go_to(tree, scene, song_id)` — statics, because
`change_scene_to_file()` takes no arguments. Both the story menu and freeplay go
through it instead of switching to the song directly.

The background is chosen by **song id**, not by level and not by stage, and two
of the five do more than swap the art: winter-horrorland drops the music's pitch
to 0.1 and goes black, dadbattle swaps the whole track. Both hide the box, BF and
the noodle, so on those screens there is no progress bar at all.

Godot has no `clipRect`, and it does not need one: a `Sprite2D` with
`region_enabled` and `centered = false` reveals its strip left to right exactly
as flixel's does, so the noodle's `region_rect.size.x` IS the progress bar.

Two things about reading `create()` that are worth keeping:

- The FunkinSprite constructor takes its position as two `Dynamic`s, and in the
  call they land in **rdx = X, rcx = Y** — settled by longNoodle, whose 671.65
  can only be the y of a 720-tall screen.
- `setFormat`-style integer arguments ride in the high half of a packed
  `Null<int>`, so a size of 32 disassembles as `movabs $0x2000000000`. Grepping
  for `$0x20` finds nothing.

And one that is a warning: **an address you can read is not a field you can
name.** `create()` writes 0.4 into field 0x260 of three sprites and 0.7 into a
fourth's. It is not `alpha` — `FlxSprite::set_alpha` writes 0x148 — and no
`set_*` in FlxObject or FlxSprite touches 0x260 at all. Those four writes are
left out of the port and written down in the script instead, because a guess at
what they mean would be a guess that shows on screen.

---

## 4. The build loop

Everything in `animania_mod/` and `songs/` is **generated**. Never hand-edit a `.tscn` or a
`.tres` — edit the builder in `tools/animania/` and re-run it.

This has now cost real time twice, so here is what it looks like when it goes wrong.
`phone_call.tscn`'s events exports were renamed BY HAND to match a script rewrite. The
rename dropped `flash` and `fade_rect` entirely, so the song's closing fade was dead;
it added three exports to `DeathSequence`, which does not declare them; and it left
`build_level_scene.gd` writing the old names, so the builder could no longer reproduce
the scene it was supposed to own. Separately, `story_menu.tscn` carried a hand-written
`PackedFloat32Array([-225, -190])` — the inner array literal is valid GDScript but a
**parse error in the .tscn format**, and it took the whole story menu down on the
device. Godot's own serializer writes `PackedFloat32Array(-225, -190)` and never
produces the broken form; only a human does.

```bash
G=/tmp/godot_bin/Godot_v4.7.1-stable_linux.x86_64      # not on PATH; re-download if gone
run() { timeout 400 xvfb-run -a --server-args="-screen 0 1920x1080x24" "$G" "$@"; }

run --headless --path . --script tools/animania/build_character_scenes.gd
run --headless --path . --script tools/animania/build_level_scene.gd       # slow, ~2 min
run --headless --path . --script tools/animania/build_main_menu.gd
run --headless --path . --script tools/animania/build_freeplay_scene.gd
run --headless --path . --script tools/animania/build_title_scene.gd
```

Rendering needs a real driver: add `--rendering-driver opengl3` and drop `--headless`.

### Autoloads are invisible to every builder and guard

Godot does **not register autoloads under `--script`**, which is how every
builder in `tools/animania/` and both guards run. A script that names one there
fails to **compile** — `Identifier not found: AnimaniaModule` — and the failure
cascades in a way that is easy to misread:

- The builder cannot `load()` the level's scripts, so it cannot set their
  exports. It still prints `OUT saved`, having packed a scene with the scripts
  missing.
- The guard instantiates a bare `Node` whose chart methods do not exist, and
  the device then reports exactly
  `Error calling deferred method: 'Node::snap_camera': Method not found.`

So shared gameplay goes behind a **`class_name`**, never an autoload identifier.
`AnimaniaModule` is a class_name for this reason, and `song_events.gd` owns the
instance — which also means its lifetime is the level's, so `first_time()`
guards and the combo counter cannot survive a death retry.

Where an autoload has to stay (`MusicFilter`), reach its statics through a
**preloaded const** instead of its name:

```gdscript
const MusicFilterScript := preload("res://animania_mod/scripts/music_filter.gd")
if MusicFilterScript.instance:
	MusicFilterScript.instance.reset()
```

Same object at runtime, and it compiles under `--script`.

**After adding a `class_name`, re-run `--import`.** The global class cache is
written by the import, and until it is the new name does not resolve: you get
`Could not resolve class "res://.../song_events.gd"` from every script that
extends it, which reads like a broken file rather than a stale cache.

### The guards never put the level in the tree

Both guards drive the level from a `SceneTree` script's `_init()`, where `root`
is not yet in the tree. An instantiated level therefore **never enters it**, so
neither `_enter_tree()` nor `_ready()` ever fires. Anything a chart event needs
has to be built in `_init()` or wired lazily on first access — `song_events.gd`
does both: the module is constructed in `_init` and reads this node's exports
the first time `module` is touched. Wiring it from `_ready` instead leaves the
module holding nulls, every chart event no-ops, and the guard passes on nothing.

### Builder traps

**A builder that loads a saved resource, adds to it and saves it back will skip its own
work** if it guards with `if has_animation(x): return`. The previous run's version is loaded
*with* the resource, so the rebuild reports success and changes nothing. This has happened
twice — `AdobeAtlas.parse()` short-circuiting to `animation_cache.res`, and `_window`
skipping an already-present animation. **Delete and rebuild, never skip.**

**A GDScript runtime error does not stop a `--script` run.** The erroring function is
abandoned and the caller carries on — so a builder can print "saved" having built half a
scene, and a guard can print "todo OK" having skipped the section that would have failed.
Guards therefore count their checks (`MIN_CHECKS`), and builders should be read for
`SCRIPT ERROR` in the output, not just for the success line.

**A builder that suddenly takes minutes is an ERROR, not slowness.** The erroring function
is abandoned before its `quit()`, so the SceneTree never exits and the run hangs to the
timeout. The usual cause is vendoring a new asset and not importing it — `load()` returns
null, the builder dies, and you wait 400 seconds to find out. So:

```bash
run --headless --path . --import            # ALWAYS, right after vendoring anything
```

And do not pipe a builder's output through `grep` until it has succeeded once: the grep
throws away the very error you need. Read the tail of the raw output instead.

**Not every builder owns its whole scene, and re-running one can DELETE work.**
`build_story_menu.gd` only rebuilds the `Titles` children: it loads the saved
scene, replaces those, and saves. Everything else in `story_menu.tscn` was put
there by hand or by an older pass — the chroma-key ShaderMaterial and the
`easy`/`normal` difficulty textures among it — and a rebuild drops all of it,
because the builder never writes it back. So "never hand-edit, re-run the
builder" holds only where the builder actually reproduces the file. Before
re-running one, diff its output against the committed scene and look at what
DISAPPEARED, not just at what changed.

**`queue_free()` does nothing inside a `--script` builder.** The deferred queue
is never pumped, so a child freed that way is still there when the scene is
packed and the rebuild APPENDS to what it meant to replace — the story menu
came out with every week twice. Use `remove_child()` + `free()`.

**Godot drops a `connect()` without `CONNECT_PERSIST` when a scene is packed.**

**Set `layout_mode`/`size` on a Control before `position`**, or the position is lost.

---

## 5. The guards

Two, and both must pass before any commit:

```bash
run --headless --path . --script tools/animania/test_phone_call_port.gd   # 853 checks
run --headless --path . --script tools/animania/harness/flow_check.gd     # the whole flow
```

**Know the baseline before you read a result.** "The guard fails" is not news
here; what matters is whether it fails MORE than it did. Measured on 4.7.1:

| commit | result |
| --- | --- |
| `9cea727` — last one where `song_events.gd` parsed | 853 run, **26 fail** |
| `58efadd`, `c54f5e4` | 643 run — duplicate `fade_in_nodes`, parse error |
| `5f8f6a7` (the autoload restructure) | 646 run — autoload unresolvable |
| this commit | 853 run, **23 fail** |

The 23 are the port's unfinished work — character swap, lane fly-in, strumline
pulse, the standing death — not a regression. To compare against an older
commit, use a worktree and give it its own import rather than checking out over
your tree:

```bash
git worktree add /tmp/baseline <commit>
cp -a .godot /tmp/baseline/.godot        # then re-import: the class cache is yours, not its
$G --headless --path /tmp/baseline --import
```

Do **not** try it with `git stash` + `git checkout <commit> -- .`: the checkout
writes the old tree into the INDEX too, and popping the stash then conflicts
against work that is only in the stash. Recovering costs more than the worktree.

`flow_check` walks title → main menu → freeplay → song, and the death retry. It is the only
place a scene *change* is exercised, which is why it catches things an instanced-scene
harness cannot.

The one-off harnesses in `tools/animania/harness/` render a moment so it can be looked at:
`menu_shot`, `menus_shot` (story and pause), `freeplay_shot`, `death_shot`, `level_shot`,
`health_bar_shot`, `lane_glow`, `standup_frame`, `opening_shot`, `sing_sheet`,
`measure_character`, `measure_title`.

**Render every screen you build, before saying it is done.** Passing guards say a screen
*works*; only a render says it *looks right*. Two screens went in on guards alone and the
first render of them found the story list sitting well above centre. It costs one command.

A harness that shoots the pause menu has to set `process_mode = PROCESS_MODE_ALWAYS` on
itself: the pause pauses the tree, and a harness that stops with it never takes the picture.

### Harness traps

- **`get_viewport().get_texture()` is the LAST frame drawn.** Under xvfb a frame can take
  half a second, so a capture taken in the same frame as the state change is a picture of a
  different moment. Queue the save for the *next* frame.
- **Drive off the scene's own clock, not a second one accumulated in the harness.** Two
  clocks counting the same frames disagree badly when frames are slow.
- **`get_viewport().get_visible_rect().size` is the LOGICAL size (1920).** The window is
  1365. Dividing by the wrong one shrinks every fraction by 0.711.
- **Tweens run on REAL time.** Winding a clock at `speed_scale = 20` leaves them behind;
  flush with `custom_step(10.0)` then `kill()`.
- **Headless outruns SceneTree timers** if you wait by accumulating
  `get_process_delta_time()`. Wait in wall clock with `Time.get_ticks_msec()`.
- `reload_current_scene()` only works when the scene under test *is* the running scene, so
  that check belongs in `flow_check` and nowhere else.

---

## 6. Adding a song

The phone-call pipeline is bespoke, so this is the shape rather than a script:

1. **Read the metadata** — `assets/data/songs/<id>/<id>-metadata.json` names the characters,
   the stage, the note style, the difficulties and the BPM/time-signature map.
2. **Characters** — one `assets/data/characters/<name>.json` each (sparrow or multisparrow
   or Adobe), plus the atlas. Build with `build_character_scenes.gd`; the animation table is
   `{ rubicon_name: [atlas_prefix, offset] }` and a third element is a frame window.
   `assets/scripts/characters/<name>.hx` carries anything scripted.
3. **Stage** — `assets/data/stages/<name>.json`: props with positions, scale, scroll factors
   and z-order, plus `cameraOffsets` per character slot.
4. **Chart** — `<id>-chart.json` is Funkin V2: notes in ms with `t`, `d`, `l`, and events
   with `t`, `e`, `v`. Convert to Rubicon's chart resource; the difficulty is a top-level
   key in `notes`.
5. **Audio** — `assets/songs/<id>/Inst.ogg` and `Voices-*.ogg`. Vendor under
   `animania_mod/source/music/` or `songs/<id>/`.
6. **Song script** — `assets/scripts/songs/<id>.hx` is the modchart and event handling.
7. **Wire it** — add an entry to `SONGS` in `animania_mod/menus/freeplay/freeplay_screen.gd`
   and vendor its disk art from `assets/images/animania-freeplay/disks/<name>.png`.
8. **Guard it** — a section in `test_phone_call_port.gd`'s shape, and a `flow_check` walk.

---

## 7. Standing constraints

- **Never push to a branch other than the one the user named.** All work is on
  `animania-port`.
- **`git push` for LFS is blocked** — `lfs.github.com` gets a 403 at CONNECT from the
  environment proxy. This repo has no LFS, so it does not bite; do not try to work around it.
- **Never delete an asset because it looks orphaned.** The repo has been broken by that at
  least three times.
- **`pkill -f <pattern>` can match and kill your own shell** — and so can
  `ps | grep <pattern> | kill`, because the running command's own line contains the pattern.
  A restore that follows the kill in the same chain then never happens, and the working tree
  is left mid-experiment. Kill by a PID you have already printed, in its own call.
- The harness **blocks chained `sleep N; cmd`**. Use `python3 -c "import time;time.sleep(N)"`
  alone, or run in the background.
- **Artifact downloads are blocked.** Builds are triggered with
  `mcp__github__actions_run_trigger` on `android-build.yml` (always `--export-debug
  "Android Debug"`); the user downloads the APK from the Actions run page themselves.
- **Texture budget is a real constraint.** The device already runs the song at 41 fps. A
  5492×8192 RGBA atlas is ~180 MB uncompressed — freeplay's `TVBACK`/`TVNOISE` were left out
  for exactly this reason. Check atlas dimensions *before* vendoring.

---

## 8. What is deliberately not ported

Recorded so the next person does not go looking for a bug that is not there.

- **The modchart's `tanWave`.** The formula is recovered exactly —
  `x += clamp(tan(p·π), −6, 6) · 40 · value` — but `p`'s unit is unidentified, so porting it
  would be guessing the sway's scale.
- **Freeplay's `TVBACK` and `TVNOISE`** — texture budget, see above.
- **The main menu's mouse furniture** — `newsButton`, `musicSocial`, `socialButtons`,
  `updateCameraScroll` (mouse parallax), `spawnHelpMouseText`. All inert on Android.
- **The credits' character.** The roll is there - all 36 people and their roles, out of the
  mod's own `data/credits.json` - but not the portraits, the typed-out text with its
  per-entry speed and pitch and its embedded `<img>` tags, the social buttons or the
  stickers. Those want the mod's bitmap fonts, which the port does not have yet.
- **A guard that asserts "how far did this get in N frames"** is a guard that fails the day
  the walk gets a heavier scene to load before it. The menu's curtain check did exactly
  that. Assert the RANGE the thing moves through, not a threshold read off one run.
- **The retry's `StickerSubState`.** Funkin returns to `PlayState` through a sticker
  transition; the port reloads the level instead and says so at the point of use.

---

## 8b. Adding a song, for real

The pipeline exists now and `tutorial` came out of it end to end. For a new song:

```bash
# 1. vendor: data/songs/<id>/<id>-{chart,metadata}.json -> animania_mod/source/songs/<id>/
#           songs/<id>/*.ogg                            -> songs/<id>/
#           data/stages/<stage>.json + its art          -> animania_mod/source/{data,images}/
run --headless --path . --import                       # ALWAYS, or the next step hangs
run --headless --path . --script tools/animania/build_song_chart.gd  -- <id>
run --headless --path . --script tools/animania/build_stage_from_json.gd -- <stage>
# 2. characters: add a _build_adobe_character(...) line, MEASURE the origin, rebuild
run --headless --path . --script tools/animania/build_character_scenes.gd
run --rendering-driver opengl3 --path . res://tools/animania/harness/measure_character.tscn
# 3. the level
run --headless --path . --script tools/animania/build_song_scene.gd  -- <id>
run --rendering-driver opengl3 --path . res://tools/animania/harness/song_shot.tscn
```

Then add it to `SONGS` in freeplay and to `SONG_SCENES` in the story menu.

Three things that bit while building this:

- **The addon's script paths are not what they look like.** The song module is
  `rubicon_level_song.gd`, not `rubicon_song_module.gd`. A wrong path is a runtime error,
  which abandons `_init` before its `quit()` - the build then hangs to the timeout printing
  nothing at all, not even the banner. Instrumenting with prints found it in one run.
- **The interpolated camera does not draw from `position`.** It eases toward
  `position_interpolate_target` / `zoom_interpolate_target`. Set only the position and the
  shot comes out framing whatever the script starts on; set both, to the same value, so it
  opens there instead of sliding in.
- **A character with no `level_note_controller` plays NOTHING** - not its sing animations
  and not even its idle. RubiconCharacter subscribes to `note_changed` and to the clock's
  `step_change` through it. Both of tutorial's stood frozen with an empty
  `current_animation`, and it read as "the camera does not follow the singer" because the
  singer was never singing.
- **Animania's `tutorial` chart has zero notes** in all three difficulties. Do not go
  hunting for why nobody sings in it: there is nothing to sing. Use `bopeebo` to exercise
  singing and the camera.
- **EVERY stage has a `.hx` that overrides its JSON**, at `scripts/stages/<name>.hx`. This
  port only knew about phoneCallStreet's and did not go looking for the rest until
  serviceEnterance drew an opaque pink sheet over the whole song - its script tweens that
  prop's alpha 1<->0.5 on a pingpong, and without it the stage is invisible. Read the `.hx`
  before believing the JSON. Their FlxBackdrops, shaders and ambience are NOT ported.
- **A stage prop's `alpha` and `blend` are easy to miss** because most props carry neither.
  mainStageAmTake's two vignettes carry both - `alpha: 0` on one, `alpha: 0.8` plus
  `blend: multiply` on the other - and ignoring them drew two opaque sheets at zIndex 317,
  over everything. Half the stage came out black.
- **A prop that says `animType: sparrow` may still be a bare PNG** with no atlas beside it
  (the wall, the posters, the floor, the vignettes). Fall back to drawing it whole rather
  than skipping it.
- **A chart's camera events are most of what a song looks like.** dadbattle authors 98 of
  them (42 focus moves, 40 zooms, angles, shakes, bars); ignoring them leaves the camera
  sitting still for the whole song, which is what "it is missing a LOT" turned out to mean.
  `song_camera_events.gd` bakes them for any song - phone-call keeps its own baker, which
  hardcodes 152 BPM and carries that song's script beats. Funkin measures an event's
  `duration` in STEPS (a sixteenth of a beat), not seconds, and the event's x/y are
  world-space so they are NOT scaled by the 1.5.
- **A Control with anchors set refuses `size`.** Godot logs "If you want to set size,
  change the anchors" and drops the write, so an animation track that writes `size` on an
  anchored Control does nothing. The cinematic bars were built with `PRESET_TOP_WIDE` and
  their whole baked track was inert. The guard said OK; only the printed error gave it
  away - which is why a run's raw output is worth reading even when it passes.
- **A shake goes on the camera's OFFSET, not on its target.** `position_interpolate_offset`
  is a separate property, so a shake and a focus move can happen at once without one eating
  the other - which is what FlxCamera.shake does. Its `intensity` is a FRACTION of the
  camera's size, not pixels, so it is against Funkin's 1280 and is not scaled.
- **Two things must not drive the camera at once.** With events baked onto the clock, the
  follow-the-singer fallback writes the same two properties every frame and they fight -
  so the builder turns it off for a song whose chart has events.
- **A note controller with a chart and no Lane children draws nothing.** It reads on screen
  as "the strumlines are off-frame".

## 9. Dadbattle: where it stands

Started, not finished. What is **in the repo and done**:

- `animania_mod/source/songs/dadbattle/` — the V-Slice chart and metadata, the three song
  scripts (`chromaticAbberation`, `reflections`, `saygex`), `dadbattle.hx`, and the
  **converted** Rubicon charts: `Meta.tres` plus `dadbattle-{easy,normal,hard}_{Player,
  Opponent}.tres`. Three difficulties where phone-call had one — the first chart to
  exercise that path. Rebuild with `tools/animania/build_dadbattle_chart.gd`.
- `songs/dadbattle/` — `Inst.ogg`, `Voices-bf.ogg`, `Voices-dad.ogg` (21 MB; the `-easy`
  and `-normal` bf vocal variants were left out until a difficulty selector exists).
- Its disk art, and an entry in freeplay's `SONGS`. The scene does not exist yet, so
  `confirm()` gives it the locked sound — no special case needed.

What is **left**, in the order it has to happen:

1. **Three characters, all Adobe Animate atlases** (`build_adobe_character.gd`, not the
   sparrow path): `bf` is `multianimateatlas` at `shared:characters/amtake/bf/bf-classic`
   with **51** animations; `gf` is `animateatlas` at `.../gf/gf-standart`, 23; `dad-beast`
   is `.../dad/BEAST_DEAREST`, 19. This is the long pole by a wide margin.
2. **The `serviceEnterance` stage** — `assets/data/stages/serviceEnterance.json`, through
   `build_stage_scene.gd`.
3. **The note style is `amtake-base`**, which the port already has from phone-call.
4. **The level scene.** `build_level_scene.gd` is written for phone-call specifically — the
   camera baking, the events script and the death sequence are all its. Generalising it is
   part of this step, not an afterthought.
5. Point freeplay's `dadbattle` entry at the scene once it exists. Nothing else changes.

The metadata to work from: player `bf`, girlfriend `gf`, opponent `dad-beast`, opponent
vocals `dad`, stage `serviceEnterance`, note style `amtake-base`, album `expansionMini`,
difficulties easy/normal/hard.
