#!/usr/bin/env python3
"""Membuat peta Hutan Lebat (170x50) dan Gua Goblin (25x30) untuk client/scripts/maps.gd.

Hasilnya deterministik (seed tetap). Skrip ini mencetak potongan GDScript (HUTAN_ROWS, GUA_GOBLIN_ROWS) ke
berkas keluaran dan memeriksa bahwa pintu masuk, singgasana bos, gerbang, dan semua peti bisa dijangkau.

Pakai:  python3 tools/gen_hutan.py client/scripts/maps_hutan.gen   (lalu salin ke maps.gd)
Legenda petak: # pohon, . rumput, f bunga, = jalan, R batu, ~ air, K singgasana bos, N menara gapura, P pagar kayu,
M lantai gua, G kerikil (tempat monster/pertemuan).
"""
import random
import sys
from collections import deque

W, H = 170, 50
ENTRY = (22, 0)       # pintu dari Perbatasan (petak jalan di baris paling atas)
BOSS = (85, 25)       # singgasana bos Goblin (harus sama dengan HutanBossX/Y di internal/game/hutan.go)
GATE_X0 = 144         # gapura "NN===NN" di baris paling bawah: N di 144-145, jalan 146-148, N di 149-150
GATE_ROAD = (146, 147, 148)
WALK = ".=fTBDMGK"


def hutan(seed=46):
    rng = random.Random(seed)
    g = [["." for _ in range(W)] for _ in range(H)]
    # 1. pohon berumpun: acak lalu dihaluskan beberapa kali (automaton sel)
    t = [[rng.random() < 0.46 for _ in range(W)] for _ in range(H)]
    for _ in range(4):
        n = [[False] * W for _ in range(H)]
        for y in range(H):
            for x in range(W):
                c = 0
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        yy, xx = y + dy, x + dx
                        c += 1 if (yy < 0 or yy >= H or xx < 0 or xx >= W or t[yy][xx]) else 0
                n[y][x] = c >= 5
        t = n
    for y in range(H):
        for x in range(W):
            if t[y][x]:
                g[y][x] = "#"
    # 2. batu dan bunga tersebar
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            if g[y][x] == ".":
                r = rng.random()
                if r < 0.025:
                    g[y][x] = "f"
                elif r < 0.032:
                    g[y][x] = "R"
    # 3. padang terbuka (tanpa pohon), kolam, dan jalan
    clearings = [(85, 25, 9), (22, 8, 6), (50, 38, 7), (118, 12, 7), (120, 40, 7), (150, 28, 6), (62, 12, 5), (100, 44, 5), (35, 28, 5), (140, 8, 5)]
    for cx, cy, r in clearings:
        for y in range(max(1, cy - r), min(H - 1, cy + r + 1)):
            for x in range(max(1, cx - r), min(W - 1, cx + r + 1)):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    g[y][x] = "." if rng.random() > 0.08 else "f"
    ponds = [(60, 12, 2), (120, 40, 2), (40, 38, 2), (140, 8, 2)]
    for cx, cy, r in ponds:
        for y in range(cy - r, cy + r + 1):
            for x in range(cx - r - 1, cx + r + 2):
                if (x - cx) ** 2 / (1.6 ** 2) + (y - cy) ** 2 <= r * r:
                    g[y][x] = "~"

    def road(points):
        for (x0, y0), (x1, y1) in zip(points, points[1:]):
            x, y = x0, y0
            while (x, y) != (x1, y1):
                g[y][x] = "="
                if x != x1 and (y == y1 or rng.random() < 0.7):
                    x += 1 if x1 > x else -1
                else:
                    y += 1 if y1 > y else -1
            g[y1][x1] = "="
    road([(22, 1), (22, 8), (35, 14), (50, 20), (70, 24), BOSS])
    road([BOSS, (110, 30), (135, 40), (147, 46), (147, 48)])
    road([(22, 8), (30, 28), (50, 38)])
    road([BOSS, (100, 14), (118, 12), (140, 8)])
    road([(110, 30), (120, 40)])
    road([(135, 40), (150, 28)])
    # 4. tepi: pohon di semua sisi, pagar di sisi selatan, gapura dan pintu masuk
    for x in range(W):
        g[0][x] = "#"
        g[H - 1][x] = "P"
    for y in range(H):
        g[y][0] = "#"
        g[y][W - 1] = "#"
    g[0][ENTRY[0]] = "="
    for x in (GATE_X0, GATE_X0 + 1, GATE_X0 + 5, GATE_X0 + 6):
        g[H - 1][x] = "N"
    for x in GATE_ROAD:
        g[H - 1][x] = "="
        g[H - 2][x] = "="
    # bersihkan sekeliling pintu masuk dan gerbang
    for y in range(1, 4):
        for x in range(ENTRY[0] - 2, ENTRY[0] + 3):
            if g[y][x] == "#":
                g[y][x] = "."
    for y in range(H - 5, H - 1):
        for x in range(GATE_X0 - 1, GATE_X0 + 8):
            if g[y][x] in "#R~":
                g[y][x] = "."
    # singgasana bos dan lingkarannya
    for y in range(BOSS[1] - 1, BOSS[1] + 2):
        for x in range(BOSS[0] - 1, BOSS[0] + 2):
            g[y][x] = "."
    g[BOSS[1]][BOSS[0]] = "K"
    for dx, dy in ((-3, -3), (3, -3), (-3, 3), (3, 3)):
        g[BOSS[1] + dy][BOSS[0] + dx] = "R"
    return g


def reach(g, start):
    seen = {start}
    q = deque([start])
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < len(g[0]) and 0 <= ny < len(g) and (nx, ny) not in seen and g[ny][nx] in WALK:
                seen.add((nx, ny))
                q.append((nx, ny))
    return seen


def chests(g, seen, count, tier_of, seed, chars=".f", gap=18):
    rng = random.Random(seed)
    cand = [(x, y) for (x, y) in sorted(seen) if g[y][x] in chars and 2 < x < len(g[0]) - 3 and 2 < y < len(g) - 3]
    out = []
    tries = 0
    while len(out) < count and tries < 5000:
        tries += 1
        x, y = rng.choice(cand)
        if any(abs(x - a) + abs(y - b) < gap for a, b in out):
            continue
        if sum(1 for dx in (-1, 0, 1) for dy in (-1, 0, 1) if g[y + dy][x + dx] in WALK) < 9:
            continue
        out.append((x, y))
    return out


def gua(seed=5):
    rng = random.Random(seed)
    w, h = 25, 30
    g = [["R" for _ in range(w)] for _ in range(h)]

    def carve(x0, y0, x1, y1, ch="M"):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                g[y][x] = ch
    carve(11, 0, 13, 4)            # pintu masuk dari Hutan Lebat
    carve(4, 5, 20, 10)            # aula pertama
    carve(10, 11, 14, 14)
    carve(2, 15, 12, 21)           # ruang kiri
    carve(14, 15, 22, 21)          # ruang kanan
    carve(10, 22, 14, 25)
    carve(11, 26, 13, 29)          # pintu keluar ke Gunung Batu
    for (x0, y0, x1, y1) in ((5, 6, 8, 8), (16, 6, 19, 8), (3, 16, 6, 19), (17, 16, 20, 19), (10, 7, 14, 9)):
        carve(x0, y0, x1, y1, "G")
    for _ in range(28):
        x, y = rng.randrange(1, w - 1), rng.randrange(1, h - 1)
        if g[y][x] == "M" and 6 < y < 26:
            g[y][x] = "R"
    for x in (11, 12, 13):
        g[0][x] = "M"
        g[h - 1][x] = "M"
    for y in range(2, 4):  # jalur masuk jangan tersumbat
        for x in (11, 12, 13):
            g[y][x] = "M"
    for y in range(26, 29):
        for x in (11, 12, 13):
            g[y][x] = "M"
    return g


def fmt(name, g, doc):
    lines = ["## " + doc, "const %s: Array[String] = [" % name]
    lines += ['\t"%s",' % "".join(r) for r in g]
    lines.append("]")
    return "\n".join(lines)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "maps_hutan.gen"
    g = hutan()
    seen = reach(g, (ENTRY[0], 1))
    assert BOSS in seen, "singgasana tidak terjangkau"
    for x in GATE_ROAD:
        assert (x, H - 2) in seen, "gerbang tidak terjangkau"
    ch = chests(g, seen, 6, None, 7)
    assert len(ch) == 6, "peti kurang"
    free = sum(1 for (x, y) in seen if g[y][x] in ".f" and y >= 3)
    assert free > 1800, "terlalu sedikit petak untuk binatang: %d" % free
    gg = gua()
    gseen = reach(gg, (12, 1))
    assert (12, 28) in gseen, "pintu keluar gua tidak terjangkau"
    gch = chests(gg, gseen, 3, None, 3, "MG", 7)
    assert len(gch) == 3, "peti gua kurang"
    text = fmt("HUTAN_ROWS", g, "Hutan Lebat (170x50): dua kali lebar Desa Awal. Pintu masuk dari Perbatasan di (22,0), singgasana bos K di tengah, gapura ke Gua Goblin di bawah.")
    text += "\n\n\n" + fmt("GUA_GOBLIN_ROWS", gg, "Gua Goblin (25x30): peta 3, terbuka setelah tiga Goblin di Hutan Lebat kalah.")
    text += "\n\n# peti hutan: %s\n# peti gua goblin: %s\n# petak bebas binatang: %d\n" % (ch, gch, free)
    open(out, "w").write(text)
    print("OK", out, "peti hutan", ch, "peti gua", gch, "petak bebas", free)


if __name__ == "__main__":
    main()
