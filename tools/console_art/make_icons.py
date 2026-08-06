import sys; sys.path.insert(0, __import__("os").path.dirname(__file__))
from marker import render, stamp, arc

def audio(fill, ink, df, di, w, h, nib):
    # Speaker box + horn as one white body, three ripple arcs beside it.
    # Drawn tall as well as large: the shape is naturally wide, and at only
    # 73% of the canvas height it rendered visibly smaller than the others
    # once every icon is normalised into the same 146px box.
    bx, by, bh = 0.06*w, 0.34*h, 0.30*h
    box  = [(bx, by), (0.30*w, by), (0.30*w, by+bh), (bx, by+bh)]
    horn = [(0.28*w, 0.49*h), (0.57*w, 0.08*h), (0.57*w, 0.90*h)]
    df.polygon(box, fill=255); df.polygon(horn, fill=255)
    stamp(ink, box + [box[0]], nib*0.90, seed=1)
    stamp(ink, horn + [horn[0]], nib*0.90, seed=2)
    for i, m in enumerate((0.19, 0.295, 0.40)):
        stamp(ink, arc(0.57*w, 0.49*h, m*w, -58, 58), nib*0.80, seed=10+i)

def graphics(fill, ink, df, di, w, h, nib):
    # A CRT set: on theme for a menu that lives inside the Collector's own
    # television, and unmistakable against the phone at thumbnail size.
    bx, by, bw, bh = 0.10*w, 0.22*h, 0.80*w, 0.46*h
    body = [(bx, by), (bx+bw, by), (bx+bw, by+bh), (bx, by+bh)]
    neck = [(0.37*w, by+bh), (0.63*w, by+bh), (0.70*w, 0.84*h), (0.30*w, 0.84*h)]
    base = [(0.22*w, 0.84*h), (0.78*w, 0.84*h), (0.78*w, 0.91*h), (0.22*w, 0.91*h)]
    for p in (body, neck, base):
        df.polygon(p, fill=255)
    for i, p in enumerate((body, neck, base)):
        stamp(ink, p + [p[0]], nib, seed=20+i)
    pad = 0.11*w
    scr = [(bx+pad, by+pad), (bx+bw-pad, by+pad), (bx+bw-pad, by+bh-pad), (bx+pad, by+bh-pad)]
    stamp(ink, scr + [scr[0]], nib*0.78, seed=25)
    stamp(ink, [(0.38*w, by), (0.21*w, 0.045*h)], nib*0.78, seed=26)
    stamp(ink, [(0.62*w, by), (0.79*w, 0.045*h)], nib*0.78, seed=27)

def mobile(fill, ink, df, di, w, h, nib):
    # Phone plus a tap. The dot is kept small and the ripples pushed well
    # clear of it: at nib weight they merge into one blob otherwise, and an
    # inset screen outline turns to mush once 82x108 art is downscaled into
    # the 640x480 console viewport.
    bx, by, bw, bh = 0.15*w, 0.09*h, 0.70*w, 0.82*h
    r = 0.13*w
    body = ([(bx+r, by), (bx+bw-r, by)] + arc(bx+bw-r, by+r, r, -90, 0, 8) +
            [(bx+bw, by+bh-r)] + arc(bx+bw-r, by+bh-r, r, 0, 90, 8) +
            [(bx+r, by+bh)] + arc(bx+r, by+bh-r, r, 90, 180, 8) +
            [(bx, by+r)] + arc(bx+r, by+r, r, 180, 270, 8))
    df.polygon(body, fill=255)
    stamp(ink, body + [body[0]], nib, seed=30)
    cx, cy = 0.50*w, 0.58*h
    stamp(ink, [(cx-0.004*w, cy), (cx+0.004*w, cy)], 0.072*w, seed=31, jitter=0.15, wobble=0.22)
    for i, m in enumerate((0.185, 0.285)):
        stamp(ink, arc(cx, cy, m*w, 203, 337), nib*0.78, seed=32+i)
    stamp(ink, [(0.41*w, 0.155*h), (0.59*w, 0.155*h)], nib*0.58, seed=35)

render(audio,    sys.argv[1] + "/audio_icon.png")
render(graphics, sys.argv[1] + "/graphics_icon.png")
render(mobile,   sys.argv[1] + "/mobile_icon.png")
