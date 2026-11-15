#!/usr/bin/env python3
"""Ikon aplikasi Game Platform (v0.84.1): rak server berisi tiga "game" + gamepad.

Menulis client/assets/icon/: icon_512.png (ikon proyek), main_192.png (ikon peluncur lama),
adaptive_foreground_432.png + adaptive_background_432.png (ikon adaptif Android 8+).
Digambar pada 4x ukuran lalu diperkecil (tepi halus). Butuh Pillow.

Pakai:  python3 tools/gen_ikon_platform.py
"""
import os

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "client", "assets", "icon")
S = 4  # supersampling

BG_TOP = (36, 52, 120)
BG_BOT = (12, 16, 40)
RACK = (44, 56, 84)
RACK_EDGE = (98, 118, 168)
SLOT = (20, 26, 44)
GAMES = [(232, 84, 61), (63, 191, 107), (122, 92, 255)]  # tiga game: merah, hijau, ungu
LED = (90, 255, 150)
GOLD = (240, 180, 41)
GOLD_DARK = (150, 100, 10)


def gradient(size, top, bot):
    img = Image.new("RGB", (size, size), top)
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        d.line([(0, y), (size, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
    # cahaya lembut di kiri atas
    glow = Image.new("L", (size, size), 0)
    ImageDraw.Draw(glow).ellipse([-size * 0.3, -size * 0.35, size * 0.75, size * 0.55], fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.12))
    img.paste((120, 150, 255), (0, 0), glow)
    return img


def draw_art(size, scale=1.0):
    """Gambar rak server + gamepad di kanvas transparan `size` (sudah termasuk supersampling).
    scale < 1 mengecilkan gambar ke tengah (zona aman ikon adaptif)."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def r(v):  # koordinat relatif 0..1 -> piksel, terpusat dengan skala
        return (0.5 + (v - 0.5) * scale) * size

    def box(x0, y0, x1, y1):
        return [r(x0), r(y0), r(x1), r(y1)]

    w = size * scale
    # bayangan rak
    sh = Image.new("L", (size, size), 0)
    ImageDraw.Draw(sh).rounded_rectangle(box(0.22, 0.17, 0.74, 0.86), radius=w * 0.06, fill=140)
    sh = sh.filter(ImageFilter.GaussianBlur(w * 0.03))
    img.paste((0, 0, 0, 255), (int(w * 0.015), int(w * 0.025)), sh)
    # badan rak
    d.rounded_rectangle(box(0.20, 0.14, 0.72, 0.84), radius=w * 0.06, fill=RACK, outline=RACK_EDGE, width=int(w * 0.014))
    # tiga unit server, masing-masing satu "game"
    for i, col in enumerate(GAMES):
        y0 = 0.20 + i * 0.205
        y1 = y0 + 0.165
        d.rounded_rectangle(box(0.25, y0, 0.67, y1), radius=w * 0.025, fill=SLOT)
        # kartu game berwarna
        d.rounded_rectangle(box(0.28, y0 + 0.03, 0.40, y1 - 0.03), radius=w * 0.018, fill=col)
        # simbol kecil di kartu: segitiga "main"
        cx, cy = (0.34, (y0 + y1) / 2)
        d.polygon([(r(cx - 0.022), r(cy - 0.03)), (r(cx - 0.022), r(cy + 0.03)), (r(cx + 0.03), r(cy))], fill=(255, 255, 255))
        # kisi ventilasi
        for k in range(3):
            yy = y0 + 0.05 + k * 0.032
            d.rounded_rectangle(box(0.44, yy, 0.56, yy + 0.012), radius=w * 0.006, fill=(60, 74, 108))
        # lampu
        d.ellipse(box(0.595, (y0 + y1) / 2 - 0.022, 0.639, (y0 + y1) / 2 + 0.022), fill=LED)
    # cahaya lampu
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for i in range(3):
        cy = 0.20 + i * 0.205 + 0.0825
        gd.ellipse(box(0.575, cy - 0.04, 0.66, cy + 0.04), fill=LED + (120,))
    glow = glow.filter(ImageFilter.GaussianBlur(w * 0.015))
    img = Image.alpha_composite(glow, img)
    d = ImageDraw.Draw(img)

    # gamepad emas di kanan bawah, menindih rak
    gx0, gy0, gx1, gy1 = 0.48, 0.60, 0.90, 0.86
    pad_sh = Image.new("L", (size, size), 0)
    ps = ImageDraw.Draw(pad_sh)
    ps.rounded_rectangle(box(gx0, gy0, gx1, gy1 - 0.04), radius=w * 0.08, fill=170)
    pad_sh = pad_sh.filter(ImageFilter.GaussianBlur(w * 0.02))
    img.paste((0, 0, 0, 255), (int(w * 0.01), int(w * 0.02)), pad_sh)
    d = ImageDraw.Draw(img)
    # badan + dua pegangan
    d.rounded_rectangle(box(gx0, gy0, gx1, gy1 - 0.05), radius=w * 0.08, fill=GOLD, outline=GOLD_DARK, width=int(w * 0.01))
    d.ellipse(box(gx0 - 0.005, gy0 + 0.06, gx0 + 0.13, gy1), fill=GOLD, outline=GOLD_DARK, width=int(w * 0.01))
    d.ellipse(box(gx1 - 0.13, gy0 + 0.06, gx1 + 0.005, gy1), fill=GOLD, outline=GOLD_DARK, width=int(w * 0.01))
    d.rounded_rectangle(box(gx0 + 0.04, gy0 + 0.012, gx1 - 0.04, gy1 - 0.07), radius=w * 0.06, fill=GOLD)
    # tombol arah
    cx, cy = gx0 + 0.10, gy0 + 0.095
    a, b = 0.045, 0.015
    d.rounded_rectangle(box(cx - a, cy - b, cx + a, cy + b), radius=w * 0.006, fill=(40, 30, 10))
    d.rounded_rectangle(box(cx - b, cy - a, cx + b, cy + a), radius=w * 0.006, fill=(40, 30, 10))
    # tombol aksi
    bx, by = gx1 - 0.10, gy0 + 0.095
    for dx, dy, col in [(0.028, 0, GAMES[0]), (-0.028, 0, GAMES[2]), (0, -0.028, GAMES[1]), (0, 0.028, (255, 255, 255))]:
        d.ellipse(box(bx + dx - 0.018, by + dy - 0.018, bx + dx + 0.018, by + dy + 0.018), fill=col)
    return img


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return m


def full_icon(px):
    big = px * S
    bg = gradient(big, BG_TOP, BG_BOT).convert("RGBA")
    icon = Image.alpha_composite(bg, draw_art(big, 0.98))
    out = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    out.paste(icon, (0, 0), rounded_mask(big, int(big * 0.2)))
    return out.resize((px, px), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    full_icon(512).save(os.path.join(OUT, "icon_512.png"), optimize=True)
    full_icon(192).save(os.path.join(OUT, "main_192.png"), optimize=True)
    big = 432 * S
    # Adaptif: launcher memotong ke berbagai bentuk; isi dijaga di ±66% tengah (zona aman).
    draw_art(big, 0.62).resize((432, 432), Image.LANCZOS).save(os.path.join(OUT, "adaptive_foreground_432.png"), optimize=True)
    gradient(big, BG_TOP, BG_BOT).resize((432, 432), Image.LANCZOS).save(os.path.join(OUT, "adaptive_background_432.png"), optimize=True)
    print("Ikon ditulis ke", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
