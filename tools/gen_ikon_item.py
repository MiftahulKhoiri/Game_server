#!/usr/bin/env python3
"""Buat ikon item 192x192 (digambar 4x lalu diperkecil) ke client/assets/items/<id>.png."""
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
S = 4
N = 192 * S


def c(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def P(*pts):
    return [(x * S, y * S) for x, y in pts]


def new(bg_top, bg_bot):
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    grad = Image.new("RGBA", (N, N))
    gd = ImageDraw.Draw(grad)
    t, b = c(bg_top), c(bg_bot)
    for y in range(N):
        f = y / (N - 1)
        gd.line([(0, y), (N, y)], fill=tuple(int(t[i] + (b[i] - t[i]) * f) for i in range(4)))
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).rounded_rectangle([6 * S, 6 * S, N - 6 * S, N - 6 * S], radius=34 * S, fill=255)
    im.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([6 * S, 6 * S, N - 6 * S, N - 6 * S], radius=34 * S, outline=c("ffffff", 70), width=3 * S)
    return im, d


def shadow(im, pts, off=(4, 6), blur=5):
    sh = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(sh).polygon([(x + off[0] * S, y + off[1] * S) for x, y in pts], fill=(0, 0, 0, 90))
    sh = sh.filter(ImageFilter.GaussianBlur(blur * S))
    im.alpha_composite(sh)


def ell_shadow(im, box, blur=6):
    sh = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    x0, y0, x1, y1 = box
    ImageDraw.Draw(sh).ellipse([x0 * S, (y0 + 6) * S, x1 * S, (y1 + 6) * S], fill=(0, 0, 0, 90))
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(blur * S)))


def finish(im, name):
    im = im.resize((192, 192), Image.LANCZOS)
    im.quantize(colors=256, method=Image.FASTOCTREE, dither=Image.NONE).save(os.path.join(OUT, name + ".png"), optimize=True)


def rot(pts, ang, cx=96 * S, cy=96 * S):
    a = math.radians(ang)
    ca, sa = math.cos(a), math.sin(a)
    return [(cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca) for x, y in pts]


def flask(name, liquid, liquid_hi, glow=None, mark=None):
    im, d = new("2c3a52", "182234")
    ell_shadow(im, (50, 150, 142, 168))
    d.rounded_rectangle([80 * S, 30 * S, 112 * S, 66 * S], radius=6 * S, fill=c("cfe6f0"), outline=c("8fb0c0"), width=2 * S)
    d.rounded_rectangle([82 * S, 20 * S, 110 * S, 36 * S], radius=5 * S, fill=c("a8703c"), outline=c("6e4420"), width=2 * S)
    d.ellipse([46 * S, 52 * S, 146 * S, 156 * S], fill=c("cfe6f0"), outline=c("8fb0c0"), width=3 * S)
    m = Image.new("L", (N, N), 0)
    ImageDraw.Draw(m).ellipse([52 * S, 58 * S, 140 * S, 150 * S], fill=255)
    ImageDraw.Draw(m).rectangle([0, 0, N, 86 * S], fill=0)
    im.paste(Image.new("RGBA", (N, N), c(liquid)), (0, 0), m)
    d = ImageDraw.Draw(im)
    d.ellipse([58 * S, 84 * S, 134 * S, 96 * S], fill=c(liquid_hi))
    d.ellipse([58 * S, 70 * S, 74 * S, 104 * S], fill=c("ffffff", 120))
    if glow:
        for (x, y, r) in [(104, 120, 5), (84, 132, 4), (116, 104, 3)]:
            d.ellipse([(x - r) * S, (y - r) * S, (x + r) * S, (y + r) * S], fill=c(glow, 200))
    if mark == "bolt":
        d.polygon(P((100, 98), (84, 124), (96, 124), (90, 146), (112, 116), (99, 116), (106, 98)), fill=c("fff2a8"), outline=c("a8741a"))
    finish(im, name)


flask("ramuan", "e03c4a", "ff8a92", glow="ffd0d4")
flask("ramuan_kekuatan", "f08a1c", "ffc060", mark="bolt")


def taring():
    im, d = new("4a3b2a", "2a2118")
    pts = P((70, 40), (126, 44), (112, 82), (104, 126), (92, 160), (84, 126), (72, 84))
    shadow(im, pts)
    d = ImageDraw.Draw(im)
    d.polygon(pts, fill=c("efe3c4"), outline=c("8a7a55"))
    d.polygon(P((74, 42), (96, 44), (92, 150), (86, 126), (76, 84)), fill=c("fff8e4"))
    d.line(P((70, 40), (126, 44)), fill=c("b9a77a"), width=3 * S)
    d.polygon(P((104, 52), (118, 54), (108, 100), (102, 124)), fill=c("c9b88c"))
    finish(im, "taring_goblin")


def koin():
    im, d = new("3a3220", "211c10")
    ell_shadow(im, (36, 40, 156, 160))
    d = ImageDraw.Draw(im)
    d.ellipse([34 * S, 34 * S, 158 * S, 158 * S], fill=c("c58d1a"), outline=c("7a5410"), width=3 * S)
    d.ellipse([46 * S, 46 * S, 146 * S, 146 * S], fill=c("e8b83a"), outline=c("a8741a"), width=3 * S)
    d.ellipse([72 * S, 72 * S, 120 * S, 120 * S], outline=c("8a5e12"), width=6 * S)
    d.line(P((96, 56), (96, 136)), fill=c("8a5e12"), width=5 * S)
    d.line(P((56, 96), (136, 96)), fill=c("8a5e12"), width=5 * S)
    d.arc([40 * S, 40 * S, 152 * S, 152 * S], 200, 260, fill=c("fff0a0"), width=5 * S)
    finish(im, "koin_kuno")


def gem(name, base, light, dark, bg=("3a2030", "20101c")):
    im, d = new(*bg)
    pts = P((60, 62), (132, 62), (156, 94), (96, 160), (36, 94))
    shadow(im, pts, blur=6)
    d = ImageDraw.Draw(im)
    d.polygon(pts, fill=c(base), outline=c(dark))
    d.polygon(P((60, 62), (74, 94), (36, 94)), fill=c(light))
    d.polygon(P((132, 62), (156, 94), (118, 94)), fill=c(dark))
    d.polygon(P((60, 62), (132, 62), (118, 94), (74, 94)), fill=c(light))
    d.polygon(P((74, 94), (118, 94), (96, 160)), fill=c(base))
    d.polygon(P((36, 94), (74, 94), (96, 160)), fill=c(dark))
    d.polygon(P((118, 94), (156, 94), (96, 160)), fill=c(light))
    d.line(P((60, 62), (132, 62), (156, 94), (96, 160), (36, 94), (60, 62)), fill=c(dark), width=3 * S)
    d.polygon(P((70, 70), (84, 70), (78, 86), (68, 86)), fill=c("ffffff", 160))
    finish(im, name)


def sword(name, blade, blade_hi, guard, grip, rune=None, bg=("34404e", "1c2430")):
    im, d = new(*bg)
    full = rot(P((90, 14), (102, 14), (112, 34), (108, 118), (84, 118), (80, 34)), 45)
    shadow(im, full)
    d = ImageDraw.Draw(im)
    d.polygon(rot(P((96, 10), (110, 34), (108, 120), (84, 120), (82, 34)), 45), fill=c(blade), outline=c("2b3340"))
    d.polygon(rot(P((96, 10), (96, 120), (84, 120), (82, 34)), 45), fill=c(blade_hi))
    d.line(rot(P((96, 22), (96, 112)), 45), fill=c("2b3340", 90), width=2 * S)
    d.polygon(rot(P((62, 120), (130, 120), (130, 132), (62, 132)), 45), fill=c(guard), outline=c("2b3340"))
    d.polygon(rot(P((88, 132), (104, 132), (104, 168), (88, 168)), 45), fill=c(grip), outline=c("2b3340"))
    px, py = rot(P((96, 176)), 45)[0]
    d.ellipse([px - 8 * S, py - 8 * S, px + 8 * S, py + 8 * S], fill=c(guard), outline=c("2b3340"))
    if rune:
        for (x, y) in [(96, 48), (96, 70), (96, 92)]:
            qx, qy = rot(P((x, y)), 45)[0]
            d.ellipse([qx - 6 * S, qy - 6 * S, qx + 6 * S, qy + 6 * S], fill=c(rune), outline=c("ffffff", 200), width=1 * S)
        glow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
        ImageDraw.Draw(glow).polygon(rot(P((96, 10), (110, 34), (108, 120), (84, 120), (82, 34)), 45), fill=c(rune, 120))
        im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(8 * S)))
    finish(im, name)


def tunic():
    im, d = new("3a2c20", "20160e")
    body = P((62, 40), (82, 34), (96, 46), (110, 34), (130, 40), (160, 70), (140, 96), (130, 86), (130, 160), (62, 160), (62, 86), (52, 96), (32, 70))
    shadow(im, body)
    d = ImageDraw.Draw(im)
    d.polygon(body, fill=c("a8703c"), outline=c("5a3818"))
    d.polygon(P((62, 86), (62, 160), (96, 160), (96, 46), (82, 34), (62, 40), (32, 70), (52, 96)), fill=c("b98048"))
    d.polygon(P((82, 34), (96, 52), (110, 34), (96, 44)), fill=c("5a3818"))
    d.rectangle([62 * S, 118 * S, 130 * S, 128 * S], fill=c("5a3818"))
    d.rectangle([88 * S, 116 * S, 104 * S, 130 * S], fill=c("d8b050"), outline=c("7a5410"))
    for y in (70, 98):
        d.line(P((74, y), (118, y)), fill=c("7a4c24"), width=2 * S)
    finish(im, "baju_kulit")


def armor():
    im, d = new("2c3644", "161c26")
    body = P((52, 34), (82, 30), (96, 44), (110, 30), (140, 34), (162, 62), (142, 92), (132, 84), (130, 160), (62, 160), (60, 84), (50, 92), (30, 62))
    shadow(im, body)
    d = ImageDraw.Draw(im)
    d.polygon(body, fill=c("9aa6b4"), outline=c("38424f"))
    d.polygon(P((60, 84), (62, 160), (96, 160), (96, 44), (82, 30), (52, 34), (30, 62), (50, 92)), fill=c("b9c4d0"))
    d.ellipse([22 * S, 40 * S, 58 * S, 78 * S], fill=c("aab6c4"), outline=c("38424f"), width=2 * S)
    d.ellipse([134 * S, 40 * S, 170 * S, 78 * S], fill=c("8794a4"), outline=c("38424f"), width=2 * S)
    d.line(P((96, 46), (96, 158)), fill=c("38424f"), width=3 * S)
    for y in (92, 114, 136):
        d.arc([66 * S, (y - 14) * S, 126 * S, (y + 14) * S], 20, 160, fill=c("38424f"), width=3 * S)
    d.polygon(P((84, 30), (96, 50), (108, 30), (96, 40)), fill=c("38424f"))
    finish(im, "zirah_besi")


taring()
koin()
gem("permata_merah", "d4283c", "ff7a88", "7a1224")
gem("berlian", "58c8f0", "c4f0ff", "2a78a8", bg=("1c3446", "0e1c28"))
sword("pedang_besi", "aab4c0", "d4dce4", "7a6a50", "6a4424")
sword("pedang_baja", "7ea6d4", "bcd6f0", "d8b050", "3a4a6a", bg=("2a3a52", "151e30"))
sword("pedang_rune", "b08cf0", "dcc8ff", "e8c860", "4a2a7a", rune="ffe27a", bg=("2e2048", "180e2c"))
tunic()
armor()
print("ok", sorted(os.listdir(OUT)))
