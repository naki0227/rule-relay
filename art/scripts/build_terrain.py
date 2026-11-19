"""島の地形を「ブロックでできているのに、角張って見えない」1つのモデルにする。

    godot --headless --script res://tools/export_terrain.gd          # 地形の箱を JSON に書き出す
    blender -b --factory-startup --python art/scripts/build_terrain.py

考え方（ブロックで作る箱庭ゲームでよく使われる見せ方。特定の作品の模倣ではない）:
- セルごとの箱を並べると、隣どうしの継ぎ目と角が全部見えて「タイル」に見える。全部のセルをつないで、
  外に出ている面だけを1つの面にする（内側の継ぎ目は消える）
- 外に出た角（凸）も、入り組んだ角（凹）も丸める。高さの段差は1ブロック単位のまま読めるが、輪郭が柔らかくなる
- 草のセルは、上面だけでなく縁の丸みまで草にして、側面へ少し垂らす（土が見えるのは側面の下の方だけ）
- 側面は頂点を少しだけ揺らして、定規で引いたような直線を崩す。上面は歩く面なので揺らさない
- ただし「ブロックでできている」ことは読めるように残す: 岩・砂岩の側面はセルごとに少し膨らませて石積みに見せ、
  上面と側面の色をセルごとにわずかに変える（マス目の線は描かない）
当たり判定は Godot 側の箱のまま（見た目と1〜2cm ずれる程度）。
"""

import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_assets as base  # noqa: E402

LAYOUT = base.SOURCE_DIR / "island_terrain.json"
BEVEL = 0.13
SEGMENTS = 3
JITTER = 0.03
GRASS_LIP = 0.26  # 草が上の縁から側面へ垂れる深さ

# Godot の6方向（x, y, z。y が上）
DIRECTIONS = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]


def load_cells():
    data = json.loads(LAYOUT.read_text())
    cells = {}
    for box in data["boxes"]:
        lo, hi = box["min"], box["max"]
        for x in range(lo[0], hi[0] + 1):
            for y in range(lo[1], hi[1] + 1):
                for z in range(lo[2], hi[2] + 1):
                    cells[(x, y, z)] = box["kind"]
    return cells


def to_blender(x, y, z):
    """Godot の座標（y が上、北が -z）→ Blender（z が上）。glTF 書き出しで Godot の向きに戻る。"""
    return Vector((x, -z, y))


def face_corners(cell, d):
    """セル cell の方向 d の面の4頂点（Godot の整数座標、外から見て反時計回り）。"""
    x, y, z = cell
    dx, dy, dz = d
    if dx:
        fx = x + (1 if dx > 0 else 0)
        quad = [(fx, y, z), (fx, y + 1, z), (fx, y + 1, z + 1), (fx, y, z + 1)]
    elif dy:
        fy = y + (1 if dy > 0 else 0)
        quad = [(x, fy, z), (x + 1, fy, z), (x + 1, fy, z + 1), (x, fy, z + 1)]
    else:
        fz = z + (1 if dz > 0 else 0)
        quad = [(x, y, fz), (x + 1, y, fz), (x + 1, y + 1, fz), (x, y + 1, fz)]
    return quad


def build_surface(cells):
    """外に出ている面だけを、頂点を共有した1つの面の集まりにする。"""
    bm = bmesh.new()
    verts = {}

    def vert(p):
        if p not in verts:
            verts[p] = bm.verts.new(to_blender(*p))
        return verts[p]

    for cell in cells:
        for d in DIRECTIONS:
            neighbour = (cell[0] + d[0], cell[1] + d[1], cell[2] + d[2])
            if neighbour in cells:
                continue
            if d == (0, -1, 0) and cell[1] <= -1:
                continue  # 島の底（下は岩の土台のモデルで隠れる）
            try:
                bm.faces.new([vert(p) for p in face_corners(cell, d)])
            except ValueError:
                pass  # 同じ面が二重にできる場合（斜めに接したセル）は飛ばす
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def round_edges(bm):
    """折れ曲がった辺（凸も凹も）だけを丸める。平らな面の中の継ぎ目は対象外。"""
    edges = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > math.radians(45)]
    bmesh.ops.bevel(
        bm, geom=edges, offset=BEVEL, segments=SEGMENTS, profile=0.5, affect="EDGES",
        clamp_overlap=True,
    )


def cell_of(center, normal, cells):
    """面の中心から、その面を持つセルを探す（Godot の座標）。"""
    g = Vector((center.x, center.z, -center.y))
    n = Vector((normal.x, normal.z, -normal.y))
    for depth in (0.05, 0.25, 0.45):
        p = g - n * depth
        key = (math.floor(p.x), math.floor(p.y), math.floor(p.z))
        if key in cells:
            return key
    return None


def cell_hash(key):
    h = math.sin(key[0] * 12.9898 + key[1] * 4.1414 + key[2] * 78.233) * 43758.5453
    return h - math.floor(h)


def paint(bm, cells):
    """材質: 土・草・岩・砂岩の2色ずつ（偶数がふつう、奇数が少し明るい）。草は上面と、上の縁から少し下まで。
    色はセルごとに決まった方を使い、同じ色の広い面にわずかなまだらを出す。"""
    for f in bm.faces:
        center = f.calc_center_median()
        key = cell_of(center, f.normal, cells)
        if key is None:
            f.material_index = 0
            continue
        kind = cells[key]
        light = 1 if cell_hash(key) > 0.55 else 0
        if kind == "grass":
            top = key[1] + 1.0
            grassy = f.normal.z > 0.45 or center.z > top - GRASS_LIP
            f.material_index = (2 if grassy else 0) + light
        elif kind == "sand":
            f.material_index = 6 + light
        else:
            f.material_index = 4 + light


def bulge_stone(bm, cells):
    """岩・砂岩の側面を、セルごとに縁を残して少し膨らませる（石を積んだように見える）。"""
    faces = []
    for f in bm.faces:
        if abs(f.normal.z) > 0.3 or f.calc_area() < 0.3:
            continue
        key = cell_of(f.calc_center_median(), f.normal, cells)
        if key is not None and cells[key] in ("rock", "sand"):
            faces.append(f)
    bmesh.ops.inset_individual(bm, faces=faces, thickness=0.07, depth=0.035)


def roughen_sides(bm):
    """側面の頂点だけを少し揺らす（決まった値なので毎回同じ形になる）。上面は歩く面なので揺らさない。"""
    for v in bm.verts:
        normal = v.normal
        if normal.z > 0.6:
            continue
        h = math.sin(v.co.x * 12.9898 + v.co.y * 78.233 + v.co.z * 37.719) * 43758.5453
        offset = (h - math.floor(h) - 0.5) * 2.0 * JITTER
        v.co += Vector((normal.x, normal.y, 0.0)) * offset


def main():
    base.reset_scene()
    cells = load_cells()
    bm = build_surface(cells)
    round_edges(bm)
    bm.normal_update()
    bulge_stone(bm, cells)
    paint(bm, cells)
    bm.normal_update()
    roughen_sides(bm)
    mats = [
        base.material("Dirt", "#b88a5c", 0.95),
        base.material("DirtLight", "#c0936a", 0.95),
        base.material("Grass", "#84bd5f", 0.85),
        base.material("GrassLight", "#8dc567", 0.85),
        base.material("Stone", "#b3a48e", 0.9),
        base.material("StoneLight", "#c1b39c", 0.9),
        base.material("Sandstone", "#e6c995", 0.9),
        base.material("SandstoneLight", "#eed4a6", 0.9),
    ]
    obj = base.mesh_object("IslandTerrain", bm, mats, smooth_angle=50)
    base.save_and_export("island_terrain", [obj])
    print(f"terrain cells: {len(cells)}, faces: {len(obj.data.polygons)}")


if __name__ == "__main__":
    main()
