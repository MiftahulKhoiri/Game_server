"""Potong latar semua gambar dan pisahkan karakter terpisah (komponen alpha).
Hasil: ~/Claude/triposr/new/<idx>_<k>.png + ringkasan new/ringkas.json"""
import sys, os, glob, json
import numpy as np
from PIL import Image
from scipy import ndimage
import rembg

SRC = sorted(glob.glob("/home/pi5/Gambar_game/*"))
OUT = os.path.expanduser("~/Claude/triposr/new")
os.makedirs(OUT, exist_ok=True)
only = [int(x) for x in sys.argv[1:]] if len(sys.argv) > 1 else list(range(len(SRC)))
sess = rembg.new_session("u2net")
info = {}
for i in only:
    f = SRC[i]
    im = Image.open(f).convert("RGBA")
    bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
    bg.alpha_composite(im)
    rgb = bg.convert("RGB")
    rgb.thumbnail((1400, 1400))
    res = rembg.remove(rgb, session=sess)
    a = np.array(res.getchannel("A")) > 40
    lab, n = ndimage.label(ndimage.binary_dilation(a, iterations=max(6, rgb.width // 90)))
    sizes = ndimage.sum(a, lab, range(1, n + 1))
    if n == 0:
        info[i] = []
        continue
    big = max(sizes)
    comps = [k + 1 for k, s in enumerate(sizes) if s > 0.18 * big]
    # urut kiri -> kanan
    comps.sort(key=lambda k: ndimage.center_of_mass(lab == k)[1])
    arr = np.array(res)
    out_list = []
    for j, k in enumerate(comps):
        m = (lab == k) & a
        sub = arr.copy()
        sub[:, :, 3] = np.where(m, arr[:, :, 3], 0)
        pim = Image.fromarray(sub)
        bb = pim.getchannel("A").getbbox()
        pim = pim.crop(bb)
        pim.thumbnail((768, 768))
        p = f"{OUT}/{i:02d}_{j}.png"
        pim.save(p)
        out_list.append({"file": p, "size": pim.size, "area": int(m.sum())})
        print("ok", p, pim.size, flush=True)
    info[i] = out_list
json.dump(info, open(f"{OUT}/ringkas.json", "w"), indent=1)
print("SELESAI", flush=True)
