"""Pengganti torchmcubes (butuh kompilasi) memakai scikit-image, hanya CPU."""
import numpy as np
import torch
from skimage.measure import marching_cubes as _mc


def marching_cubes(vol, thresh):
    v = vol.detach().cpu().numpy().astype(np.float32)
    verts, faces, _, _ = _mc(v, level=float(thresh))
    # torchmcubes mengurutkan sumbu terbalik (z,y,x); isosurface.py membaliknya lagi.
    verts = np.ascontiguousarray(verts[:, ::-1])
    return torch.from_numpy(verts.copy()).float(), torch.from_numpy(faces.astype(np.int64).copy())
