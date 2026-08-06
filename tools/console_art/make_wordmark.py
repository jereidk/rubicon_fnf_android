"""Auto-sizes the canvas to a target cap height and gives the outline the
uneven, paper-like quality of the scanned originals.

Two failed attempts are worth knowing about, because the fix is the
opposite of what it looks like:

1. A uniform `MaxFilter` dilation reads as noticeably heavier and blockier
   than GAMEPLAY/MISC/VISUALS even at a matching cap height - an even
   stroke is simply more solid ink than a variable one.
2. So the next pass broke the edge up with high-frequency noise on the
   threshold. That was wrong in the other direction: it produced ~21
   isolated specks per word (the originals have 0-1) and edges that read
   as splattered paint. **The originals are not jagged.** They are soft and
   slightly blurred, with a grey halo from the scan; the unevenness lives
   in the stroke WIDTH, not in the boundary.

So: thickness drifts via low-frequency noise only, the boundary gets a
long-wavelength wobble rather than a break-up, and a soft grey halo sits
outside the ink."""
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
# in others instead of a uniform ring. Single octave and a wide cell - any
# higher-frequency term here turns into speckle rather than weight.
thin = np.array(layer.filter(ImageFilter.MaxFilter(int(8 * SS) | 1)), np.float32)
thick = np.array(layer.filter(ImageFilter.MaxFilter(int(13 * SS) | 1)), np.float32)
width_mix = noise2(h, w, 11, 30 * SS, octaves=1) * 0.5 + 0.5
dilated = thin * (1 - width_mix) + thick * width_mix

# Long-wavelength boundary wobble, then a plain blur+threshold. The blur is
# what keeps the edge smooth; the LANCZOS downscale at the end turns it
# into the soft, slightly-out-of-focus edge the scans have.
wobble = noise2(h, w, 23, 16 * SS, octaves=1) * 14.0
outline = Image.fromarray(np.clip(dilated + wobble, 0, 255).astype(np.uint8))
outline = outline.filter(ImageFilter.GaussianBlur(0.6 * SS)).point(lambda v: 255 if v > 96 else 0)

fill = layer.filter(ImageFilter.GaussianBlur(0.35 * SS)).point(lambda v: 255 if v > 128 else 0)

img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
# Soft grey halo just outside the ink. Every scanned original carries one -
# it is what makes their edge read as ink on paper instead of a cut-out -
# and without it these sat visibly crisper than their neighbours.
halo = outline.filter(ImageFilter.MaxFilter(int(3 * SS) | 1))
halo = halo.filter(ImageFilter.GaussianBlur(2.2 * SS)).point(lambda v: int(v * 0.42))
img.paste((70, 70, 70, 255), (0, 0), halo)
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
