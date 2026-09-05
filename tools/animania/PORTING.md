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

**This was once true and is not any more, so CHECK before repeating it:** pixeldrain,
Google Drive and GameBanana used to be blocked by the default egress policy. The user opened
the network afterwards - which is how the tarball got here in the first place - and it has
stayed open. Measured 2026-09-04: `gamebanana.com` and `pixeldrain.com` both answer 200, and
`recentRelayFailures` in `curl -sS "$HTTPS_PROXY/__agentproxy/status"` is **empty**. A stale
line in this file cost a wrong answer to the user today; one `curl -sS -o /dev/null -w
"%{http_code}"` settles it in a second.

A large download through the proxy is paced, so a 400MB file can take a quarter of an hour
even though a fresh probe reports 4MB/s. And for "what shape is this build?" the whole file
is not needed: a zip's central directory is at the END, so a `Range: bytes=<size-200000>-`
plus a scan for `PK\x01\x02` lists every entry and its size without downloading the body.

If the network IS closed again, either
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

### A stripped Windows build is still readable: `.pdata` + `_hx_pos`

Animania ships a Linux ELF with its symbols, which is the easy case. Most FNF mods ship a
Windows `.exe` and most of those are stripped - `nm` and `objdump -t` both answer
`no symbols`. That is not the end of it. Verified end to end on an unrelated Codename
Engine mod (131MB PE32+, fully stripped):

1. **`.pdata` gives every function's bounds for free.** A PE64 must carry unwind info, one
   12-byte `RUNTIME_FUNCTION {start, end, unwind}` per function, and nothing strips it.
   That mod had **104552** of them. Parse the section straight out of the file:
   `beg, end, unw = struct.unpack("<III", pdata[i*12:i*12+12])`, plus the image base.

2. **hxcpp writes its own stack-trace table into `.data`, in clear text.** Each method has a
   48-byte record of six slots:

       +0x00  int    (id)
       +0x08  ptr -> "funkin.menus.MainMenuState"
       +0x10  ptr -> "create"
       +0x18  ptr -> "funkin.menus.MainMenuState.create"
       +0x20  ptr -> "funkin/menus/MainMenuState.hx"
       +0x28  int    33            <- the source LINE

   Sweep `.data` on an 8-byte stride, keep every offset whose four pointers land in the
   image and whose third string is exactly `class + "." + method`, and the table falls out:
   **40267 records over 3889 classes** in that build. This is *better* than what the ELF
   gives, because the line number is right there instead of being inferred from the
   `movl $0xNNN` markers.

3. **Joining the two names the code.** Find the record for the method you want, scan `.text`
   for the rip-relative `lea` that loads it (`48 8d ?5 <rel32>`, check
   `text_va + i + 7 + disp`), and look up which `.pdata` range contains that address. That
   is the function. The per-statement line markers are still there inside it, just written
   to `[rsp+0x58]` in an MSVC frame rather than to `-0x40(%rbp)` in a GCC one.

Getting the binary out of a 393MB mod zip does not need the zip: the central directory is at
the END, so a `Range` on the last ~250KB lists all 1835 entries with each one's compressed
size and local-header offset, and a second `Range` on just the executable's entry plus
`zlib.decompressobj(-15)` yields it. 82MB instead of 393.

### `vtslot.py`: name the vtable slot instead of guessing it

`call *0x210(%rax)` is a method call through a vtable, and which method depends
on the RECEIVER's class. `tools/animania/vtslot.py` resolves it:

    python3 tools/animania/vtslot.py "funkin::graphics::FunkinSprite_obj" 0x210 0x3a8
    python3 tools/animania/vtslot.py "flixel::math::FlxBasePoint_obj"      # toda la tabla

Two traps it exists to avoid. The pointer an object carries points **0x10 past**
the `vtable for X` symbol (skipping offset-to-top and the typeinfo), so slot N is
at symbol + 0x10 + N — read it from the symbol itself and every name comes out
shifted and plausible. And when the name makes no sense for the arguments, the
receiver is not what you assumed: in `createLock` the calls at 0x118 and 0x120
each take a double, which would be `update(double)` and `draw()` on the sprite —
they are `set_x`/`set_y` on its `scale`, an `FlxBasePoint`.

The confirmed table for a FunkinSprite, since it comes up constantly:

    0x128 set_visible   0x210 set_x        0x218 set_y      0x230 get_width
    0x238 get_height    0x2b0 setGraphicSize  0x2b8 updateHitbox
    0x3a8 set_alpha     0x3b0 set_color    0x3c8 set_clipRect
    0x448 loadTexture   0x470 loadSparrow

Fields are not slots and need their own evidence. `FunkinSprite`'s 0x260 was
identified by asking which methods read it: all four are the zoom-scale
procedure, so it is `zoomFactor`.

### A sub-state belongs to whoever ALLOCATES it, not to whoever it is named after

`StoryMenuSelectSubState` sounds like the story menu's, and it is the MAIN
MENU's: its constructor takes a `MainMenuScreen`, and the only call to its
`__alloc` is inside `MainMenuScreen::doSelect`, in the branch that tests the
pressed button's name against `"storymode"`. It calls back with
`MainMenuScreen::startTransitionToMenu`. The port had it opening off the story
menu's own confirm, one screen too late, and the whole amtake/animania question
read as "which song" instead of "which half of the mod".

    nm -C --defined-only Animania | grep '<Class>_obj::__alloc'   # la direccion
    objdump -d Animania | grep 'call   <direccion> <'             # quien la crea

The name of a class is a hint. The caller is the answer.

### `animania::states::` is the mod; `funkin::ui::` is the game it forked

The binary carries BOTH, and the one that runs is `animania::states::`. Reading
`funkin::ui::story::StoryMenuState_obj::create()` at 0x2fac530 gives a perfectly
coherent story menu that is not this menu; the real one is
`animania::states::StoryMenu_obj::create()` at 0x32f20a0. Same for the select
sub-state, the freeplay screen, the title, the main menu, the options and the
credits - `nm -C | grep -oE "animania::[a-z]+::[A-Za-z]+_obj" | sort -u` lists
them.

The cost of getting this wrong is not a crash, it is a confident wrong answer:
base Funkin's `changeDifficulty` animates `leftConfirm`/`rightConfirm` arrows and
the mod's sets an alpha instead, and both read as "the arrows react".

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

### The credits screen is a card, not a list

`animania::states::CreditsMenu` (0x138bc90..0x1398785, 24 methods) shows **one** crew
member at a time and moves between them with two `menus/story/diff-selector` arrows.
`create()` calls `loadCreditsData`, `createBackground`, `createParticles`,
`createUIElements`, `createSocialButtons`, `changeItem(0)` and `sortStickers`, and not
one of those builds a row. The scrolling roll of names this port used to draw — and the
row hitboxes the guard tested it with — were invented, which is also why the tap always
landed on row 0: `Rows` had no children at all, because the builder that was supposed to
fill it read two constants (`ROW_HEIGHT`, `LIST_CENTRE`) that the script does not
declare, so it had never run.

What is actually there, all of it in the mod's 1280×720 space:

| thing | where | address |
| --- | --- | --- |
| `AnimaniaLogo Smaller` | (40, 0), scale 0.5, `zoomFactor` 0.875, zIndex 15 | 0x1391000 |
| note paper `textnote` | (666, 63), zIndex 45 | 0x1391bb0 |
| note text `AtlasText` | (715, 180), `alphabet-white`, wordWrap, zIndex 46 | 0x1391119 |
| — its fieldWidth | `noteBg.width - 2*(noteTxt.x - noteBg.x)` = 483 | 0x1391c56 |
| name plate | centred on the note, `y = noteBg.y - height/3` | 0x1393863 |
| photo clip `pic-clip` | (1020, 452) | 0x1391e7b |
| role words ×5 | `createSparrow(24, 409, "menus/credits/roles")`, pooled | 0x139129d |
| stickers ×36 | `x = FlxG.initialWidth*0.225 + i`, `y = 720 - h - 15`, scale 0.5 | 0x1392174 |
| social buttons ×4 | youtube (661,620,−6°), x (750,630,6°), soundcloud (843,600,8°), newgrounds (923,620,−6°) | 0x138aad8 |

`ARROWS_PAD` is **30** and `BASE_ICON_SIZE` is **150** (both read straight out of
`__boot`, 0x138bfbe / 0x138c01b). The port had 40 and 0.8 — the second one read as a
*scale* when it is a width in pixels.

Three things this cost time and are worth keeping:

- **The arrows hang off the FIRST sticker and are never moved again.**
  `left.x = sticker[0].x - BASE_ICON_SIZE/2 - ARROWS_PAD - left.width`,
  `left.y = sticker[0].y + (BASE_ICON_SIZE - left.height)/2 + 20`, and the right one is
  the same with the signs flipped and no width term; its `y` is copied from the left
  one's. So the pair straddles the sticker's left edge, not its middle. That is not a
  misreading — it is what 0x1392cf7 and 0x13930a5 do.
- **All 36 stickers exist at once**, stacked one pixel apart; `sortStickers` is a single
  `FlxTypedGroup.sort` (0x138b642) and changes nothing but the draw order. The JSON's
  `stickerOffset` is subtracted from the sprite's `offset`, which moves the art without
  moving `x`/`y` — so it never moves the arrows.
- **`setRoles` centres the words in a 550-wide column at x=24**, shrinking anything wider
  with `setGraphicSize(550)`, and stacks them at
  `y = ((5 - n)/1.25 + i) * (250/5) + 244` (0x138f239). That column is exactly the span
  of the mod's own hand-laid role board, whose nine seats the constructor stores in
  `rolePositions`: director (24,244), co-director (24,301), artist (24,355) with animator
  beside it at (257,355), coder (24,409) with charter at (217,409) and `?` at (529,409),
  composer (24,464) with voice actor at (360,464). Read those pairs the other way round
  and they are nonsense; read them this way and each row's words butt up against the
  previous one's width to the pixel, which is what proves the order.

`alphabet-white` had to be vendored for the note, and it is the first font here with
`rotated="true"` frames — 34 of its 89. An `AtlasTexture` cannot turn a glyph back, so
`AtlasText._unrotate` cuts it out and rotates the image once at load. Its palette is
white-with-an-alpha-ramp, so `_whiten` is a no-op on it and **nothing in the class tints
it**: white lettering on the cream note is what the binary says, not a port bug.

Left unported on purpose: `AtlasText.startTyping` (0x13945b6), which types the note out
at the entry's `textSpeed` with `textPitch` — the units of that speed are not recovered,
so the note is shown whole rather than at an invented rate. The note's `<img>` markup is
dropped rather than printed.

### The main menu's create(), and the three things that were missing from it

`MainMenuScreen.create()` (0x18110d0) is eleven calls and they are worth having written
down, because the port had three of them missing outright:

    initMouseEvents, initMusic, createBackground, createParticles, createVisualizers,
    createUIComponents, createButtons, createSeasonalEffects, createSpecialElements,
    setupEventListeners, finalizeSetup

- **createVisualizers** (0x17ff530) is a `WaveformSprite` down the left edge —
  `setPosition(-100, -15)`, `setSize(256, 900)`, alpha 0.8 — and a `BarsVisualizer(-90,
  390, 950, 350)`. The bars' own constructor (0x51c4ea0) carries 24 bars, alpha 0.6 and a
  five-stop gradient (white, pale yellow twice at 69%, pink, cyan); `initBars` (0x51c5620)
  divides the width by the count, draws each bar that wide minus 5 and the full height, and
  `drawFFT` writes each one's `scale.y` — which Flixel applies about the frame's centre, so
  a bar opens out of the middle of the band rather than growing off its floor.
- **createSocialButtons** (0x180ce20) is five buttons, not four: amazon is in the atlas
  next to youtube, soundcloud, spotify and apple music. Their seats are a **running sum**,
  which is why they read as unmeasurable before — the first is at x = 37.3 and each next
  one starts `previous frame width - 6` further right, all on y = 620.9 at scale 0.85. The
  last ends at 539 and `music_social_lines` is 661 wide at 0.85 running 7.5 to 569: the
  strip they sit on. That the sum lands inside the strip is the check that it is read the
  right way round, and the five URLs in `.rodata` are in the same order as the anons.
- **createParticles** (0x17fb440) is an `FlxTypedEmitter` at (750, -150) on
  `menus/particle`, a plain white 100x100 square. Its settings looked unreadable at first
  because every `set` call goes through an unnamed field pointer — until you notice that
  **hxcpp returns the bounds object for chaining, so the hidden return slot takes `rdi` and
  the field being configured is in `rsi`.** Read `rdi` and all six calls look like the same
  anonymous temporary; read `rsi` and the offsets fall straight onto FlxTypedEmitter's
  declaration order: `velocity` 0xa8, `lifespan` 0xe8, `scale` 0xf0, `alpha` 0xf8, `color`
  0x100, `drag` 0x108. The arguments are hxcpp's **right-to-left** evaluation, so the last
  parameter is the first `Dynamic` built - which is what turns alpha from nonsense into
  `set(0.9, 1, 0, 0)`, a plain fade-out, and is the check that the reading is right.
- **createBackground** (0x1800500) is `loadTexture`, `screenCenter`, `scrollFactor.set(0.65,
  0.65)` and then `x -= 75`. **No scale.** The 1352x790 art is drawn at its own size on a
  1280x720 screen, overhanging 36 a side, and slides 75 left. This port had it scaled to
  cover, which made it 5% small and lost the 75.
- **spawnHelpMouseText** (0x1802d10) is a first-run hint: a solid box at (-85, 125) at alpha
  0.6 sized to the text plus ten, and `"  Use your mouse and keys to navigate and choose!"`
  in `Inconsolata-Black.ttf` at alpha 0.9 five pixels inside it, both sliding in on quadOut
  over 1.3s after 1.55s and 1.65s, held for a 7s timer. `finalizeSetup` only spawns it when
  `Save.instance.animania.seenMainMenuHelp` is unset. The font ships **inside the
  executable**, not beside it, and is extracted the same way the tracklist's faces were.
  The box's colour is the one thing here that is not recovered - `makeGraphic` takes it in a
  register the dump does not resolve - so it is black.

**createSeasonalEffects** (0x1808ab0) is not just what falls past the menu. Each season also
hangs an `AdjustColorShader` on `FlxG.camera` — autumn `hue -10, sat -35, contrast 30,
brightness -25`, winter `hue 12, sat -6, contrast 10, brightness -5` — and winter loads
`animaniaLOOP/bells` as a second music layer and tweens its volume 0 to 1. Autumn also adds
a `RuntimeRainShader` that `updateSeasonalEffects` drives at `elapsed * 0.2`; that one is
identified and not ported, because writing a rain shader from nothing is writing one.

**And the shader source itself is IN the binary.** Funkin compiles its GLSL at runtime, so
the fragment shader is a plain string literal:

    strings -n 8 Animania | grep -n "uniform float hue"

gives `applyHueRotate`, `applySaturation`, `applyContrast` and `applyHSBCEffect` character
for character, magic numbers and `//Just roll with it...` included. Transcribing that beats
reconstructing Adobe's AdjustColor from documentation, and it is the same trick for any
other shader the mod uses.

`updateCameraScroll` (0x1804ac0) follows the **mouse**, not a clock:
`scroll.x = lerp(scroll.x, remapToRange(mouse.x, 0, FlxG.width, -10, 3), elapsed * 3)` and
the same on y with a range of -1 to 1. The port had a pair of sines off the music's
playback position, which is why the camera never came back to centre after the intro and
why the guard had been failing on it for weeks.

### A guard check has to name the moment it means

`change_item` was already deaf during the intro — `_live()` has been on its first line all
along — and the guard failed on it anyway for weeks. The reason is that `_live()` opens when
the CAMERA tween lands at 0.75s while the curtains run to 1.0s, and the guard asserted
"the curtains are still moving, so the menu must be deaf" and then looked at whatever
moment the frames happened to fall on. Two true statements about different moments. Parking
`_intro` at 0.1 first makes the check deterministic and it passes, and adding a second
`_live()` guard to `change_item` — which is what this looked like from the failure — fixes
nothing, because the first one was never the problem.

The knock-on is worth knowing: that one failure had been hiding the whole tail of
`flow_check`. The walk it corrupted landed on options instead of freeplay, the guard hit its
`_report(); return`, and **everything after it — freeplay, the loading screen, the song, the
pause menu — had not run in weeks.** When it finally did, it needed the loading screen
driven (`_done`, then `_enter()`), a wall-clock wait for freeplay's 0.6s confirm timer, and
one check that could never have passed (`root.has_node("DebugOverlay")`, an autoload, which
`--script` does not register) rewritten to ask `ProjectSettings` instead. An early
`return` in a guard hides more than it reports.

### The main menu, method by method

With the above done, `MainMenuScreen` is ported end to end. What is deliberately NOT in the
port, and why, so nobody re-derives it:

| left out | why |
| --- | --- |
| `RuntimeRainShader` (autumn) | writing a rain shader from nothing is writing one, not porting it |
| the emitter's `maxParticles` / `spawnValue` | their `cpp::Variant`s go by reference and the dump does not resolve them |
| `MusicFilterController` | the reverb and lowpass it drives are only used by the `exit` button's quit ramp, which is not ported either |
| the `exit` button's audio ramp | `REVERB`/`LOWPASS` through `MusicFilterController`, which this port has no equivalent of |
| `credits`' `StickerSubState` | the sticker wipe is its own screen; credits leaves through the curtain here |

Two details that are easy to miss and both show on screen: `createBlockedButton` **greys the
button under the padlock** to `0xFFAAAAAA` before adding the lock (0x1806989), and
`musicSocialPlayAnim` is the method that chooses the OST disc's state — calling it from
`finalizeSetup`, as this port did, leaves the disc looking permanently hovered.

### `__GetFields` names every field, and that settles arguments

Chasing `this->0x120` one cross-reference at a time is the slow way. `MainMenuScreen_obj::
__GetFields(Array<String>&)` pushes every member NAME as a string literal, in declaration
order, and hxcpp lays the POINTER fields out first, contiguously, 8 bytes apart. So one
known offset anchors the whole block:

    python3 raw.py <__GetFields start> <end> | grep -oE "S='[^']*'"

For `MainMenuScreen` that gives `background, waveform, barsViz, buttonsBg, menuDude,
menuButtons, menuButtonsUI, locks, blackLineUp, blackLineDown, newsButton, musicSocial,
musicSocialLines, musicSocialButtons, mouseEvents, seasonalEmitter, colorShader, rainShader,
debugMenuCamera`, then the bools, a String, three sounds, three more bools, and two objects.
`rainShader` was already known to be 0x158 from `updateSeasonalEffects`, so the base is 0xD0
and the rest falls out:

    0xd0 background      0xd8 waveform        0xe0 barsViz        0xe8 buttonsBg
    0xf0 menuDude        0xf8 menuButtons     0x100 menuButtonsUI 0x108 locks
    0x110 blackLineUp    0x118 blackLineDown  0x120 newsButton    0x128 musicSocial
    0x130 musicSocialLines  0x138 musicSocialButtons  0x140 mouseEvents
    0x148 seasonalEmitter   0x150 colorShader          0x158 rainShader
    0x160 debugMenuCamera   0x168 canChange   0x169 transitioning 0x16a overMusic
    0x170 currentSeason (String, 16 bytes)
    0x180 gokMoveSound   0x188 bassSound      0x190 musicLayerSound
    0x198 allowToUseNewsButton  0x199 allowToUseMusicSocial  0x19a toogleMusicSocialButtons
    0x1a0 musicFilter    0x1a8 imLowkeyWannaPlayManager

Two independent confirmations fall straight out: `handleInput` reads 0x160 for the
`DebugMenuSubState`'s camera, and `createNewsButton` writes 0x120. And the joke name at
0x1a8 explains the dead branch — `imLowkeyWannaPlayManager` is a dev door nobody wired up.

**It also corrected a finding from the previous pass.** `doSelect` line 889 fades out field
0x190, which is `musicLayerSound` — the extra stem — not the menu music. And
`updateSeasonalEffects` line 750 does `musicLayerSound.volume = FlxG.sound.music.volume`
every frame, unconditionally (0x17fd129, `set_volume` through vtable 0x1b8). Flixel updates
`FlxG.plugins` — where the tween managers live — BEFORE the state, so that per-frame
assignment lands after the tween's and wins it every frame: **the fade never reaches the
speakers in this build.** The port had briefly been made to fade its menu music on select,
which is louder than anything the mod does. Reverted.

### Auditing "it is all there" against the binary

"Everything is added" and "everything is added right" are different claims, and the second
one only gets answered by reading the function again next to the port. Four methods were
re-read that way — `changeItem`, `doSelect`, `startIntroAnimation`, `startTransitionToMenu`
— and the two with tweens came back clean while the two with logic did not.

**Clean.** `startIntroAnimation` (0x1802250): `camera.zoom = 3`, `scrollAngle =
random(-10, 10)`, `scroll = random(-200, 200)` each axis, the two curtains tweened over
**1.0s** on `smootherStepOut` to `+-(height - 30)`, and the camera tweened over **0.75s** on
`smootherStepInOut` to `{zoom: 0.9, scrollAngle: 0}` with an onComplete that clears
`isTransitioning` (field 0x169). `startTransitionToMenu` (0x1809790) is the same run
backwards with a default duration of **0.75** (0x180a250) — dude `x - 650` on `backInOut`,
curtain up to `10 - height*0.5` and down to `350` on `smootherStepOut`, camera to
`{zoom: 3, scrollAngle: random(-10,10)}` and scroll to `random(-200,200)` on
`smootherStepInOut`, then an `FlxTimer` of that same duration that switches the state. Every
number already in the port.

**Not clean.**

- `changeItem(huh, skipBlocked)`'s second `Dynamic` is **not** a play-sound flag, which is
  what the port had guessed. Line 849 makes `huh` a hard `+-1` before the sound test, so the
  sound is unconditional; the flag gates the **blocked-button skip**, and it defaults to
  *false* (0x17fdde7). `handleInput` passes true on every keyboard and wheel branch; the
  mouse callbacks pass nothing, because a blocked button never gets a mouse callback at all
  (`createButtons` sends those to `createBlockedButton` instead, 0x18075b7).
- `changeItem` ends by **raising the selected plaque**: the forEach at line 859 gives it
  `zIndex = 0` and every other button `~ID`, and line 872 sorts the group by that key
  ascending (`sortByZ`, 0x17fe280, is `FlxSort.byValues` on `zIndex`). The port had
  `_sort_by_z()` but never set a key, so it was sorting eight nodes that all compared equal
  and the raise never happened — visible, because the `white` art is bigger than the `basic`
  art and slides under its neighbour without it. In Godot the key is a `sort_z` **meta**, not
  `z_index`: `z_index` is a real layer, and the mod's negative values would push the plaques
  behind the background.
- `changeItem(-444)` is a sentinel meaning **nothing is selected** (`curSelected = -1`, every
  plaque back to `basic`, no sound). A button's `onMouseOut` sends it when the pointer leaves
  the button that was selected, so on a desktop the menu really does go blank between
  plaques. The port had no such state, and none of the three mouse callbacks at all —
  `initMouseEvents` was a `pass` with a comment saying clicks were enough. They are not:
  `createInteractiveButton` (0x17fc0c0) registers over, out and up, and the menu is
  hover-driven with a mouse.
- `doSelect(id)` **returns on `id < 0`** (0x1805555). That is not defensive: with the -444
  state reachable, GDScript's negative indexing would have made `BUTTONS[-1]` = `exit` and
  quit the game on a confirm with nothing hovered.
- `doSelect` **fades the music out** over 0.15s (the inlined `FlxSound.fadeOut` body at
  0x18056db), which the port did not.
- The **timing was a second short**. `doSelect` does not start the transition: it plays
  `confirm` and arms `new FlxTimer().start(1.0, ...)` (0x180531a), and only that timer's
  closure picks the destination and calls `startTransitionToMenu`. So the two waits are
  **1.0 then 0.75**, back to back. The port had fused them into one 0.75 derived from the
  animation's own 18 frames at 24fps — a plausible number that cut the confirm animation off
  a quarter of the way in. Where the frame count and the binary disagree, the binary wins.

**`handleInput` (0x180ee10) and `finalizeSetup` (0x1803be0).** Four more findings, and one
of them is the kind you only see by leaving the screen and coming back.

- **`curSelected` is a class STATIC** (0x7e568a8) and the only write of 0 to it is in
  `__boot()` — once, at program start. `__construct` never touches it. So the selection
  survives leaving the menu and returning: go into freeplay, come back, and the plaque you
  left from is still lit. The port had it as an instance field, so every return snapped back
  to `storymode`. It is a `static var` now, and a probe confirms a fresh instantiation of the
  scene keeps the value.
- **`handleInput` reads the four UI actions as two pairs that are not the same code.** Left
  and right (Controls 0x38 / 0x40) step by ∓1 and nothing else. Up and down (0x48 / 0x30)
  first ask `if (curSelected == -1)` and, when nothing is selected, pass **0** — and
  `FlxMath.wrap(-1, 0, 7)` is 7, so up or down from nothing lands on the **last** button.
  The port stepped by one on all four. (0x30 is `UI_UP`: `OptionsSubMenu.update`, a plain
  vertical list, tests that same offset for its own -1 at 0x3f7a736.)
- **`finalizeSetup` line 611 is `changeItem()` with both defaults**, and everything past the
  wrap still runs — including line 853's sound test, which line 849 has already made
  unconditional. The mod clicks once as the menu opens. The port did not.
- `changeItem` has **no `amount == 0` guard** in the binary, which is what makes both of the
  above work. The port had added one.

Deliberately left out of these two: `refresh()` (vtable 0x370, MusicBeatState's zIndex sort
of the whole state — covered here by construction, since the builder emits the scene in draw
order), `changePresence` (vtable 0x388, Discord Rich Presence off `RANDOM_MESSAGES` at
0x7e568b0), a `ManagerPlayState` behind a field at 0x1a8 that is **only ever written false**
(0x17fe8bd, 0x180c8da, 0x180ef84 — nothing in the binary sets it true), and
`DebugMenuSubState` on the DEBUG_MENU action. The last two are dev doors.

**The per-frame trio and the OST widget.** `update` (0x1812a70) is six calls and no
conditions at all — `super.update`, `musicFilter.update`, `updateSeasonalEffects`,
`updateCameraZoom`, `updateButtonsAnimation`, `handleInput`, `updateCameraScroll` — every
frame, with the gating living inside `handleInput`. `updateCameraScroll` (0x1804ac0) matched
the port number for number: `remapToRange(mouse.x, 0, FlxG.width, -10, 3)` and
`(mouse.y, 0, FlxG.height, -1, 1)`, lerped by `elapsed * 3`. `updateSeasonalEffects`
(0x17fd030) is the rain shader plus the volume line above. No numeric defects in any of
them.

One divergence stays on purpose: this port's `_process` hands the camera to `_advance_intro`
/ `_advance_exit` alone and skips the zoom decay, the scroll and the beat while either runs.
The mod runs all of them alongside its tweens, and because the state updates after the
plugins its per-frame easing takes the last five to ten percent of each frame off the
tween's value. That is a slightly different settle curve, not a different shape, and it is
not worth restructuring the camera's ownership on a framerate-dependent guess.

`toggleSocialButtons` (0x17fcd00) and its two halves were the real find here, because the
port had them as a `visible` flip:

    634  if (toogleMusicSocialButtons) showSocialButtons(onDone) else hideSocialButtons(onDone);
    647  FlxTween.tween(newsButton.<0x160>, {x: 500}, 0.7, {ease: cubeIn});    // opening
         FlxTween.tween(newsButton.<0x160>, {x: 0},   1.3, {ease: cubeOut});  // closing

and `showSocialButtons` (0x17fc870) is a 0.1s one-shot `FlxTimer` whose closure (0x18081f0)
walks the five buttons, makes each visible at scale 1, and tweens it over **0.8s** on
`backOut` with `startDelay = (1.0 - i / length + 0.2) * 0.8` — 0.96, 0.80, 0.64, 0.48, 0.32,
so the FAR button arrives first and the one nearest the disc last. Opening and closing are
not mirror images: the news banner is pushed 500 out in 0.7 and takes 1.3 to come back.

Not resolved and written down rather than guessed: the x/y the buttons tween FROM (they come
out of a stored seat the dump does not reach), and the companion `FlxTween.num` at 0x1808886
that runs alongside on `backInOut` over the same 0.8. The port scales them in from zero at
their seats, which is the same stagger with a substituted gesture.

**`create` and the rest of the create* chain.** `create()` (0x18110d0) is eleven calls in
order: `super.create()`, a bool, then `initMouseEvents, initMusic, createBackground,
createParticles, createVisualizers, createUIComponents, createButtons, createSeasonalEffects,
createSpecialElements, setupEventListeners, finalizeSetup`. The mouse and the music go up
FIRST, before anything is built; this port had the seasonal layer spun up before the music it
plays against, and that order is fixed now. `createUIComponents` (0x1804170) builds
`menus/menu/buttons back`, the `MenuDude` and the two black curtains — all four are in the
scene, so nothing was missing there. `createBlockedButton` (0x1806920) greys the plaque to
`0xFFAAAAAA`, puts the lock at the button's CENTRE, and gives it `zoomFactor = 0.85`
(field 0x260, not scale) and `zIndex = 30` — above every plaque, which is what keeping the
locks last in the node already gives.

`destroy()` (0x1813fc0) is mostly the mod's own bookkeeping, but its first act is
`Cursor.cursorMode = Default` — and now that the hover callbacks set a pointer shape, the
port has to do the same on the way out or the next screen inherits a hand cursor.

### The OST widget, measured: the numbers were right, the behaviour was not

`createMusicSocial` (0x180e050) and `createSocialButtons` (0x180ce20) came back matching the
port on **every** number, which is worth recording because this is the corner where the
binary and the mod's own capture disagree and `WORLD_OFFSET` is the calibration between them:

    disc      FunkinSprite(570, 590), scale 0.85, zoomFactor 0.875
              soundtrack basic -> `idle`, soundtrack white -> `selected`,
              soundtrack press -> `press`, all addByPrefix at 24
    lines     music_social_lines at (7.5, 625.35), scale 0.85, zoomFactor 0.875
    buttons   amazon, youtube button, soundcloud button, spotify button,
              apple music button - from x = 37.3, y = 620.9, each stepping the running
              sum by its unscaled frame width MINUS 6.0 (0x180d835)

Note the disc's argument order: `mov $0x24e` (590) is built before `mov $0x23a` (570), and
hxcpp evaluates right to left, so the first Dynamic built is Y — the sprite is at
(570, 590), not (590, 570). That is the same trap this file warns about for `FunkinSprite`
generally, and it is the one place where getting it backwards would look plausible.

Two behaviours were missing even though the numbers were right:

- The lines strip gets `clipRect = FlxRect(0, 0, 0, frameHeight)` at creation (0x180e83f) —
  **width zero**, so it is not hidden, it is rolled up, and something unrolls it. The port
  flips `visible`, which is the same appearance without the unroll.
- `createMusicSocial` ends with its own `FlxMouseEventManager.add` on the disc (0x180e98a),
  three closures like every plaque gets. So the disc lights up under the pointer too. Ported.
  Its `press` clip is the mouse-DOWN state and is replaced by `selected` on the up that
  follows; a tap has no room between the two, so the clip stays mapped and unused rather than
  flashed for no frames.

### `setupEventListeners` is not empty, and the loop has two stems

Two things this port had written off. Both were wrong, and both are audible or visible.

**`setupEventListeners` (0x17fc540)** was recorded here as "empty". It is one line, and it is
what makes the menu react to the music:

    594  barsViz.<0x158> = function(intensity:Float) {
    596      if (intensity > 1.35 && ... && FlxG.sound.music.volume > 0.1) {
    598          FlxG.camera.shake(0.00075, 0.1);
    599          FlxG.camera.zoom += 0.0005;
    601          for (lock in locks)                                  // this->0x108
                     lock.frameOffset.set(FlxG.random.float(-0.75 * i, 0.75 * i),
                                          FlxG.random.float(-0.75 * i, 0.75 * i));
    604          menuDude.frameOffset.set(<the same pair>);           // this->0xf0
             }
         };

So the visualiser is not decoration: it is the thing that tells the menu a loud hit landed.
On one, the camera shivers about a pixel and a half for a tenth of a second, gains half a
thousandth of zoom, and the three padlocks and the dancer jitter by up to 0.75x the
intensity. A fine shiver, not a punch — `beatHit` is the punch.

What `BarsVisualizer` measures to produce that number is its own business and this port
cannot read the same signal, so the substitution is named where it lives: `menu_visualizer`
emits `peaked(intensity)` with intensity = the loudest band's level doubled, which puts a
full-scale bar at 2.0 and keeps the mod's own 1.35 meaning "well past half". The shake is
written to the camera's `position`, not its `offset`, because `updateCameraScroll` owns
offset and lerps it every frame — a shake written there is eaten by the lerp and leaves a
drift behind.

**`initMusic` (0x17ffeb0)** plays the theme and then, at line 181, loads
`Paths.music('AnimaniaLOOPbass')` into `bassSound` (field 0x188) at the music's own volume,
looped, autoplaying. **The menu loop is two stems.** `AnimaniaLOOPbass.ogg` had already been
extracted next to `animaniaLOOP.ogg` and was simply never played, so this port had been
running the menu without its bass. An asset sitting unused next to one that IS used is worth
a second look — that is the same lesson as "never delete an asset because it looks orphaned",
read from the other end.

`createBackground` (0x1800500) came back clean: `menus/menu/menu background`, centred on
`FlxG.width/height`, `scrollFactor` 0.65, then `x -= 75`. Every one of those is already in
the port.

### The second `__GetFields` trick, and the offsets NOT to port

`FlxSprite_obj::__GetFields` names the sprite side the same way, and `updateHitbox`
(0x512bff0) anchors it: it writes `-0.5 * (width - frameWidth)` into one point and
`frameWidth * 0.5` into another, so

    0x158 origin    0x160 offset    0x168 frameOffset    0x170 scale

That settles two readings at once. `toggleSocialButtons` tweens `newsButton.offset.x` from 0
to 500, and flixel draws at `x - offset.x`, so the banner really is pushed 500 to the LEFT.
And `musicSocialPlayAnim` (0x180fc10) writes `frameOffset`, not offset:

    623  var offsets = ['selected' => [8, 8], 'press' => [80, 67]];
         musicSocial.animation.play('soundtrack ' + name, force);
         musicSocial.frameOffset.set(o[0], o[1]);

**That one is deliberately not ported, and the reason is worth keeping.** Those numbers are
the mod re-centring animations whose authored canvases are different sizes — `music_social`'s
Sparrow frames are 158x135 for `basic`, about 311x310 for `white` and 341x334 for `press`.
Godot's `AtlasTexture` carries that as `margin`, and the builder emits it: fourteen of the
frames in `music_social_frames.tres` have a non-zero margin. An `AnimatedSprite2D` with
`centered = true` therefore re-centres each frame on its own authored canvas already.
Applying the mod's `frameOffset` on top would double-count it and fling the disc a hundred
pixels on click. Where the engine already does by construction what the mod does by hand,
porting the hand-work is a regression.

That dispatcher is also where the destinations diverge: only `freeplay` and `options` reach
`startTransitionToMenu` (0x180ad15, 0x180af65). `storymode` allocates
`StoryMenuSelectSubState` over a menu that is still standing — no curtain run at all, which
is why backing out of the picker has nothing to reverse — `credits` opens a `StickerSubState`
and `exit` runs the audio-filter ramp.

### One capture is not the build you have

The mod's own main-menu capture and this 0.6 Linux build **disagree**, and it took a while
to accept it. The plate is at world x = 700 in the binary (centred, then
`plate.set_x(390 + x)`) and the capture has its left edge on 693 — seven pixels, fine. But
`createMusicSocial` puts the OST disc at (570, 590) with a 158x134 frame, so Flixel draws
it centred on (649, 657), and the capture has that centre on (645, 620): **37 out in y and
right in x**. `createVisualizers` puts the waveform's spine on x = 28 and the capture has
it near 97: **69 out in x**. Three different offsets on three elements rules out a camera
transform — a zoom or a scroll would move all of them together, and the mouse-driven scroll
above only spans ten pixels anyway.

So the disc's pair is kept as the ONE calibration between the two — `WORLD_OFFSET` in
`main_menu.gd`, (-4, -37) — and everything the menu places against `FlxG.width/height` takes
it, so the OST widget stays in one piece and lands where the capture has it. Where the
binary and the capture cannot both be satisfied, the binary wins and the difference is
written down rather than tuned away.

---

### The title screen: the citations were fine, two of the readings were not

`animania.states.TitleScreen` is the compiled half of that screen (the intro text is
`TitleScreen.script`, plain HScript). Its twelve methods live around 0x2b2xxxx, and the
comments this port carries cite things like `0x2ed0ce8` — which look like nonsense until you
notice they are the **RIP displacement bytes**, not the resolved data address. They are from
this build and they are correct; only the convention is confusing. `0x2ed0ce8(%rip)` from
inside `update` resolves to `0x59fad78`, which holds 1/24.

Read against the port:

- **The camera never stops moving, and the port had none of it.** `update` line 365
  (0x2b2a069-0x2b2a13f):

      var t = FlxG.game.ticks * (1/24);
      var wobble = Math.sin(t / 15 / Math.PI) + Math.sin(t / Math.PI) / 5;
      camera.scrollAngle = wobble + (outroAngle - wobble) * lerpOutroFactor;

  `ticks` is milliseconds, so the slow term turns over about every seven seconds and the
  fast one about every half second: a degree of sway with a fifth of a degree of flutter.
- **"Skipped when [this + 0x158] != 0, which is the follows_singer flag" was invented.**
  `follows_singer` is a PlayState idea and has no business here. `__GetFields` names
  TitleScreen's members — `inIntro, transition, txtVersion, camOverlay, blackScreen,
  gradient, nonIntroGroup, propsGroup, pressEnterText, fallBF, fallGF, logoTV,
  particleEmitter, titleText, boilShader, BOIL_INTERVAL, boilTimer, introSound,
  lerpOutroFactor, outroAngle, lastBeat, cheatArray, curCheatPos, cheatActive,
  playingLoveJingle, swagShader` — and 0x158 is `lerpOutroFactor`, the weight of that
  scrollAngle lerp. The zoom lerp has no condition at all.
- **The zoom rate really is -3.125 here.** There is no `addsd %xmm0,%xmm0` in this one,
  unlike `MainMenuScreen::updateCameraZoom` where the same-looking code doubles it to -6.25.
  Two screens, two rates; the port had both right by luck and now by evidence.
- **`MUSIC_FINAL_VOLUME = 0.7` was a misattribution.** The 0.7 is at the displacement the
  comment names, but doJingle line 548 (0x2b24b49) puts it in the `Null<double>` of
  `FunkinSound.playOnce(Paths.sound('confirmMenu'), 0.7)` — it is the confirm SOUND's volume.
  The music's own numbers are in `playMusic` (line 295): the options anon carries
  `{overrideExisting: true, startingVolume: 0, restartTrack: true}` and its closure sets
  `volume = 1.0` (0x2b241fc). The loop starts silent and ends at full, and `gfLoveJingle`
  goes through `playMusic` with no volume override at all.
- **`FLASH_COLOR = BLACK`, `FLASH_DURATION = 8.0` are right.** playIntro's `Null<int>` block
  at 0x2b239d6 is `0xFF000000` — opaque black — and the duration double is 8.0. `skipIntro`
  (line 334) has its own, shorter one: `camera.zoom += 0.1`, everything visible, `alpha = 1`,
  `FlxTween.cancelTweensOf`, and a **1.0s** flash.
- `beatHit` (line 445) dispatches `'titleBeat'` into the script (0x2b2b840), which is exactly
  the split this port already assumes: the compiled side counts beats, the HScript places the
  text.
- `seenIntro` is a **static** (0x7fa8008), set by playIntro and read by playMusic, so the
  intro plays once per RUN and is skipped afterwards.

**The confirm is an outro, not a scene change.** `update`'s back half, lines 404-439:

    404  pressEnterText.animation.play('press');
    405  FlxG.camera.flash(<colour>, 0.75);
    407  FunkinSound.playOnce(Paths.sound('confirmMenu'), 0.7);
         transition = true;                                   // field 0xd1
    410  FlxTween.tween(<a>, {y: <a>.y + 600}, 1.8, {ease: cubeIn});
    416  new FlxTimer().start(0.5, ...);
    420  var r0 = FlxG.random.float(0.25, 1.75);   // and r1, r2 the same
    424  FlxTween.num(0, 1, 1.8, {ease: cubeIn}, <the driver at 0x2b213a0>);
    434  FlxTween.tween(<b>, {y: <b>.y - 100}, ..., {ease: cubeIn});
    439  moveToMain();

That `FlxTween.num(0, 1, 1.8)` is the outro's progress, and its driver (line 427) runs one
formula three times, once per random: a `pow` curve keyed on `1.5 * progress` against 0.75,
times **1400**, times that sprite's own random — the three title pieces are flung off screen
at different speeds. The three are `fallBF`, `fallGF` and `logoTV`. And the progress is the
same `lerpOutroFactor` that weights the scrollAngle lerp, so the camera swings from its
wobble to `outroAngle` across the same 1.8s. `outroAngle` and the factor are reset together
at 0x2b254b4: the factor to 0, the angle to `FlxG.random.int(-10, 0) * 2` — the
`add %eax,%eax` after the call is the doubling, so it lands between 0 and -20 degrees, rolled
per visit.

Ported: the press animation, the 0.75s flash, the sound at 0.7, the camera swing, and the
1.8s before the scene changes — this port used to jump straight to the menu. Written down
rather than faked: the three-way 1400px fling, because this scene has one Logo where the mod
has three sprites, and building them is `create()`'s job.

**`create()` (0x2b26ea0, lines 137-266)**, the layout, in order:

    141  swagShader = new ColorSwap();
    143  FlxG.mouse.visible = <bool>;
    145  camOverlay = new FullScreenCamera(...);  FlxG.cameras.add(camOverlay, false);
    149  particleEmitter = new FlxTypedEmitter(-100, ...);
    150      loadParticles(Paths.imageGraphic('menus/particle'), ...);   // SQUARE mode
    154      velocity.set(-50, -950, 50, -750);      // straight up, fast
    159      scale.set(0.35, 0.35, 0.1, 0.1);
    161      <colour>.set(0xFFFFC0CB, 0xFF00FFFF, 0xFFFFFFFF);   // pink, cyan, white
    163      start(<bool>, 0.09);
    165  propsGroup = new FlxTypedGroup();
    167  six x new TitleProp(), each parked at -1000000
    168  updateProps();
    173  gradient  = 'title/void gradient', sized off FlxG.initialWidth
    186  nonIntroGroup = new FlxTypedSpriteGroup(...);
    189  fallBF = new FallCharacter();  'title/fallguys', addByPrefix('fall', 'bf fall', 24)
    195      x = FlxG.width / 3 - 100
    198  fallGF = new FallCharacter();  'gf fall', same shape
    209  logoTV        = 'title/LOGO_OBJECT',  scale 0.32 both axes
    219  pressEnterText = 'title/PRESS_ENTER', addBySymbolIndices('loop', [2 indices])
    223                                        addBySymbolIndices('press', [30 indices])
    225      play('loop')
    229  txtVersion = FlxFixedText('Animania! Mod ' + Constants.VERSION_clear), vcr.ttf, 12
    237  titleText  = FlxFixedText('ANIMANIA!CREW' / 'Hello there! :>'), Blueprint.ttf
    243  boilShader = new BoilShader();  bumpTimer();  set_amount(1.0);
    254  playMusic();
         if (seenIntro) skipIntro(); else playIntro();

`LOGO_SCALE = 0.32` checks out exactly (0x59fb4e0). **`CONFIRM_DELAY = 0.35` does not.** The
0.35 is at the displacement the comment names, but both loads are in line 159 feeding the
emitter's `FlxPointRangeBounds.set(0.35, 0.35, 0.1, 0.1)` — it is the PARTICLES' start scale,
shrinking to 0.1, the same pair the main menu's emitter uses. There is no deaf window in the
mod at all: `inIntro` and `transition` are separate branches of `update()`, so one keypress
can only ever be consumed by one of them. The window stays in the port as its own device, now
labelled as such.

Ported from this: the particle emitter. Still missing and now named, with the assets already
extracted (`title/fallguys.png+xml`, `title/props.png+xml`) — the six props' placement beyond
what `title_props.gd` already carries, the two `FallCharacter`s (which are two of the three
pieces the outro flings), and the two texts. `Blueprint.ttf` is not on disk; like
Inconsolata-Black it ships inside the executable and would have to be extracted.

**The cheat code comes out of the binary whole.** `cheatCodeShit` (line 514, 0x2b265b0)
polls **eight** Controls actions — the four arrows at 0x30/0x38/0x40/0x48 (named by the
main-menu audit) and four more at 0x90/0x98/0xa0/0xa8, which are the gameplay lane keys, so
either set works — and calls `codePress(flag)` with one of four bits per direction.
`codePress` (line 526) is not only a script dispatch: it walks `cheatArray` (0x168) against
`curCheatPos` (0x170) and fires `doJingle()` on the last one (0x2b26532). `__construct`
builds the array from `_hx_array_data_46b436b0_1` at 0x5ba9a40, eight ints:

    [1, 16, 1, 16, 256, 4096, 256, 4096]

Pairing those against the order the eight polls appear in gives 1 = UP, 16 = DOWN,
256 = RIGHT, 4096 = LEFT — so the sequence is **UP DOWN UP DOWN RIGHT LEFT RIGHT LEFT**, a
Konami riff. This port had the right SHAPE (A B A B C D C D) with the wrong letters, which is
what a guess looks like when it is close. Fixed, lane-key aliases included.

`destroy()` (line 488) is short and had no equivalent here: `super.destroy()`, a FlxSound
cleanup, and `if (playingLoveJingle) FunkinSound.playMusic(Constants.defaultThemeTrack, ...)`
— leaving the title while the cheat's jingle plays puts the normal theme back so the next
screen does not inherit it. Ported.

**The two `FallCharacter`s, and the fling they exist for.** create() lines 186-206:

    186  nonIntroGroup = new FlxTypedSpriteGroup(...);
    189  fallBF = new FallCharacter();  loadFrames('title/fallguys');
    191      screenCenter();                      // (FlxG.width - width) * 0.5, same for y
    192      animation.addByPrefix('fall', 'bf fall', 24);
    194      x -= FlxG.width / 3;   y -= 100;
    198  fallGF = the same, with 'gf fall', x += FlxG.width / 3, and moves = false (0x250)

`fallguys.xml` has six subtextures, three frames each. Both are built into the scene now,
under a `NonIntro` node that stays hidden until the intro's 31 beats are done — which is
what `nonIntroGroup` means.

They exist for the outro. The driver at 0x2b213a0 gives, exactly: the setter is vtable
**0x218**, which is `set_y`, so the fling is **vertical**; the travel is **1400** times that
piece's own `FlxG.random.float(0.25, 1.75)`; and the curve is a `pow` whose exponent is the
0.75 loaded beside it, behind a NaN guard on `1.5 * r`. How the pow's base and the sprite's
resting y combine into the final `set_y` is this port's reading — the registers cross a call
boundary the dump does not resolve — so it is written as `y = rest - 1400 * r * pow(t, 0.75)`,
the only arrangement of those three that leaves the piece at rest when `t = 0`. The three
pieces are `fallBF`, `fallGF` and `logoTV`; all three are wired.

Two stale comment blocks in `title_screen.gd` were removed rather than left to contradict the
code: the `follows_singer` claim, and the old cheat sequence. A comment that disagrees with
its own function is worse than no comment — it is what sent this audit chasing a wrong
binary in the first place.

**The two texts, and how to get a font out of the executable.** create() lines 229-241:

    229  txtVersion = new FlxFixedText(10, 10, ?, 'Animania! Mod ' + VERSION_clear);
    230      font = 'assets/fonts/vcr.ttf';
    231      x = FlxG.initialWidth - x - width;      // right edge, the same 10 margin
    232      alpha = 0.9;
    237  titleText = new FlxFixedText(0, 0, FlxG.width, 'ANIMANIA!CREW');
    238      alignment = 'center';
    240      font = 'Blueprint.ttf';

`VERSION_clear` is `'v'` plus the manifest's version, and the binary carries `0.6.0`. Note
what **'Hello there! :>'** is not: it sits beside these two in .rodata and reads like a third
caption, but it is the Discord presence string that goes with `'Title Screen'` through
`changePresence` at line 137. Adjacent strings are not related strings.

### What rendering the screen found that reading it did not

`title_shot.gd` now takes six frames: three inside the intro, one on the finished title, and
two inside the confirm outro. Running it caught three things the audit had not.

1. **The 31-beat intro was dead code.** `_run_beat` had no caller: commit `affb218`
   ("Fix camera lerp to only run during intro") rewrote `_process` and took the beat driver
   with it, so the BEATS table, the text spelling itself out, the bars and the zoom punches
   had not run since. `flow_check` never saw it, because it only asks whether `_finish()`
   leaves the title visible — which it does whether or not a single beat ever ran. The render
   said `beat=0` in all six frames with the text field empty. Restored, driving off the
   music's playback position with `_elapsed` as the headless fallback.
2. **The background did not cover the view.** The camera RESTS at 0.885, so it shows
   `1/0.885` more world than the screen, and a gradient sized to exactly 1920x1080 left grey
   down both edges and along the bottom. The beats only ever zoom IN from the rest, so the
   resting zoom is the widest view there is; the gradient is sized and centred for it now.
3. **The press-enter prompt was drawing all along — as the "props".** Those scattered white
   letters across the top of every title render were not `title_props`; they were
   `PRESS ENTER TO PLAY` permanently in mid-flight. `main`'s timeline is 34 frames of the
   letters assembling themselves, and the library that ships beside the atlas animates the
   whole timeline, so the port looped the assembly forever.

   create() lines 222-223 say which frames belong to which state, by symbol index: `loop`
   pushes **[1, 2]** and `press` pushes **[3 .. 32]** — the thirty that "30 indices" meant.
   So the two-frame hold is the idle and **the scatter is the CONFIRM animation**.
   `build_title_scene.gd` rewrites both animations over those spans now, and `confirm()`
   plays `press_enter_press`.

   Two traps on the way: the symbol resolves fine (`main` IS in the dictionary, and the node
   reported 73 canvas items) so "nothing is drawing" was the wrong diagnosis from the start —
   it was drawing in the wrong place. And the AnimationLibrary is an **ExtResource** in the
   packed scene, so mutating the loaded copy changed nothing on screen until it was written
   back with `ResourceSaver.save`.

4. **The clear colour was grey.** Flixel clears to black — `FlxCamera.bgColor` defaults to
   `FlxColor.BLACK` and every screen in the mod is drawn on that — while Godot's default is a
   mid grey. That is what showed around the title's gradient, and it would show anywhere else
   a screen does not cover the full view. Set once, in `project.godot`, not per scene.

The general lesson is (1) and (3) together: **a guard that checks a flag is not a guard that
checks the screen.** Every constant on this screen had been read against the binary and half of them
corrected, and the whole sequence they drive was still not running.

### The news banner: an invented scale, and a probe that measured the camera

"The bottom-left icon is missing" turned out to be one number nobody had read out of the
binary. `build_main_menu.gd` carried `NEWS_SCALE := 0.5` with a comment claiming
`createNewsButton` placed the banner "at (-70, 620) at scale 0.5". The position was real; the
scale was not. Read line by line, `createNewsButton` (0x18017a0, Haxe lines 401-417) is:

```
401  newsButton = new FunkinSprite(-70, 620, Paths.getLibraryPath('menus/changelog/news_button'))
403  anim.addByFrameLabel('idle',     'loop white',  24, true)
404  anim.addByFrameLabel('selected', 'loop white2', 24, ...)
405  anim.addByFrameLabel('open',     'open',        24, ...)
406  anim.play('idle')
407  anim.updateTimelineBounds()
408  scrollFactor.set(0.5, 0.5)
409  zIndex = 26
410  zoomFactor = 0.875
411  add(newsButton)
413  initHitbox(-10, 10, 215, 90)
414  x -= 350
415  FlxTween.tween(this, {x: x + 350}, 0.65, {startDelay: 1, ease: expoOut})
417  FlxMouseEventManager.add(newsButton, over, out, down, up)
```

There is no `setGraphicSize`, no `scale`, nothing between the constructor and `add` that
touches size. The banner draws at the atlas' own 213x104. At 0.5 it became a 160x78 sliver
that sat almost entirely past the left edge, which is exactly what "missing" looked like.

Two conventions worth keeping from the read:

- **The constructor's two `Dynamic(int)`s are built right to left.** `Dynamic(620)` is
  constructed first and `Dynamic(-70)` second, and the call then passes `-70` in `rdx` and
  `620` in `rcx`: the LAST parameter is the FIRST Dynamic built, so the first one you see in
  the disassembly is Y, not X.
- **`initHitbox` is not the art.** `FunkinSprite::initHitbox` (vtable +0x440) allocates a
  `FunkinAttachedSprite` into field 0x290 and it is that rectangle - offset (-10, 10), size
  215x90, in Funkin px relative to the sprite's own x/y - that `FlxMouseEventManager` gets.
  The port's `touch_rect` had been guessed from `new_update_bub.png` being 1184x106, a
  flattened copy of the same banner that the screen never loads.

And a trap in the measuring, not in the code. The first probe moved the node to a known
point, tinted it magenta and read the drawn bounding box, and reported the art landing about
215 px LEFT of the node origin - which would have meant the symbol needed a corner
compensation like the title logo's `LOGO_CORNER`. It needed none. Two things were wrong with
the probe: it left the menu's own `Camera2D` in place (zoom and offset both non-unit, and the
menu jitters the camera every frame), and it compared a bounding box in VIEWPORT pixels
against a node position in WORLD pixels. The window override makes those differ by
1365/1920 = 0.711. Neutralise the camera and divide by that ratio and the art sits at the node
origin, +10 px of transparent margin, exactly where `centered = false` says it should.

So: when a probe reports a placement, it has to report the viewport size and the camera it
measured through, or the number it gives back is a number about the camera.

One more thing the render itself caught: `menu_states.gd` shot "02settled" the moment the
intro ended, at about t=1.4 s. The banner's entrance is `startDelay 1` plus `0.65` of expoOut,
so at that instant it is still legitimately off the left edge. The harness now holds until
t=1.9 before that shot - a screenshot taken before an animation has finished is not evidence
that the animation is broken.

### `handleInput`: the axes were swapped, and the `Controls` object hides behind three hops

The port had UP/DOWN changing the SONG and LEFT/RIGHT changing the DIFFICULTY. The binary
has it the other way round, and once the disks turned out to be a horizontal row rather
than the invented vertical column, left/right for the song is the reading that makes sense
of the whole screen at once.

```
1828  if (UI_LEFT.checkPressed() || UI_RIGHT.checkPressed()) {
1835      if (spamming && spamTimer >= 0.07)                 // repeat while held
1844      else if (!spamming)                                // first press
              changeSelection(UI_LEFT.checkPressed() ? -1 : 1);
      } else { spamming = false; spamTimer = 0; }
1854  UI_UP.checkJustPressed() / UI_DOWN.checkJustPressed()
1856      changeDiff(UI_DOWN.checkJustPressed() ? -1 : 1);
1861  <something>() -> handleExit();
```

Two things needed real care:

- **Pairing each `checkPressed` with its action.** An earlier pass got two of seven wrong
  because it took "the last plausible offset seen". The reads come in two shapes and both
  have to be matched: `PlayerSettings.player1` → `mov 0x10(%rax),%r15` (`.controls`) →
  `mov 0xNN(%r15),%rdi`; or three chained `operator->` calls with the offset in the `lea`
  *between* them — `lea 0x10(%rax),%rdi` then `lea 0x30(%rax),%rdi`. Bounding the search to
  ~14 instructions before each call and only accepting known action offsets resolved all
  seven. The offsets are 0x30 UI_UP, 0x38 UI_LEFT, 0x40 UI_RIGHT, 0x48 UI_DOWN,
  0x108 ACCEPT, 0x110 BACK, 0x158 DEBUG_MENU.
- **The sign is an idiom, not a constant.** `cmp $1,%al; sbb %eax,%eax; and $2,%eax;
  sub $1,%eax` is `condition ? -1 : 1` — worth recognising on sight, because it is where
  the direction of every one of these lives. LEFT is -1, and, less obviously, DOWN is -1
  for the difficulty.

`checkPressed` versus `checkJustPressed` is the difference between a key that repeats and
one that does not: selection repeats every **0.07 s** while held, difficulty does not repeat
at all. An event-driven port gets neither — it inherits the operating system's repeat rate
for both.

And the reason a whole third of the conditions were missing from the first scan:
**`FunkinAction.check()` is VIRTUAL** — slot 0x100 on its vtable — while `checkPressed()`
and `checkJustPressed()` are direct calls. Grepping the disassembly for the method names
finds the latter two and silently drops every use of the first. In freeplay that was three
conditions, including both of the important ones:

```
1807  ACCEPT.check()       -> the confirm path (reads selectableDisks.length, curSelected)
1859  BACK.check()         -> handleExit()   (1861)
1864  DEBUG_CHART.check()  -> the chart editor for the selection
```

`DEBUG_CHART` is `Controls` field 0x160. The full action table, from
`Controls_obj::__GetFields`, is worth having whole: 0x30 UI_UP, 0x38 UI_LEFT,
0x40 UI_RIGHT, 0x48 UI_DOWN (and 0x50-0x88 their P/R variants), 0x90-0xa8 the note
directions, 0xf0 MECHANIC, 0x108 ACCEPT, 0x110 BACK, 0x118 PAUSE, 0x120 RESET,
0x128 WINDOW_SCREENSHOT, 0x130 WINDOW_FULLSCREEN, 0x138 FREEPLAY_FAVORITE,
0x140 FREEPLAY_LEFT, 0x148 FREEPLAY_RIGHT, 0x150 CUTSCENE_ADVANCE, 0x158 DEBUG_MENU,
0x160 DEBUG_CHART, 0x168 DEBUG_STAGE. Note that freeplay uses the generic UI_LEFT/UI_RIGHT
and not `FREEPLAY_LEFT`/`FREEPLAY_RIGHT`, which exist and are for something else.

### The small methods are where the assumptions hide

Seven of the shortest methods left in `FreeplayScreen`, read properly rather than skimmed.
Three of them said something the port had got wrong, and one of them said nothing at all —
which was itself the finding.

- **`openHelp` (0x34bc930, line 1685) is EMPTY.** Its 312 bytes are the hxcpp stack-frame
  prologue and epilogue and not one instruction between them. The port's `pass` was right
  by accident: its comment said "in the full mod, `FreeplayScreenHelp` manages this", when
  in fact this method calls nobody. `FreeplayScreenHelp` exists — 22 symbols — and
  something else opens it.
- **`destroy` (1981-1998)** ends with `FunkinSound.playMusic(Constants.defaultThemeTrack,
  {overrideExisting: true, restartTrack: false})`. `defaultThemeTrack` lives in `.bss`, so
  it cannot be read out of the file — it is read out of `Constants_obj::__boot` at
  0x1f8dec7, and it is `'animaniaLOOP'` (length 12, matching the `movl $0xc` beside it).
  Both anon fields are read too, not assumed: `overrideExisting` true, `restartTrack` false.
- **`fadeOut` (line 877)** does exactly one thing: `FlxTween.cancel` on the sound, then a
  volume tween with an `onComplete`. The port had `_load_songs` + `_refresh` +
  `_init_characters` + `_update_data_stuff` bolted onto the end of it "from the HScript
  bridge pattern" — not in this method, not anywhere on this screen.
- **`getCurrentDisk` (579-586)** is a bounds-checked accessor, and the port was indexing
  `disks.get_child(cur_selected)` — the same child-index-versus-ID confusion `updateDisks`
  had.

And a tool bug that would have quietly corrupted all of this: `hxlines.py` matched symbols
by SUBSTRING, so asking for `build` returned `buildBg` — 460 bytes of one method reported as
14 018 bytes of another, with no warning. It now matches the method name exactly.

**The near-miss worth recording.** Porting `destroy`'s music restore, I wrote
`get_node_or_null("/root/MenuMusic")` — an autoload this project does not have (its three
are `ErrorLog`, `MusicFilter`, `DebugOverlay`). It would have compiled, returned null, and
done nothing for ever while looking ported. The real answer is that this line has no port at
all: the mod has one global `FlxG.sound.music` that freeplay must hand back, while here
each scene owns its own players and the main menu rebuilds them in `_init_music` on the way
back in. A line with no counterpart should be written down as having none, not aimed at an
invented node.

### `initHeader`: the z-order is read, the positions cannot be

`initHeader` (0x34cca20, lines 1428-1545) builds the top-right furniture, and it settles
the one number that was still an admitted guess — the UI layer's z-order:

```
1428-1437  a backing panel, 0xFF000000, zIndex 50
1440-1453  helpButton         'animania-freeplay/help',       zIndex 52, alpha 0.4
1485-1497  charactersButtons  'animania-freeplay/characters',  zIndex 52
1506-1512  clearBoxSprite     'bg/clearBox',                   zIndex 52
1514-1519  completionText     AtlasText 'freeplay-clear',      zIndex 53
1540-1545  freeplayScore                                       zIndex 54
1521-1532  highScoreSpr       'animania-freeplay/highscore',    zIndex 55
```

Both buttons carry one 19-frame prefix that `addByIndices` splits into `idle`
(0..17 then back to 0) and `pressed` (frame 18) — the index arrays are readable straight
out of the `Array_obj<int>::fromData` calls. `highScoreSpr` is
`addByPrefix('y', 'highscore small instance 1')` followed by `finish()`, so it sits on its
last frame.

**The positions are a different matter, and not for lack of trying.** `initHeader` places
nothing by constant: every piece is positioned from `albumRoll.width`,
`highScoreSpr.height` and a margin of **76**. Until `AlbumRoll` exists in the port — it is a
`funkin.ui.freeplay.AlbumRoll` — those expressions cannot be evaluated, so there are no
numbers to read. The only literal is the 76. The port's placements stay approximate and are
marked as such in the builder, rather than dressed up as read values.

### `changeSelection` and `changeDiff`: where the score comes from

`changeSelection` (0x34c8f30, lines 818-864) in order: wrap the index, **play
`freeplay/song switch` at 0.4 first** (line 824, not last), start a timer, refresh the info
texts, rebuild `currentDiffsIds`, **call `changeDiff()`** (840), `changeCharacter` on both
characters (842-843), `updateDisks` (852), `refresh` (856), the script event, and
`updateDataStuff` (864).

`changeDiff` (0x34c7a40, 978-1073) is the one that matters, because it is where the numbers
come from:

```
 989  currentDifficulty = MathUtil.curSelectionWrap(...)
1004  FunkinSound.playOnce(Paths.sound('freeplay/diffChange'))
1009  SongRegistry.instance ...   (warns to the console if the song id is unknown)
1020  Save.instance.getSongScore(<song>, <difficulty>)
1021  score = <that>.score
1022  <that>.tallies.sick / .good / .totalNotes    -> the completion percentage
1073  updateDataStuff(false)
```

So `intendedScore` and `intendedCompletion` — the two numbers `update` eases toward — come
from **`Save.getSongScore` and its tallies**. That is the missing piece behind
`updateDataStuff`, and it needs a save file the port does not have.

**Reading a `Null<T>` default takes the prologue, not a guess.** `changeSelection` calls
`changeDiff()` with both arguments null, and what null MEANS is written at 0x34c7a69:
`xor %eax,%eax` before each flag test, so the fall-through value is 0 — `amount = 0` and
`playSound = false`. Without that, adding the `changeDiff()` call would have made every
song change play two sounds. The convention, confirmed twice now: the `Null<T>` pair is
`{flag, value}` and **flag 0 means present**.

Not fully traced: the `playOnce` at 1004 sits behind a second gate, `cmpb $0x0,0x2d8`
(`allowInput`), and how that composes with the `playSound` branch is lost in the
compiler's block reordering. The port plays it on a deliberate difficulty change and stays
quiet when a song change drags one along.

### hxcpp does not always keep declaration order

`FreeplayScreen` declares `totalDiffs:Int`, `curSelectedFloat:Float`, `curSelected:Int` in
that order, and lays them out as **0xf8 curSelectedFloat, 0x100 curSelected,
0x104 totalDiffs** — the double moved in front of the two ints. The field table here had
them in declaration order and was wrong for all three.

`changeSelection` (0x34c8f30) settles it without any inference: `mov %eax,0x100(%rbx)` is a
four-byte store, so 0x100 is the Int, and `cvtsi2sdl 0x100(%rbx),%xmm0; movsd %xmm0,
0xf8(%rbx)` is literally `curSelectedFloat = curSelected`.

The lesson for reading a `__GetFields` list: declaration order gets the POINTERS right
(`__Mark` confirms those anyway), but within a run of scalars the sizes can be reordered.
Anchor every scalar on an instruction that reveals its width — a `movsd` versus a 32-bit
`mov` — before trusting its name.

### `hxlines.py`: read a big method as a table first

Three methods in a row were read by hand-rolling the same script, so it is now
`tools/animania/hxlines.py`. hxcpp stamps the source line into the stack frame before each
line's code, so everything a method does can be grouped by the Haxe line that produced it,
and for construction-heavy methods that turns instruction-by-instruction work into one
readable pass:

```
1241   =>darkOverlay  esi=-16777216  set_color
1243   z=8
1244   0.4  set_alpha
```

Per line it prints the field written, the `zIndex` immediate, the `esi` ints (hxcpp passes
constructor arguments that way), rip-relative strings and doubles, the vtable slot of each
indirect call, and the name of each direct one. `--fields freeplay` names the offsets.

Two things it got wrong before they were fixed, both worth knowing:

- **A stack slot is not a field.** `mov %rax,0x1f0(%rsp)` matched the same pattern as a
  field store and printed `=>tvNoiseForward` inside a `FlxTween.tween` line, where no such
  field is in play. Excluding `%rsp`/`%rbp` as the base fixes it. Field *reads* were also
  missing at first, which is the half that says WHICH object a `set_visible` is acting on.
- **The field table applies to any base register**, so `.curSelected` right after
  `.tvSprite` is really `tvSprite.animation` — 0x108 on `FlxSprite` collides with 0x108 on
  `FreeplayScreen`. The offset is the fact; the name is a hint.

### `buildBg`, read as a table

14 018 bytes and about 200 Haxe lines, but almost all of it is state: a sprite, its
position, its `zIndex`, sometimes an alpha or a colour. Dumping it as one line per Haxe
line — field written, `zIndex` immediate, `esi` constructor ints, rip-relative strings and
doubles, vtable slot — turns it into something readable in one pass, and that table is what
found the rest of this screen's mistakes. Worth doing before reading a big builder method
instruction by instruction.

What it gave up:

- **The draw order is a `zIndex` per sprite, not the tree order**: bgWall 1, bgBed 2,
  shadowsOnBed 3, tvGlow 7, darkOverlay 8, tvBg 10, diskPlayer 16, grpDisks 19, tvBackBG 20,
  diskPlayerMask 24, tvNoiseBack 26, albumRoll 27, tvNoiseForward 28, tvSpriteFlash 29,
  tvSprite 30, difficultyStars 35, selectorsGroup 100, bossfightSkull 900. The port had
  every node at 0 and leaned on tree order, which put `DarkOverlay` — an 8, i.e. *under* the
  television and the disks — on top of the entire screen because it was added last.
- **`darkOverlay` is 0xFF000000 at alpha 0.4** (1241-1244), not opaque.
- **The backdrop is 0xFF18121C** (1195), not black.
- `albumRoll.y = -100` with `albumId 'animania05'` and a GaussianBlur of 0.1 (1319-1324);
  `DifficultyStars(525, 120)` (1338); `bossfightSkull` at (105, -200) with its own
  `freeplay/bossIndicator` sound (1345-1357).

A Godot detail that matters when copying a flixel `zIndex` table: **a child's `z_index` is
relative to its parent's** unless `z_as_relative` is off. The disks are `5`/`10` inside
`grpDisks` in the mod, but that only orders them among themselves — the group occupies slot
19. Ported literally as `z_index = 5` under a parent at 19 they would sit at 24, on top of
`diskPlayerMask`. They are `0`/`1` here, which keeps both the relative order and the group's
slot.

### What `update` actually does, and where the port had put it

`FreeplayScreen.update` (0x34d7200) is short, and three of the seven things the port's
`_process` ran were not in it. In full:

```
super.update(elapsed);
lerpScore      = MathUtil.smoothLerpPrecision(lerpScore, intendedScore, elapsed, 0.65);
lerpCompletion = MathUtil.smoothLerpPrecision(lerpCompletion, intendedCompletion, elapsed, 0.65);
if (Math.isNaN(lerpScore)) ...            if (Math.isNaN(lerpCompletion)) ...
_prevDisplayedScore = Std.int(lerpScore);
freeplayScore.updateScore(Std.int(lerpScore));
completionText.text = Std.string(Std.int(Math.floor(lerpCompletion * 100)));
handleInput(elapsed); updateCameraScroll(elapsed); updateTvGlow(elapsed);
callOnScripts('update', [elapsed]);
```

So the per-frame work is: two eased numbers and their two labels, plus three calls. The
port instead ran `updateDisks`, `shakeShadows`, `checkBed` and `updateDataStuff` every
frame — all four of which the mod drives from events — and did *not* ease the score or the
completion at all. The easing it did have lived inside `updateDataStuff`, with an invented
factor of 0.1 and a threshold.

`MathUtil.smoothLerpPrecision(base, target, dt, duration, precision = 0.01)` (0x188bb20) is
`lerp(base, target, 1 - precision^(dt/duration))`, with an early-out when the gap is under
1e-7 — the value lands within `precision` of the target after `duration` seconds, which is
a different curve from a fixed per-frame factor and from a half-life.

And the completion label carries **no percent sign**: it is `Std.int(Math.floor(x * 100))`
and nothing else. The `%` is art — the same `CLEARED %` graphic already on screen.

### `updateDisks(elapsed)` does not take an elapsed

The signature is `updateDisks(double)` and the port had read that as a per-frame updater
with a delta. It is the SELECTION, as a float, which is why `changeSelection` calls it and
`update` never does. Read out, lines 798-807:

```
for (disk in grpDisks) {
    disk.x = (disk.ID - sel) * 225 - 20;              // 800
    disk.y = DiskSpr.intendedY(disk.ID - sel);        // 801
    disk.zIndex = 5;                                  // 802
    disk.selected = (sel == disk.ID);                 // 803
    if (sel == disk.ID) { disk.<0x258>.y -= 3; disk.zIndex = 10; }   // 804-807
}
```

and `DiskSpr.intendedY(d)` (0x200c7a0) is `(d * 1.5)² * 6 + 520`. So the carousel is a ROW
along the bottom on a shallow parabola — selected at (-20, 520), then (205, 533.5), then
(430, 574) — not the vertical column at (1390, 560) the port had. That column was invented,
and the comment above it said the constants "are not simple constants in the mod", while
`DISK_BASE_Y := 225.0` and `DISK_SPACING_Y := 20.0` sat four lines below, already read and
misnamed as Y quantities when 225 and 20 are the X formula.

Two smaller things fall out of the same line:

- **`disk.x` in flixel is the LEFT EDGE**, so the row aligns left and the disks do not all
  have to be the same width. The port had `centered = true` on them, which lines up their
  centres instead — visibly different once the disks differ in size.
- **A guard can encode the bug.** `flow_check` asserted that a tap at (120, 900) is not a
  disk, a point chosen to sit clear of the invented column on the right. With the real row
  that point is inside the first disk, so the guard failed on a corrected layout. The
  check moved to the wall above the TV. Worth remembering when a guard fails right after a
  fix: ask whether the assertion was written against the old, wrong behaviour.

### The television: three port-side guesses, and what the constants said

Wiring the TV's screen exposed that the port had the television in the wrong place, showing
the wrong frame. All three mistakes came from the same habit — placing something by eye and
writing the arithmetic down afterwards as if it had been read.

`buildBg` positions the TV housing with setters, so the port had reasoned: "the wall is 912
wide in a 1280 screen, which leaves 368 to the right, and the TV is 727 wide, so put its
right edge on the screen's, at x = 553." Plausible, and wrong. **The pieces INSIDE the TV
are constants, and they are what pins it down**: `tvBackBG`, `tvSpriteFlash`, `tvNoiseBack`
and `tvNoiseForward` all share a corner at (117, 128), and the first two are
`makeGraphic(375, 305, ...)` — a black rectangle and a white one, exactly a TV screen and
its flash. Anything four sprites agree on is not a coincidence.

The frame was wrong too. The `freeplay tv` sparrow holds six frames in three sizes: a
727×627 pair with an **opaque** screen and a blue halo, and two hollow pairs, 451×473 and
466×457. `buildBg` does `addByPrefix('f', ...)`, which matches all six, then `finish()`
(line 1281), which parks the animation on the LAST one — the hollow 466×457. The port sat on
the first, so the screen was a painted-on rectangle and nothing behind it could ever show.

And the geometry only closes once the sparrow's TRIMMING is taken into account. All six
frames declare `frameWidth 727 × frameHeight 749`, and the 466×457 region is pasted into
that canvas at (135, 288) — its `frameX`/`frameY` negated. Its screen hole runs (60, 49) to
(402, 326), so in canvas space (195, 337) + 342×277. With the sprite at the constructor's
own **(-60, -198)** that lands at (135, 139)-(477, 416), sitting just inside the
(117, 128) + 375×305 rectangle, which overhangs a few pixels on each side so the rounded
bezel leaves no gap. Godot's sparrow importer pads to the same common canvas, so the frame
index in the port is 2, not 5.

Two lessons worth keeping:

- **A constant beats an inference, even a tidy one.** The arithmetic about the wall was
  self-consistent and produced a screen that looked fine, which is exactly why it survived.
  It only fell over when something with real coordinates had to line up with it.
- **Render after the animation settles, not on frame six.** `doIntroAnim` plays the TV
  animation, so an early screenshot catches it mid-turn-on and on the wrong frame — the
  first two renders of this fix looked broken for that reason alone, not because the
  placement was wrong. `freeplay_shot` now waits.

### Making a fat atlas thin: measure the content, not the sheet

`TVBACK` (5492×8192 RGBA, 171.6 MB) and `TVNOISE` (5279×2528, 50.9 MB) were the two assets
that kept freeplay's television out of the port. `tools/animania/optimize_atlas.py` cuts
them to 40.7 MB and 10.4 MB — 4.2× and 4.9× — with nothing visible lost. What worked, in the
order the reasoning has to go:

1. **Repacking gains nothing here, and that is a measurement, not an opinion.** TVBACK packs
   41.4 Mpx of unique frames into a 45.0 Mpx sheet (92%); TVNOISE 12.5 into 13.3 (94%).
   Whatever exported them already packed them tight. Before rewriting a packer, sum the
   frame areas out of the `.xml` and divide.

2. **Look at what the frames are.** TVBACK is 98 frames of 668×721 — of which only **86 are
   distinct regions**, so 12 were already duplicates. Its content is scanline bands: measured
   over the opaque area, the mean vertical gradient is **3.51 and the horizontal 0.54**, a
   ratio of 6.45. Nearly all the information is in the row positions, almost none along a
   row. So reduce the WIDTH and leave the height alone. At equal memory (~120k px/frame),
   **167×721 scores 44.9 dB against 40.4 dB for an isotropic 334×360** — 4.5 dB free, just
   from resampling along the axis that carries less.

3. **TVNOISE is television static, and static has no continuity.** The correlation between
   the per-row brightness profile of any two frames is **0.05**: nothing drifts, every frame
   is an independent draw. So frames are interchangeable and 111 → 24 is invisible, while
   *resolution* is not free — downscaling changes the grain size, which is the one thing the
   eye does notice. Cut the frame count, keep the pixels. The kept frames come out
   bit-identical.

4. **Compare composited, at the size it is drawn.** The port draws these at 1.5×, so the
   reference is the original upscaled to 1002×1082, not the original. And compose over the
   background: an early pass of this used `Image.convert('RGB')`, which DROPS the alpha
   channel rather than compositing, and produced a bright fringe along the parallelogram's
   diagonal edge that does not exist on screen. That fringe sent me looking for a
   premultiplied-alpha fix for a problem the harness had invented — and premultiplying
   genuinely makes it worse here, because the alpha is 99.5% binary and un-premultiplying
   divides the edge pixels by a near-zero alpha. Straight-alpha Lanczos is correct.

5. **PSNR alone would have picked the wrong answer.** The isotropic and anisotropic options
   scored within 4.5 dB of each other while looking clearly different side by side, and a
   100×577 candidate at 40.9 dB visibly smears the short horizontal segments into streaks.
   Score to narrow the field, then look at a crop of the worst region before choosing.

The packer picks its rows by trying every `per_row` that keeps both sides under 4096 (a safe
GLES3 limit on Android) and taking the smallest area: for 86 equal tiles, 22×4 wastes two
slots where the square-ish 19×5 wastes nine. That is 90% → 97% occupancy for free.

**On disk is a different problem from in GPU, and it has different answers.** Getting both
files under 5 MB took two more things, neither of which touches GPU memory at all:

- **Colour depth.** Lanczos leaves 1.26 million distinct colours where the source art had
  fairly flat bands, and that is what inflates the PNG: compressed on their own the three
  colour channels cost 3.5-3.8 MB each and the alpha channel 0.06 MB. Quantising to **64
  levels per channel** takes TVBACK from 7.8 MB to 4.4 MB for 1.8 dB, with no banding
  visible in a side-by-side of the gradient areas (5 bits does start to eat the faint
  speckle). Reconstruct to the middle of the step, not its floor, or the whole image
  darkens by half a level. Compared against the alternative at equal file size - dropping
  to 122×721 at full colour depth - quantising wins, 43.1 dB against about 42.7, and it
  keeps the resolution where the band edges live.
- **Not widening the mode.** TVNOISE is `LA` (grey + alpha) and the first version of this
  tool did `Image.open(...).convert("RGBA")`, doubling it on disk without adding one colour.
  Preserving the source mode alone took it from 4.19 MB to 2.55 MB.

Final: TVBACK 3697×2889, **4.43 MB** on disk and 3.94 MB as `.ctex`; TVNOISE 1497×1813 LA,
**2.55 MB** and 2.06 MB. In GPU they are still 40.7 and 10.4 MB, because that is set by
pixel count and import mode, not by how well the file compresses.

One lever deliberately NOT pulled: every texture in this project imports with
`compress/mode=0` (lossless), so these two sit in GPU memory as RGBA8. Switching them to
VRAM compression would be another ~4× **in GPU**, but that is a project-wide convention
across 341 textures and a quality decision of its own, not something to change inside an
asset fix.

### Getting a font out of the executable

`Blueprint.ttf` is not on disk — `assets/fonts/` does not exist in the build and
`find -name '*.ttf'` over it returns nothing, because Lime packs fonts INTO the binary. But
an sfnt is self-describing: a header, a table directory, and a `name` table carrying the
family. So they can all be found by scanning for the signature and validating the directory.
`tools/animania/extract_font.py` does it:

    python3 tools/animania/extract_font.py --list
    python3 tools/animania/extract_font.py Blueprint animania_mod/source/fonts/Blueprint.ttf

That listed **forty** embedded faces — VCR OSD Mono, six weights of Inconsolata, Blueprint,
Comic Sans MS, Impact, CCMeanwhile, 5by7, DS-Digital, Quantico, Fafo Sans, Ruthless Sketch,
Dephunked BRK, Linglong, Brusnika, Monsterrat, Nokia Cellphone FC, Pixel Arial 11, MP Manga,
Funkin-options — so the next font this port needs is one command, not an investigation.

A newly extracted asset needs `--headless --path . --import` before a builder can `load()` it,
and that run rewrites `animania_mod/source/icon.png.import` with a fresh uid that no longer
matches `project.godot`'s `config/icon`. Revert that one file afterwards; it is the same trap
this file already warns about.

**`updateProps` and its closure (0x2b258f0)**, the last of the screen. The constant list
`title_props.gd` carried was partly guessed: it claimed "-550, 400" where the packed
`Null<int>` immediates are -550 and **-440**, and it was missing half of them. Measured:

    doubles  -300.0, 0.85, 1.15, 1.6, 2.05, 110.0, 50.0, 0.8, 0.7, 0.5
    ints     10, 200, -10, -200, -440, -550, 0

Two of them now have a job. Line 277 is `FlxG.random.float(0.85, 1.15)` and line 278 scales
the prop by `<ratio> * 0.8 + 0.7` times that jitter; and line 283 is unambiguous —
`get_width` (0x230) plus `get_height` (0x238), times 0.5, divided into **110** — so **a
bigger prop falls slower**. This port had a flat 50-110 range with no size term at all.

`POOL` was 9 with a note saying the number was not derivable. It is: `create()` line 167
allocates **six** `TitleProp`s, each parked at -1000000 until `updateProps` places one.

What the ratio in line 278 divides, and the two factors that multiply into line 283's speed,
are still unresolved. So what the port takes from 283 is the SHAPE — speed inversely
proportional to size — normalised on the prop's own art so it lands as `1 / scale`. A first
attempt invented a pixel constant to make the units work and put an average prop at 4600
px/s, across the screen in a quarter of a second; the runtime probe caught it. **When a
formula's units are not in the dump, take the relationship and normalise it, rather than
inventing a factor to close the gap — and then look at the number it produces.**

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

**A builder that does not know about a node DELETES it.** `build_freeplay_scene.gd` packs
the tree it builds and saves over `freeplay_screen.tscn`. Twelve nodes in that scene -
`ShadowsOnBed`, the whole `UI/` group with its labels, `ClearBox`, `DifficultyStars`,
`AlbumRoll`, `HelpButton`, and `DarkOverlay` - had been hand-added afterwards, and one run
of the builder wiped every one of them. `_resolve_nodes()` looks them up, so the screen
came back with nine null references and no error: `get_node_or_null` returns null and every
user of them checks for null first. **`flow_check` still said "todo OK".**

Two rules out of it:

- Anything the script resolves has to be BUILT by the builder. If you hand-add a node to a
  generated scene, put it in the generator in the same change or it is already lost.
- After running any builder, diff the packed scene against the committed one before
  committing, node by node. Differences that are only Godot dropping default values
  (`position = Vector2(0, 0)`, `text = ""`, `centered = true` on a Sprite2D) are noise; a
  missing `[node]` line is not.


**Vendoring an asset and building a resource from it in the SAME run produces a resource
with a dangling reference.** Three sparrow atlases were copied in and a `SpriteFrames` built
from each in one builder run, before Godot had imported the new PNGs. The builder loaded
them, reported the right animations, and `get_frame_texture(...).get_size()` returned the
right sizes — and the saved `.tres` came out with `AtlasTexture` sub-resources that have a
`region` and no `atlas` at all, because the source had no import to reference. At runtime
that is `ERR_CANT_OPEN` and a node that is `visible = true`, has an animation, has a frame
count, and draws nothing. Import first, then build the resource; or run the builder twice.

The debugging detour is worth remembering too: the first probe tinted the sprite magenta
and counted magenta pixels, and reported a large box in the wrong place. **The bedroom floor
is pink.** Pick a probe colour the scene cannot contain — green here — or the scenery
answers for you.

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

Two, and **which one to run depends on what changed** - running both after every edit is
waste, and running either after every intermediate edit is more waste:

```bash
run --headless --path . --script tools/animania/harness/flow_check.gd     # the whole flow
run --headless --path . --script tools/animania/test_phone_call_port.gd   # 853 checks
```

- `flow_check` instantiates the menus and walks them, so **any menu, transition or scene
  change needs it** - once, before the commit, not after every edit.
- `test_phone_call_port` is about the song: charts, characters, camera events, the death
  sequence. **Menu work does not touch it**, and running it there proves nothing.
- Both, only when the change reaches across the two - a scene the flow enters, a shared
  script, `AnimaniaModule`, the loading screen.

`flow_check` costs about **20 seconds**, measured. The "about four minutes" this file used
to claim was stale and it did real damage: it made long runs look normal, so a 600-second
hang got waited out instead of diagnosed. It was a parse error - the title screen's script
failed to load and the guard span in its title phase.

**Check that the scripts PARSE before running any guard.** It costs 0.6s and it catches the
whole class of failure that otherwise looks like "the guard is slow":

    # scratchpad/parse.gd
    extends SceneTree
    func _initialize() -> void:
        for p in ["res://.../title_screen.gd", "res://.../main_menu.gd"]:
            print(p, " -> ", "OK" if load(p) != null else "FALLO")
        quit()

Note the trap in it: `load()` on a script with a parse error still returns non-null, so the
"OK" it prints means nothing. What tells you is the `SCRIPT ERROR: Parse Error` lines Godot
writes to stderr - read those, not the return value.

**A run that takes more than ten seconds needs a reason, not patience.** Godot
itself starts and quits in 0.6s here, so anything longer is the script's own
work and can be located. Pipe the run through a timestamper and print only the
lines that took over a second:

    p = Popen([...], stdout=PIPE, text=True, bufsize=1)
    for line in p.stdout:  t = now - t0;  print(t, t - prev, line) if t - prev > 1

For `test_phone_call_port.gd` that says 73s total, and where: +17.6s before the
note-position checks, +21.1s before the standing death, +9s and +6s elsewhere -
all of it building level and character scenes off multi-thousand-pixel Animate
atlases. Not the check count; the scene loads.

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

**A frame is not a unit of time here.** Rendering is llvmpipe, and a frame of a
full menu takes the better part of a second, while a `Tween` runs on the real
clock. "Capture four frames after `change_level`" therefore lands three seconds
in, long after a 0.3s tween has finished, and the shot is identical to the
settled one - which reads as "the port snaps instead of tweening" when the port
is fine. Pass **`--fixed-fps 60`** whenever the shot is of something mid-flight;
four frames is then 0.066s and means it.


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
- **A harness that drives a screen into a scene change loses the node it is holding.**
  `menu_states.gd` calls `do_select()`, which ends by changing scene and freeing the menu;
  its next `_flush()` then threw on `_menu.BUTTONS` before `_step` could advance, so the
  process spun until it was killed - after having already written every screenshot. Check
  `is_instance_valid()` and quit. An exit code of 0 with the PNGs on disk is not proof the
  harness terminated on its own.
- **A shot taken before an animation finishes is not evidence.** Key a screenshot to the
  thing you are looking at, not to the nearest flag: the news banner's entrance ends 1.65 s
  in, well after the intro flag clears.

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
  for exactly this reason. Check atlas dimensions *before* vendoring. Both have since been
  cut down and vendored: see below. And note the three numbers are independent — pixels in
  GPU, bytes on disk, bytes in the APK — so say which one a budget is about.

---

## 8. What is deliberately not ported

Recorded so the next person does not go looking for a bug that is not there.

- **The modchart's `tanWave`.** The formula is recovered exactly —
  `x += clamp(tan(p·π), −6, 6) · 40 · value` — but `p`'s unit is unidentified, so porting it
  would be guessing the sway's scale.
- ~~**Freeplay's `TVBACK` and `TVNOISE`**~~ — done: cut from 222.5 MB to 51.1 MB by
  `optimize_atlas.py` (below), vendored, and wired as `TvBg`, `TvNoiseBack`,
  `TvNoiseForward`, `TvBackBG` and `TvSpriteFlash`, with `shakeShadows` hanging off the
  forward noise's frame changes the way `buildBg` line 1337 does it.
- **Freeplay's intro, below the top level.** The two timers and what they reveal are
  ported; three callbacks the 0.5 s closure registers are not — `tvSprite.animation`'s
  `onFrameChange` and `onFinish`, and `diskPlayer.animation`'s `onFinish` (lines 1605-1607)
  — nor `dotsGrp.setDots`, `albumRoll.playIntro`, or the two 0.291667 s `quadIn` colour
  tweens at 1619 and 1630.
- **Freeplay's shadow art.** `shadowsOnBed` is a `FlxLayerGroup` and `shakeShadows` scales
  its matrix, but nothing has been put inside it: the shadows ride on `tvNoiseBack` and have
  not been separated out. The transform is ported and correct; it is simply invisible.
- ~~**The main menu's mouse furniture**~~ — this entry is out of date. `newsButton`,
  `musicSocial`, `socialButtons`, `updateCameraScroll` and `spawnHelpMouseText` were all
  ported during the fidelity audit: the banner and the OST disc are real screen furniture
  even without a pointer, and the taps reach them through `_touch`. Kept here struck through
  so nobody reads an older commit's list and puts them back on the not-done pile.
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

## 8c. The freeplay theme music, and how the four files were chosen

`assets/music/freeplayThemes/` in the mod build is seven .ogg files, 21.4 MB. The port
shipped none of them, because `changeTheme` had been ported as if a "theme" were a
picture: it built `images/freeplayThemes/Freeplay_<song id>.png` and pasted it on the
Backwall. There is no such directory. A theme is music.

### What the binary actually says

`changeTheme` (0x34c2540, lines 920-970) takes the selected `DiskSpr`, reads two strings
off the `FreeplaySongData` at its offset 0x268, and crossfades two tracks:

| line | what |
|---|---|
| 920 | `theme = songData.<0xa8>` |
| 922 | `layer = "-" + songData.<0xb8>` — the dash is added here, not in the metadata |
| 925 | `if (theme != oldThemeName)` — nothing reloads when the name is unchanged |
| 933 | `FunkinSound.load("freeplayThemes/Freeplay_" + theme)` |
| 940 | `FlxTween.num(..., 1.0, {onComplete}, snd.volumeTween)` |
| 945 | `if (layer != oldThemeLayerName)` |
| 954 | `layerSound = FunkinSound.load("freeplayThemes/Freeplay_Layer" + layer)` |
| 960 | the same 1.0 s volume tween on the layer |
| 970 | `oldThemeName`/`oldThemeLayerName` updated, `onChangeTheme` dispatched |

The 1.0 is a literal: the double at 0x59fa558, loaded twice. The two path prefixes are the
literals at 0x5c28fa0 and 0x5c290f8; the second carries no dash for the reason above.

The only caller is `playCurSongPreview` (0x34c3670, the call is at 0x34c3984, line 911),
and that has exactly two callers of its own: `changeSelection` line 855, and the
one-second closure of `doIntroAnim`, line 1651. **That second one is load-bearing.** Line
1648 already calls `changeSelection`, but at that moment `allowInput` is still false and
`changeSelection` leaves through its own guard — so line 1651 is what actually starts the
first disk's theme. Port both calls or freeplay opens silent.

### Which files the port can reach

The theme and the layer are **declared metadata**, not derived from the opponent
character. I had assumed the opponent decided the layer and it is false — `dadbattle`
fights `dad-beast` and declares the layer `dad`. Straight from
`assets/data/songs/<id>/<id>-metadata.json`:

| song | freeplayTheme | freeplayLayer | in the port |
|---|---|---|---|
| phone-call | — | komi | yes |
| bopeebo | — | dad | yes |
| fresh | — | dad | yes |
| dadbattle | — | dad | yes |
| tutorial | — | — | in songs/, not in freeplay's list |
| cocoa | Base | christmas | no |
| eggnog | — | christmas | no |
| winter-horrorland | Base-ChristmasCursed | Christmas-Cursed | no |

A song that declares neither falls back to `Base` and `default` — `default` is the string
at 0x5c28e62, in FreeplayScreen.hx's own literal block. So the port reaches
`Freeplay_Base`, `Freeplay_Layer-dad`, `Freeplay_Layer-komi`, and `Freeplay_Layer-default`
as the fallback. **Four of seven, before touching a single sample.** The three Christmas
files belong to songs the port does not have; they are not deleted from anything, they are
simply not vendored. If a Christmas song is ported, copy the two or three files it names
from the table above and nothing else changes.

`preloadThemes` (0x34ba820, lines 398-405) caches every entry of the two statics
`freeplayThemes` (.bss 0x805ef58) and `freeplayThemesLayers` (0x805ef50) up front, plus
`music/freeplayRandomAnimania/freeplayRandomAnimania`. The port does not copy the blind
preload: it fires `load_threaded_request` on the reachable set instead, because loading
7.6 MB on entry is worse on Android than loading one track when `changeTheme` asks, which
has a full second of crossfade to do it in.

### The re-encode, and what it costs

`tools/animania/optimize_audio.py`. All seven sources are stereo 44100 Hz, 72.5 s, ~354
kbps nominal Vorbis — a wild rate for this material: `Freeplay_Base` keeps 98.4% of its
energy under 2 kHz and 0.076% above 12 kHz, and every track peaks 11-16 dB below full
scale. They are also seven distinct pieces: the pairwise correlation between any two
mono mixdowns is ~0.00, so there is nothing to deduplicate.

**Read this before trusting the numbers.** This box has no libvorbis. The only Vorbis
encoder available is ffmpeg's native one, which ffmpeg marks experimental and which
ignores every quality knob there is — `global_quality`, `q`, `b` and `cutoff` all produce
a byte-identical file. One fixed operating point, take it or leave it. With libvorbis this
should be redone and compared.

| file | before | after | |
|---|---|---|---|
| Freeplay_Base | 3.06 MB | 1.50 MB | 2.04x |
| Freeplay_Layer-komi | 3.06 MB | 1.88 MB | 1.63x |
| Freeplay_Layer-dad | 3.06 MB | 2.24 MB | 1.37x |
| Freeplay_Layer-default | 3.06 MB | 1.95 MB | 1.57x |

21.4 MB of source becomes **7.7 MB on disk**: 12.2 -> 7.7 from the encoder, and the other
9.2 MB purely from shipping what the port reaches.

What it costs, measured rather than assumed. Per-band error, in dB below the signal's
*total* energy (`--report` prints this): 29 / 41 / 43 / 39 for `Freeplay_Base`. In-band
SNR that works out to roughly 29 / 22 / 18 / 8 dB, so above 12 kHz the encoder effectively
discards the content — which is 0.076% of the energy. Two checks say that error is
ordinary codec noise and not damage:

- **It is not a misalignment artifact.** The decoded re-encode has lag 0 against the
  source and is 30 samples longer. Had it been shifted, the block-wise comparison would
  have reported a large error for no audible reason. Check this first, always.
- **It is spread, not concentrated.** Block-wise SNR over 93 ms windows: median 33.6 dB,
  5th percentile 23.1, and only 5 blocks out of 780 under 15 dB — those five are
  near-silent passages, where the ratio means nothing. Artefacts (clicks, dropouts) would
  show as a handful of very deep blocks against a clean median. They do not.

Downsampling to 32 kHz would buy perhaps another megabyte and is *not* done: there is no
`scipy` here, and a hand-rolled 441->320 decimator risks aliasing that no amount of saved
space justifies.

### What is left open

- `playCurSongPreview`'s random-capsule branch (line 891, when `songData` is null) is
  written but its music, `freeplayRandomAnimania.ogg` (1.31 MB), is not vendored: the port
  has no random capsule in the disk list, so nothing can reach that branch today. Vendor
  the file when the capsule lands and the branch works as written.
- `?` The layer fades *to* field 0xe0 of the base music. 0xd8 is `volume` — `FlxSound.
  set_volume` writes it at 0x15f7530 — so 0xe0 is the double right after it, which in
  HaxeFlixel is `_volumeAdjust`: 1.0 unless `proximity` is used, and freeplay never uses
  it. The port fades to 1.0. Inferred, not read.

### A tool bug worth remembering

`hxlines.py` picked the **largest** matching symbol, and the base game declares the same
method names as the mod. Asking for `changeTheme` therefore returned
`funkin::ui::freeplay::FreeplayState_obj::changeTheme` — 4611 bytes of the wrong function,
which reads plausibly and mentions `winter-horrorland`. It now sorts `animania::` first.
This is the third time a matcher has quietly handed back the wrong thing (see also: the
substring match that returned `buildBg` for `build`). When a disassembly reads plausibly,
check the symbol before believing it.


## 8d. A tool bug that faked field reads out of vtable slots

`hxlines.py` labelled `mov 0x198(%rax),%rax` as a read of the field at 0x198. Sometimes it
is. But when the register was just loaded by `mov (%rax),%rax` — dereferencing an object
pointer to get its **vtable** — the same instruction is a vtable slot, and the call that
follows is `call *%rax`.

The offsets collide exactly where it hurts: slots 0x188, 0x190 and 0x198 sit on top of
`shadowsOnBed`, `currentGirlfriend` and `currentPhone`. That is how a reading of
`changeTheme` came out claiming the method touches `currentPhone` at line 959. It does
not: that is `FunkinSound`'s `volumeTween` slot, and the layer's fade target has nothing
to do with the phone.

The tool now tracks which registers hold a vtable and prints `vt+0x198` for those. Two
things about the fix are worth keeping in mind, because the first attempt got them wrong:

- The register is cleared **after** the read, not before. `mov 0x198(%rax),%rax` reads
  through the vtable *and* overwrites the register in one instruction; discarding first
  undid the whole fix and the output looked exactly as broken as before.
- A `call` clears every tracked register. Deliberately conservative — losing a label is
  cheap, inventing one is not.

Re-read anything important that was read before this fix. Checked so far and unchanged:
`playCurSongPreview` (its `.currentPlayer` / `.currentGirlfriend` at lines 902-904 are
genuine — it really does call `changeCharacter` on them) and `preloadThemes`.


## 8e. initCharacters, and why only the phone is ported

`initCharacters` (0x34c1800, lines 1401-1423) builds three things. The old port comment
said "230.0 and 235.0 for positioning, 0.5 for scale" — half right, and wrong on the last
point: **0.5 is not a scale**, it is the parallax ratio handed to `FlxTypedRatioHandler`.

| line | what |
|---|---|
| 1401 | `currentGirlfriend = new CharGirlfriend(FlxG.width - 508, 230, 'none')`, zIndex 4 |
| 1404 | `<ratioHandler>.add(gf, 0.5, 0)`; `shadowsOnBed.add(gf)` |
| 1407 | `currentPlayer = new CharPlayer(FlxG.width - 780, 235, 'none', null, null)`, zIndex 5 |
| 1415 | `currentPhone = new FunkinSprite(FlxG.width - 517.6, 265.9, '…skinSelector/phone')`, zIndex 6 |
| 1418 | `addByPrefix('switch', 'Phone fall', 24)`, then `play('switch')` |
| 1420 | `currentPhone.visible = false` |

`FlxG.width` is 1280, so: girlfriend at x 772, player at 500, phone at 762.4. All three go
into `shadowsOnBed`, which `buildBg` leaves invisible (line 1219) and `doIntroAnim` turns
on — the characters do not appear until the television lights up.

**The phone is ported**, exactly: a single-animation sparrow, built by the scene builder,
invisible, with `z_as_relative` off so the mod's absolute zIndex 6 survives being a child
of `ShadowsOnBed`. It is created invisible and nothing else in `FreeplayScreen` touches it
— `initCharacters` is the only method in the class that reads field 0x198, checked across
every method of the class — so whatever shows it lives outside this screen.

**The two characters are not ported, and that is a decision.** `CharPlayer` and
`CharGirlfriend` are not the mod's classes at all: they are
`funkin::ui::freeplay::charSelect::`, from the base game, carrying `loadCharacter`,
`getData` over a character JSON, `loadSkinChanger` and `loadIcon`; their skins are Adobe
Animate atlases (`Animation.json` + spritemap) under `skinSelector/bf` and `/gf`, with
standart / animania / xmas variants plus miku, teto and tadano. That is a subsystem, not
two sprites. Both are constructed with the skin `'none'`, and the only `changeCharacter`
call inside this class is the random-disk branch of `playCurSongPreview`, which also
passes `'none'` — so whatever picks a real character is in `updateDataStuff` or
`postHeader`. Read those before porting the characters. Every constant needed is in the
table above.

Note also that `currentCharacterId` (field 0xe0) is a **different** thing from the `'none'`
in those constructors: that is the skin, this is the freeplay character that comes from
`rememberedCharacterId`. `initCharacters` never writes it, so the port must not either.


## 8f. postHeader: the bottom capsule and the info strip

`postHeader` (0x34cb6e0, lines 1550-1594) builds the difficulty dots and the bottom info
capsule. The geometry is now fully traced — no approximations left in it.

```
1564  songInfoCapsule.zIndex = 650
1565  scrollFactor.set(0, 0)
1566  x = tvSprite.x + tvSprite.width * 0.5 - capsule.width * 0.5
1567  y = FlxG.height - capsule.height + 1
1574  all THREE texts share one x: capsule.x + capsule.width * 0.5 - 153
1580  y = capsule.y + 23, field width 300
1576  infoBpmText   → 'left'
1577  infoTitleText → 'center'
1578  infoDiffText  → 'right'
1585  size 28        1586  zIndex 652        1588  colour 0xFFCCFFFF
1593  alpha 0.0001 on the seven header items   1594  dotsGrp.visible = false
```

Two things in there took tracing rather than reading:

- **`r12` is `tvSprite`.** The function opens with `lea 0x1e0(%rbx),%r12` and never
  reassigns it, so line 1566's `x + width*0.5` is the *television's* centre. The capsule is
  centred under the TV, not on the screen.
- **The three texts share one x**, from a single `get_width` and a single `subsd 153.0`.
  That is not a misreading: it is one 300-wide box with three alignments — BPM flush left,
  title centred, difficulty flush right — which is how the strip is built. 153 is half of
  306, the capsule's 382 minus the 38 of margin on each side.

The TV frame is 727 wide at mod (-40, -132) and the capsule art is 382×54, so the capsule
lands at (132.5, 667) and the text box at (170.5, 690), all in the mod's 1280×720.

### The font is a substitution, and it costs a size

`DS-DIGIB.TTF` is **not in the build** — there is no `.ttf` anywhere in it, so it lives in
the executable or a packed archive. The port substitutes `VCR OSD Mono Cyr.ttf`:
monospace, CRT-ish, and it covers the Cyrillic the art on this screen uses.

It is also much wider than a seven-segment face, and because the three strings share one
box that shows up immediately as overlap. Measured, not guessed:

| size (port px) | left + centre + right | of 450 |
|---|---|---|
| 42 (the read 28×1.5) | 196 + 246 + 270 = 712 | collides |
| 32 | 150 + 188 + 206 = 544 | collides |
| 28 | 132 + 164 + 181 = 477 | collides |
| 24 | 112 + 140 + 154 = 406 | "fits" — but see below |
| 20 | 94 + 118 + 129 = 341 | fits |

**Summing widths is not enough when one of the three is centred.** At 24 the total fits in
450, and the strings still touch: the centred title occupies 155-295 and the
right-aligned one starts at 296. At 20 the left ends at 94, the title runs 166-284 and the
right starts at 321 — 72 and 37 px of air. That is the size the port uses, through a
`FONT_SUBSTITUTE_NARROW` constant so the read 28 stays visible and the fudge has a name
instead of being baked into it.

### Still not built

- **`dotsGrp`** (zIndex 70, `loadDots`, `setDots`, `set_curDiff`) — the difficulty dots.
  `_post_header` hides a `UI/DotsGrp` if it finds one; nothing creates it yet.


## 8g. updateDataStuff, and three labels with two writers each

`updateDataStuff(bool)` (0x34c5f50, lines 1081-1176) is the header's whole content: it
loads the score, writes the three info texts, raises the difficulty stars and the dots, and
kicks the television static. Two branches — a song is selected, or none is.

| line | what |
|---|---|
| 1088-1089 | `songData.currentDifficulty = currentDifficulty`; `songData.updateValues(currentCharacter)` |
| 1090-1092 | `getSongScore(...)` → `score`; the percentage from `tallies.good`, `.sick`, `.totalNotes` |
| 1097-1098 | `albumRoll.albumId = …`, `albumRoll.skipIntro()` |
| 1100-1102 | `cancelTweensOf(tvNoiseForward, ['alpha'])`; `alpha = 0.7`; tween to **0.45 over 0.25 s, sineInOut** |
| 1104-1106 | `cancelTweensOf(infoTitleText)`; `amount = 2`; tween `amount` to 0.1, same 0.25 s |
| 1113-1115 | `difficultyStars.difficulty`, `dotsGrp.setDots(currentDiffsIds)`, `songInfoCapsule.curDiff` |
| 1117-1118 | alpha **1** on the seven header items; `visible = true` |
| 1120-1125 | `'BPM: ' + bpm`, the title, `'DIF: ' + difficulty` |
| 1131-1133 | bossfightSkull: `cancelTweensOf`, alpha tween over **0.1 backOut**, `play('y')` |
| 1165-1173 | the no-song branch: same setters, alpha **0.0001**, `visible = false` |
| 1176 | `dispatch('onUpdateDataStuff')` |

The seven are the same seven `postHeader` line 1593 leaves at 0.0001: `infoBpmText`,
`infoTitleText`, `infoDiffText`, `highScoreSpr`, `clearBoxSprite`, `freeplayScore`,
`completionText`. So the header does not start hidden by `visible` — it starts at an alpha
of essentially zero, and `updateDataStuff` raises it. That is what makes it appear when a
song is picked instead of being there from the first frame.

### What this turned up in the port

Three node references were wrong, and every one of them failed **silently** because
`_resolve_nodes` uses `get_node_or_null`:

- `freeplay_score` pointed at `UI/FreeplayScore`, **a node that does not exist**. It is the
  score number, and the code that writes it has been running against `null`, so the score
  never displayed at all.
- `high_score_spr` pointed at the `UI/HighScore` *Label*. `highScoreSpr` (field 0x218) is
  the sprite; the number is `freeplayScore` (0x1c0). The two were crossed.
- `tv_noise_forward` was **declared and never assigned**.

And three properties had two writers each, with the invented one winning because it ran
later:

- **alpha**: `_init_header` set `HEADER_ALPHA` on the info labels; alpha belongs to
  `postHeader` (0.0001) and `updateDataStuff` (1).
- **BPM**: `_update_song_info` — a method with no counterpart in the mod — set
  `info_bpm_text.text = ""` with the comment "BPM would come from the song data". Called
  from `_refresh`, i.e. *after* `updateDataStuff`, so the BPM was blanked every time. The
  title survived only by coincidence: `"phone-call".capitalize()` happens to give
  `"Phone Call"`.
- **difficulty**: `_update_difficulty_display` wrote the bare name; line 1125 writes it
  with a `'DIF: '` prefix.

One writer per property. When a value is wrong and there are two writers, the bug is
almost never in the one you are reading.

### Not ported, and why

- **The score and the completion percentage.** They come from `getSongScore` over a save
  this project does not have — the story menu hardcodes its score to 0 too. The formula is
  in the table above; the values stay at zero.
- **The title tween (line 1106).** `amount` is a property of the mod's `FlxFixedText`, an
  effect over the glyphs. The port's labels are Godot `Label`s with no equivalent.
- **The bossfight skull.** `BossfightSkull` is not in the scene, so `bossfight_skull` is
  null; the ported code guards for it. None of the port's four songs is a boss fight, so
  only the fade-out branch would run today anyway.


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
