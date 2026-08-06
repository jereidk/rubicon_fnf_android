"""Same lettering pass that produced mobile.png, but auto-sizing the canvas
to a target cap height instead of a fixed one. audio.png (70px caps) and
graphics.png (56px) were drawn much smaller than gameplay (101), misc (98)
and visuals (92), which is a large part of why the sidebar column read as
uneven."""
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

outline = layer.filter(ImageFilter.MaxFilter(int(10 * SS) | 1))
outline = outline.filter(ImageFilter.GaussianBlur(0.6 * SS)).point(lambda v: 255 if v > 96 else 0)
fill = layer.filter(ImageFilter.GaussianBlur(0.35 * SS)).point(lambda v: 255 if v > 128 else 0)

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
