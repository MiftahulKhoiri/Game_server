"""Menyiapkan NPC (Nenek dan Petani) dari karakter KayKit (CC0, Kay Lousberg) menjadi GLB ringan.

Sumber: https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 (CC0)

Dua karakter KayKit yang tidak dipakai sebagai pahlawan diubah lewat tekstur dan sedikit geometri:
  nenek  : Mage.glb  -> tanpa topi/tongkat/buku; jubah jadi merah-mawar, selendang krem, rambut putih
  petani : Rogue.glb -> tanpa tudung/pisau/panah; tunik hijau jadi cokelat-kuning, topi jerami buatan sendiri

Warna diubah di atlas tekstur (palet gradasi KayKit) berdasarkan rona, jadi bayangan halus tetap
terjaga. Warna topi jerami diambil dari petak kecil di pojok atlas yang tidak dipakai bagian lain.

Klip diberi nama sesuai aturan game (model_rig.gd): idle-loop, walk-loop, attack, hurt, die.

Jalankan:
  ~/Claude/blender.sh -b --factory-startup -P kaykit_npc.py -- masuk.glb keluar.glb nenek|petani
"""
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix

src, dst, mode = sys.argv[sys.argv.index("--") + 1:][:3]
if mode not in ("nenek", "petani"):
    raise SystemExit("mode harus nenek atau petani")

PREFIX = "Mage" if mode == "nenek" else "Rogue"
KEEP = {"%s_%s" % (PREFIX, n) for n in ("ArmLeft", "ArmRight", "Body", "Head", "LegLeft", "LegRight")}
if mode == "nenek":
    KEEP.add("Mage_Cape")  # selendang

CLIPS = {
    "Unarmed_Idle_Rig": "idle-loop",
    "Walking_A_Rig": "walk-loop",
    "Interact_Rig": "attack",
    "Hit_A_Rig": "hurt",
    "Death_A_Rig": "die",
}

STRAW = (0.88, 0.72, 0.36)  # topi jerami (sRGB 0-1)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

# --- buang yang tidak dipakai ---
for o in list(bpy.data.objects):
    if o.type == "MESH" and o.name not in KEEP:
        bpy.data.objects.remove(o, do_unlink=True)
missing = KEEP - {o.name for o in bpy.data.objects}
if missing:
    raise SystemExit("GAGAL: mesh tidak ditemukan: %s" % sorted(missing))
head = bpy.data.objects[PREFIX + "_Head"]
for o in bpy.data.objects:  # bentuk kustom tulang ("Icosphere") ikut terekspor bila tidak dilepas
    if o.type == "ARMATURE":
        for pb in o.pose.bones:
            pb.custom_shape = None
for o in list(bpy.data.objects):
    if o.type == "MESH" and o.name not in KEEP:
        bpy.data.objects.remove(o, do_unlink=True)


# --- warna di atlas tekstur ---
def rgb_to_hsv(a):
    r, g, b = a[:, 0], a[:, 1], a[:, 2]
    mx, mn = a.max(1), a.min(1)
    d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-6
    rm = m & (mx == r)
    gm = m & (mx == g) & ~rm
    bm_ = m & ~rm & ~gm
    h[rm] = ((g[rm] - b[rm]) / d[rm]) % 6
    h[gm] = (b[gm] - r[gm]) / d[gm] + 2
    h[bm_] = (r[bm_] - g[bm_]) / d[bm_] + 4
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0.0)
    return h * 60.0, s, mx


def hsv_to_rgb(h, s, v):
    h6 = (h % 360.0) / 60.0
    i = np.floor(h6).astype(int) % 6
    f = h6 - np.floor(h6)
    p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    r = np.choose(i, [v, q, p, p, t, v])
    g = np.choose(i, [t, v, v, q, p, p])
    b = np.choose(i, [p, p, t, v, v, q])
    return np.stack([r, g, b], 1)


img = bpy.data.images[0]
W, H = img.size
orig_cs = img.colorspace_settings.name
img.colorspace_settings.name = "Non-Color"  # baca/tulis nilai mentah tanpa konversi warna
buf = np.empty(W * H * 4, dtype=np.float32)
img.pixels.foreach_get(buf)
px = buf.reshape(-1, 4)
idx = np.arange(W * H)
U = ((idx % W) + 0.5) / W
V = ((idx // W) + 0.5) / H
hue, sat, val = rgb_to_hsv(px[:, :3])


def recolor(mask, h, s, vmul=1.0, vadd=0.0):
    """Ganti rona dan kejenuhan, pertahankan terang-gelap (gradasi) piksel asli."""
    nv = np.clip(val[mask] * vmul + vadd, 0, 1)
    px[mask, :3] = hsv_to_rgb(np.full(mask.sum(), h), np.full(mask.sum(), s), nv)


if mode == "nenek":
    # Jubah biru-ungu -> merah-mawar; selendang magenta -> krem; rambut hitam -> putih.
    recolor((hue >= 200) & (hue <= 290) & (sat > 0.2), h=350, s=0.45, vmul=1.35)
    recolor((hue >= 300) & (hue <= 350) & (sat > 0.5), h=42, s=0.28, vmul=1.3)
    hair = (U > 0.15) & (U < 0.23) & (V > 0.86) & (V < 0.98) & (sat < 0.2) & (val < 0.35)
    nv = np.clip(0.72 + 1.2 * (val[hair] - 0.1), 0, 1)
    px[hair, 0] = nv * 0.98
    px[hair, 1] = nv * 0.98
    px[hair, 2] = nv
else:
    # Tunik hijau -> cokelat-kuning (kain karung).
    recolor((hue >= 140) & (hue <= 200) & (sat > 0.5), h=40, s=0.55, vmul=1.1)

# Petak kecil di pojok atas-kanan atlas untuk warna topi: pastikan tidak dipakai UV mana pun.
PATCH = 6
px_idx = (idx % W >= W - PATCH) & (idx // W >= H - PATCH)
for o in bpy.data.objects:
    if o.type != "MESH":
        continue
    for loop_uv in o.data.uv_layers.active.data:
        u, v = loop_uv.uv
        if u > 1 - (PATCH + 2) / W and v > 1 - (PATCH + 2) / H:
            raise SystemExit("GAGAL: pojok atlas dipakai oleh %s; pilih petak lain" % o.name)
px[px_idx, 0], px[px_idx, 1], px[px_idx, 2] = STRAW
px[px_idx, 3] = 1.0

img.pixels.foreach_set(buf)
img.update()
img.colorspace_settings.name = orig_cs
img.pack()
patch_uv = (1 - PATCH / 2 / W, 1 - PATCH / 2 / H)


# --- topi jerami untuk petani ---
if mode == "petani":
    bm = bmesh.new()
    bm.from_mesh(head.data)
    uv_layer = bm.loops.layers.uv.active
    deform = bm.verts.layers.deform.verify()
    group = head.vertex_groups["head"].index
    added = []
    # pusat kepala (x=0, y=-0.01); dahi paling atas z=1.87, rambut paling atas z=2.19
    brim = bmesh.ops.create_cone(bm, cap_ends=True, segments=24, radius1=0.92, radius2=0.62, depth=0.14,
                                 matrix=Matrix.Translation((0, -0.01, 1.95)))
    crown = bmesh.ops.create_cone(bm, cap_ends=True, segments=24, radius1=0.6, radius2=0.52, depth=0.44,
                                  matrix=Matrix.Translation((0, -0.01, 2.17)))
    added = brim["verts"] + crown["verts"]
    faces = {f for v in added for f in v.link_faces}
    for f in faces:
        for loop in f.loops:
            loop[uv_layer].uv = patch_uv
    for v in added:
        v[deform][group] = 1.0  # ikut tulang kepala
    bm.to_mesh(head.data)
    bm.free()
    head.data.update()


# --- klip animasi ---
miss = [k for k in CLIPS if k not in bpy.data.actions]
if miss:
    raise SystemExit("GAGAL: klip tidak ditemukan: %s" % miss)
for act in list(bpy.data.actions):
    if act.name not in CLIPS:
        bpy.data.actions.remove(act)
for old, new in CLIPS.items():
    act = bpy.data.actions[old]
    act.name = new
    act.use_fake_user = True
    act.use_frame_range = False

rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
rig.animation_data_create()
for tr in list(rig.animation_data.nla_tracks):
    rig.animation_data.nla_tracks.remove(tr)
for new in CLIPS.values():
    act = bpy.data.actions[new]
    tr = rig.animation_data.nla_tracks.new()
    tr.name = new
    st = tr.strips.new(new, int(act.frame_range[0]), act)
    st.name = new
rig.animation_data.action = None

bpy.ops.export_scene.gltf(
    filepath=dst,
    export_format="GLB",
    export_animations=True,
    export_animation_mode="ACTIONS",
    export_force_sampling=True,
    export_apply=False,
)
print("SELESAI:", dst, "klip:", sorted(a.name for a in bpy.data.actions))
