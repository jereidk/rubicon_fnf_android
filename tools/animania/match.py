# Correlacion normalizada CON MASCARA, para buscar un personaje del puerto dentro de la
# captura del mod.
#
# El alineador por bordes (align3.py) no sirve aqui: sobre la pareja da escalas 1.15, 0.88
# y 0.87 segun la caja, con r de 0.23, 0.19 y 0.12. El arte es blando, lleva un brillo
# verde encima y los dos personajes se pisan, asi que no hay bordes limpios que casar.
#
# Esto es otra cosa: se coge el recorte LIMPIO del personaje -renderizado solo, sobre
# negro, por char_solo.gd- con su mascara de opacidad, y se busca en la captura contando
# unicamente los pixeles de dentro de la mascara. El fondo del recorte no cuenta, que es
# lo que hacia inutil una correlacion normal con un recorte rectangular.
#
#   ncc = sum_M((I-Ī)(T-T̄)) / (sqrt(sum_M(I-Ī)^2) * sqrt(sum_M(T-T̄)^2))
#
# con las sumas sobre la mascara, calculadas por FFT para no barrer a mano.
#
#   python3 match.py solo_bf.png orig2_1280.png 520 1280 120 700  0.55 1.20 0.05
import sys
import numpy as np
from PIL import Image


def gray(img):
    a = np.asarray(img.convert("RGB"), dtype=np.float64)
    return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


def corr(image, kernel, shape):
    """Correlacion completa de `image` con `kernel` por FFT, recortada a `shape`."""
    fs = [1 << int(np.ceil(np.log2(image.shape[i] + kernel.shape[i]))) for i in (0, 1)]
    F = np.fft.rfft2(image, fs) * np.conj(np.fft.rfft2(kernel, fs))
    out = np.fft.irfft2(F, fs)
    return out[:shape[0], :shape[1]]


def search(tpl_path, ref_path, box, scales):
    tpl_img = Image.open(tpl_path).convert("RGB").resize((1280, 720), Image.LANCZOS)
    # La toma del banco viene del framebuffer, o sea OPACA: el fondo es negro, no
    # transparente. La mascara es "lo que no es negro", el mismo criterio que usa
    # char_solo.gd para dar la caja.
    alpha = gray(tpl_img) > 8
    ys, xs = np.nonzero(alpha)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    tpl_full = gray(tpl_img)[y0:y1, x0:x1]
    msk_full = alpha[y0:y1, x0:x1].astype(np.float64)
    print("# recorte %dx%d en (%d,%d) del render del puerto"
          % (x1 - x0, y1 - y0, x0, y0))

    bx0, bx1, by0, by1 = box
    ref = gray(Image.open(ref_path))[by0:by1, bx0:bx1]
    ref2 = ref * ref

    best = None
    for sc in scales:
        h = max(8, int(round(tpl_full.shape[0] * sc)))
        w = max(8, int(round(tpl_full.shape[1] * sc)))
        if h >= ref.shape[0] or w >= ref.shape[1]:
            continue
        t = np.asarray(Image.fromarray(tpl_full).resize((w, h), Image.LANCZOS))
        m = np.asarray(Image.fromarray(msk_full).resize((w, h), Image.LANCZOS)) > 0.5
        m = m.astype(np.float64)
        n = m.sum()
        if n < 200:
            continue
        tm = t * m
        shape = (ref.shape[0] - h + 1, ref.shape[1] - w + 1)
        s_it = corr(ref, tm, shape)
        s_i = corr(ref, m, shape)
        s_i2 = corr(ref2, m, shape)
        st, st2 = tm.sum(), (tm * tm).sum()
        num = s_it - s_i * (st / n)
        d_i = s_i2 - s_i * s_i / n
        d_t = st2 - st * st / n
        den = np.sqrt(np.maximum(d_i, 1e-9) * max(d_t, 1e-9))
        ncc = num / den
        k = int(np.argmax(ncc))
        yy, xx = divmod(k, ncc.shape[1])
        v = float(ncc[yy, xx])
        if best is None or v > best[0]:
            best = (v, sc, xx + bx0, yy + by0, w, h)
        print("  escala %.3f  r %.3f  en (%d, %d)" % (sc, v, xx + bx0, yy + by0))
    return best


if __name__ == "__main__":
    tpl, ref = sys.argv[1], sys.argv[2]
    box = tuple(int(v) for v in sys.argv[3:7])
    lo, hi, step = (float(v) for v in sys.argv[7:10])
    b = search(tpl, ref, box, np.arange(lo, hi + 1e-9, step))
    print("MEJOR r %.3f  escala %.3f  caja x %d..%d  y %d..%d"
          % (b[0], b[1], b[2], b[2] + b[4], b[3], b[3] + b[5]))
