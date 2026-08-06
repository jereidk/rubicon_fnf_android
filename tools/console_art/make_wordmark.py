"""Auto-sizes the canvas to a target cap height, like the previous pass, but
replaces the uniform MaxFilter dilation with the same kind of roughness
marker.py already uses for the icons: stroke width drifts (low-frequency
noise blends a thin and a thick dilation) and the edge is perturbed by
higher-frequency noise before thresholding, instead of being cleanly
antialiased. Without this, AUDIO/GRAPHICS/MOBILE came out as smooth, evenly
thick "bubble letters" next to GAMEPLAY/MISC/VISUALS' actual scanned-marker
originals - visually heavier and blockier despite a similar cap height,
because a uniform stroke reads as more solid ink than a variable one."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import numpy as np, sys

FONT = "lullaby_mod/resources/fonts/fnt_hypno_options.ttf"
OUT, TEXT, TARGET = sys.argv[1], sys.argv[2], int(sys.argv[3])
# Words are centred at x=169 in a button whose icon sits at x=-69, so
# anything past ~330px wide runs into the icon. A long word is therefore
# CONDENSED rather than shrunk - that keeps its cap height in line with
# the rest of the column, which is what made GRAPHICS look wrong.
MAXW = int(sys.argv[4]) if len(sys.argv) > 4 else 0
SS = 4
PAD = 8


def noise2(h, w, seed, cell, octaves=1):
    """Smooth 2-D value noise: a coarse random grid resized up, a couple of
    octaves summed. No scipy/cv2 in this environment, so this stands in for
    the Perlin-ish field a real ink-roughness pass would use."""
    rng = np.random.default_rng(seed)
    out = np.zeros((h, w), np.float32)
    amp = 1.0
    for o in range(octaves):
        c = max(2, int(cell / (2 ** o)))
        gh, gw = h // c + 3, w // c + 3
        grid = rng.uniform(-1, 1, (gh, gw)).astype(np.float32)
        small = Image.fromarray(((grid + 1) * 127.5).astype(np.uint8))
        big = small.resize((w, h), Image.BICUBIC)
        out += (np.array(big, np.float32) / 127.5 - 1.0) * amp
        amp *= 0.5
    out /= out.std() if out.std() > 0 else 1.0
    return out


f0 = ImageFont.truetype(FONT, 400)
metrics = []
for ch in TEXT:
    l, t, r, b = f0.getbbox(ch)
    metrics.append((r - l, b - t))
cap = max(m[1] for m in metrics)
k = (TARGET * SS) / cap                      # font scale for the wanted cap height
size = max(8, int(400 * k))
f = ImageFont.truetype(FONT, size)

gap = int(-1.0 * SS)
widths = [f.getbbox(c)[2] - f.getbbox(c)[0] for c in TEXT]
heights = [f.getbbox(c)[3] - f.getbbox(c)[1] for c in TEXT]
w = sum(widths) + gap * (len(TEXT) - 1) + PAD * 4 * SS
h = max(heights) + PAD * 4 * SS

layer = Image.new("L", (w, h), 0)
rng = np.random.default_rng(7)
x = PAD * 2 * SS
for ch, cw in zip(TEXT, widths):
    l, t, r, b = f.getbbox(ch)
    tilt = float(rng.uniform(-3.2, 3.2))
    dy = float(rng.uniform(-0.035, 0.035)) * h
    tmp = Image.new("L", (int((r - l) * 1.7) + 40, int((b - t) * 1.7) + 40), 0)
    ImageDraw.Draw(tmp).text((20 - l, 20 - t), ch, font=f, fill=255)
    tmp = tmp.rotate(tilt, resample=Image.BICUBIC, expand=True)
    layer.paste(tmp, (int(x) - 20, int((h - (b - t)) / 2 + dy) - 20), tmp)
    x += cw + gap

a = np.array(layer, np.float32)
yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
fx = (np.sin(yy / (9.0 * SS)) * 1.5 + np.sin(yy / (3.1 * SS) + 1.7) * 0.8) * SS * 0.55
fy = (np.sin(xx / (8.0 * SS) + 0.4) * 1.4 + np.sin(xx / (2.7 * SS)) * 0.7) * SS * 0.55
sx = np.clip(xx + fx, 0, w - 1).astype(np.int32)
sy = np.clip(yy + fy, 0, h - 1).astype(np.int32)
layer = Image.fromarray(a[sy, sx].astype(np.uint8))

# Variable-width stroke: blend a light and a heavy dilation by a
# low-frequency noise mask, so the ink is thick in some stretches and thin
# in others instead of a uniform ring (compare a scanned marker letter to a
# vector outline - the difference is entirely in this unevenness).
small_dil = np.array(layer.filter(ImageFilter.MaxFilter(int(7 * SS) | 1)), np.float32)
big_dil = np.array(layer.filter(ImageFilter.MaxFilter(int(15 * SS) | 1)), np.float32)
width_mix = noise2(h, w, 11, 26 * SS, octaves=2) * 0.5 + 0.5
dilated = small_dil * (1 - width_mix) + big_dil * width_mix

# Jagged edge: perturb the threshold with higher-frequency noise so the
# boundary crosses at different points instead of a smooth antialiased
# curve - a torn/scanned look rather than clean vector art.
edge_noise = noise2(h, w, 23, 3 * SS, octaves=2) * 46
outline = np.where(dilated + edge_noise > 118, 255, 0).astype(np.uint8)
outline = Image.fromarray(outline).filter(ImageFilter.GaussianBlur(0.35 * SS))
outline = outline.point(lambda v: 255 if v > 110 else 0)
# Keeps the jaggedness at the true edge; without this gate the same noise
# also lit up stray flecks out in the empty background.
gate = np.array(layer.filter(ImageFilter.MaxFilter(int(19 * SS) | 1)), np.float32) > 10
outline = Image.fromarray(np.array(outline) * gate.astype(np.uint8))

fill_noise = noise2(h, w, 41, 3 * SS, octaves=2) * 46
fill_base = np.array(layer.filter(ImageFilter.GaussianBlur(0.35 * SS)), np.float32)
fill = Image.fromarray(np.where(fill_base + fill_noise > 128, 255, 0).astype(np.uint8))

img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
img.paste((20, 20, 20, 255), (0, 0), outline)
img.paste((255, 255, 255, 255), (0, 0), fill)

bb = img.split()[-1].getbbox()
img = img.crop((max(0, bb[0] - PAD * SS), max(0, bb[1] - PAD * SS),
                min(w, bb[2] + PAD * SS), min(h, bb[3] + PAD * SS)))
img = img.resize((img.width // SS, img.height // SS), Image.LANCZOS)
if MAXW and img.width > MAXW:
    img = img.resize((MAXW, img.height), Image.LANCZOS)
img.save(OUT)
print(f"{OUT.split('/')[-1]:16} lienzo={img.size}  alto_letra≈{TARGET}")
