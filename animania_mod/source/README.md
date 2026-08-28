# Animania 0.6 - source slice for the `phone-call` port

Not the whole mod. This is exactly what the `phone-call` song needs, lifted
verbatim out of `animania061.zip` (696 MB, sha256
`9458367d7cf69f44d5dcdfcb4bf68b7086ff7956cb2148d139699972f52d8f3f`) so the
port has its reference material in tree instead of on somebody's disk.

## Why this song

Animania 0.6 is mostly a **reskin**. Its four levels are:

| level | visible | songs |
|---|---|---|
| `tutorial` | yes | `tutorial` |
| `week1` "DADDY DEAREST" | yes | `bopeebo`, `fresh`, `dadbattle` |
| `week5` "RED SNOW" | yes | `cocoa`, `eggnog`, `winter-horrorland` |
| `KomiCantCommunicate` | **no** | `phone-call` |

The seven visible songs are base-game Funkin'. What the mod adds on top is
art, characters and a note style. Its own week is marked `"visible": false`
and holds one song, which is this one - so `phone-call` is the only original,
complete thing it has, and the smallest end-to-end slice worth proving.

`manager` is a second original song, but it is in no level and its metadata
says `generatedBy: v0.5.1 DEVELOPER`, so it is dev content, not shipped.

## What is here

    songs/phone-call/     chart, metadata, the song's own .script, subtitles
    songs/audio/          Inst.ogg + Voices-komi.ogg + Voices-tadano.ogg
    images/phoneCallStreet/   stage art
    images/phonecall/     komi and tadano
    scripts/              phoneCallStreet.hx + characters/*.hx
    data/                 phoneCallStreet.json (prop layout)

Not here: `scripts/notestyles/amtake-base.hx`. It belongs with this slice and
is read from the archive when needed.

## Facts the port depends on

Measured from the files, not assumed:

- **362 notes, one difficulty (`standart`)**, 180 of them holds (24.7ms to
  1480.3ms), spanning 12.3s to 129.5s.
- **`d` is a lane AND a side.** 0-3 opponent, 4-7 player; the lane is `d % 4`.
  The split here is 167 / 195. Reading `d` as a plain lane silently moves 195
  notes to the wrong strumline and the song plays itself.
- **`k` (note kind) is an empty string for an ordinary note** - 360 of the 362.
  It must not become a note type named `""`.
- One time change: **152 BPM, 4/4**.
- 103 events, seven types: `FocusCamera`, `ZoomCamera`, `AddCameraZoom`,
  `SetCameraBop`, `CinematicBars`, `PlayAnimation`, `SetProperty`.
- **Vocals are split per character** (`Voices-komi` / `Voices-tadano`), which
  is a V-Slice feature. Whether Rubicon can play two vocal tracks against one
  instrumental is still unverified and is the first real risk in this port.

## Provenance

Animania is somebody else's work and its source is not published. This slice
exists to port it, and the port needs the mod team's blessing to be shared.

## The port so far: stage and characters

Built by the four scripts in `tools/animania/`, all of them re-runnable, and
pinned by `tools/animania/test_phone_call_port.gd`. Nothing here was authored by
hand: the scenes are packed from the mod's own JSON and XML, so re-exporting the
mod and re-running the tools moves the port with it instead of leaving hand-typed
numbers to drift.

    animania_mod/characters/chr_komi.tscn      sparrow, 8 root animations
    animania_mod/characters/chr_tadano.tscn    Adobe Animate, 22
    animania_mod/stages/stg_phone_call_street.tscn
    animania_mod/scripts/phone_call_leaves.gd

### Four conversions, and why each one is what it is

**Coordinates stay in Funkin's 1280x720 space.** This project is 1920x1080, so
the same framing needs 1.5x - and that 1.5x lives on the level camera, not on the
scenes. Baking it into the art would resample every sprite and make every number
in the scene un-diffable against `phoneCallStreet.json`, which is the property
that lets the guard re-derive its expectations from the source instead of
carrying a copy. The stage's own `cameraZoom` (0.65) rides on the root as
metadata; the camera's zoom is `1.5 x cameraZoom`.

**A character is anchored by its feet, not its corner.** `Stage.addCharacter`
places a character at `stagePosition - characterOrigin + offsets`, and
`characterOrigin` is `(width / 2, height)` - horizontal centre, vertical
**bottom**. That anchor is baked into each character scene's sprite `position`,
so placing one is just `marker.position + the character JSON's offsets` and
nothing downstream has to know the rule. The first render of this port skipped
it and put komi three quarters of her own height below the pavement, which is
what the render caught and no amount of reading would have.

komi's size is the sparrow frame of `idle0000` (307x776 in `komi.xml`). tadano is
an Animate atlas with no authored size at all - gdanimate draws it out of a
symbol tree - so its bounds were **measured by rendering it** and counting opaque
pixels (`tools/animania/harness/measure_character.gd`). Re-measure if the art
changes; do not nudge it by eye.

**Funkin negates a per-animation offset** (`offset.set(-x, -y)`), so komi's seven
authored offsets are negated in the root animation library. The sign is invisible
on `idle`, which is (0, 0), and doubles the error on everything else. tadano
authors no per-animation offsets, so every one of its root animations keys the
offset back to zero.

**`zoomFactor` has no Godot equivalent, and only its extreme is ported.** Two
props are authored at 0 - `overlay-all` and `introText` - which means "the camera
zoom does not reach this", i.e. screen space, i.e. a `CanvasLayer`. That is
ported exactly. `bushes right` at 0.9 is a partial exemption with no clean
equivalent; it is built at 1.0 and called out rather than faked.

### Where the .hx overrides the .json, and the script wins

`phoneCallStreet.json` is the layout and `phoneCallStreet.hx` is what
`buildStage()` does to it. They disagree in four places:

| | |
|---|---|
| `lightShade` | scroll becomes (0, 1), not the JSON's (0, 0.5); blend NORMAL, alpha 0.1, `scale.x = 1882.6 * 3`, height doubled. `light.png` is **1x1741** - a one-pixel vertical gradient column - so those scales *are* the prop |
| `overlay-all` | ships with `shouldDraw` off and the script turns it on. `"blend": "add"` at alpha 0.01 over the whole screen: a ~2.5/255 lift, and the first thing to measure if this song is ever fill-rate bound on a phone |
| the six `stand-` props | hidden by name in `buildStage()`. Built here as authored and shipped `visible = false` rather than dropped, so the scene stays diffable against the JSON |
| the sky | not a prop at all - an `FlxBackdrop` added in code, repeating on X (`FlxAxes` `0x01`), drifting at 20 px/s, at scroll 0.1 and scale 1.2. A `Parallax2D` with `repeat_size.x` set and `autoscroll.x = 20` |

The sky texture is not seamless, so its tile edge is visible if you zoom far
enough out. It is not reachable in game: one tile is 4243 world px and the song's
camera never shows more than ~1970, so the seam is always off screen. The same is
true of the original's `FlxBackdrop`.

### The one place the port deviates on purpose

`introText` ships **hidden**, against its authored `alpha: 1`. Nothing in the
data Animania ships ever turns it off - no chart event names it, and
`phoneCallStreet.hx` does not touch it - so the mod's own PlayState must, and a
989x750 title card looping over the whole song is clearly not what plays.
Shipping it on would be a visible bug. Whatever level scene is built for this
song switches it on for as long as the intro lasts.

### Characters

Both are `rubicon_character.gd` with the same shape as `bf.tscn`: a root
`AnimationPlayer` whose animations dispatch a clip on the sprite's own player and
key the sprite offset.

| | komi | tadano |
|---|---|---|
| art | sparrow, 7 animations x 15 frames | Adobe Animate, 21 symbols |
| `danceEvery` 1 | `dancing_measure_step = 0.25` (4 / (4 x 4)) | same |
| `singTime` | `singing_sing_to_dance_interval = 8` | 6 |
| `loopHoldFrame` 2 | `singing_repeat_loop_point = 2/24` | same |
| miss animations | **none**, so `miss_*` map onto `sing_*` - which is what Funkin does anyway when `<anim>miss` is absent | its own, plus a full `-alt` set |
| `flipX` | no | yes, as `scale.x = -1` on the node rather than on the art |

**komi has no miss art and that is not an omission.** She is the opponent, and
`SetProperty boyfriend.idleSuffix = "-alt"` at 65.5s is what pulls tadano's whole
`-alt` set into play for the second half of the song.

The `-chart.json` also asks for `endAnimation` on the player and `endConv` on the
opponent at 132.2s, and **neither exists on these two characters**. They are on
`tadano-stand` / `komi-stand`, the standing variants whose atlases carry `end`,
`endkun` and `komigameover`. The song swaps characters near the end; that swap is
not ported yet.

**Frame durations are the trap in the sparrow path.** The importer dedups
identical consecutive regions and carries the time in `frame_duration` - komi's
15-frame `idle` becomes 4 frames held for [2, 2, 2, 9]. The
`spriteframes_keyframer` addon ignores that: it lengths the animation by the
*deduped* count and drops a key every `1/fps`, so `idle` would come out 0.167s
long and play four times too fast. The addon's own source says as much
("temporary until frame duration usage is fixed") with the correct version
commented out beside it. `build_sparrow_character.gd` keys off the running
duration total instead, and every komi animation comes out at exactly 0.625s.

Every tadano symbol's length matches the frame-label duration on the main
timeline of `Animation.json` exactly (idle 15, miss 30, intro 178, deathStart 99,
deathLoop 101), which is the independent check that the symbol mapping is right -
gdanimate falls back to the *stage* symbol for a name it cannot find, so a typo
draws the wrong character rather than nothing. The guard pins every name against
the symbol dictionary for that reason.

`animation_cache.res` beside the atlas is gdanimate's parsed symbol tree, 47KB
against 106KB of JSON re-parsed on every load. It is generated by the build tool
and committed on purpose.

### The leaves

`phone_call_leaves.gd` is a direct port of `createLeaf`/`onBeatHit`/`onUpdate`:
three leaves from the moment the stage builds, a 10% roll per beat while there
are nine or fewer, and a leaf past y = 1550 re-randomised and put back at the top
rather than freed - so the pool never exceeds ten and nothing is instantiated
mid-song. Each leaf gets its own horizontal scroll factor (0.9 .. 1.1), which is
why each one lives under its own `Parallax2D` instead of the group sharing one.

`Preferences.lowQuality` skips the whole system in the mod. Here that is a plain
exported `low_quality` bool, because this branch has no quality ladder yet; wire
it to one when it lands rather than reading a settings autoload that does not
exist.

`beat_hit()` has to be called by whatever drives the song clock. Nothing calls it
yet - there is no level scene for this song.

### What is verified, and what is not

Verified: the scenes load, every animation track resolves, every alias the note
controller can ask for maps to a real animation, every symbol name exists in the
atlas, and the whole stage plus both characters **renders** - under Xvfb with the
GL driver, which for a 2D-only scene has none of the caveats the Lullaby branch's
3D renders carry. `tools/animania/harness/stage_shot.gd` takes the shots.

Not verified, and not guessable from here: camera framing. The song's 103 events
drive `FocusCamera` / `ZoomCamera` / `SetCameraBop` / `CinematicBars`, none of
which is ported, so the shots aim the camera at a character's midpoint plus its
`cameraOffsets` and nothing else. The stage has no ground art below the back wall
(y = 1403) - in the original the camera never looks down there either, but which
frame is correct is a question for the level scene, not the stage.

Also not ported: the `amtake-base` note style, the character swap at 132.2s, the
health icons (komi's is an animated icon with `toLosing`/`fromLosing` states
driven by `komi.hx`, and tadano's comes from a module this slice does not have),
and tadano's death sequence (`tadano.hx` tweens the HUD off screen and adds a
`tadano-phone-death-text` atlas that this slice does carry).

## The level scene

`songs/phone-call/phone_call.tscn`, built by `tools/animania/build_level_scene.gd` and
modelled on `songs/test/test.tscn` — the only worked example of a Rubicon level in this
repo. Two things about that reference are worth knowing before reading either:

- its `Lane` children have `Note N` children saved into them. Those are pooled notes the
  handler spawns at runtime that got serialised by accident. Four `Lane` nodes per side is
  the actual requirement.
- **the camera's aim is an animation track.** `RubiconLevelClock/AnimationPlayer` plays a
  `scene` animation that keys `RubiconPositionSetter:current_point`, and that is the seam
  the chart's 20 `FocusCamera` events belong in.

And one thing that changes how everything else is tested: **the clock reads its time
straight off that player's `current_animation_position`.** The animation *is* the song's
timeline — when it ends, the song ends, so its length is the instrumental's 142.152s and
not a rounded guess. It also means a harness can seek anywhere in the song instead of
waiting for it, which is what `play_level.gd` and `level_shot.gd` both do.

### Verified by running it

A full 145-second pass with both sides on autoplay:

| | |
|---|---|
| notes | **167 / 167** opponent, **195 / 195** player, all `perfect`, zero misses |
| clock | reached 142.15s — measure 90, beat 360.1 |
| script errors | **0** |
| vocals vs. instrumental | 11.6 ms (tadano) / 23.2 ms (komi) worst case |
| **vocals against each other** | **23.2 ms** worst case |

That last row is the one worth keeping. `check_for_desync()` compares every player against
`sync_reference_player` only, so two vocals drifting apart while both stay near the
instrumental is invisible to the engine — which was the open risk when the split-vocal
question was first raised. Measured, it stays well inside the 45 ms resync threshold, so
no resync ever fires and the three Vorbis `seek()`s a resync would cost never happen.

The note totals also close the loop on the converter: 167/195 is the split the V-Slice
`d`-is-lane-and-side rule predicts, arrived at independently by playing the chart.

### Four silent failures this scene walked into

Each was found by building it, and each is now pinned by `test_phone_call_port.gd`.

**`PackedScene` drops a node whose parent is inside an instanced sub-scene**, with no
error. Komi goes inside one of the stage's own `Parallax2D` nodes — `addCharacter` gives
DAD `scrollFactor (0.9, 0.95)` — and simply vanished from the first build. The fix is
`set_editable_instance(stage, true)` before packing.

**An instanced `Control` loses its authored anchors** unless `layout_mode` says to keep
them. Godot recomputes a Control's layout on reparent, and with `layout_mode` unset it
resets the anchors to zero: the health bar came out 4x27 pixels in the top-left corner
instead of the 884x18 bar across the top it is authored as. `test.tscn` carries
`layout_mode = 1` on every instanced Control for exactly this reason.

**Instancing without `GEN_EDIT_STATE_INSTANCE`** leaves a packed node with no record of
what it inherited, so `pack()` writes every property *and every connection* as if it were
local. The health bar's own `value_changed -> _on_value_changed` got authored a second
time and errored at load with "already connected", and the scene was 630 lines of frozen
copies of sub-scene properties instead of 235 lines of overrides.

**A note kind with no database entry throws once per frame, not once.** Two of the 362
notes carry the V-Slice kind `noAnimation`, Rubicon builds the key `noAnimation_mania`,
and the two paths that matter (`rubicon_level_note_handler.gd:384` and `:515`) index the
dictionary without the `has()` guard the pool prewarm at `:262` uses. Two notes produced
**911 errors** in one pass — and the stalls they caused are what pushed the vocal drift to
92.9 ms in that run, against 23.2 ms once they were gone.
`animania_mod/songs/phone_call_note_overrides.tres` gives the kind an entry.

What that override does *not* do is the half the kind is named for: in V-Slice
`noAnimation` means the note is hit but the character does not sing, and Rubicon picks the
sing animation from the **lane**, never from the note type. There is no flag on
`RubiconLevelNoteMetadata` to suppress it and no seam that is not vendored engine code.
Both notes land within 25 ms of the two `PlayAnimation` events that put komi into
`breath`, which is presumably why the charter marked them; until a character-side hook
exists, tadano sings through them.

### A landmine in the camera addon

`RubiconPositionSetter` reads only `target.position`. Its `_get_2d_global_position` looks
like it walks an ancestor chain, but `_get_node_2d_position` opens with

```gdscript
if node is Parallax2D or ParallaxBackground or ParallaxLayer:
	return Vector2.ZERO
```

which parses as `(node is Parallax2D) or ParallaxBackground or ParallaxLayer` — a class
used as an expression is truthy, so the function always returns zero. It also walks the
chain from the *setter's* parent, not the target's. The two bugs cancel into "use the
target's local position", which is correct as long as **every camera marker is a direct
child of the level root**. Parent one anywhere else and its parent's offset is dropped in
silence. Both markers here are root children for that reason.

### Still the placeholder

The camera currently alternates between the two singers on the measure, the way
`test.tscn` does. The chart's **103 camera events** — `FocusCamera`, `ZoomCamera`,
`AddCameraZoom`, `SetCameraBop`, `CinematicBars` — replace that track wholesale and are
the next pass.
