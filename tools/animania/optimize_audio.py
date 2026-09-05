#!/usr/bin/env python3
"""Adelgaza la musica de un .ogg midiendo lo que se pierde, no suponiendolo.

Los siete temas de freeplay del mod son 21.4 MB: siete pistas de 72.5 s, estereo,
44100 Hz, a 350 kbps nominales de Vorbis. Eso es una tasa disparatada para el material:
`Freeplay_Base` tiene el 99% de su energia por debajo de 2 kHz y un 0.006% por encima de
18 kHz, y todas vienen grabadas muy bajas -picos de 0.16 a 0.29, o sea entre 11 y 16 dB
por debajo de fondo de escala-.

Antes de recodificar conviene mirar dos cosas, que son las que dan las ganancias sin
coste ninguno:

  - Cuantas pistas alcanza el puerto de verdad. Cada cancion elige su base por
    `freeplayTheme` y su capa por el personaje rival, asi que de las siete solo se
    alcanzan las de las canciones que hay. Tres de las siete son navidenas.
  - Si alguna esta repetida. Aqui no: la correlacion entre cualquier par de pistas es
    ~0.00, son siete piezas distintas.

Uso:

    python3 tools/animania/optimize_audio.py ENTRADA.ogg SALIDA.ogg
    python3 tools/animania/optimize_audio.py ENTRADA.ogg --report

`--report` mide sin escribir: reparto de energia por bandas y, si se pide una salida, el
error que el recodificado introduce en cada banda, en dB por debajo de la energia TOTAL
de la señal. Ese es el numero que dice si se oye: un error 60 dB por debajo del total es
inaudible aunque en su propia banda solo este 18 dB por debajo.

AVISO sobre el codificador: este entorno no tiene libvorbis, solo el codificador Vorbis
NATIVO de ffmpeg, que ffmpeg marca como experimental y que ademas IGNORA el bitrate que
se le pida -a 96, 128, 160 y 192 kbps saca exactamente el mismo fichero-. Lo que sale
son unos 174 kbps. Con libvorbis disponible habria que rehacer esto y comparar.
"""

import argparse
import os
import sys
from fractions import Fraction
from pathlib import Path

import numpy as np
import soundfile as sf

BANDS = ((0, 2000), (2000, 6000), (6000, 12000), (12000, 22050))


def encode(data, rate, path):
    """Vorbis por el codificador nativo de ffmpeg. Ver el aviso de arriba."""
    import av
    out = av.open(str(path), "w", format="ogg")
    # `strict -2` porque ffmpeg no abre su Vorbis nativo sin permiso explicito.
    stream = out.add_stream("vorbis", rate=rate, options={"strict": "-2"})
    stream.layout = "stereo"
    stream.format = "fltp"
    step = 4096
    for i in range(0, len(data), step):
        frame = av.AudioFrame.from_ndarray(
            np.ascontiguousarray(data[i:i + step].T), format="fltp", layout="stereo")
        frame.sample_rate = rate
        frame.pts = i
        frame.time_base = Fraction(1, rate)
        for packet in stream.encode(frame):
            out.mux(packet)
    for packet in stream.encode(None):
        out.mux(packet)
    out.close()
    return os.path.getsize(path)


def spectra(a, b, rate):
    """Energia por banda de `a`, y energia del error a-b, ambas absolutas."""
    n = min(len(a), len(b))
    left = a[:n].mean(axis=1)
    right = b[:n].mean(axis=1)
    size = 1 << 14
    window = np.hanning(size)
    err = np.zeros(size // 2 + 1)
    ref = np.zeros(size // 2 + 1)
    for i in range(0, n - size, size * 4):
        A = np.abs(np.fft.rfft(left[i:i + size] * window))
        B = np.abs(np.fft.rfft(right[i:i + size] * window))
        err += (A - B) ** 2
        ref += A ** 2
    freqs = np.fft.rfftfreq(size, 1.0 / rate)
    return freqs, ref, err


def report(path, encoded=None):
    data, rate = sf.read(path, dtype="float32", always_2d=True)
    seconds = len(data) / rate
    print("%s  %d canales  %d Hz  %.1f s  %.2f MB  (%.0f kbps)"
          % (Path(path).name, data.shape[1], rate, seconds,
             os.path.getsize(path) / 1048576,
             os.path.getsize(path) * 8 / seconds / 1000))
    print("   pico %.3f (%.1f dBFS)   rms %.4f"
          % (np.abs(data).max(), 20 * np.log10(max(np.abs(data).max(), 1e-9)),
             float(np.sqrt((data ** 2).mean()))))

    freqs, ref, _ = spectra(data, data, rate)
    total = ref.sum()
    parts = []
    for lo, hi in BANDS:
        sel = (freqs >= lo) & (freqs < hi)
        parts.append("%d-%dHz %.3f%%" % (lo, hi, 100 * ref[sel].sum() / total))
    print("   energia:  " + "   ".join(parts))

    if encoded is None:
        return
    other, _ = sf.read(encoded, dtype="float32", always_2d=True)
    freqs, ref, err = spectra(data, other, rate)
    total = ref.sum()
    parts = []
    for lo, hi in BANDS:
        sel = (freqs >= lo) & (freqs < hi)
        # El error de esta banda, en dB por debajo de la energia TOTAL de la señal.
        parts.append("%d-%dHz %.0f dB" % (
            lo, hi, 10 * np.log10(total / max(err[sel].sum(), 1e-20))))
    print("   error del recodificado, bajo la energia total:  " + "   ".join(parts))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("target", type=Path, nargs="?")
    parser.add_argument("--report", action="store_true")
    args = parser.parse_args()

    if args.report or not args.target:
        report(args.source)
        return

    data, rate = sf.read(args.source, dtype="float32", always_2d=True)
    args.target.parent.mkdir(parents=True, exist_ok=True)
    size = encode(data, rate, args.target)
    before = os.path.getsize(args.source)
    print("%-34s %6.2f MB -> %5.2f MB  (%.2fx)"
          % (args.source.name, before / 1048576, size / 1048576, before / size))
    report(args.source, args.target)


if __name__ == "__main__":
    main()
