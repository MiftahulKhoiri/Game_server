# Gambar -> model 3D di Raspberry Pi (TripoSR, CPU)

Alat pengembang untuk mengubah gambar bertransparan (`client/assets/enemies/*.png`,
`characters/*.png`) menjadi `.glb` untuk `client/assets/models/<id>.glb`. Satu model sekitar
1,5 menit di Pi 5 (CPU), memori < 4 GB. Hasil: mesh berwarna per titik, **tanpa rangka**
(klien menggerakkan badan utuh: goyang, maju saat serang). Sisi belakang ditebak model.

Model: [TripoSR](https://github.com/VAST-AI-Research/TripoSR) (lisensi MIT, bobot `stabilityai/TripoSR`).

## Pasang (sekali)

```bash
python3 -m venv env && . env/bin/activate
pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
pip install omegaconf einops "transformers>=4.44,<4.50" trimesh pillow scikit-image numpy huggingface-hub imageio
git clone --depth 1 https://github.com/VAST-AI-Research/TripoSR.git
cp torchmcubes.py TripoSR/torchmcubes.py      # pengganti torchmcubes (tanpa kompilasi)
cp rembg_stub.py  TripoSR/rembg.py            # gambar sudah bertransparan, rembg tidak dipakai
```

`transformers` harus 4.x (5.x mengubah nama bobot sehingga bobot TripoSR gagal dimuat).
Unduhan model ±1,7 GB saat pertama jalan.

## Pakai

```bash
python gen.py ../../client/assets/enemies/golem_lava.png out/golem_lava 192
cp out/golem_lava.glb ../../client/assets/models/golem_lava.glb
```

Argumen ketiga = resolusi marching cubes (192 cukup; 256 lebih detail tapi lebih lambat).
Klien mengukur ulang tinggi model (`HEIGHTS` di `client/scripts/models.gd`), jadi ukuran
asli GLB tidak penting. Hasil mengikuti gambar sumber: gambar berwatermark menghasilkan
model berwatermark; ganti gambar sumber dengan karya sendiri sebelum rilis resmi.
