#!/usr/bin/env python3
"""Paket visual 5.0: ganti bangunan generator yang lemah dengan model KayKit (CC0) + tambah dekorasi desa.
Idempoten: objek bertanda "v5" tidak ditambah dua kali. Data permainan lain (misi, NPC, tempat) tidak diubah."""
import json, math, sys

D = __import__("os").path.join(__import__("os").path.dirname(__import__("os").path.abspath(__file__)), "..", "..", "client", "games", "education_sd", "data") + "/"
ROOF = {1: "red", 2: "green", 3: "yellow", 4: "blue", 5: "red", 6: "blue"}


def seg_dist(p, a, b):
    ax, az = a; bx, bz = b; px, pz = p
    dx, dz = bx - ax, bz - az
    L = dx * dx + dz * dz
    t = 0 if L == 0 else max(0, min(1, ((px - ax) * dx + (pz - az) * dz) / L))
    return math.hypot(px - (ax + dx * t), pz - (az + dz * t))


for n in range(1, 7):
    p = D + "island%d.json" % n
    d = json.load(open(p, encoding="utf-8"))
    col = ROOF[n]
    objs = d["objects"]
    objs[:] = [o for o in objs if not o.get("v5")]
    houses = [o for o in objs if o["asset"] in ("buildings/joglo", "buildings/rumah_gadang", "buildings/tongkonan")
              or o.get("orig_asset", "").startswith("buildings/") and o["asset"].startswith("kaykit/building_home")
              or o.get("orig_asset") in ("buildings/joglo", "buildings/rumah_gadang", "buildings/tongkonan")]
    # rumah ke-1 tetap rumah adat Nusantara; sisanya rumah KayKit & warung
    repl = [("kaykit/building_home_B_" + col, 4.6), ("kaykit/building_home_A_" + col, 5.2), ("kaykit/building_tavern_yellow", 3.8)]
    for i, o in enumerate(houses[1:4]):
        o.setdefault("orig_asset", o["asset"])
        o.setdefault("orig_scale", o.get("scale", 1.0))
        o["asset"], o["scale"] = repl[i]
        o["rot"] = 90 if o["pos"][0] < 0 else -90
    for o in objs:
        if o["asset"] == "buildings/library" or o.get("orig_asset") == "buildings/library":
            o.setdefault("orig_asset", "buildings/library")
            o["asset"] = "kaykit/building_castle_yellow"
            o["scale"] = 3.4
            o["rot"] = 0
    # dekorasi baru (tanpa tabrakan untuk benda kecil supaya jalur penduduk tidak terhalang)
    paths = d.get("paths", [])
    places = {pl["id"]: pl for pl in d.get("places", [])}

    def free(x, z, r):
        if math.hypot(x, z) > d["radius"] - 6:
            return False
        for s in paths:
            if seg_dist((x, z), s[0], s[1]) < r + 2.2:
                return False
        for o in objs:
            if math.hypot(o["pos"][0] - x, o["pos"][1] - z) < r + 2.5:
                return False
        for npc in d.get("npcs", []):
            if math.hypot(npc["pos"][0] - x, npc["pos"][1] - z) < r + 2.0:
                return False
        rv = d.get("river")
        if rv and abs(z - rv["z"]) < rv["half_width"] + r + 2:
            return False
        f = d.get("fort")
        if f and math.hypot(f["pos"][0] - x, f["pos"][1] - z) < f["half"] * 1.6 + r + 2:
            return False
        fm = d.get("farm")
        if fm and abs(x - fm["pos"][0]) < fm["size"][0] / 2 + r + 1 and abs(z - fm["pos"][1]) < fm["size"][1] / 2 + r + 1:
            return False
        for pid in ("akademi",):
            if pid in places and math.hypot(places[pid]["pos"][0] - x, places[pid]["pos"][1] - z) < 13 + r:
                return False
        return True

    def add(asset, x, z, scale, rot=0, solid=False, r=0.6, radius=None):
        if not free(x, z, r):
            return False
        o = {"asset": asset, "pos": [round(x, 2), round(z, 2)], "rot": rot, "scale": scale, "v5": True}
        if not solid:
            o["solid"] = False
        if radius:
            o["radius"] = radius
        objs.append(o)
        return True

    fm = d.get("farm")
    if fm:
        fx, fz = fm["pos"]
        sx = 1 if fx >= 0 else -1
        for dx, dz in [(fm["size"][0] / 2 + 5, -fm["size"][1] / 2 - 4), (fm["size"][0] / 2 + 5, fm["size"][1] / 2 + 4), (-fm["size"][0] / 2 - 5, -fm["size"][1] / 2 - 4)]:
            if add("kaykit/building_windmill_yellow", fx + dx * sx, fz + dz, 4.0, -90 * sx, True, 3.0, 2.6):
                break
        add("kaykit/wheelbarrow", fx - fm["size"][0] / 2 * sx - 1.5 * sx, fz + 2, 3.0, 30)
        add("kaykit/sack", fx - fm["size"][0] / 2 * sx - 1.4 * sx, fz - 1.5, 3.0)
        add("kaykit/building_grain", fx + 1.5, fz + fm["size"][1] / 2 + 2.6, 3.2, 0, True, 1.6, 1.6)
    # warung & rumah: tong, peti, karung di samping
    for o in [o for o in objs if o["asset"].startswith("kaykit/building_home") or o["asset"].startswith("kaykit/building_tavern") or o["asset"] == "buildings/market_stall"]:
        x, z = o["pos"]
        side = 1 if z < 42 else -1
        for k, (a, sc) in enumerate([("kaykit/barrel", 3.2), ("kaykit/crate_A_big", 2.6), ("kaykit/sack", 3.0)]):
            ox = x + (2.8 + k * 0.9) * (1 if x < 0 else -1) * (0.6 if "market" in o["asset"] else 1)
            oz = z + side * (3.2 + k * 0.6)
            add(a, ox, oz, sc, k * 37)
    # sumur di desa
    if "desa" in places:
        cx, cz = places["desa"]["pos"]
        for dx, dz in [(-9, 9), (9, 9), (-9, -12), (9, -12)]:
            if add("kaykit/building_well_yellow", cx + dx, cz + dz, 3.2, 0, True, 1.6, 1.4):
                break
    # teratai di sungai
    rv = d.get("river")
    if rv:
        k = 0
        for x in range(-50, 51, 7):
            if abs(x) < 8:
                continue
            k += 1
            o = {"asset": "kaykit/waterlily_%s" % ("A" if k % 2 else "B"), "pos": [x + (k % 3) * 1.3, rv["z"] + ((k * 37) % 5 - 2) * 0.55],
                 "rot": k * 47, "scale": 2.6, "solid": False, "v5": True, "y": -0.18}
            objs.append(o)
    # bendera di benteng
    f = d.get("fort")
    if f:
        for sx in (-1, 1):
            objs.append({"asset": "kaykit/flag_%s" % ("red" if n % 2 else "blue"), "pos": [f["pos"][0] + sx * (f["gate_half"] + 2.2), f["pos"][1] + f["half"] + 1.6],
                         "rot": 0, "scale": 3.0, "solid": False, "v5": True})
    json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent="\t")
    print(n, "objek:", len(objs), "baru v5:", sum(1 for o in objs if o.get("v5")))
