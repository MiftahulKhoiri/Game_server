#!/usr/bin/env python3
"""Alat paket game platform multi-game (v0.84.0). Dipanggil scripts/build-game-pack.sh.

Subperintah:
  check-pck PCK ID            periksa header + direktori PCK (aturan sama dengan client/core/pck_reader.gd)
  publish   --id ID --pck PCK --game-json JSON --engine X.Y.Z --catalog DIR --key PRIV.pem
                              salin paket ke katalog, tulis manifest.json + manifest.sig, lalu bangun ulang
                              catalog.json + catalog.sig
  catalog   --catalog DIR --key PRIV.pem
                              bangun ulang catalog.json + catalog.sig dari semua <id>/manifest.json
  verify    FILE SIG PUB.pem  periksa tanda tangan (untuk uji)

Tanda tangan: RSA PKCS#1 v1.5 + SHA-256 (openssl dgst -sha256 -sign), disimpan base64 satu baris. Kunci
privat TIDAK pernah disalin ke repo atau APK; hanya dibaca dari path yang diberikan.
"""
import argparse
import base64
import datetime
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile

ID_RE = re.compile(r"^[a-z][a-z0-9_]{1,31}$")
SEMVER_RE = re.compile(r"^(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})$")
ENGINE_FILES = {"project.binary", ".godot/uid_cache.bin", ".godot/global_script_class_cache.cfg",
                "icon.svg.import", "icon.svg", "assets/icon/icon_512.png"}
DISPLAY_FIELDS = ["id", "name", "description", "category", "version", "type", "entry_scene", "package", "size",
                  "sha256", "min_launcher_version", "min_engine_version", "icon", "icon_sha256", "icon_color", "background_music", "enabled", "updated"]


def read_pck(path):
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 40 or data[:4] != b"GDPC":
        raise ValueError("bukan berkas PCK")
    fmt, ma, mi, pa, flags = struct.unpack_from("<5I", data, 4)
    if fmt not in (3, 4):
        raise ValueError(f"format PCK {fmt} tidak didukung")
    if flags & 1:
        raise ValueError("direktori PCK terenkripsi")
    if flags & ~2:
        raise ValueError(f"flag PCK tidak dikenal {flags}")
    file_base, dir_off = struct.unpack_from("<QQ", data, 24)
    base = file_base if flags & 2 else 0
    o = dir_off
    (n,) = struct.unpack_from("<I", data, o)
    o += 4
    files = []
    for _ in range(n):
        (plen,) = struct.unpack_from("<I", data, o)
        o += 4
        p = data[o:o + plen].split(b"\0")[0].decode("utf-8")
        o += plen
        off, size = struct.unpack_from("<QQ", data, o)
        o += 32
        (fflags,) = struct.unpack_from("<I", data, o)
        o += 4
        if base + off + size > len(data):
            raise ValueError("isi berkas di luar batas: " + p)
        files.append((p.removeprefix("res://"), size, fflags))
    return (ma, mi, pa), files


def check_paths(files, gid):
    ns = f"games/{gid}/"
    has_ns = False
    for p, _size, fl in files:
        if fl != 0:
            return f"berkas berflag khusus: {p}"
        if ".." in p or p.startswith("/") or "\\" in p or "//" in p:
            return f"path tidak aman: {p}"
        if p.startswith(ns):
            has_ns = True
            continue
        if p.startswith("games/"):
            return f"menyentuh namespace game lain: {p}"
        if p.startswith(".godot/exported/") or p.startswith(".godot/imported/") or p in ENGINE_FILES:
            continue
        return f"berkas di luar namespace res://{ns}: {p}"
    return "" if has_ns else f"paket tidak berisi res://{ns}"


def sign(path, key):
    with tempfile.NamedTemporaryFile(delete=False) as t:
        tmp = t.name
    try:
        subprocess.run(["openssl", "dgst", "-sha256", "-sign", key, "-out", tmp, path], check=True)
        with open(tmp, "rb") as f:
            return base64.b64encode(f.read()).decode() + "\n"
    finally:
        os.unlink(tmp)


def verify(path, sig_b64, pub):
    with tempfile.NamedTemporaryFile(delete=False) as t:
        t.write(base64.b64decode(sig_b64.strip()))
        tmp = t.name
    try:
        r = subprocess.run(["openssl", "dgst", "-sha256", "-verify", pub, "-signature", tmp, path],
                           capture_output=True, text=True)
        return r.returncode == 0
    finally:
        os.unlink(tmp)


def write_atomic(path, data):
    tmp = path + ".tmp"
    with open(tmp, "wb" if isinstance(data, bytes) else "w", **({} if isinstance(data, bytes) else {"encoding": "utf-8"})) as f:
        f.write(data)
    os.replace(tmp, path)


def build_catalog(cat_dir, key):
    games = []
    for gid in sorted(os.listdir(cat_dir)):
        mp = os.path.join(cat_dir, gid, "manifest.json")
        if not ID_RE.match(gid) or not os.path.isfile(mp):
            continue
        with open(mp, encoding="utf-8") as f:
            m = json.load(f)
        pkg = os.path.join(cat_dir, gid, m["package"])
        if m.get("id") != gid or not os.path.isfile(pkg) or os.path.getsize(pkg) != m["size"]:
            print(f"Lewati {gid}: manifest/paket tidak cocok", file=sys.stderr)
            continue
        games.append({k: m[k] for k in DISPLAY_FIELDS if k in m})
    doc = {"catalog_version": 1, "generated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
           "games": games}
    cp = os.path.join(cat_dir, "catalog.json")
    write_atomic(cp + ".new", json.dumps(doc, ensure_ascii=False, indent=1) + "\n")
    sig = sign(cp + ".new", key)
    # Tanda tangan ditulis dulu ke .new juga, lalu keduanya diganti berurutan (jendela tidak cocok sangat singkat;
    # klien yang kebetulan mendapat pasangan tidak cocok hanya menolak lalu memakai katalog lamanya).
    write_atomic(os.path.join(cat_dir, "catalog.sig.new"), sig)
    os.replace(cp + ".new", cp)
    os.replace(os.path.join(cat_dir, "catalog.sig.new"), os.path.join(cat_dir, "catalog.sig"))
    print(f"Katalog: {len(games)} game -> {cp}")


def cmd_check(a):
    eng, files = read_pck(a.pck)
    why = check_paths(files, a.id)
    if why:
        sys.exit("PCK ditolak: " + why)
    print(f"PCK sah: Godot {eng[0]}.{eng[1]}.{eng[2]}, {len(files)} berkas, namespace games/{a.id}/")


def cmd_publish(a):
    if not ID_RE.match(a.id):
        sys.exit("id tidak sah")
    with open(a.game_json, encoding="utf-8") as f:
        src = json.load(f)
    if src.get("id") != a.id:
        sys.exit("id di game.json tidak sama")
    for k in ("version", "min_launcher_version"):
        if not SEMVER_RE.match(str(src.get(k, ""))):
            sys.exit(f"{k} di game.json tidak sah")
    if not str(src.get("entry_scene", "")).startswith(f"res://games/{a.id}/"):
        sys.exit("entry_scene harus di res://games/<id>/")
    eng, files = read_pck(a.pck)
    why = check_paths(files, a.id)
    if why:
        sys.exit("PCK ditolak: " + why)
    engine = f"{eng[0]}.{eng[1]}.{eng[2]}"
    if a.engine and a.engine != engine:
        sys.exit(f"versi mesin PCK {engine} tidak sama dengan --engine {a.engine}")
    gdir = os.path.join(a.catalog, a.id)
    os.makedirs(gdir, exist_ok=True)
    mp = os.path.join(gdir, "manifest.json")
    if os.path.isfile(mp):
        with open(mp, encoding="utf-8") as f:
            old = json.load(f)
        if [int(x) for x in old["version"].split(".")] > [int(x) for x in src["version"].split(".")]:
            sys.exit(f"versi {src['version']} lebih lama daripada yang diterbitkan ({old['version']})")
    with open(a.pck, "rb") as f:
        blob = f.read()
    sha = hashlib.sha256(blob).hexdigest()
    pkg_name = f"{a.id}-{src['version']}.pck"
    pkg_path = os.path.join(gdir, pkg_name)
    if os.path.isfile(pkg_path):
        with open(pkg_path, "rb") as f:
            if hashlib.sha256(f.read()).hexdigest() != sha:
                sys.exit(f"{pkg_name} sudah diterbitkan dengan isi berbeda; naikkan versi di game.json")
    write_atomic(pkg_path, blob)
    m = dict(src)
    m.update({"type": "download", "package": pkg_name, "size": len(blob), "sha256": sha,
              "min_engine_version": engine,
              "updated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")})
    m.setdefault("enabled", True)
    # Ikon (opsional): game.json "icon" = res://games/<id>/....png -> disalin ke <katalog>/<id>/icon.png;
    # sha256-nya masuk manifest bertanda tangan supaya launcher bisa memverifikasi ikon yang diunduh.
    icon = str(src.get("icon", ""))
    if icon:
        if not icon.startswith(f"res://games/{a.id}/") or not icon.endswith(".png") or ".." in icon:
            sys.exit("icon harus berkas .png di res://games/<id>/")
        client_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(a.game_json))))
        with open(os.path.join(client_dir, icon[len("res://"):]), "rb") as f:
            ib = f.read()
        if not ib.startswith(b"\x89PNG\r\n\x1a\n") or len(ib) > 1 << 20:
            sys.exit("icon harus PNG <= 1 MB")
        write_atomic(os.path.join(gdir, "icon.png"), ib)
        m["icon_sha256"] = hashlib.sha256(ib).hexdigest()
    write_atomic(mp + ".new", json.dumps(m, ensure_ascii=False, indent=1) + "\n")
    sig = sign(mp + ".new", a.key)
    write_atomic(os.path.join(gdir, "manifest.sig.new"), sig)
    os.replace(mp + ".new", mp)
    os.replace(os.path.join(gdir, "manifest.sig.new"), os.path.join(gdir, "manifest.sig"))
    # Sisakan paket versi aktif dan satu versi sebelumnya.
    pcks = sorted((p for p in os.listdir(gdir) if p.endswith(".pck")),
                  key=lambda p: os.path.getmtime(os.path.join(gdir, p)), reverse=True)
    for old in pcks[2:]:
        os.unlink(os.path.join(gdir, old))
    print(f"Terbit: {a.id} {src['version']} ({len(blob) // 1024} KB, sha256 {sha[:12]}…)")
    build_catalog(a.catalog, a.key)


def cmd_catalog(a):
    build_catalog(a.catalog, a.key)


def cmd_verify(a):
    with open(a.sig, encoding="utf-8") as f:
        ok = verify(a.file, f.read(), a.pub)
    print("SAH" if ok else "TIDAK SAH")
    sys.exit(0 if ok else 1)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("check-pck")
    p.add_argument("pck")
    p.add_argument("id")
    p.set_defaults(fn=cmd_check)
    p = sub.add_parser("publish")
    for k in ("--id", "--pck", "--game-json", "--catalog", "--key"):
        p.add_argument(k, required=True)
    p.add_argument("--engine", default="")
    p.set_defaults(fn=cmd_publish)
    p = sub.add_parser("catalog")
    p.add_argument("--catalog", required=True)
    p.add_argument("--key", required=True)
    p.set_defaults(fn=cmd_catalog)
    p = sub.add_parser("verify")
    p.add_argument("file")
    p.add_argument("sig")
    p.add_argument("pub")
    p.set_defaults(fn=cmd_verify)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
