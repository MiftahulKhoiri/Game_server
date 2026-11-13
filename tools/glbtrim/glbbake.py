#!/usr/bin/env python3
"""glbbake: "panggang" transformasi node ke dalam titik mesh (v0.80.0).

Model unduhan sering memakai node berskala 100 dan berputar (sumbu Z ke atas dari FBX). Pemasang bangunan
di world_build.gd hanya memakai mesh (tanpa transformasi node), jadi transformasi itu dipanggang ke titik,
lalu semua node menjadi identitas. Bisa juga diputar tambahan di sumbu Y (--yaw derajat) supaya bagian
depan model menghadap +Z, dan diskalakan supaya tingginya --height satuan.

  python3 tools/glbtrim/glbbake.py masuk.glb keluar.glb --yaw 90 --height 4
  python3 tools/glbtrim/glbbake.py belalang.glb info   # hanya cetak arah (titik tengah tiap node)
"""
import argparse
import json
import math
import struct
import sys

import numpy as np

sys.path.insert(0, __file__.rsplit('/', 1)[0])
from glbtrim import load, save  # noqa: E402

CT = {5126: np.float32}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}


def node_mat(nd):
    if 'matrix' in nd:
        return np.array(nd['matrix'], dtype=float).reshape(4, 4).T
    t = nd.get('translation', [0, 0, 0])
    x, y, z, w = nd.get('rotation', [0, 0, 0, 1])
    s = nd.get('scale', [1, 1, 1])
    r = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    m = np.eye(4)
    m[:3, :3] = r * np.array(s)
    m[:3, 3] = t
    return m


def world_mats(js):
    out = {}

    def walk(i, parent):
        m = parent @ node_mat(js['nodes'][i])
        out[i] = m
        for c in js['nodes'][i].get('children', []):
            walk(c, m)
    for root in js['scenes'][js.get('scene', 0)]['nodes']:
        walk(root, np.eye(4))
    return out


def view(js, binc, acc_i):
    ac = js['accessors'][acc_i]
    bv = js['bufferViews'][ac['bufferView']]
    n = NC[ac['type']]
    start = bv.get('byteOffset', 0) + ac.get('byteOffset', 0)
    stride = bv.get('byteStride', 4 * n)
    arr = np.ndarray((ac['count'], n), dtype=CT[ac['componentType']], buffer=binc, offset=start, strides=(stride, 4))
    return arr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src')
    ap.add_argument('dst')
    ap.add_argument('--yaw', type=float, default=0.0)
    ap.add_argument('--height', type=float, default=0.0)
    a = ap.parse_args()
    js, binc = load(a.src)
    binc = bytearray(binc)
    wm = world_mats(js)
    yaw = math.radians(a.yaw)
    ry = np.array([[math.cos(yaw), 0, math.sin(yaw), 0], [0, 1, 0, 0], [-math.sin(yaw), 0, math.cos(yaw), 0], [0, 0, 0, 1]])
    if a.dst == 'info':
        for i, m in wm.items():
            nd = js['nodes'][i]
            if 'mesh' in nd:
                pts = np.vstack([view(js, binc, pr['attributes']['POSITION']) for pr in js['meshes'][nd['mesh']]['primitives']])
                w = (m @ np.c_[pts, np.ones(len(pts))].T).T[:, :3]
                print(nd.get('name'), 'tengah', w.mean(0).round(3), 'min', w.min(0).round(3), 'max', w.max(0).round(3))
        return
    done = set()
    allpts = []
    for i, m in wm.items():
        nd = js['nodes'][i]
        if 'mesh' not in nd:
            continue
        full = ry @ m
        nrm = np.linalg.inv(full[:3, :3]).T
        for pr in js['meshes'][nd['mesh']]['primitives']:
            pi = pr['attributes']['POSITION']
            if pi in done:
                continue
            done.add(pi)
            p = view(js, binc, pi)
            p[:] = (full @ np.c_[p, np.ones(len(p))].T).T[:, :3]
            allpts.append(p.copy())
            if 'NORMAL' in pr['attributes']:
                nv = view(js, binc, pr['attributes']['NORMAL'])
                q = (nrm @ nv.T).T
                q /= np.maximum(np.linalg.norm(q, axis=1, keepdims=True), 1e-9)
                nv[:] = q
    pts = np.vstack(allpts)
    lo, hi = pts.min(0), pts.max(0)
    s = a.height / (hi[1] - lo[1]) if a.height > 0 else 1.0
    off = np.array([-(lo[0] + hi[0]) / 2, -lo[1], -(lo[2] + hi[2]) / 2])  # kaki di tanah, di tengah
    for pi in done:
        p = view(js, binc, pi)
        p[:] = (p + off) * s
        js['accessors'][pi]['min'] = p.min(0).tolist()
        js['accessors'][pi]['max'] = p.max(0).tolist()
    for nd in js['nodes']:
        for k in ('translation', 'rotation', 'scale', 'matrix'):
            nd.pop(k, None)
    save(a.dst, js, bytes(binc))
    print(f'{a.dst}: ukuran {((hi - lo) * s).round(3)}')


if __name__ == '__main__':
    main()
