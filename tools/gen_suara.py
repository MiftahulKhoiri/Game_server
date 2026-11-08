#!/usr/bin/env python3
"""Bangkitkan musik latar desa + suara bicara NPC (OGG mono) ke client/assets/audio/.
Semuanya sintesis sendiri (tanpa sampel luar), jadi bebas lisensi."""
import os, subprocess, sys, wave
import numpy as np

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
SR = 22050
rng = np.random.default_rng(7)


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def env_pluck(n, sr, attack=0.006, decay=3.5):
    t = np.arange(n) / sr
    return np.minimum(1, t / attack) * np.exp(-t * decay)


def tone(freq, dur, kind="pluck", vib=0.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    if vib:
        ph = 2 * np.pi * freq * t + vib * np.sin(2 * np.pi * 5.0 * t) / 5.0 * 2 * np.pi * 0.0 + 0.0
        ph = 2 * np.pi * freq * t + 0.012 * freq / 5.0 * np.sin(2 * np.pi * 5.2 * t)
    else:
        ph = 2 * np.pi * freq * t
    if kind == "pluck":
        w = np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.12 * np.sin(3 * ph)
        return w * env_pluck(n, SR, 0.004, 4.2)
    if kind == "bass":
        w = np.sin(ph) + 0.25 * np.sin(2 * ph)
        return w * env_pluck(n, SR, 0.01, 2.2)
    if kind == "flute":
        w = np.sin(ph) + 0.18 * np.sin(2 * ph) + 0.05 * np.sin(3 * ph)
        a = np.minimum(1, t / 0.07) * np.minimum(1, (dur - t) / 0.12).clip(0, 1)
        return w * a
    if kind == "pad":
        w = np.sin(ph) + 0.5 * np.sin(ph * 1.003) + 0.2 * np.sin(2 * ph)
        a = np.minimum(1, t / 0.5) * np.minimum(1, (dur - t) / 0.7).clip(0, 1)
        return w * a
    raise ValueError(kind)


def musik():
    bpm = 92
    beat = 60.0 / bpm
    bar = 4 * beat
    chords = [  # (akar bass midi, nada akor midi)
        (36, [60, 64, 67]),  # C
        (33, [57, 60, 64]),  # Am
        (41, [57, 60, 65]),  # F
        (43, [59, 62, 67]),  # G
        (36, [60, 64, 67]),  # C
        (40, [59, 62, 67]),  # Em
        (41, [57, 60, 65]),  # F
        (43, [59, 62, 67]),  # G
    ]
    bars = len(chords) * 2
    total = int((bars * bar + 3.0) * SR)
    mix = np.zeros(total)

    def put(sig, at, gain):
        i = int(at * SR)
        j = min(total, i + len(sig))
        mix[i:j] += sig[: j - i] * gain

    penta = [72, 74, 76, 79, 81, 84, 86]  # C pentatonik oktaf 5
    melody_rng = np.random.default_rng(11)
    for b in range(bars):
        root, notes = chords[b % len(chords)]
        t0 = b * bar
        # bas: ketukan 1 dan 3
        put(tone(midi(root), beat * 1.9, "bass"), t0, 0.55)
        put(tone(midi(root + 7 if b % 2 else root), beat * 1.9, "bass"), t0 + 2 * beat, 0.42)
        # alas akor
        for nn in notes:
            put(tone(midi(nn - 12), bar, "pad"), t0, 0.07)
        # arpeggio delapanan
        pattern = [0, 1, 2, 1, 0, 1, 2, 1]
        for k, pi in enumerate(pattern):
            put(tone(midi(notes[pi] + 12), beat * 1.2, "pluck"), t0 + k * beat / 2, 0.20)
        # melodi suling: dua frasa per birama, ada jeda
        if b >= 2:
            pos = 0.0
            while pos < 4 * beat - 0.4:
                dur = melody_rng.choice([1.0, 1.0, 1.5, 2.0]) * beat
                if melody_rng.random() < 0.22:
                    pos += dur
                    continue
                ch = [n for n in penta if (n % 12) in [x % 12 for x in notes + [root + 12]]] or penta
                nn = int(melody_rng.choice(ch if melody_rng.random() < 0.65 else penta))
                dur = min(dur, 4 * beat - pos)
                put(tone(midi(nn), dur * 0.95, "flute", vib=1.0), t0 + pos, 0.20)
                pos += dur
    # lilitkan ekor ke awal supaya mulus saat diputar ulang
    body = bars * bar
    n_body = int(body * SR)
    tail = mix[n_body:]
    out = mix[:n_body].copy()
    out[: len(tail)] += tail
    # reverb ringan: gema dua tap
    for d, g in ((0.19, 0.22), (0.31, 0.14)):
        k = int(d * SR)
        out = out + g * np.roll(out, k)
    out /= np.max(np.abs(out)) / 0.62
    return out


VOWELS = {  # formant (F1, F2)
    "a": (800, 1200), "e": (450, 1950), "i": (320, 2300), "o": (500, 900), "u": (350, 700),
}


def blip(f0, vowel, dur=0.085, contour=0.12):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = f0 * (1 + contour * np.sin(np.pi * t / dur))
    phase = 2 * np.pi * np.cumsum(f) / SR
    f1, f2 = VOWELS[vowel]
    sig = np.zeros(n)
    for h in range(1, 28):
        fh = h * f0
        if fh > 5000:
            break
        w = np.exp(-((fh - f1) / 260.0) ** 2) + 0.6 * np.exp(-((fh - f2) / 420.0) ** 2) + 0.05
        sig += w * np.sin(h * phase) / h ** 0.35
    env = np.minimum(1, t / 0.008) * np.exp(-t * 11) * np.minimum(1, (dur - t) / 0.01).clip(0, 1)
    sig *= env
    return sig / (np.max(np.abs(sig)) + 1e-9) * 0.8


def simpan(name, data, q=3):
    wav = os.path.join(OUT, name + ".wav")
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
    with wave.open(wav, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    ogg = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", str(q), ogg], check=True)
    os.remove(wav)
    print(name, os.path.getsize(ogg))


simpan("musik_desa", musik(), q=2)
combos = [(190, "a"), (220, "e"), (250, "o"), (170, "u"), (280, "i"), (205, "o")]
for i, (f0, v) in enumerate(combos):
    simpan("npc_%d" % i, blip(f0, v), q=3)
