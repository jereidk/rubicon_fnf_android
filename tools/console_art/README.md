# Console section art

Regenerates the settings sidebar's section icons and wordmarks in the
hand-inked style of the originals (`gameplay_icon.png`, `misc_icon.png`).

    python3 tools/console_art/make_icons.py <outdir>
    python3 tools/console_art/make_wordmark.py <out.png> "AUDIO" <cap_height> [max_width]

Run from the repo root; `make_wordmark.py` reads
`lullaby_mod/resources/fonts/fnt_hypno_options.ttf`, the console's own
handwritten face.

Two constraints the sidebar imposes, both learned the hard way:

- A wordmark is centred at x=169 in a button whose icon sits at x=-69, so
  anything past ~330px wide collides with the icon. Long words are
  condensed to that width rather than shrunk, which is why `GRAPHICS`
  keeps the column's cap height instead of being drawn small.
- Every icon is normalised in `console.tscn` so its longest side is 146px.
  Art that does not fill its own canvas therefore renders smaller than
  its neighbours - keep the ink at ~95%+ of the canvas.
- A uniform-thickness outline reads as visibly heavier/blockier than the
  scanned originals (`gameplay.png`, `misc.png`, `visuals.png`) even at the
  same cap height, because a variable stroke has less solid ink overall.
  `make_wordmark.py` blends a light and a heavy dilation by low-frequency
  noise and perturbs the threshold with high-frequency noise so the stroke
  drifts in width and the edge is jagged rather than antialiased - this is
  what made the first AUDIO/GRAPHICS/MOBILE pass (plain `MaxFilter`
  dilation) look like clean vector art next to the real scans.
