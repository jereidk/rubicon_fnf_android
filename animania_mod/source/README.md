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
