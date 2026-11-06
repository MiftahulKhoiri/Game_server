"""Menyiapkan karakter KayKit (CC0, Kay Lousberg) menjadi GLB ringan untuk game.

Sumber: https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 (CC0)

Yang dilakukan:
- membuang semua perlengkapan cadangan (pedang tambahan, perisai lain, bola kosong),
  hanya menyisakan bagian tubuh + pedang satu tangan + perisai yang dipilih;
- membuang 70an klip animasi yang tidak dipakai, menyisakan lima klip yang diberi nama
  sesuai aturan game (model_rig.gd): idle-loop, walk-loop, attack, hurt, die.

Jalankan:
  ~/Claude/blender.sh -b --factory-startup -P kaykit_karakter.py -- masuk.glb keluar.glb [Knight] [perisai]

  perisai: Badge_Shield | Rectangle_Shield | Round_Shield | Spike_Shield (bawaan Badge_Shield)
"""
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
src, dst = argv[0], argv[1]
prefix = argv[2] if len(argv) > 2 else "Knight"
shield = argv[3] if len(argv) > 3 else "Badge_Shield"

# nama klip KayKit -> nama klip game
CLIPS = {
    "Idle_Rig": "idle-loop",
    "Running_A_Rig": "walk-loop",
    "1H_Melee_Attack_Slice_Diagonal_Rig": "attack",
    "Hit_A_Rig": "hurt",
    "Death_A_Rig": "die",
}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

keep_mesh = {"1H_Sword", shield}
for o in list(bpy.data.objects):
    if o.type == "MESH" and not (o.name.startswith(prefix + "_") or o.name in keep_mesh):
        bpy.data.objects.remove(o, do_unlink=True)

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
# Pengimpor membuat jalur NLA bernama klip asli; nama itulah yang dipakai pengekspor,
# jadi buang dan buat ulang dengan nama klip game.
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
