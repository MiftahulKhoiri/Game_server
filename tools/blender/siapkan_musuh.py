"""Menyiapkan model musuh CC0 (KayKit Skeletons, Quaternius monster/hewan) menjadi GLB ringan.

Hasil: satu GLB berangka dengan klip bernama sesuai aturan game (model_rig.gd):
idle-loop, walk-loop, attack, hurt, die. Klip yang tidak ada di sumber (mis. hewan Quaternius
hanya punya idle/walk) dilengkapi gerak buatan di model_rig.gd.

Jalankan:
  ~/Claude/blender.sh -b --factory-startup -P siapkan_musuh.py -- masuk dest.glb 'OPSI_JSON'

OPSI_JSON:
  keep_prefix : awalan nama mesh yang dipertahankan (mesh lain, mis. "Icosphere", dibuang)
  keep_names  : nama mesh tambahan yang dipertahankan
  clips       : [[nama_klip_sumber, nama_klip_game], ...]  (sumber boleh dipakai dua kali)
  weapon      : {"file": gltf senjata, "bone": "handslot.r", "loc": [x,y,z]}  (opsional)
  max_tex     : perkecil semua tekstur lebih besar dari ini (piksel) supaya APK ringan
  rotz        : putar seluruh model mengelilingi sumbu Z (derajat) supaya wajah menghadap -Y
  src_pick    : "contains" -> cocokkan nama klip dengan "mengandung" bukan sama persis
"""
import json
import math
import sys

import bpy
import mathutils

argv = sys.argv[sys.argv.index("--") + 1:]
src, dst = argv[0], argv[1]
opt = json.load(open(argv[2][1:])) if argv[2].startswith("@") else json.loads(argv[2])

bpy.ops.wm.read_factory_settings(use_empty=True)
if src.lower().endswith(".fbx"):
    bpy.ops.import_scene.fbx(filepath=src)
else:
    bpy.ops.import_scene.gltf(filepath=src)

for o in list(bpy.data.objects):
    if o.type in ("CAMERA", "LIGHT"):
        bpy.data.objects.remove(o, do_unlink=True)

keep_prefix = tuple(opt.get("keep_prefix", [""]))
keep_names = set(opt.get("keep_names", []))
for o in list(bpy.data.objects):
    if o.type == "MESH" and not (o.name.startswith(keep_prefix) or o.name in keep_names):
        if o.name == "Icosphere" or keep_prefix != ("",):
            bpy.data.objects.remove(o, do_unlink=True)

rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")

if "weapon" in opt:
    w = opt["weapon"]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=w["file"])
    for o in set(bpy.data.objects) - before:
        if o.type == "MESH":
            o.parent = rig
            o.parent_type = "BONE"
            o.parent_bone = w.get("bone", "handslot.r")
            o.location = mathutils.Vector(w.get("loc", [0, -0.079, 0]))
            o.rotation_euler = (0, 0, 0)
            o.scale = (1, 1, 1)
        elif o.type != "ARMATURE":
            bpy.data.objects.remove(o, do_unlink=True)
        else:
            bpy.data.objects.remove(o, do_unlink=True)

pairs = opt["clips"]
by_name = {a.name: a for a in bpy.data.actions}


def find(orig):
    if orig in by_name:
        return by_name[orig]
    for n, a in by_name.items():
        if orig in n:
            return a
    raise SystemExit("GAGAL: klip '%s' tidak ada. Tersedia: %s" % (orig, sorted(by_name)[:60]))


final = {}
for orig, new in pairs:
    a = find(orig)
    if a.name in [x.name for x in final.values()]:
        a = a.copy()
    final[new] = a
used = {a.name for a in final.values()}
for a in list(bpy.data.actions):
    if a.name not in used:
        bpy.data.actions.remove(a)
for new, a in final.items():
    a.name = new
    a.use_fake_user = True
    a.use_frame_range = False

rig.animation_data_create()
for tr in list(rig.animation_data.nla_tracks):
    rig.animation_data.nla_tracks.remove(tr)
for new, a in final.items():
    tr = rig.animation_data.nla_tracks.new()
    tr.name = new
    st = tr.strips.new(new, int(a.frame_range[0]), a)
    st.name = new
rig.animation_data.action = None

if opt.get("rotz"):
    # Putar semua objek tingkat atas lewat satu Empty induk.
    root = bpy.data.objects.new("Putar", None)
    bpy.context.scene.collection.objects.link(root)
    tops = [o for o in bpy.data.objects if o.parent is None and o is not root]
    for o in tops:
        o.parent = root
    root.rotation_euler = (0, 0, math.radians(opt["rotz"]))

if opt.get("max_tex"):
    m = int(opt["max_tex"])
    for im in bpy.data.images:
        if im.size[0] > m or im.size[1] > m:
            im.scale(m, m)
            im.pack()

bpy.ops.export_scene.gltf(
    filepath=dst,
    export_format="GLB",
    export_animations=True,
    export_animation_mode="ACTIONS",
    export_force_sampling=True,
    export_apply=False,
)
print("SELESAI:", dst, "klip:", sorted(final))
