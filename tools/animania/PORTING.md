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

The mod's Linux build is not in this repo (836 MB). The user supplies a URL; it unpacks to
`/home/user/animania_build`. **The container is ephemeral** — `/home/user` and `/tmp` are
both lost on recreation. Only committed work survives. sha256 of `animania061-Linux.tar.gz`
is `22c804dd53b269dd3e9235ea4e2d388d39a51c1d9afe7609d48b1a950aeea677`.

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

---

## 4. The build loop

Everything in `animania_mod/` and `songs/` is **generated**. Never hand-edit a `.tscn` or a
`.tres` — edit the builder in `tools/animania/` and re-run it.

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

**Godot drops a `connect()` without `CONNECT_PERSIST` when a scene is packed.**

**Set `layout_mode`/`size` on a Control before `position`**, or the position is lost.

---

## 5. The guards

Two, and both must pass before any commit:

```bash
run --headless --path . --script tools/animania/test_phone_call_port.gd   # ~870 checks
run --headless --path . --script tools/animania/harness/flow_check.gd     # the whole flow
```

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
- **The retry's `StickerSubState`.** Funkin returns to `PlayState` through a sticker
  transition; the port reloads the level instead and says so at the point of use.

---

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
