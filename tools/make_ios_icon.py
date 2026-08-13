#!/usr/bin/env python3
"""Builds the 1024x1024 iOS app icon out of the Android adaptive pair.

iOS wants one opaque square per app and masks it to a squircle itself, so
an icon with transparency or with its own rounded corners comes out wrong -
transparent pixels render black, and pre-rounded corners get rounded twice.
Android's adaptive icon is the opposite shape of problem: a 432x432 canvas
where the launcher only ever shows the central 72dp of 108dp, so the art is
drawn small on purpose and compositing the two layers at full size leaves
the logo looking shrunken on a platform that shows the whole square.

So this crops rather than scales the whole canvas. VISIBLE_PX is chosen so
the artwork ends up filling about three quarters of the icon, which is
where Apple's own icons sit; the Android safe zone (288px) would put it at
87% and read as cropped.

The project icon is not usable for this - Icon.png is Godot's default at
205x199, and the iOS exporter would upscale it into every slot.

    python3 tools/make_ios_icon.py

Writes icons/ios_app_1024.png. Run it again whenever the adaptive layers
change; the output is committed so CI never needs PIL.
"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
FOREGROUND = ROOT / "icons" / "launcher_adaptive_foreground_432.png"
BACKGROUND = ROOT / "icons" / "launcher_adaptive_background_432.png"
OUTPUT = ROOT / "icons" / "ios_app_1024.png"

## Side of the centred crop taken out of the 432px adaptive canvas. 320
## leaves the 250px-wide artwork at 78% of the icon.
VISIBLE_PX = 320
SIZE = 1024


def main() -> None:
    foreground = Image.open(FOREGROUND).convert("RGBA")
    background = Image.open(BACKGROUND).convert("RGBA")

    if foreground.size != background.size:
        raise SystemExit(
            "adaptive layers differ in size: %s vs %s" % (foreground.size, background.size)
        )

    composed = Image.alpha_composite(background, foreground)

    inset = (composed.width - VISIBLE_PX) // 2
    cropped = composed.crop((inset, inset, inset + VISIBLE_PX, inset + VISIBLE_PX))
    scaled = cropped.resize((SIZE, SIZE), Image.LANCZOS)

    # Flattened onto the background's own colour rather than white: any
    # alpha left after compositing is a hole in the artwork, and it should
    # read as more background, not as a bright square.
    base_colour = background.getpixel((0, 0))[:3]
    flat = Image.new("RGB", (SIZE, SIZE), base_colour)
    flat.paste(scaled, (0, 0), scaled)

    flat.save(OUTPUT, "PNG")
    print("wrote %s (%dx%d, opaque)" % (OUTPUT.relative_to(ROOT), SIZE, SIZE))


if __name__ == "__main__":
    main()
