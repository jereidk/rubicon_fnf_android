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

Still missing on this screen: only the six props' placement beyond what `title_props.gd`
already carries.

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
