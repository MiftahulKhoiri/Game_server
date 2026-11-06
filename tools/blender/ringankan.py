"""Mengecilkan jumlah segitiga GLB hasil TripoSR (untuk dekorasi: pohon, batu, tanaman).

Jalankan:
  ~/Claude/blender.sh -b --factory-startup -P ringankan.py -- masuk.glb keluar.glb [target_segitiga] [tinggi_m] [maks_lebar_m] [pipih]

- target_segitiga: bawaan 1500 (cukup untuk ratusan instance di HP).
- tinggi_m: kalau diisi, model diskalakan sehingga tingginya segitu.
- maks_lebar_m: kalau diisi, lebar/dalam model dibatasi sampai nilai ini
  (supaya satu pohon/batu tidak menutupi petak di sebelahnya).
- pipih: kata "pipih" sebagai argumen ke-5 -> hanya lebar yang dipipihkan, tinggi tetap sesuai
  tinggi_m (cocok untuk pohon, karena hasil TripoSR cenderung gemuk). Tanpa ini seluruh model
  diperkecil seragam sehingga tingginya ikut turun.
- Dengan tinggi_m: alas diletakkan di y=0 dan model dipusatkan di sumbu x/z.
  Tanpa argumen ini ukuran tidak diubah.
Warna per titik tetap dipertahankan.
"""
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
src, dst = argv[0], argv[1]
target = int(argv[2]) if len(argv) > 2 else 1500
tinggi = float(argv[3]) if len(argv) > 3 else 0.0
maks_lebar = float(argv[4]) if len(argv) > 4 else 0.0
pipih = len(argv) > 5 and argv[5] == "pipih"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
if not meshes:
    raise SystemExit("GAGAL: tidak ada mesh di " + src)
body = max(meshes, key=lambda m: len(m.data.polygons))
for o in list(bpy.data.objects):
    if o is not body:
        o.parent = None
        bpy.data.objects.remove(o)
bpy.context.view_layer.objects.active = body
body.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# Gabungkan titik kembar dulu supaya pengecilan bersih.
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.remove_doubles(threshold=1e-5)
bpy.ops.object.mode_set(mode="OBJECT")

sebelum = len(body.data.polygons)
if sebelum > target:
    mod = body.modifiers.new("kecil", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = max(0.0005, min(1.0, target / float(sebelum)))
    bpy.ops.object.modifier_apply(modifier=mod.name)

# Segitigakan, lalu halus.
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.quads_convert_to_tris()
bpy.ops.object.mode_set(mode="OBJECT")
bpy.ops.object.shade_smooth()


def kotak():
    xs = [v.co.x for v in body.data.vertices]
    ys = [v.co.y for v in body.data.vertices]
    zs = [v.co.z for v in body.data.vertices]
    return min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)


# Di Blender sumbu atas = Z (di glTF/Godot = Y).
x0, x1, y0, y1, z0, z1 = kotak()
tinggi_asli = z1 - z0
lebar_asli = max(x1 - x0, y1 - y0)
skala = 1.0
if tinggi > 0 and tinggi_asli > 0:
    skala = tinggi / tinggi_asli
    skala_h = skala  # skala mendatar (x, y di Blender)
    if maks_lebar > 0 and lebar_asli * skala > maks_lebar:
        if pipih:
            skala_h = maks_lebar / lebar_asli
        else:
            skala = skala_h = maks_lebar / lebar_asli
    body.scale = (skala_h, skala_h, skala)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    x0, x1, y0, y1, z0, z1 = kotak()
    body.location = (-(x0 + x1) / 2, -(y0 + y1) / 2, -z0)
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)

sesudah = len(body.data.polygons)
kw = dict(filepath=dst, export_format="GLB", export_animations=False, export_apply=True)
try:
    bpy.ops.export_scene.gltf(export_vertex_color="ACTIVE", **kw)
except TypeError:
    bpy.ops.export_scene.gltf(**kw)
x0, x1, y0, y1, z0, z1 = kotak()
print("RINGKAS: %s  %d -> %d segitiga, tinggi %.2f, lebar %.2f (skala %.3f)" %
      (dst, sebelum, sesudah, z1 - z0, max(x1 - x0, y1 - y0), skala))
