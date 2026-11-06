"""Menyiapkan pahlawan KayKit (CC0, Kay Lousberg) menjadi GLB ringan untuk game.

Sumber: https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 (CC0)

Seperti kaykit_karakter.py tetapi untuk semua pahlawan: tubuh + senjata pilihan saja, dan lima
klip yang diberi nama sesuai aturan game (model_rig.gd): idle-loop, walk-loop, attack, hurt, die.

Jalankan:
  ~/Claude/blender.sh -b --factory-startup -P kaykit_pahlawan.py -- \
      masuk.glb keluar.glb AWALAN senjata1,senjata2 KLIP_IDLE KLIP_SERANG [spear] [-helmet]

  AWALAN   : Knight | Barbarian | Rogue | Mage (awalan nama mesh tubuh)
  senjata  : nama mesh senjata yang dipertahankan ("-" = tidak ada)
  spear    : tambahkan tombak buatan sendiri di tangan kanan (KayKit tidak punya tombak)
  -helmet  : buang <AWALAN>_Helmet
"""
import sys

import bpy
import bmesh

argv = sys.argv[sys.argv.index("--") + 1:]
src, dst, prefix = argv[0], argv[1], argv[2]
keep = set() if argv[3] == "-" else set(argv[3].split(","))
idle_clip, attack_clip = argv[4], argv[5]
opts = set(argv[6:])

CLIPS = {
    idle_clip: "idle-loop",
    "Running_A_Rig": "walk-loop",
    attack_clip: "attack",
    "Hit_A_Rig": "hurt",
    "Death_A_Rig": "die",
}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

spear_parent = None
if "spear" in opts:
    sword = bpy.data.objects["1H_Sword"]
    spear_parent = sword
    keep.add("1H_Sword")  # sementara, untuk ditiru lalu dibuang

for o in list(bpy.data.objects):
    if o.type != "MESH":
        continue
    if o.name.startswith(prefix + "_"):
        if "-helmet" in opts and o.name == prefix + "_Helmet":
            bpy.data.objects.remove(o, do_unlink=True)
        continue
    if o.name not in keep:
        bpy.data.objects.remove(o, do_unlink=True)

if spear_parent is not None:
    # Tombak: gagang kayu sepanjang sumbu Z lokal pedang (arah bilah), ujung baja berbentuk kerucut.
    me = bpy.data.meshes.new("Spear")
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.035, radius2=0.035, depth=1.9,
                          matrix=__import__("mathutils").Matrix.Translation((0, 0, 0.55)))
    shaft_faces = list(bm.faces)
    bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.09, radius2=0.0, depth=0.38,
                          matrix=__import__("mathutils").Matrix.Translation((0, 0, 1.69)))
    tip_faces = [f for f in bm.faces if f not in shaft_faces]
    wood = bpy.data.materials.new("tombak_kayu")
    wood.use_nodes = True
    wood.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.42, 0.26, 0.11, 1)
    wood.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.8
    steel = bpy.data.materials.new("tombak_baja")
    steel.use_nodes = True
    steel.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.78, 0.80, 0.85, 1)
    steel.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.45
    me.materials.append(wood)
    me.materials.append(steel)
    for f in tip_faces:
        f.material_index = 1
    bm.to_mesh(me)
    bm.free()
    spear = spear_parent.copy()  # menyalin induk tulang (handslot.r) dan posisi
    spear.name = "Spear"
    spear.data = me
    bpy.context.scene.collection.objects.link(spear)
    bpy.data.objects.remove(spear_parent, do_unlink=True)

missing = [k for k in CLIPS if k not in bpy.data.actions]
if missing:
    raise SystemExit("GAGAL: klip tidak ditemukan: %s" % missing)
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
