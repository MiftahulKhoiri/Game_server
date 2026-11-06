"""Rig + animasi untuk GLB hasil TripoSR (tanpa tulang).

Jalankan: ~/Claude/blender.sh -b --factory-startup -P rig.py -- masuk.glb keluar.glb jenis
jenis: biped | quad | bat | snake
Klip yang dibuat (NLA, nama dikenali model_rig.gd): idle-loop, walk-loop, attack, hurt, die.
Depan model = -Y di Blender (= +Z glTF).
"""
import sys
import math
import time

import bpy
import numpy as np
from mathutils import Vector, Matrix, Euler

argv = sys.argv[sys.argv.index("--") + 1:]
src, dst, kind = argv[0], argv[1], argv[2]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
body = max(meshes, key=lambda m: len(m.data.vertices))
for o in list(bpy.data.objects):
    if o is not body:
        o.parent = None
        if o.type != "MESH":
            bpy.data.objects.remove(o)
bpy.context.view_layer.objects.active = body
body.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.shade_smooth()  # normal bersama -> titik tidak terbelah saat ekspor (ukuran berkas 6x lebih kecil)

V = np.array([v.co[:] for v in body.data.vertices])
x0, y0, z0 = V.min(axis=0)
x1, y1, z1 = V.max(axis=0)
H, W, L = z1 - z0, x1 - x0, y1 - y0
# Pusat badan: median titik di tinggi tengah (tahan terhadap senjata/ekor yang menonjol).
mid = V[(V[:, 2] > z0 + 0.35 * H) & (V[:, 2] < z0 + 0.75 * H)]
cx = float(np.median(mid[:, 0])) if len(mid) else (x0 + x1) / 2
cy = float(np.median(mid[:, 1])) if len(mid) else (y0 + y1) / 2
print("UKURAN H=%.3f W=%.3f L=%.3f pusat=(%.3f,%.3f) jenis=%s" % (H, W, L, cx, cy, kind))

bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
arm_obj = bpy.context.object
arm_obj.name = "Rangka"
arm = arm_obj.data
eb = arm.edit_bones
eb.remove(eb[0])


def bone(name, head, tail, parent=None):
    b = eb.new(name)
    b.head, b.tail = Vector(head), Vector(tail)
    if parent:
        b.parent = eb[parent]
        b.use_connect = False


def Z(f):
    return z0 + f * H


# ---------------------------------------------------------------- tata letak tulang
if kind == "biped":
    # lebar bahu & posisi kaki diukur dari mesh, bukan ditebak
    def slice_x(f0, f1):
        s = V[(V[:, 2] > Z(f0)) & (V[:, 2] < Z(f1))]
        return s[:, 0] if len(s) else np.array([cx])
    xs = slice_x(0.02, 0.30)
    left = xs[xs < cx]
    right = xs[xs >= cx]
    lx = float(np.mean(left)) if len(left) else cx - 0.08 * W
    rx = float(np.mean(right)) if len(right) else cx + 0.08 * W
    if rx - lx < 0.10 * W:
        lx, rx = cx - 0.10 * W, cx + 0.10 * W
    sh = slice_x(0.62, 0.78)
    sw = float(np.percentile(sh, 97) - np.percentile(sh, 3))
    sw = min(max(sw, 0.30 * W), W)
    bone("pinggul", (cx, cy, Z(.48)), (cx, cy, Z(.56)))
    bone("tulang_belakang", (cx, cy, Z(.56)), (cx, cy, Z(.72)), "pinggul")
    bone("leher", (cx, cy, Z(.72)), (cx, cy, Z(.80)), "tulang_belakang")
    bone("kepala", (cx, cy, Z(.80)), (cx, cy, Z(.98)), "leher")
    for s, sign, legx in (("k", -1, lx), ("kn", 1, rx)):
        ax = cx + sign * 0.5 * sw
        bone("lengan_atas_" + s, (cx + sign * 0.18 * sw, cy, Z(.72)), (ax, cy, Z(.60)), "tulang_belakang")
        bone("lengan_bawah_" + s, (ax, cy, Z(.60)), (ax + sign * 0.03 * W, cy, Z(.47)), "lengan_atas_" + s)
        bone("paha_" + s, (legx, cy, Z(.48)), (legx, cy, Z(.26)), "pinggul")
        bone("betis_" + s, (legx, cy, Z(.26)), (legx, cy, Z(.03)), "paha_" + s)
    sigma = 0.075 * H
elif kind == "quad":
    four = W > 0.38 * L
    zb = 0.52
    bone("pinggul", (cx, cy + .28 * L, Z(zb)), (cx, cy + .08 * L, Z(zb)))
    bone("tulang_belakang", (cx, cy + .08 * L, Z(zb)), (cx, cy - .14 * L, Z(zb)), "pinggul")
    bone("dada", (cx, cy - .14 * L, Z(zb)), (cx, cy - .30 * L, Z(zb + .05)), "tulang_belakang")
    bone("leher", (cx, cy - .30 * L, Z(zb + .05)), (cx, cy - .40 * L, Z(zb + .15)), "dada")
    bone("kepala", (cx, cy - .40 * L, Z(zb + .15)), (cx, cy - .50 * L, Z(zb + .15)), "leher")
    bone("ekor1", (cx, cy + .28 * L, Z(zb)), (cx, cy + .40 * L, Z(zb - .02)), "pinggul")
    bone("ekor2", (cx, cy + .40 * L, Z(zb - .02)), (cx, cy + .50 * L, Z(zb - .08)), "ekor1")
    legs = []
    if four:
        for s, sign in (("k", -1), ("kn", 1)):
            legs.append(("depan_" + s, cy - .24 * L, cx + sign * .28 * W, "dada"))
            legs.append(("belakang_" + s, cy + .22 * L, cx + sign * .28 * W, "pinggul"))
    else:
        legs.append(("depan", cy - .24 * L, cx, "dada"))
        legs.append(("belakang", cy + .22 * L, cx, "pinggul"))
    for nm, ly, lx_, par in legs:
        bone("kaki_atas_" + nm, (lx_, ly, Z(zb - .08)), (lx_, ly, Z(.22)), par)
        bone("kaki_bawah_" + nm, (lx_, ly, Z(.22)), (lx_, ly, Z(.02)), "kaki_atas_" + nm)
    sigma = 0.11 * max(H, L * 0.6)
elif kind == "bat":
    bone("badan", (cx, cy, Z(.35)), (cx, cy, Z(.60)))
    bone("kepala", (cx, cy, Z(.60)), (cx, cy, Z(.92)), "badan")
    for s, sign in (("k", -1), ("kn", 1)):
        bone("sayap1_" + s, (cx + sign * .06 * W, cy, Z(.55)), (cx + sign * .26 * W, cy, Z(.60)), "badan")
        bone("sayap2_" + s, (cx + sign * .26 * W, cy, Z(.60)), (cx + sign * .50 * W, cy, Z(.62)), "sayap1_" + s)
    sigma = 0.09 * max(H, W * 0.6)
else:  # snake / umum: rantai vertikal
    n = 5
    for i in range(n):
        bone("ruas%d" % i, (cx, cy, Z(i / n * .98)), (cx, cy, Z((i + 1) / n * .98)), "ruas%d" % (i - 1) if i else None)
    sigma = 0.11 * H

bpy.ops.object.mode_set(mode="OBJECT")


# ---------------------------------------------------------------- bobot (jarak ke ruas tulang)
def manual_weights(keep=3):
    for g in list(body.vertex_groups):
        body.vertex_groups.remove(g)
    names, segs = [], []
    for b in arm.bones:
        names.append(b.name)
        segs.append((np.array(b.head_local), np.array(b.tail_local)))
    d = np.zeros((len(V), len(segs)))
    for i, (h, t) in enumerate(segs):
        ab = t - h
        u = np.clip(((V - h) @ ab) / max(ab @ ab, 1e-9), 0, 1)
        d[:, i] = np.linalg.norm(V - (h + u[:, None] * ab), axis=1)
    w = np.exp(-(d / sigma) ** 2)
    idx = np.argsort(-w, axis=1)[:, :keep]
    out = np.zeros_like(w)
    rows = np.arange(len(V))[:, None]
    out[rows, idx] = w[rows, idx]
    dead = out.sum(axis=1) < 1e-6
    out[dead, np.argmin(d[dead], axis=1)] = 1.0
    out /= out.sum(axis=1, keepdims=True)
    vgs = [body.vertex_groups.new(name=n) for n in names]
    for i, vg in enumerate(vgs):
        for vi in np.nonzero(out[:, i] > 0.01)[0]:
            vg.add([int(vi)], float(out[vi, i]), "REPLACE")


manual_weights()
body.parent = arm_obj
body.parent_type = "OBJECT"
mod = body.modifiers.new("Rangka", "ARMATURE")
mod.object = arm_obj

# ---------------------------------------------------------------- animasi
bpy.context.view_layer.objects.active = arm_obj
bpy.ops.object.mode_set(mode="POSE")
bpy.context.scene.render.fps = 24
R_REST = {pb.name: pb.bone.matrix_local.to_3x3() for pb in arm_obj.pose.bones}
BONES = [pb.name for pb in arm_obj.pose.bones]


def has(n):
    return n in R_REST


class Pose:
    def __init__(self):
        self.d = {}

    def rot(self, name, x=0.0, y=0.0, z=0.0):
        if has(name):
            old = self.d.get(name, (0, 0, 0, (0, 0, 0)))
            self.d[name] = (old[0] + x, old[1] + y, old[2] + z, old[3])
        return self

    def loc(self, name, v):
        if has(name):
            old = self.d.get(name, (0, 0, 0, (0, 0, 0)))
            self.d[name] = (old[0], old[1], old[2], tuple(v))
        return self


def apply(p, frame):
    for pb in arm_obj.pose.bones:
        x, y, z, lv = p.d.get(pb.name, (0, 0, 0, (0, 0, 0)))
        Rw = Euler((x, y, z), "XYZ").to_matrix()
        R = R_REST[pb.name]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (R.inverted() @ Rw @ R).to_quaternion()
        pb.location = R.inverted() @ Vector(lv)
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb.keyframe_insert("location", frame=frame)


def make_action(name, frames, fn):
    act = bpy.data.actions.new(name)
    arm_obj.animation_data_create()
    arm_obj.animation_data.action = act
    for f in range(frames + 1):
        apply(fn(f / frames), f + 1)
    return act


S = math.sin
TAU = 2 * math.pi
HOLD = {"die": None}


def smooth(t):
    return t * t * (3 - 2 * t)


# --- biped
def b_idle(t):
    p = Pose()
    p.rot("tulang_belakang", S(TAU * t) * .03).rot("kepala", -S(TAU * t) * .03)
    p.rot("lengan_atas_k", S(TAU * t) * .04).rot("lengan_atas_kn", -S(TAU * t) * .04)
    return p


def b_walk(t):
    p = Pose()
    s = S(TAU * t)
    p.rot("paha_k", s * .55).rot("paha_kn", -s * .55)
    p.rot("betis_k", max(0, -s) * .5).rot("betis_kn", max(0, s) * .5)
    p.rot("lengan_atas_k", -s * .45).rot("lengan_atas_kn", s * .45)
    p.rot("tulang_belakang", 0, 0, s * .06).rot("pinggul", 0, 0, -s * .04)
    p.loc("pinggul", (0, 0, abs(S(TAU * t)) * .015 * H))
    return p


def b_attack(t):
    p = Pose()
    k = S(smooth(min(t * 1.6, 1.0)) * math.pi) if t < .625 else 0.0
    p.rot("lengan_atas_kn", -k * 2.2).rot("lengan_bawah_kn", -k * .5)
    p.rot("lengan_atas_k", -k * .6)
    p.rot("tulang_belakang", -k * .30, 0, k * .25).rot("kepala", k * .2)
    p.rot("pinggul", 0, 0, k * .12)
    return p


def b_hurt(t):
    p = Pose()
    k = S(t * math.pi)
    p.rot("tulang_belakang", k * .45).rot("kepala", k * .35).rot("lengan_atas_k", k * .6).rot("lengan_atas_kn", k * .6)
    p.rot("pinggul", k * .12)
    return p


def b_die(t):
    p = Pose()
    k = smooth(t)
    p.rot("pinggul", -k * math.pi / 2)
    p.rot("lengan_atas_k", -k * .9).rot("lengan_atas_kn", -k * .9).rot("kepala", -k * .3)
    p.loc("pinggul", (0, 0, -k * DIE_DROP))
    return p


# --- quad
def q_walk(t):
    p = Pose()
    s = S(TAU * t)
    fd = {"depan_k": s, "belakang_kn": s, "depan_kn": -s, "belakang_k": -s, "depan": s, "belakang": -s}
    for nm, v in fd.items():
        p.rot("kaki_atas_" + nm, v * .55).rot("kaki_bawah_" + nm, max(0, -v) * .5)
    p.rot("tulang_belakang", 0, 0, s * .07).rot("kepala", 0, 0, -s * .08)
    p.rot("ekor1", 0, 0, s * .35).rot("ekor2", 0, 0, s * .3)
    p.loc("pinggul", (0, 0, abs(s) * .02 * H))
    return p


def q_idle(t):
    p = Pose()
    s = S(TAU * t)
    p.rot("tulang_belakang", s * .025).rot("kepala", -s * .04).rot("ekor1", 0, 0, s * .3).rot("ekor2", 0, 0, s * .35)
    p.loc("pinggul", (0, 0, s * .008 * H))
    return p


def q_attack(t):
    p = Pose()
    k = S(smooth(min(t * 1.6, 1.0)) * math.pi) if t < .625 else 0.0
    p.rot("tulang_belakang", k * .25).rot("dada", k * .2).rot("kepala", -k * .4)
    p.loc("pinggul", (0, -k * .10 * L, 0))
    for nm in ("depan_k", "depan_kn", "depan"):
        p.rot("kaki_atas_" + nm, -k * .6)
    return p


def q_hurt(t):
    p = Pose()
    k = S(t * math.pi)
    p.rot("tulang_belakang", -k * .2).rot("kepala", k * .5).rot("dada", -k * .2)
    p.loc("pinggul", (0, k * .06 * L, 0))
    return p


def q_die(t):
    p = Pose()
    k = smooth(t)
    p.rot("pinggul", 0, k * math.pi / 2)  # roboh ke samping
    p.loc("pinggul", (0, 0, -k * DIE_DROP))
    p.rot("kepala", 0, 0, -k * .3)
    return p


# --- kelelawar
def bat_flap(amp, speed):
    def fn(t):
        p = Pose()
        s = S(TAU * t * speed)
        for sg, s_ in (("k", -1), ("kn", 1)):
            p.rot("sayap1_" + sg, 0, s_ * s * amp)
            p.rot("sayap2_" + sg, 0, s_ * s * amp * .8)
        p.loc("badan", (0, 0, S(TAU * t * speed) * .03 * H))
        return p
    return fn


def bat_attack(t):
    p = bat_flap(.5, 2)(t)
    k = S(smooth(min(t * 1.6, 1.0)) * math.pi) if t < .625 else 0.0
    p.rot("badan", k * .6).loc("badan", (0, -k * .15 * L if L > 0 else 0, -k * .05 * H))
    return p


def bat_hurt(t):
    p = Pose()
    k = S(t * math.pi)
    p.rot("badan", 0, S(t * TAU * 2) * .3, k * .3)
    return p


def bat_die(t):
    p = Pose()
    k = smooth(t)
    for sg, s_ in (("k", -1), ("kn", 1)):
        p.rot("sayap1_" + sg, 0, s_ * -k * .9).rot("sayap2_" + sg, 0, s_ * -k * .6)
    p.rot("badan", k * 1.2, k * 1.0)
    p.loc("badan", (0, 0, -k * DIE_DROP))
    return p


# --- ular / umum
def sn_idle(speed, amp):
    def fn(t):
        p = Pose()
        for i in range(5):
            p.rot("ruas%d" % i, 0, 0, S(TAU * t * 1 + i * .9) * amp * speed)
            p.rot("ruas%d" % i, S(TAU * t + i * .7) * amp * .4)
        return p
    return fn


def sn_attack(t):
    p = Pose()
    k = S(smooth(min(t * 1.6, 1.0)) * math.pi) if t < .625 else 0.0
    for i in range(5):
        p.rot("ruas%d" % i, -k * .22 * (1 + i * .3))
    return p


def sn_hurt(t):
    p = Pose()
    k = S(t * math.pi)
    for i in range(5):
        p.rot("ruas%d" % i, k * .25, 0, S(t * TAU * 2) * .3)
    return p


def sn_die(t):
    p = Pose()
    k = smooth(t)
    # gulungan ular: kepala terkulai ke depan, badan miring ke samping lalu menyentuh tanah
    p.rot("ruas0", 0, k * .55)
    for i, a in ((2, .5), (3, .9), (4, 1.2)):
        p.rot("ruas%d" % i, k * a)
    p.loc("ruas0", (0, 0, -k * DIE_DROP))
    return p


SETS = {
    "biped": dict(idle=b_idle, walk=b_walk, attack=b_attack, hurt=b_hurt, die=b_die),
    "quad": dict(idle=q_idle, walk=q_walk, attack=q_attack, hurt=q_hurt, die=q_die),
    "bat": dict(idle=bat_flap(.45, 1), walk=bat_flap(.7, 2), attack=bat_attack, hurt=bat_hurt, die=bat_die),
    "snake": dict(idle=sn_idle(1, .12), walk=sn_idle(2, .18), attack=sn_attack, hurt=sn_hurt, die=sn_die),
}[kind]
FRAMES = dict(idle=48, walk=24, attack=14, hurt=10, die=30)
NAMES = dict(idle="idle-loop", walk="walk-loop", attack="attack", hurt="hurt", die="die")
DIE_DROP = {"biped": .42 * H, "quad": .30 * H, "bat": .35 * H, "snake": .0}[kind]


def eval_extent():
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    arr = np.array([v.co[:] for v in ev.data.vertices])
    return arr


# --- kalibrasi 'die': turunkan hingga bagian terbawah menyentuh tanah (z0)
def calibrate_die():
    global DIE_DROP
    for _ in range(3):
        apply(SETS["die"](1.0), 1)
        arr = eval_extent()
        lo = arr[:, 2].min()
        if abs(lo - z0) < 0.01 * H:
            break
        DIE_DROP += (lo - z0)  # bisa negatif = angkat bila tembus tanah
    print("DIE: turun %.3f (tinggi %.3f)" % (DIE_DROP, H))


calibrate_die()
acts = {}
for key in ("idle", "walk", "attack", "hurt", "die"):
    acts[key] = make_action(NAMES[key], FRAMES[key], SETS[key])

# uji deformasi tiap klip pada beberapa fase
rest = np.array([v.co[:] for v in body.data.vertices])
rep = {}
for key in ("idle", "walk", "attack", "hurt", "die"):
    mx = 0.0
    bad = False
    for t in (.25, .5, .75, 1.0):
        apply(SETS[key](t), 1)
        arr = eval_extent()
        d = np.linalg.norm(arr - rest, axis=1)
        mx = max(mx, float(d.max()))
        bad = bad or bool(np.isnan(arr).any())
    rep[key] = (round(mx / H, 3), bad)
print("DEFORMASI (maks/tinggi, NaN):", rep)
apply(SETS["die"](1.0), 1)
arr = eval_extent()
print("DIE akhir: z %.3f..%.3f (tanah %.3f), tinggi sisa %.2f H" % (arr[:, 2].min(), arr[:, 2].max(), z0, (arr[:, 2].max() - arr[:, 2].min()) / H))


def ascii_view(arr, ah, av, title, cols=56, rows=20):
    lo_h, hi_h = V[:, ah].min() - .05 * W, V[:, ah].max() + .05 * W
    lo_v, hi_v = z0 - .6 * H, z1 + .1 * H
    sx = (cols - 1) / (hi_h - lo_h)
    sy = (rows - 1) / (hi_v - lo_v)
    g = [[" "] * cols for _ in range(rows)]
    gr = int((hi_v - z0) * sy)
    for c in range(cols):
        g[min(rows - 1, gr + 1)][c] = "-"
    for p in arr[::3]:
        c = int((p[ah] - lo_h) * sx)
        r = int((hi_v - p[av]) * sy)
        if 0 <= c < cols and 0 <= r < rows:
            g[r][c] = "#"
    print("SILUET", title)
    for row in g:
        print("|" + "".join(row))


rest_arr = np.array([v.co[:] for v in body.data.vertices])
ascii_view(rest_arr, 1, 2, "samping diam (kiri=depan)")
ascii_view(rest_arr, 0, 2, "depan diam")
apply(SETS["die"](1.0), 1)
ascii_view(eval_extent(), 1, 2, "samping MATI")
ascii_view(eval_extent(), 0, 2, "depan MATI")
apply(Pose(), 1)

bpy.ops.object.mode_set(mode="OBJECT")
for a in acts.values():
    a.use_fake_user = True
    tr = arm_obj.animation_data.nla_tracks.new()
    tr.name = a.name
    tr.strips.new(a.name, 1, a)
arm_obj.animation_data.action = None

kw = dict(filepath=dst, export_format="GLB", export_animations=True,
          export_animation_mode="NLA_TRACKS", export_skins=True, export_apply=False)
try:
    bpy.ops.export_scene.gltf(export_vertex_color="ACTIVE", **kw)
except TypeError:
    bpy.ops.export_scene.gltf(**kw)
print("EKSPOR: selesai ->", dst)
