"""Hand-inked icon renderer.

The originals (gameplay_icon, misc_icon) are scanned marker drawings: the
stroke changes width along its length, the edges are soft rather than
crisp, and the black is dense. A geometric primitive plus a uniform
dilation cannot produce any of that - it comes out as clean vector art,
which is exactly how the first attempt read.

So strokes are *stamped*: a marker nib is walked along each path, its
radius drifting with smooth noise and its position jittered, which gives
the uneven weight for free. Nothing is hard-thresholded at the end, so
the anti-aliased edge survives as the soft scan-like border the originals
have.
"""
from PIL import Image, ImageDraw, ImageFilter
import numpy as np, math

W, H, SS = 82, 108, 8


def _noise1(n, seed, octaves=3):
    """Smooth 1-D noise in [-1,1], for drifting the nib radius."""
    rng = np.random.default_rng(seed)
    out = np.zeros(n)
    for o in range(octaves):
        k = 2 ** o
        ctrl = rng.uniform(-1, 1, max(2, n // (24 // k) + 2))
        out += np.interp(np.linspace(0, len(ctrl) - 1, n),
                         np.arange(len(ctrl)), ctrl) / (o + 1)
    m = np.abs(out).max()
    return out / m if m else out


def stamp(img, pts, r, seed=0, jitter=0.30, wobble=0.55):
    """Walk `pts` stamping a nib of radius ~r. Radius drifts, centre wobbles."""
    d = ImageDraw.Draw(img)
    dense = []
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        seg = math.hypot(x1 - x0, y1 - y0)
        n = max(2, int(seg / (r * 0.22)))
        for i in range(n):
            t = i / (n - 1)
            dense.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t))
    if not dense:
        return
    rad = r * (1.0 + jitter * _noise1(len(dense), seed))
    ox = wobble * r * _noise1(len(dense), seed + 991)
    oy = wobble * r * _noise1(len(dense), seed + 4177)
    for (x, y), rr, dx, dy in zip(dense, rad, ox, oy):
        d.ellipse([x + dx - rr, y + dy - rr, x + dx + rr, y + dy + rr], fill=255)


def arc(cx, cy, r, a0, a1, n=40):
    return [(cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a)))
            for a in np.linspace(a0, a1, n)]


def render(build, out, nib=0.040):
    w, h = W * SS, H * SS
    fill = Image.new("L", (w, h), 0)   # white paper interior
    ink = Image.new("L", (w, h), 0)    # black marker
    build(fill, ink, ImageDraw.Draw(fill), ImageDraw.Draw(ink), w, h, nib * w)

    # Global displacement: the whole drawing sits slightly off-true, the way a
    # scan of paper does. Applied to both layers so they stay registered.
    def warp(img):
        a = np.array(img, np.float32)
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        fx = (np.sin(yy / (13.0 * SS)) * 1.6 + np.sin(yy / (3.6 * SS) + 1.1) * 0.9) * SS * 0.5
        fy = (np.sin(xx / (10.0 * SS) + 0.6) * 1.5 + np.sin(xx / (3.1 * SS)) * 0.8) * SS * 0.5
        sx = np.clip(xx + fx, 0, w - 1).astype(np.int32)
        sy = np.clip(yy + fy, 0, h - 1).astype(np.int32)
        return Image.fromarray(a[sy, sx].astype(np.uint8))

    fill, ink = warp(fill), warp(ink)
    fill = fill.filter(ImageFilter.GaussianBlur(0.45 * SS))
    ink = ink.filter(ImageFilter.GaussianBlur(0.40 * SS))

    f = np.array(fill, np.float32) / 255.0
    k = np.array(ink, np.float32) / 255.0
    # Ink is opaque; paper only shows where ink is not. Gamma pushes the black
    # dense (the originals are very heavy) without hard-clipping the edge.
    k = np.clip(k * 1.35, 0, 1) ** 0.75
    f = np.clip(f * 1.30, 0, 1) ** 0.85

    alpha = np.clip(np.maximum(f, k), 0, 1)
    lum = (1.0 - k)
    rgb = np.stack([lum * 252 + 18 * (1 - lum)] * 3, -1)

    img = np.concatenate([rgb, (alpha * 255)[..., None]], -1).astype(np.uint8)
    Image.fromarray(img, "RGBA").resize((W, H), Image.LANCZOS).save(out)
    print("escrito", out)
