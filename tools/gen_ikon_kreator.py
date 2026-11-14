#!/usr/bin/env python3
"""Ikon 128x128 untuk kosmetik dan perlengkapan Character Creator (v0.82.0).

Pakai:  python3 tools/gen_ikon_kreator.py katalog.json client/assets/items
katalog.json = jawaban GET /v1/wardrobe (cosmetics + gear). Latar mengikuti kelangkaan, gambar mengikuti
jenis barang, warna utama dari katalog. Ikon yang sudah ada (dibuat gen_ikon_item.py) tidak ditimpa.
"""
import json, math, os, sys
from PIL import Image, ImageDraw, ImageFilter

S = 4
N = 128 * S
TIER_BG = {
    "common": ("8a9298", "4a5258"), "uncommon": ("5aa25a", "2a5a2a"), "rare": ("4a8ad8", "1e3a78"),
    "epic": ("a85ad8", "4a1e78"), "legendary": ("f0b030", "8a4a10"), "mythic": ("ff5a3a", "6a0e1e"),
}
WEAPON_KIND = {
    "belati": "pedang", "pedang_pendek": "pedang", "pedang_panjang": "pedang", "pedang_dua_tangan": "pedang",
    "pedang_legenda": "pedang", "pedang_naga_purba": "pedang", "kapak_tangan": "kapak", "kapak_besar": "kapak",
    "palu_perang": "palu", "tombak_besi": "tombak", "tombak_naga": "tombak", "tongkat_kayu": "tongkat",
    "tongkat_kristal": "tongkat", "busur_pendek": "busur", "busur_panjang": "busur",
}
GEAR_COLOR = {
    "pedang_legenda": "ffe08a", "pedang_naga_purba": "ff7a4a", "tombak_naga": "ff7a4a", "tongkat_kristal": "8ad8ff",
    "tongkat_kayu": "7adf6a", "perisai_kayu": "9a6a3a", "perisai_legenda": "e8c050", "zirah_legenda": "ffe08a",
    "helm_legenda": "e8c050", "sepatu_legenda": "e8c050", "sepatu_kulit": "7a4a2a", "sepatu_petualang": "8a5a30",
    "sepatu_biasa": "8a7a6a", "busur_pendek": "a87a4a", "busur_panjang": "8a5a30",
}


def col(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def P(*pts):
    return [(x * S, y * S) for x, y in pts]


def base(tier):
    top, bot = TIER_BG.get(tier, TIER_BG["common"])
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    grad = Image.new("RGBA", (N, N))
    gd = ImageDraw.Draw(grad)
    t, b = col(top), col(bot)
    for y in range(N):
        f = y / (N - 1)
        gd.line([(0, y), (N, y)], fill=tuple(int(t[i] + (b[i] - t[i]) * f) for i in range(4)))
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).rounded_rectangle([4 * S, 4 * S, N - 4 * S, N - 4 * S], radius=22 * S, fill=255)
    im.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([4 * S, 4 * S, N - 4 * S, N - 4 * S], radius=22 * S, outline=(255, 255, 255, 90), width=3 * S)
    return im, d


def dark(c, k=0.6):
    return tuple(int(v * k) for v in c[:3]) + (255,)


def light(c, k=0.45):
    return tuple(int(v + (255 - v) * k) for v in c[:3]) + (255,)


def draw(d, kind, c):
    o = dark(c)
    w = 3 * S
    if kind == "pedang":
        d.polygon(P((60, 18), (68, 18), (68, 86), (64, 92), (60, 86)), fill=light(c, 0.3), outline=o, width=w)
        d.rectangle(P((44, 86), (84, 94)), fill=col("c8a24a"), outline=o, width=w)
        d.rectangle(P((60, 94), (68, 112)), fill=col("6a4426"), outline=o, width=w)
    elif kind == "kapak":
        d.rectangle(P((60, 20), (67, 112)), fill=col("7a5232"), outline=o, width=w)
        d.pieslice(P((30, 18), (78, 70)), 100, 260, fill=light(c, 0.2), outline=o, width=w)
        d.pieslice(P((50, 18), (98, 70)), -80, 80, fill=light(c, 0.2), outline=o, width=w)
    elif kind == "palu":
        d.rectangle(P((60, 40), (67, 112)), fill=col("5a3a22"), outline=o, width=w)
        d.rectangle(P((34, 20), (94, 50)), fill=c, outline=o, width=w)
    elif kind == "tombak":
        d.line(P((30, 108), (92, 30)), fill=col("8a6238"), width=7 * S)
        d.polygon(P((84, 22), (106, 14), (98, 38)), fill=light(c, 0.2), outline=o)
    elif kind == "tongkat":
        d.line(P((44, 112), (76, 38)), fill=col("7a5232"), width=8 * S)
        d.ellipse(P((62, 14), (94, 46)), fill=c, outline=o, width=w)
        d.ellipse(P((70, 20), (80, 30)), fill=(255, 255, 255, 180))
    elif kind == "busur":
        d.arc(P((26, 18), (90, 110)), -80, 80, fill=c, width=8 * S)
        d.line(P((63, 22), (63, 106)), fill=col("eeeae0"), width=2 * S)
    elif kind == "perisai":
        d.polygon(P((64, 16), (102, 30), (96, 78), (64, 112), (32, 78), (26, 30)), fill=c, outline=o, width=w)
        d.ellipse(P((56, 52), (72, 68)), fill=col("e8c050"), outline=o)
    elif kind == "zirah":
        d.polygon(P((34, 30), (52, 22), (64, 30), (76, 22), (94, 30), (90, 104), (38, 104)), fill=c, outline=o, width=w)
        d.line(P((64, 34), (64, 100)), fill=o, width=w)
    elif kind in ("helm", "topi_helm"):
        d.pieslice(P((28, 26), (100, 104)), 180, 360, fill=c, outline=o, width=w)
        d.rectangle(P((26, 64), (102, 74)), fill=dark(c, 0.8), outline=o, width=w)
        d.rectangle(P((60, 62), (68, 92)), fill=dark(c, 0.8), outline=o)
    elif kind == "sepatu":
        d.polygon(P((40, 20), (68, 20), (70, 80), (104, 88), (104, 106), (36, 106)), fill=c, outline=o, width=w)
    elif kind == "rambut":
        d.ellipse(P((38, 34), (90, 96)), fill=col("e8bc94"), outline=dark(col("e8bc94")))
        d.pieslice(P((32, 22), (96, 86)), 180, 360, fill=col("5a3620"), outline=o)
        d.rectangle(P((32, 52), (44, 98)), fill=col("5a3620"))
        d.rectangle(P((84, 52), (96, 98)), fill=col("5a3620"))
    elif kind == "pakaian":
        d.polygon(P((40, 24), (54, 20), (64, 30), (74, 20), (88, 24), (106, 46), (92, 56), (88, 50), (88, 106), (40, 106), (40, 50), (36, 56), (22, 46)), fill=c, outline=o, width=w)
    elif kind == "celana":
        d.polygon(P((38, 20), (90, 20), (96, 108), (72, 108), (64, 52), (56, 108), (32, 108)), fill=c, outline=o, width=w)
    elif kind == "sarung":
        d.rounded_rectangle(P((36, 44), (88, 108)), radius=12 * S, fill=c, outline=o, width=w)
        for x in (38, 52, 66):
            d.rounded_rectangle(P((x, 18), (x + 12, 52)), radius=6 * S, fill=c, outline=o, width=w)
        d.rounded_rectangle(P((84, 50), (104, 70)), radius=8 * S, fill=c, outline=o, width=w)
    elif kind == "topi":
        d.ellipse(P((16, 70), (112, 96)), fill=c, outline=o, width=w)
        d.rounded_rectangle(P((38, 30), (90, 82)), radius=14 * S, fill=c, outline=o, width=w)
        d.rectangle(P((38, 68), (90, 78)), fill=dark(c, 0.5))
    elif kind == "tudung":
        d.pieslice(P((26, 18), (102, 110)), 180, 360, fill=c, outline=o, width=w)
        d.rectangle(P((26, 62), (102, 110)), fill=c, outline=o, width=w)
        d.ellipse(P((44, 50), (84, 96)), fill=col("2a2a2a"))
    elif kind == "mahkota":
        d.polygon(P((24, 92), (24, 40), (44, 66), (64, 30), (84, 66), (104, 40), (104, 92)), fill=c, outline=o, width=w)
        for x in (40, 64, 88):
            d.ellipse(P((x - 6, 74), (x + 6, 86)), fill=col("e83a5a"))
    elif kind == "jubah":
        d.polygon(P((44, 20), (84, 20), (106, 108), (22, 108)), fill=c, outline=o, width=w)
        d.rectangle(P((40, 18), (88, 26)), fill=col("e8c050"), outline=o)
    elif kind == "kalung":
        d.arc(P((30, 14), (98, 82)), 20, 160, fill=c, width=5 * S)
        d.ellipse(P((54, 74), (74, 98)), fill=c, outline=o, width=w)
    elif kind == "cincin":
        d.ellipse(P((34, 40), (94, 100)), outline=c, width=10 * S)
        d.ellipse(P((54, 22), (74, 44)), fill=col("8ad8ff"), outline=o)
    elif kind == "sabuk":
        d.rounded_rectangle(P((14, 52), (114, 76)), radius=6 * S, fill=c, outline=o, width=w)
        d.rectangle(P((52, 46), (76, 82)), outline=col("e8c050"), width=5 * S)
    elif kind == "perisai_punggung":
        d.ellipse(P((22, 22), (106, 106)), fill=c, outline=o, width=w)
        d.ellipse(P((54, 54), (74, 74)), fill=col("c8ccd4"), outline=o)
    elif kind == "ornamen":
        d.pieslice(P((18, 40), (64, 96)), 180, 360, fill=c, outline=o, width=w)
        d.pieslice(P((64, 40), (110, 96)), 180, 360, fill=c, outline=o, width=w)
    elif kind in ("sayap", "sayap_naga"):
        for sx in (-1, 1):
            for k in range(4):
                ang = math.radians(20 + k * 18)
                cx, cy = 64 + sx * 26 * math.cos(ang), 78 - 26 * math.sin(ang)
                d.ellipse(P((cx - 22, cy - 9), (cx + 22, cy + 9)), fill=c if k % 2 == 0 else dark(c, 0.8), outline=o)
    elif kind == "skin":
        d.ellipse(P((22, 22), (106, 106)), fill=c, outline=o, width=w)
        d.pieslice(P((22, 22), (106, 106)), 200, 340, fill=light(c, 0.5))
    else:
        d.ellipse(P((34, 34), (94, 94)), fill=c, outline=o, width=w)


def kind_of(item, is_cos):
    if not is_cos:
        slot = item.get("slot")
        return {"weapon": WEAPON_KIND.get(item["id"], "pedang"), "offhand": "perisai", "armor": "zirah", "helmet": "helm", "boots": "sepatu"}.get(slot, "")
    cat, shape = item.get("category"), item.get("shape", "")
    if cat == "aksesori":
        return shape
    if cat == "topi":
        return shape
    return {"skin": "skin", "rambut": "rambut", "pakaian": "pakaian", "celana": "celana", "sarung": "sarung", "jubah": "jubah"}.get(cat, "")


def main():
    data = json.load(open(sys.argv[1]))
    out = sys.argv[2]
    os.makedirs(out, exist_ok=True)
    made = 0
    for is_cos, list_ in ((True, data["cosmetics"]), (False, data["gear"])):
        for it in list_:
            path = os.path.join(out, it["id"] + ".png")
            if os.path.exists(path) and it["id"] in ("pedang_besi", "pedang_baja", "pedang_rune", "baju_kulit", "zirah_besi", "helm_kulit", "helm_besi"):
                continue  # ikon lama buatan gen_ikon_item.py tetap
            color = it.get("color") or ("#" + GEAR_COLOR.get(it["id"], "c8d0dc"))
            if color.lower() == "#ffffff":
                color = "#e8e0d0"
            im, d = base(it.get("tier", "common"))
            draw(d, kind_of(it, is_cos), col(color))
            im = im.resize((128, 128), Image.LANCZOS)
            im.save(path, optimize=True)
            made += 1
    print("ikon dibuat:", made)


if __name__ == "__main__":
    main()
