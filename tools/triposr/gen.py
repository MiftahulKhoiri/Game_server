import sys, os, time, numpy as np, torch, trimesh
sys.path.insert(0, os.path.expanduser("~/Claude/triposr/TripoSR"))
from PIL import Image
from tsr.system import TSR
from tsr.utils import resize_foreground

src, out = sys.argv[1], sys.argv[2]
res = int(sys.argv[3]) if len(sys.argv) > 3 else 192
t = time.time()
model = TSR.from_pretrained("stabilityai/TripoSR", config_name="config.yaml", weight_name="model.ckpt")
model.renderer.set_chunk_size(4096)
model.to("cpu")
print("model dimuat", round(time.time() - t), "dtk", flush=True)

im = Image.open(src).convert("RGBA")
im = resize_foreground(im, 0.85)
a = np.array(im).astype(np.float32) / 255.0
a = a[:, :, :3] * a[:, :, 3:4] + (1 - a[:, :, 3:4]) * 0.5
inp = Image.fromarray((a * 255).astype(np.uint8))
inp.save(out + "_input.png")
t = time.time()
with torch.no_grad():
    codes = model([inp], device="cpu")
print("inferensi", round(time.time() - t), "dtk", flush=True)
t = time.time()
mesh = model.extract_mesh(codes, True, resolution=res)[0]
print("mesh", round(time.time() - t), "dtk", len(mesh.vertices), "titik", len(mesh.faces), "segitiga", flush=True)
# TripoSR menghasilkan sumbu Y ke atas dengan menghadap +Z setelah rotasi ini
mesh.apply_transform(trimesh.transformations.rotation_matrix(-np.pi / 2, [1, 0, 0]))
mesh.apply_transform(trimesh.transformations.rotation_matrix(-np.pi / 2, [0, 1, 0]))  # depan = +Z
trimesh.repair.fix_normals(mesh)
# Warna titik dari TripoSR bernilai sRGB; glTF/Godot menganggapnya linear -> ubah ke linear.
vc = np.array(mesh.visual.vertex_colors, dtype=np.float32) / 255.0
vc[:, :3] = np.power(vc[:, :3], 2.2)
mesh.visual.vertex_colors = (np.clip(vc, 0, 1) * 255).astype(np.uint8)
mesh.export(out + ".glb")
print("selesai", out + ".glb", flush=True)
