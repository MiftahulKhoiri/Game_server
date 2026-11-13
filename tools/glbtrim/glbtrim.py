#!/usr/bin/env python3
"""glbtrim: pangkas berkas GLB tanpa Blender (dipakai untuk model penyihir v0.80.0).

- --keep-mesh NAMA      : simpan hanya node mesh bernama ini (boleh berulang); mesh lain dilepas dari nodenya.
- --anim BARU=LAMA      : simpan hanya animasi LAMA dan beri nama BARU (boleh berulang).
- --image NAMA=berkas   : ganti gambar tertanam NAMA dengan berkas PNG.
Buffer ditulis ulang hanya berisi data yang masih dipakai, jadi berkas jadi jauh lebih kecil.

Contoh:
  python3 tools/glbtrim/glbtrim.py Rogue_Hooded.glb penyihir.glb --keep-mesh Rogue_Body ... \\
      --anim attack=Spellcast_Shoot --anim idle-loop=Idle --image rogue_texture=penyihir.png
"""
import argparse
import json
import struct


def load(path):
    b = open(path, 'rb').read()
    assert b[:4] == b'glTF', 'bukan GLB'
    off, js, binc = 12, None, b''
    while off < len(b):
        n, kind = struct.unpack_from('<II', b, off)
        chunk = b[off + 8:off + 8 + n]
        if kind == 0x4E4F534A:
            js = json.loads(chunk)
        elif kind == 0x004E4942:
            binc = chunk
        off += 8 + n
    return js, binc


def save(path, js, binc):
    jb = json.dumps(js, separators=(',', ':')).encode()
    jb += b' ' * (-len(jb) % 4)
    binc += b'\0' * (-len(binc) % 4)
    total = 12 + 8 + len(jb) + 8 + len(binc)
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, total))
        f.write(struct.pack('<II', len(jb), 0x4E4F534A) + jb)
        f.write(struct.pack('<II', len(binc), 0x004E4942) + binc)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src')
    ap.add_argument('dst')
    ap.add_argument('--keep-mesh', action='append', default=[])
    ap.add_argument('--anim', action='append', default=[])
    ap.add_argument('--image', action='append', default=[])
    a = ap.parse_args()
    js, binc = load(a.src)

    # 1. mesh yang tidak dipakai dilepas dari nodenya
    if a.keep_mesh:
        for nd in js['nodes']:
            if 'mesh' in nd and nd.get('name') not in a.keep_mesh:
                del nd['mesh']
                nd.pop('skin', None)
    # 2. animasi
    if a.anim:
        want = dict(x.split('=', 1) for x in a.anim)
        byname = {an.get('name'): an for an in js.get('animations', [])}
        missing = [old for old in want.values() if old not in byname]
        assert not missing, f'animasi tidak ada: {missing}'
        js['animations'] = [dict(byname[old], name=new) for new, old in want.items()]
    # 3. gambar pengganti (sebagai bufferView baru di akhir)
    extra = {}
    for x in a.image:
        name, path = x.split('=', 1)
        hit = [i for i, im in enumerate(js.get('images', [])) if im.get('name') == name]
        assert hit, f'gambar tidak ada: {name}'
        extra[hit[0]] = open(path, 'rb').read()

    # 4. kumpulkan accessor/bufferView/mesh/material/... yang masih dipakai
    used_mesh = sorted({nd['mesh'] for nd in js['nodes'] if 'mesh' in nd})
    used_skin = sorted({nd['skin'] for nd in js['nodes'] if 'skin' in nd})
    acc = set()
    mats = set()
    for mi in used_mesh:
        for pr in js['meshes'][mi]['primitives']:
            acc.update(pr['attributes'].values())
            if 'indices' in pr:
                acc.add(pr['indices'])
            if 'material' in pr:
                mats.add(pr['material'])
            for t in pr.get('targets', []):
                acc.update(t.values())
    for si in used_skin:
        if 'inverseBindMatrices' in js['skins'][si]:
            acc.add(js['skins'][si]['inverseBindMatrices'])
    for an in js.get('animations', []):
        for s in an['samplers']:
            acc.update((s['input'], s['output']))
    bvs = {js['accessors'][i]['bufferView'] for i in acc if 'bufferView' in js['accessors'][i]}
    imgs = set()
    for m in mats:
        for v in js['materials'][m].values():
            if isinstance(v, dict):
                for k in ('baseColorTexture', 'normalTexture', 'emissiveTexture', 'metallicRoughnessTexture', 'occlusionTexture'):
                    if k in v:
                        imgs.add(js['textures'][v[k]['index']].get('source'))
                if 'index' in v:
                    imgs.add(js['textures'][v['index']].get('source'))
    imgs.discard(None)
    for i in imgs:
        if i not in extra and 'bufferView' in js['images'][i]:
            bvs.add(js['images'][i]['bufferView'])

    # 5. tulis ulang buffer
    new_bin = bytearray()
    bv_map = {}
    new_bvs = []
    for old in sorted(bvs):
        bv = dict(js['bufferViews'][old])
        data = binc[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']]
        new_bin += b'\0' * (-len(new_bin) % 4)
        bv['byteOffset'] = len(new_bin)
        bv['buffer'] = 0
        new_bin += data
        bv_map[old] = len(new_bvs)
        new_bvs.append(bv)
    for i, data in extra.items():
        new_bin += b'\0' * (-len(new_bin) % 4)
        new_bvs.append({'buffer': 0, 'byteOffset': len(new_bin), 'byteLength': len(data)})
        new_bin += data
        js['images'][i] = {'name': js['images'][i].get('name', 'image'), 'mimeType': 'image/png', 'bufferView': len(new_bvs) - 1}
    acc_map = {}
    new_acc = []
    for old in sorted(acc):
        ac = dict(js['accessors'][old])
        if 'bufferView' in ac:
            ac['bufferView'] = bv_map[ac['bufferView']]
        acc_map[old] = len(new_acc)
        new_acc.append(ac)
    for i in range(len(js.get('images', []))):
        im = js['images'][i]
        if i not in extra and 'bufferView' in im:
            im['bufferView'] = bv_map.get(im['bufferView'], 0) if i in imgs else 0
    mesh_map = {old: n for n, old in enumerate(used_mesh)}
    new_meshes = []
    for old in used_mesh:
        m = json.loads(json.dumps(js['meshes'][old]))
        for pr in m['primitives']:
            pr['attributes'] = {k: acc_map[v] for k, v in pr['attributes'].items()}
            if 'indices' in pr:
                pr['indices'] = acc_map[pr['indices']]
            if 'targets' in pr:
                pr['targets'] = [{k: acc_map[v] for k, v in t.items()} for t in pr['targets']]
        new_meshes.append(m)
    for nd in js['nodes']:
        if 'mesh' in nd:
            nd['mesh'] = mesh_map[nd['mesh']]
    for sk in js.get('skins', []):
        if 'inverseBindMatrices' in sk:
            sk['inverseBindMatrices'] = acc_map.get(sk['inverseBindMatrices'], sk['inverseBindMatrices'])
    for an in js.get('animations', []):
        for s in an['samplers']:
            s['input'], s['output'] = acc_map[s['input']], acc_map[s['output']]
    js['meshes'] = new_meshes
    js['accessors'] = new_acc
    js['bufferViews'] = new_bvs
    js['buffers'] = [{'byteLength': len(new_bin)}]
    js['asset']['generator'] = 'glbtrim (Game_server) dari ' + js['asset'].get('generator', '')
    save(a.dst, js, bytes(new_bin))
    print(f'{a.dst}: {len(new_meshes)} mesh, {len(js.get("animations", []))} animasi, {len(new_bin)} byte data')


if __name__ == '__main__':
    main()
