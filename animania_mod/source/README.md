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

## The camera events

All 97 of the chart's camera events, baked into the level clock's `scene` animation by
`tools/animania/camera_events.gd` and pinned by the guard against the chart JSON.

Funkin drives its camera in **two stages**, and reproducing both is what makes this look
like the original rather than approximately like it:

1. an event **tweens a target** — `currentCameraZoom`, or `cameraFollowPoint` — over a
   duration, with a named ease;
2. every frame the camera **lerps toward that target** at a fixed rate
   (`FlxMath.lerp(target, current, 0.95)`, which at 60fps is a Godot
   `position/zoom_interpolate_speed` of about 3.0 — near enough to Rubicon's own default
   of 3.125 that the second stage needs no porting at all).

So only stage 1 is baked, into `position_interpolate_target` and `zoom_interpolate_target`,
and `RubiconInterpolatedCamera2D`'s own lerp does stage 2 exactly as Flixel's does. The
eases are **baked as sampled linear keys** rather than mapped onto Godot's per-key
transition exponent — a transition curve cannot express `elasticInOut` at all, and sampling
reproduces every one of them without having to argue about which is close enough.

| event | count | ported as |
|---|---|---|
| `FocusCamera` | 20 | baked `position_interpolate_target`; `INSTANT` also writes `position`, which is where the camera *is*, so it snaps |
| `ZoomCamera` | 55 | baked `zoom_interpolate_target`; `mode` is `stage` on all 55 and the value is a multiplier on the stage's own `cameraZoom` |
| `AddCameraZoom` | 12 | a one-shot punch through a method track |
| `SetCameraBop` | 3 | `RubiconCameraBumper`'s rate and amount |
| `CinematicBars` | 7 | two `ColorRect`s, heights baked with their eases |

`AddCameraZoom` being a **punch and not a setting** is the one reading that needed
deciding. The giveaway is that the first of the twelve is `0.05` at 6.5s, inside the
stretch where `SetCameraBop` has the automatic bop switched off — a manual accent where the
automatic one cannot reach. The other eleven all carry `0.015`, which is Funkin's default
per-bop game zoom, i.e. eleven extra bops on top of the regular ones.

This does **not** use `RubiconPositionSetter`. That node picks between *named* points, which
is the right shape for a level that alternates between two singers on the measure; this
song authors 20 camera moves with their own offsets, durations and eases, which is strictly
more than a name can carry.

Also, unlike the world coordinates everywhere else in this port, **camera offsets do get
scaled** by 1.5 — they are distances on screen, not positions in the world.

### The letterbox sits under the HUD, on purpose

Funkin's receptors are at the top of the screen and its bars can cover the bottom freely.
Rubicon anchors its strumlines to the **bottom** (`anchor_top 1.0`, `offset -160` — the same
as `test.tscn`), and the chart asks for 120px bars at 90.8s while notes are still arriving.
Drawn over the HUD that is a black bar across the strumline you are being asked to hit. So
`CinematicBars` is layer 1, `UILayer` is 2, and the letterbox frames the scene and leaves
the notes alone.

### Two things that had to be got right, both invisible when wrong

**A cancelled tween has to stop where it was cancelled.** Funkin cancels the running tween
on a property when a new event starts on it. A baked tween does not cancel itself: the old
tween's remaining keys keep writing past the new event and the two interleave on the track.
The first version of this drifted up to 200px on a focus and 0.13 on a zoom that way. Each
tween is now truncated at the next event of its kind — or at the end of the song, which is
what cuts the last `FocusCamera` and `ZoomCamera` short, both running 9.5s from 135.8s into
an instrumental that stops 6.4s later. The value carried forward is the truncated one,
because that is where Funkin's next tween starts from too.

**`Animation`'s key-collision test is relative, and it eats pins late in a song.**
Every track here is LINEAR, so a value has to be *pinned* at the end of its tween or it
slides straight on toward the next event's first key — a `CLASSIC` focus, which is a single
key with no tween at all, was arriving 211px short of its target for exactly that reason.
The pin goes just before the next event. But `Animation::_insert` decides two keys are the
same key with `Math::is_equal_approx`, whose tolerance is **relative**
(`CMP_EPSILON * abs(time)`, floored at `CMP_EPSILON`), so the further into a song a key
sits, the wider the window in which it silently overwrites its neighbour:

```
dos claves separadas 0.001s      t=10.0000  ->  2 claves
                                 t=97.8947  ->  2 claves
                                 t=104.2105 ->  1 clave
                                 t=142.0000 ->  1 clave
```

That is measured, not reasoned: at t = 97.89 the tolerance is 0.00098 and a 0.001 gap
survives, at t = 104.21 it is 0.00104 and the same gap collapses. And it is exactly where
this port started failing — every camera event before ~100s was right and every one after
it was short, because the pin had been eaten by the key it was meant to sit in front of.
The margin is 0.005s now.

### The split vocals, settled

The earlier pass reported worst-case drift and left it at that. Sampled once a second
across the whole song instead, the picture is different and better:

```
traza t= 10.1s  Tadano  +0.0 ms   Komi   +0.0 ms
traza t= 40.1s  Tadano  +0.0 ms   Komi   +0.0 ms
traza t= 50.2s  Tadano -46.4 ms   Komi  -92.9 ms
traza t= 60.2s  Tadano  +0.0 ms   Komi   +0.0 ms
traza t=100.2s  Tadano -69.7 ms   Komi  -92.9 ms
traza t=120.2s  Tadano  +0.0 ms   Komi  -11.6 ms
traza t=140.2s  Tadano  +0.0 ms   Komi   +0.0 ms
```

Twelve of the fourteen samples read **exactly zero**, and every non-zero reading is a whole
multiple of **11.61 ms — 512 samples at 44100 Hz, one audio mix buffer**. Nothing is
drifting: `get_playback_position()` reports on mix-buffer boundaries, so reading three
players in the same frame can catch them a buffer or two apart. Drift that was real would
climb; this does not, it snaps back to zero. That retires the split-vocal risk this port
opened with, and the number to re-check on device is the same one — a *trace*, not a
maximum.

## The character events

The last six of the chart's 103, which finishes the event track.

**`SetProperty boyfriend.idleSuffix = "-alt"` at 65.5s** is the big one: it puts tadano
onto his whole alt pose set for the back half of the song, which is what all those `-alt`
symbols in his atlas are for. Rubicon has no `idleSuffix` — a character picks its animation
from `animations`, which maps a lane alias to an animation name, and dances whatever is in
`dancing_animations` — so a suffix switch is a remap of both. `rubicon_character.gd`'s
`_refresh_last_sing_anim()` already exists to handle exactly this landing in the middle of
a hold note. tadano's alt idle is named `dance_idle_alt`, not `idle_alt`, so the same
append-the-suffix rule reaches it.

**`PlayAnimation` ×5**: komi's `reaction` at 66.4s and her two `breath`s at 80.1s and
86.4s, plus `endAnimation` and `endConv` at 132.2s that belong to the `tadano-stand` /
`komi-stand` characters the song swaps in near the end — that swap is not ported, and those
two warn and skip rather than fail.

Two things about `PlayAnimation` were worth getting right:

- **`force` is `restart`, not a condition.** Funkin passes the event's `force` straight into
  `playAnimation(name, restart, ...)`. Reading it as "only play if the character is idle"
  would have thrown away both `breath` events, since komi is mid-note when they fire.
- **The animation is held in `STATE_OVERRIDE` until the clip ends**, and this is the one
  place the port does not simply mirror Funkin. Rubicon re-dances a resting character on
  the next dance step — 0.4s at 152bpm — while `breath` and `reaction` are 0.625s. Played
  and released, the event was visible for **seven milliseconds** before `dance_idle` took it
  back. An event the chart spends a key on and nobody can see is the same as not porting it.
  The cost is that a note arriving inside the window does not animate; for the two `breath`
  events that costs nothing (there is not a single opponent note in either window), and for
  `reaction`, which the chart marks `force: true`, komi skips one sing — which is what
  forcing it means.

### Method-track keys are not fired by seeking

Worth knowing because it silently invalidates any harness that jumps around the song.
A seek only runs a method key if it lands **close after** it. Measured on this scene, with
the `SetProperty` key at 65.477s and the seek starting at 65.0:

```
salto de  1.0s desde 65.0 -> sing_left_alt     (dispara)
salto de  2.0s desde 65.0 -> sing_left         (no dispara)
salto de  4.0s / 5.0s / 6.0s / 8.0s / 10.0s    (no dispara)
```

Gameplay never does this — a song plays start to finish and a retry rebuilds the scene —
but every harness here does, so they **wind** the clock forward in 0.5s hops instead of
seeking. The first version of the guard reported the idleSuffix switch as broken purely
because it jumped 60s → 70s in one seek.

Winding has its own tail: it fires every camera bop and `AddCameraZoom` punch on the way
with no real time passing for them to decay in, so they stack — the screenshots came out at
**zoom 2.03** against a base of 0.975. `level_shot.gd` settles the camera onto its
interpolate target before capturing, which is where a real playthrough sits between bops,
and it has to do that on the frame *before* the capture: `get_texture()` returns what was
last rendered, so settling on the capture frame is a frame too late.

## The amtake-base note style

`amtake-base.json` names the receptors `LeftStatic` / `left press` / `left confirm` and
colours its notes purple, blue, green, red; Rubicon names the same things
`<dir>_lane_<neutral|press|confirm>` and `<dir>_note_<neutral|hold|tail>`, and drives them
through `AnimationTree` state machines keyed on `lane_id` and `lane_state`. So the whole
port is **a rename plus a set of regions** — the state machines, the trail masking and the
hit logic are Rubicon's and stay untouched.

The frames are built as `AtlasTexture`s over the mod's own PNGs rather than by repacking
them into a Rubicon-shaped sheet. One `SpriteFrames` can hold regions from several atlases,
so `notes.png` and `note-holds.png` sit side by side in one resource, and every region
comes out of the mod's own XML instead of out of a new sheet nobody can diff. The two
atlases happen to be authored at the same size as Funkin's — amtake's `LeftStatic` is
161×163 against funkin's 154×157 — so no rescaling is needed anywhere; the JSON's
`scale: 0.675` is Funkin's own display scale, which Rubicon bakes into its layout instead.

`Lane.tscn` and `Note.tscn` are produced by **rewriting** the funkin ones: three resource
paths, one library key and eight regions, with anything the transform cannot find treated
as a hard error rather than a silent no-op.

### `note-holds.png` ships with no XML

It is a bare 528×87 strip. Read off the image, it is eight 64×87 cells with 2–3px gutters,
in colour order purple, blue, green, red, and within each colour the body first and the
tapering end second — the even cells are opaque top to bottom and the odd ones taper. The
guard pins that slicing two ways: each region against its expected cell offset, and each
one's **average colour** against the direction the JSON assigns it. Names alone would not
catch two colours swapped between lanes, which is the one mistake here that stays
invisible.

### Three things that bit

**A swapped path keeps winning with its old uid.** `note-holds.png` inherited
`funkin_notes.png`'s `uid=`, and a `uid=` beside a `path=` wins — so the scene kept loading
the funkin sheet from a line that clearly read `note-holds.png`. Every rewritten
`ext_resource` now loses its uid.

**The library key is spelled into the clip names.** `Note.tscn` mounts its library as
`funkin_notes_library` and its animation-track clips are literally
`"funkin_notes_library/left_note_neutral"`. Renaming the key without the clips would have
broken every direction switch silently; both go in one swap, and the swaps are ordered so
the *paths* are replaced before the key, or
`res://assets/levels/ui/funkin/mania/funkin_notes_library.tres` would have had its middle
rewritten and pointed at a file that does not exist in a directory that does.

**A `TextureRect` with no `expand_mode` takes its texture's size as its minimum.** A
Control's rect is the larger of its anchored size and its minimum size. Funkin's tail
graphic is 64×50 and the trail is 50 thick, so the two agree *by accident*; amtake's is
64×87, and the cap came out 87 thick against a 50-thick trail, sticking out past both
edges. `IGNORE_SIZE` on all four `Tail` nodes drops the minimum to zero and lets the
anchors decide — which is what the trail body was already doing.

### Verified by looking

`tools/animania/harness/notestyle_sheet.gd` renders every lane and note animation frame by
frame onto a contact sheet. That exists because the first check of this port was a
gameplay screenshot, and a gameplay screenshot cannot tell *"the port is wrong"* from
*"that lane has no note on screen right now"* — it looked broken and was not.

Not ported: `noteSplashes` and `strum-holds` (the hit splashes and hold covers, 2.2MB of
art between them). Rubicon's `Note.tscn` has no slot for either, so they need new nodes
rather than a rename.

## The health icons

Rubicon has nothing like these. `RubiconHealthBar` moves a `PathFollow2D` and never touches
the two `AnimatedSprite2D`s hanging off it; `bf_icon.tres` carries a `neutral` and a `lose`
animation that no code ever switches between. Animania's icons animate **into and out of**
the losing state and komi's **sings along with her**, so this is new behaviour
(`animania_mod/scripts/animated_health_icon.gd`), not a rename.

Everything in it is `komi.hx`'s `initHealthIcon` and `onUpdate`, transcribed:

- the threshold is `LOSING_THRESHOLD = 0.25 * 2` on a bar that runs 0..2 — a quarter;
- a sing pose holds for `iconTimer` counting 0→4 at 6× elapsed, i.e. **two thirds of a
  second**, and any new note restarts it;
- below the threshold every sing pose takes the `-alt` set (`iconAnimPostfix`);
- an opponent's icon reads the **inverse** of the player's health, the way Funkin calls
  `iconP2.updateHealthIcon(100 - healthPercent)`;
- the icon is drawn flipped, which is why the atlas's `right` art is this port's
  `sing_left`.

Measured on a live level, the state machine runs exactly as written:

```
t= 0.13  idle
t= 0.31  to_losing          <- la vida del jugador sube al 95%
t= 0.64  losing
t= 2.01  sing_right_alt     <- nota estando por detras
t= 2.68  losing             <- 0.67s exactos de aguante
t= 3.51  from_losing        <- la vida vuelve al 50%
t= 3.84  idle
```

Two placement decisions, both to fit Rubicon's layout rather than move it. The bar authors
`offset.x = -73` for bf's 138px icon — half its width — so komi's 167px frame keeps `-73`
and slides out of place, overlapping the other icon in the middle of the bar; the offset is
now half of each icon's own width. And Rubicon **centres** its icons on the bar, which
already runs bf's 150px icon 19px off the top of the screen, so tadano's 171px one is
scaled to bf's height instead of the layout being moved to suit it. Both character JSONs
carry `healthIcon.scale: 0.9`, so the mod scales them down too.

### The sparrow importer crashes on these

`sparrow.gd` carries `last_frame` **across animation boundaries**, so when an animation's
first frame has the same region as the previous animation's last frame it evaluates
`frame_list[anim][find(last_frame)]` with `find()` returning −1 on a still-empty array.
Both icon atlases are full of duplicate frames and both hit it. Turning frame durations off
takes the other branch, and for these animations it loses nothing — they are authored at a
flat 24fps, unlike the character sheets where held frames carry real timing.

### tadano's icon does not sing

Its atlas carries `basic`, `lose`, `win` and `predeath` with all six transitions between
them, and all four rungs are wired up — see the ladder above. What it has no frames for is
singing: only komi's atlas carries sing poses.

## The hit splashes and the hold covers

`amtake-base.json` turns both on (`noteSplash.enabled`, `holdNoteCover.enabled`) and
Rubicon has a slot for neither: a Lane is a receptor with a three-state `AnimationTree` and
nothing else. So `animania_mod/scripts/lane_effects.gd` is new behaviour, driven off the
handler's own `just_pressed` / `just_released`, and it hangs off the **note style** rather
than off the level — which is what it is.

The numbers are the JSON's: splash scale 0.9, cover scale 0.7, `rotationVariance` 180
(applied either way from centre), cover offset `[0, -60]`. Only the offset scales by 1.5 —
it is a screen distance, while both atlases are already Funkin-sized like the notes.

**Only a perfect hit splashes.** Funkin splashes on `sick` and nothing else, and letting
every press splash turns the effect into wallpaper. The hold cover starts from the hit note
having an `ending_row`, which is what a hold *is* in a `RubiChart`.

### The importer cannot separate these two variants

Each colour ships two variants, and the subtextures are spelled
`note splash purple 10000`. The importer strips a frame index with `\d+$` — so the
**variant digit sits immediately before the index**, the regex eats both, and variants 1
and 2 collapse into a single animation named `note splash purple ` (trailing space, 8
frames). They are separated by halving that merged animation, which is sound because the
importer sorts frames by `int(index)` and `10000..10003` all come before `20000..20003`.
The guard pins the halves at their authored lengths (4, 5 and 3 frames) so a change in the
atlas cannot silently produce two wrong-length variants.

### The cover follows the source, not a guess

`amtake-base.hx`'s `getHoldCoverOffsets()` returns `[x, -y]` and
`buildNoteHoldCoverSprite` sets `flipY`, both when `Preferences.downscroll` is on — and
Rubicon's notes fall toward receptors at the *bottom*, which is downscroll. So the authored
`[0, -60]` becomes `[0, 60]` and the sprite is flipped.

It was rendered the other way round too, with the cover above the receptor where the tail
is, on the theory that Funkin anchors this somewhere other than the receptor's centre. That
looked worse — the cover lands on top of the receptor and swallows it. What the offset is
anchored to in Funkin is not recoverable from this slice, so this follows the source.

### Catching a four-frame effect in a still

`level_shot.gd` nudges every lane's `just_pressed` once before capturing. A splash lasts
four frames at 24fps and a still frame almost never lands on one, which makes an effect
that *is* working look absent — the same trap the note style walked into.

## `phone-call.script`, and what it corrects

The slice carries `songs/phone-call/phone-call.script` — 273 lines of `onBeatHit` and
`onCreatePost` — and reading it properly answers questions this README had previously
listed as unanswerable. Two corrections first:

**`introText` is not "never turned off".** An earlier section here said nothing in the data
Animania ships ever hides it, so it was shipped hidden. The song script hides it: beat 1
plays its `loop` animation, screen-centres it at 0.8 scale and fades it in over 2.5s; beat
11 fades it back out. Shipping it hidden was the right call for the wrong reason, and the
right reason is now on file.

**The stage's six `stand-` props are not decoration.** `standUP()` inverts the whole stage
— `prop.visible = prop.name.indexOf("stand-") != -1` — so every prop the song has used so
far goes away and the six that have been hidden since `buildStage()` are what is left.

### `standUP()`, at beat 232

91.6s at 152bpm, and the biggest thing that happens in the song: **nothing in
`phone-call-chart.json` mentions it.** The two characters are swapped for `tadano-stand` and
`komi-stand`, the stage inverts, the pair are repositioned, and the camera flashes white.

The script destroys the phone characters and fetches the standing pair from the character
registry. Here all four are in the scene from the start and the swap is a **visibility
change**: instantiating two multisparrow characters mid-song on a phone is a stall, and
there is nothing to gain from it. `setPosition()` places an `FlxSprite` by its *corner*, so
the script's `(-175, 325)` and `(300, 325)` become `(-30, 992)` and `(434.5, 995)` once each
scene's own bottom-centre anchor is taken off, at `zIndex + 500` = 710.

Three things it needs that Funkin gets for free:

- **The cast has to be rebound.** The chart's `PlayAnimation` events at 132.2s ask for
  `endAnimation` on boyfriend and `endConv` on dad, and those animations only exist on the
  standing pair — which is what the swap is *for*. Funkin destroys the old characters and
  puts the new ones in the same slots; a table of node references has to be reassigned.
- **`stand_up()` has to be idempotent**, and the rebind is why: a second call would hide the
  characters the first one just revealed. A method key fires again whenever something
  re-seeks across it, which every harness here does.
- **The camera has to switch focus tables.** After the swap the same `FocusCamera` `char`
  index means a different character standing somewhere else — Funkin's camera follows
  `getBoyfriend()`/`getDad()` and those now return the standing pair. The baked track takes
  the standing pair's points for every event at or after beat 232.

Animation names also needed a translation: the chart spells them Funkin's way (`endConv`)
and this port spells them Rubicon's (`end_conv`). An exact match always wins and
`to_snake_case()` is only a fallback, so every name already in snake_case is unaffected.

### A sharper version of the method-key rule

Earlier this README recorded that a seek fires a method key only when it lands close after
it. The ending sharpened that: **when two keys sit close together, a seek fires only the
nearest one.** `endAnimation` at 132.2122s and `endConv` at 132.2368s are 24.6ms apart, and
a wound clock played the second and skipped the first — silently, with the right animation
on one character and nothing on the other. In normal playback both fire, because the
non-seeking path walks every key in the frame's range. `level_shot.gd` now *plays* the last
1.6s into each moment rather than winding all the way, which is what makes a shot show what
the song actually does.

### Still not ported from the script

**Most of the modchart.** `Modchart.set("tanWave", ...)` and `"shake"` deform receptors
individually and need the whole subsystem. The strumline scales that go with them
(`changeMode(false, 1.05)` / `(false, 0.95)`) are left out too: the second argument of a
two-argument `changeMode` is a guess, and guessing wrong moves the lanes.

The `scale` pulse *is* ported — see below — because it is a property of the strumline
rather than of a receptor, and a strumline here is one Control with four lanes under it.

**The script's own letterbox bars**, and this one is not a gap — it is arithmetic. They are
100px, and the chart's first `CinematicBars` event puts the ported bars at exactly 100px
0.39s in. The only window where the two differ is those first 0.39 seconds, and the black
cover is over the whole screen for the first thirteen beats. A node that can never be seen
is not a port.

## The subtitles

`phone-call.script` does not create these — the engine has a subtitle display and the script
only restyles it (`subtitles.subtitleText.font = Paths.font('MP Manga.ttf')`, size 26). So
the cues, their timings and their colours are the mod's, in
`songs/phone-call/subtitles/song-lyrics.srt`, and `animania_mod/scripts/song_subtitles.gd`
is a SubRip parser plus a display driven off the clock.

Seven cues, and they land on the three moments the song is built around: three during the
black intro, one at beat 166 as komi's lanes fly in, three over the ending after the HUD
has left. `{font color="#..."}` is Flixel's markup for what BBCode spells `[color=...]`, so
the cue text converts rather than being stripped.

**On its own layer above the HUD**, and that is forced rather than chosen: camHUD's alpha
is 0 until beat 31 and the first cue is at 8.7s, under the black cover. Anything parented
to the HUD would never show it. The title card is moved to `camOther` for exactly the same
reason, and `camOther` draws over both.

Two things are not derivable and are therefore choices. **The font**: `MP Manga.ttf` is not
in this repo, so the line renders in the project default. **The placement**: the engine owns
it, so the line sits centred in a two-line band above both the letterbox bar at its widest
and the receptors — this song is downscroll, so the bottom of the screen is busy. The one
piece of styling evidence the script does leave is its `import
flixel.text.FlxTextBorderStyle`, so the text is outlined.

**`iconP1.bopEvery = 4 * 4`**: Funkin's icons bop on the beat and these do not bop at all —
they bob against the health value, which is `makeAmTakeAnimatedIcon`'s own behaviour and
the one the ladder was built around.

**`standUP()`'s `tweenCameraZoom(0.8, ...)`**, on purpose: the chart's baked `ZoomCamera`
track owns the camera continuously and has events either side of the swap, so a competing
zoom would fight it.

## The opening

`onCreatePost` plus cases 0, 1, 11, 13, 31, 166 and 168 — the thirty-three beats before the
song is a song, and the reason the port looked finished while it was missing them.

| beat | | |
|---|---|---|
| — | onCreatePost | black cover up, HUD alpha 0, title card off, strumlines swapped, opponent's lanes parked a screen right at alpha 0 and a full turn of rotation |
| 1 | title card | centred, scaled to 0.8, fades up over 2.5s |
| 11 | | and back out over 2.5s |
| 13 | the reveal | the cover fades off over 2.5s and tadano walks in playing `intro` |
| 31 | the HUD | alpha 0 → 1 and zoom 1.1 → 1 over 0.35s, the player's lanes with it |
| 166 | the opponent | after 2s, 1.35s of cube-out onto the player's home, unwinding 360° to half alpha |
| 168 | tadano | slides 800 right over 1.35s |
| 232 | | the opponent's lanes reach full alpha, riding on `standUP()` |

### The strumlines do not exchange sides — a derivation the device overturned

Worth keeping as a worked example of a reading that was internally consistent and wrong.

`onCreatePost` moves the player's lanes half a screen left and **nothing ever moves them
back**. The arithmetic seemed to force one conclusion: if their home were
`STRUMLINE_X_OFFSET`, half a screen left of it is off the edge, and 195 player notes would
spend the whole song outside the screen — so their home had to be `width / 2 + OFFSET`, half
a screen left of that is `OFFSET`, the opponent's home, and beat 166 flies the opponent's
lanes to what would then be the player's. They swap. It even held whatever
`Constants.STRUMLINE_X_OFFSET` turned out to be, which mattered because this repo does not
carry Funkin's `Constants`.

On a phone it was plainly wrong: you control tadano and your lanes sit on komi's side.
Something compensates that line — `changeMode`'s second argument is the obvious suspect,
and its meaning is still a guess — and **the observed result wins over the derivation**. The
swap is reverted; both strumlines keep their authored sides.

What survives, and is not in dispute, is the opponent's entrance: komi is a voice on a phone
for 67 seconds, so her lanes are off-screen from the first frame — her notes start at 18.9s
and are simply not shown — they fly in at half alpha at beat 166 and only reach full alpha
at beat 232, when she is standing there in person. Which is also why she gets no strumline
entrance of her own at beat 31.

### The cover is not the fade

`blackScreenSpr` is zIndex 5999. `overlay-all` is 5000 and `introText` is 6000, so the
title card reads *over* the black and everything else reads under it. Put the cover in the
level's overlays — where `camGame.fade` correctly lives — and it covers the title card too,
and the opening is five seconds of nothing. So it is built into the stage's screen-space
layer instead, between the two, which is what `parent_id_path` in the packed scene is.

### Beat 168 and the camera that does not follow

Funkin's `FocusCamera` takes a **snapshot** of the character's midpoint when the event
fires and tweens the follow point to it. It does not track a moving character — which is
the whole reason this port could bake twenty camera moves into a value track. So tadano's
entrance walk and his 800px slide are character moves against a camera that stays where it
was aimed, and they need nothing from the bake.

The slide is also not arbitrary: the chart's `FocusCamera` on the same beat carries an x
offset of 700, and the two were clearly written together.

### The pulse, and the one bit of modchart that ports

From beat 234 on, every even beat, both strumlines snap to 1.05 and ease back over exactly
one beat — the opponent's onto 1.0 and the player's onto **0.95**, which is not a typo in
the script: the player's lanes end each pulse smaller than they started and spend the odd
beats there, so they breathe between the two values while the opponent's punch down onto
rest.

It is the only piece here driven off a beat signal rather than a baked key, because that is
what it is: `onBeatHit`'s tail, with no upper bound. Funkin guards the whole handler with
`if (isPlayerDying) return`, so the death sequence sets a flag that stops it.

A Control scales about its pivot, and these lane containers are anchored on the point the
receptors sit on — so the receptors hold still and the field breathes around them, which is
what a strumline scale does.

The beat length is measured off the clock's own `RubiconTimeChange` list rather than
written down, so the ease stays one beat whatever tempo is in effect.

### Two keys at one beat collapse into one

Beat 232 wants `standUP()` and the opponent's last alpha step. Given a key each they become
**one key**: `Animation::_insert` compares times with `Math::is_equal_approx`, whose
tolerance is relative (`CMP_EPSILON * |t|`), so at 91.6s two keys have to be a full
millisecond apart to survive as two. The alpha step therefore rides inside `stand_up()`.

The same rule, read the other way, is why beat 168 lands where it does: it is 98ms from the
chart's `PlayAnimation` at 66.414s, which is far enough apart to be two keys but close
enough that a **wound** clock fires only the nearer of them. The guard lets real frames run
through that window rather than seeking across it.

## The title screen

`animania_mod/menus/title/`, and the first piece of the port that is not the song.

It has two halves that come from two different places, and knowing which is which is the
whole story:

- **The intro** — the 31 beats of text that spell themselves out over the gradient — is
  `data/scripts/states/TitleScreen.script`, which the mod ships as plain HScript. So this
  half is **transcribed**, beat for beat, including the camera punches on 28-31 and the
  circIn tween that lifts the last line.
- **Everything after it** is `animania.states.TitleScreen`, compiled into `Animania.exe`.
  The assets and their animations are the mod's; the layout is this port's.

The beat is the music's own: `animaniaINTRO-metadata.json` says 102bpm 4/4, so a beat is
60/102s and the intro runs about eighteen seconds. Funkin drives `titleBeat` off the
Conductor the same way.

### Two compositions, two different scales

The logo and the press-enter prompt are Adobe Animate atlases — the same gdanimate pipeline
as tadano — and each is a **stage timeline** rather than a symbol: 200 frames called
`Logolol` and 34 called `main`. `build_adobe_character.gd` had to learn about that, because
a composition's top level is not in the symbol dictionary. It lives in `stage_symbol`, and
gdanimate plays it by falling back to it when the requested symbol is unknown — the runtime
needed nothing, the builder was dropping it as missing.

Placing them by hand went wrong **twice**: once at screen coordinates, which put the logo in
a corner, and once at the project's flat 1.5x, which filled the screen with a quarter of it.
So they are measured instead, by `tools/animania/harness/measure_title.gd`, the same
render-and-count-opaque-pixels trick `measure_character.gd` uses:

| | drawn | local corner |
|---|---|---|
| logo | 2277x1643 | (-122, -22) |
| press enter | 816x139 | (11, 11) |

They are authored at different scales. The logo is far bigger than Funkin's 1280x720 stage —
it is the whole TV, not a wordmark, so the compiled `TitleScreen` must scale it down — while
the prompt is stage-sized and only wants the project's 1.5x. Both are placed by their
**drawn bounds** rather than their node origin, which is what the measured corner is for.

### The props, and what a disassembly actually yields

`updateProps` is compiled, so the props started out unported rather than invented. The
mod's **Linux build ships unstripped** — 270,967 symbols with demangled C++ names and
addresses — which makes `objdump` enough on its own, no decompiler required.

What came out of that function, exactly:

- **The constants.** `0.5`, `50`, `110`, `1.6`, `-300` out of `.rodata`, and `-10`, `-200`,
  `-550`, `400` out of the packed `Null<int>` immediates the `FlxRandom` calls are handed
  (hxcpp passes a `Null<int>` as a struct in one register, value in the high half).
- **The shape.** One `FlxTypedGroup` of `TitleProp`, six integer randoms and exactly one
  float random per pass, and props that are **recycled rather than respawned** —
  `TitleProp`'s only method is `reloadProp`.

What did *not* come out of it: **which number lands in which field**. That needs the struct
offsets resolved against `TitleProp`'s layout, which is another pass entirely. So
`title_props.gd` carries the mod's real numbers with this port's reading of where they go,
and says so constant by constant.

That is the honest shape of the method: exact numbers, exact structure, inferred mapping.
It cost about an hour for one small function. `create()` is 12.5 KB of code.

### playIntro turned out to be a state flip

Disassembled, `playIntro` is 223 instructions with **no outbound calls** — its only
references are to statics, one of them `seenIntro`. It choreographs nothing. The intro's
choreography is `titleBeat` in the `.script`, which this port already transcribes; the
compiled method just flips state.

That is worth writing down because it is the pleasant kind of finding: a function that
looked like a gap was not one. And it explains `seenIntro` being **static** rather than a
member — it survives the state being rebuilt, which is how the intro knows to skip itself on
a second visit. This port always plays it.

### The boil, ported by behaviour

`assets/shaders/` has no boil frag, so the GLSL is compiled into the binary as a Haxe
string. What the binary does give is the class: `set_amount(double)`,
`loadBoilTexture(String)` with a `DEFAULT_BOIL_TEXTURE` static, and the pair
`bumpTimer()` / `updateBoil()` sitting beside `BOIL_INTERVAL` and `boilTimer` on the title
state.

That pair **is** the technique, and it is the whole reason the effect reads the way it does:
the displacement is re-rolled on an interval and does not move at all between rolls. A
continuous version of the same displacement looks wrong even with the right texture — it
swims instead of boiling. So the shader takes its offset from outside and the title state
steps it.

`BOIL_INTERVAL` is read as **0.25** — four steps a second, which is hand-drawn animation
shot on twos. It is one of six doubles `update()` carries (1, 1.75, 100, 600, 0.7 are the
others) and the only one that makes sense as a boil cadence; the rest belong to the camera
and the outro lerp. The texture is the mod's own `boil_texture.png`.

## AnimaniaModule, and the icon thresholds it corrected

`scripts/modules/AnimaniaModule.hx` and `AnimaniaStuff.hx` ship as plain HScript, so this is
transcribed rather than inferred. Three things in them touch phone-call.

**The icon thresholds were wrong, and now are not.** `makeAmTakeAnimatedIcon` declares them
against a bar that runs 0..2, so each is half of what it writes: death `0.125 * 2`, losing
`0.25 * 2`, winning `0.8 * 2`. This port had no access to that module and read the ladder's
thresholds off `phone-call.script`'s *tilt* numbers instead - the healthLerp 1.75 and 0.25
that set the icon's ANGLE. Two of the three agreed by coincidence; the winning face waited
until 0.875 when the mod turns it on at **0.8**. They are separate constants now, because
they are separate things.

**`ONLY_HUD_SONGS = ["phone-call"]`.** `allowedHUD()` is false for this song, so
`loadAmTakeUI()` returns early and the module's whole extra HUD - the ratings assets, the
score numbers, the full-combo sprite, the combo tracking - never loads. Phone-call runs on
the plain HUD **on purpose**, which retires it as a gap rather than leaving it as one.

**`triggerCameraMovement`.** Every note the currently focused character hits shoves the
camera 25px in that note's direction, easing back to nothing over a second. The offset is
`camX / camGame.zoom * (stageZoom / 2)`, and dividing by the live zoom is what keeps the
nudge the same size on screen however far in the camera is - so both terms are read live.
It is skipped for `BANNED_NOTEKINDS` (`noAnimation`, `noanim`, `parents-miss`, `solotime`)
and when the hitting side is not the one the camera is on: a note from off-camera does not
move it. There is no `curFocus` to read here, since the focus is a baked track, so it is
taken from where the camera is actually aimed.

The shake and the nudge now share one `position_interpolate_offset` and are summed. Written
separately, whichever ran last erased the other.

**And the splashes were on one rule for two sides.** `onNoteHit` splashes the player only on
a perfect, and the opponent on `FlxG.random.bool(60)` - six notes in ten, at random,
whatever the judgment. The opponent is autoplayed and therefore perfect on every note, so
one rule for both had komi's side splashing on all 167 of hers.

## The debug overlay, and the duplicate it found

`animania_mod/scripts/debug_overlay.gd`, an autoload, and deliberately one line:
`FPS: 60 | MEMORY: 200 MBS`, white, in the project's own font. An autoload rather than a
node in a scene because the port changes scenes now, and a per-scene overlay blinks out
exactly when the frame time is worth watching. Debug builds only — it frees itself
otherwise. F3 toggles it, or a tap in the top-left corner, which is off the lanes.

The mod ships no TTF to use instead: its `images/fonts/` are sparrow atlases
(`alphabet-white`, `bold`, `default`, `freeplay-clear`) and the `vcr.ttf` the binary names
is embedded in the executable rather than shipped.

Writing it turned up something else. The touch controls are an autoload *and* the level
scene instanced a second copy, and the addon has no singleton guard: both ran
`_setup_buttons`, both drew, and their alpha stacked. That is why the hitboxes read as a
slab on a device — and why dropping the level copy's opacity to 0.4 changed nothing, since
the copy in charge was the autoload at 0.7. The level no longer carries one. The autoload
alone is also what the title screen needs, since skipping the intro is a tap.

`flow_check.gd` now counts them, so a second one cannot come back quietly.

### Getting into the song

`run/main_scene` is the title screen, and the title's confirm goes straight to
`songs/phone-call/phone_call.tscn`. In the mod that confirm is `moveToMain` and it goes to
the main menu; there is no main menu on this branch, so this is a deliberate shortcut to
make the thing playable, and it is one line to change the day `MainMenuScreen` exists.

So the flow on a device is: boot, eighteen seconds of intro (any key or tap skips it),
another press, and the song is running.

The confirm is deaf for `CONFIRM_DELAY` after the intro ends, or the same keystroke that
skips the intro also confirms it. That check lives **inside `confirm()`**, not in the input
handler — `tools/animania/harness/flow_check.gd` caught the first version, which guarded
only the keystroke and let every other caller straight through.

That harness walks the real path rather than instantiating the level: `change_scene_to_file`
replaces the running scene, so a level that loads fine in a harness can still fail as a
scene change. It checks that the game boots on the title, that skipping shows it, that the
confirm is deaf and then is not, that the scene actually becomes the song, and that the
song's clock is *advancing* rather than merely present.

### What is not ported

The falling bf/gf are built (`fallguys_frames.tres`) but nothing drops them.
`doJingle` and `cheatCodeShit` are untouched, and so are `swagShader`, `txtVersion` and the
`lerpOutroFactor`/`outroAngle` rotation on the way out.

The font is the project default. The real one is named in the binary's literal pool —
`assets/fonts/vcr.ttf`, which is VCR OSD Mono — but it is embedded in the executable rather
than shipped in `assets/`.

## Tadano's death sequence

Rubicon has no game-over machinery at all: `RubiconHealthModule` emits `health_depleted`
and nothing in the engine listens. So every piece of this is new, and every piece of it is
`tadano-stand.hx`'s `createDeathSprites()` and `tadano.hx`'s `setupDeath()` transcribed —
the two forms the song can die in, which differ in how elaborate they are rather than in
shape.

| | phone form | standing form |
|---|---|---|
| dark wash | opens at 0.9, dips to 0.5 over a second, settles to 0.75 from a second in | fades from nothing to 0.75 over 1.25s, half a second in |
| black side panels | — | two 400px panels sliding in over six seconds |
| komi | — (the phone komi was never drawn dying) | plays `gameOver` and stops dancing |
| retry text | `tadano-phone-death-text`, 850 left and 450 down of the character, shown **when `deathLoop` begins** | `tadano-phone-stand-death-text`, 240 to the right, shown on a quarter-second timer |
| camera | aims at the character, `death` offsets `(-350, 50)`, zoom ×1.05, then slides 450 left over 3.5s on `deathLoop` | offsets `(190, -40)`, zoom ×1.1, and **no slide at all** |
| HUD leaves | bar at 0.25s, strumlines at 0.5s | bar immediately, strumlines at 0.15s |
| death music | `GameOverSubState`'s own, at full volume from the moment it opens | started by the sequence at 0.25s, faded up over twelve |

Then what really is shared: the HUD leaves the way beat 332 sends it, the tempo is a forced
112 BPM, and every other beat of that adds 0.0075 to the camera zoom.

**The two forms are not the same sequence at different levels of detail** — reading them
that way is what the first version did, and it got both halves wrong. The camera slide and
the retry text hang off `deathLoop`, which `GameOverSubState` only plays when `firstDeath`
ends: four seconds of dying later, not at death. And the slide is `tadano.hx`'s alone —
`tadano-stand.hx` returns on `deathLoop` without touching the camera, because its text sits
beside the character and needs no bringing into frame. Sliding both forms at death put the
standing tadano hard against the right edge with his retry text off screen entirely, which
is what the render showed.

The phone form ends with tadano just off the right edge, and that is faithful: the camera
lands 637 Funkin px left of his corner against a 610px half-screen at zoom 1.05. The slide
is a move *away* from him and onto the text.

### Three things it needed that Funkin gets for free

**The clock has to stop, and that one is not cosmetic.** The baked camera animation writes
`position_interpolate_target` every frame, so a death camera aimed at the dying character is
overwritten by the song's next `FocusCamera` key before it is ever drawn. Pausing it also
stops the note controllers, which read their time from it. Funkin pushes a substate over
`PlayState`; here there is one scene, so the level simply stops being a level.

**The retry text lives on a CanvasLayer, not in the world.** Funkin adds it to
`GameOverSubState`, which draws above `darkBg`; drawn in the world it sits *under* the dark
wash, which is to say invisible — which is exactly how the first version came out. It still
has to move with the camera the way an `FlxSprite` at scroll factor 1 does, so it is put
back under the camera every frame.

**Funkin measures from the character's corner.** These scenes are anchored bottom-centre —
the same `characterOrigin` rule as everywhere else in this port — so the corner has to be
taken back off before `(-850, 450)` means what it meant.

Also: `firstDeath` hands over to `deathLoop`, which is where the character waits. Funkin
does that by calling `playAnimation` twice from the substate; here the first animation
ending is the cue. tadano's phone form got its animations renamed to `first_death` /
`death_loop` to match the standing form's, so the sequence asks for one name and reaches
either — and that handover is also what the phone form's camera slide and retry text wait
on, so it carries a callback rather than only swapping animations.

Only the phone form *has* a `death_loop` (4.208s, against `first_death`'s 4.125s). The
standing form has none, and neither does komi-stand's `game_over`: both hold their last
frame, which is precisely what `tadano-stand.hx` does by returning on `deathLoop`.

### What it does not do

**Retry.** There is no pause menu, no game-over scene and no song select on this branch to
go back to, so `confirm()` plays the confirm beat — the text's `confirm` label, the camera
pulling up 350, the panels sliding further out, the end music — and stops. Whatever drives
the flow later calls it and does its own transition.

Nor the confirm's black gradient sweep, and nor komi-stand's `gameOver-loop`: the JSON gives
it as `frameIndices: [6, 7, 8, 9, 10]`, a five-frame subset, and the sparrow importer's
frame-duration dedup renumbers frames, so those indices no longer address what they were
written against. Both stand characters hold their death animation's last frame instead of
breathing on it.

### A guard that walks the song has to autoplay

Found by this: the camera-events phase did not, so the player missed every note, the health
emptied, and **the death sequence fired in the middle of the check** — pausing the clock and
re-aiming the camera, after which every `FocusCamera` reading slid negative together. The
expectations held until 63s and then drifted, which is a very legible signature once you
know what makes it. Every phase that walks the clock now autoplays, and the one that is
*supposed* to die deliberately does not.

The guard also frees each level immediately rather than with `queue_free()`: it builds six
of them, and a deferred free plus a single awaited frame leaves the old one alive alongside
the new, each still processing a stage, four characters and eight lanes of `AnimationTree`.
The whole thing runs in **53 seconds**, most of the growth being the opening, the pulse and
the death, which are tween-driven and need real frames rather than seeks.

And it has to run `--headless`, the way its header says. Under a real renderer the frame
deltas change where the walk lands inside each tween, and six camera readings come out a
few hundredths off — 1.0614 against 1.0530, 169px of letterbox against 180 — which looks
exactly like a broken bake and is not one.

## The menu slice

Added when the port moved past `TitleScreen`. Same rule as the rest: lifted
verbatim, so the port has its reference in tree.

    images/menus/menu/    the main menu - buttons, backgrounds, the dude,
                          the seasonal emitters

The music is already here: `music/animaniaLOOP` is what the title's intro
leads into.

### Why it is in tree at all

The first attempt at the menus was blocked because a container was recreated
and took `/tmp/linuxbuild` with it - the extracted Linux build every fact
about the compiled states had been read out of. The slice for `phone-call`
survived because it was committed; nothing about the menus was. This is that
lesson applied.

The build itself is NOT in tree: it is 728MB, it is somebody else's work, and
the parts that matter are either plain text (transcribed below) or need a
disassembler. Its sha256 is
`22c804dd53b269dd3e9235ea4e2d388d39a51c1d9afe7609d48b1a950aeea677`
(`animania061-Linux.tar.gz`).

### Facts, read from the files

The main menu's states live in the binary as `animania.states.MainMenuScreen`,
`MenuButton`, `MenuDude` and `SeasonalEmitter`, so behaviour is disassembly.
The LAYOUT is not: it ships as JSON.

**Eight buttons**, one `butts/<name>.json` each, carrying an id and a rect:

| id | name | x | y | w | h |
|---|---|---|---|---|---|
| 0 | storymode | 757 | 7 | 404 | 150 |
| 1 | shop | 1171 | 7 | 177 | 178 |
| 2 | freeplay | 757 | 160 | 592 | 136 |
| 3 | website | 757 | 300 | 586 | 124 |
| 4 | options | 758 | 435 | 170 | 133 |
| 5 | credits | 941 | 435 | 400 | 133 |
| 6 | awards | 758 | 578 | 170 | 132 |
| 7 | exit | 941 | 578 | 400 | 133 |

They are a 2D arrangement, not a list, and `MainMenuScreen.changeItem` takes
TWO arguments - so navigation is directional rather than an index walk.

**The coordinate space is 1352x790, not 1280x720.** `menu background.png` is
exactly that, and the shop button's right edge lands at 1348. Read off the
files rather than assumed; where the mod puts that space on a 1280x720 stage
is still to be settled.

**Every button has three states**, as named symbols in one Adobe Animate atlas
(`butts/buttons/`, 3680x1262, 24fps): `render/eng/<name> basic`,
`<name> white` and `<name> confirm`. The main timeline labels them
`basic <name>` / `white <name>` / `confirm <name>`, six frames for basic, four
for white and eighteen for confirm.

**The dude** is `dudes/caramelDance.json`: the `caramen-dance` Sparrow atlas at
(-75, 225), scale 1.1, layer 1, animation `caramel`.

**Some buttons are locked.** `MainMenuScreen.BLOCKED_BUTTONS` holds THREE names
and `button_lock.png` is the art for it; which three is still to be read out of
`__boot`, whose arrays sit in .bss and are filled at runtime.
