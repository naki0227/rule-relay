"""3D モデルで共有する色（パレット）と、丸い形を作る小さな部品。

色は UI（src/ui/ui_theme.gd）と同じ系統にそろえる。世界観が決まったら、ここの値を差し替えて
各スクリプトを実行し直せば、モデル全体の色が変わる（形は変えない）。
ゲーム側で色を変える部品（プレイヤーの色違い・ブロックのパネル）は、マテリアル名で探して上書きする。
その名前は src/game/art_palette.gd の定数とそろえる。

使い方: 他の生成スクリプトから `import palette as pal`（sys.path にこのフォルダを足す）。
"""

import math

import bmesh
from mathutils import Matrix, Vector

# --- 色（#rrggbb、sRGB） ---------------------------------------------------------

CREAM = "#fff3df"  # 生成り（布・札の地）
CREAM_DEEP = "#f1dfc2"
INK = "#4d3a2c"  # 目・文字（こげ茶。真っ黒にしない）
INK_SOFT = "#7a6352"
BLUSH = "#f2a99a"
SKIN = "#f4d0ae"

WOOD_LIGHT = "#e8c595"  # 明るい木（台・枠）
WOOD = "#c8935e"
WOOD_DARK = "#93653f"
STONE = "#e9dcc4"  # 暖かい石
STONE_DEEP = "#cdb999"
CLAY = "#d98c63"  # 素焼きの鉢

LEAF = "#7fb562"  # 若葉（有効・チェックポイント）
LEAF_DEEP = "#5d9147"
LEAF_LIGHT = "#a8d487"
SUN = "#f09a45"  # 夕日（目標・選択）
SUN_SOFT = "#ffc98a"
HONEY = "#e8b13f"  # はちみつ（能力のメダル）
HONEY_DEEP = "#c48a2a"
SKY = "#8cc4e8"  # 空色（入口・信号）
SKY_DEEP = "#5f9fcf"
BAN = "#e0644f"  # 禁止（柔らかい赤）
BAN_DEEP = "#b8473a"
PEWTER = "#b9b4ad"  # 禁止の器の地（くすんだ灰）
PEWTER_DEEP = "#8d8780"
LAMP = "#ffd9a0"  # 灯りの色

# プレイヤー1〜4の色（布の色）。明るさも少しずつ変え、色だけに頼らず見分けやすくする。
# ゲーム側の src/game/art_palette.gd の PLAYER_COLORS と同じ値にする。
PLAYER_COLORS = ["#6fa8dc", "#ec8a6a", "#82b866", "#b794d9"]
PLAYER_COLORS_DEEP = ["#4f86bd", "#c96a4d", "#5f9548", "#9172b8"]

# ゲーム側で色を差し替えるマテリアルの名前
ACCENT = "Accent"
ACCENT_DEEP = "AccentDeep"


def srgb(hex_color):
    """'#rrggbb' を Blender のリニア色 (r, g, b, 1) にする。"""
    hex_color = hex_color.lstrip("#")
    out = []
    for i in range(0, 6, 2):
        c = int(hex_color[i : i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (*out, 1.0)


# --- 丸い形（bmesh に足す。足した面を返す） --------------------------------------


def _faces_of(verts):
    return list({f for v in verts for f in v.link_faces})


def _set(faces, index):
    for f in faces:
        f.material_index = index


def lathe(bm, profile, segments=24, material_index=0, center=(0, 0, 0), matrix=None):
    """断面 [(半径, 高さ), ...]（下から上）を Z 軸の周りに回した形。半径 0 の点は1頂点にまとめる。"""
    rings = []
    for r, z in profile:
        if r <= 1e-6:
            rings.append([bm.verts.new((0, 0, z))])
            continue
        ring = []
        for i in range(segments):
            a = math.tau * i / segments
            ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, z)))
        rings.append(ring)
    faces = []
    for k in range(len(rings) - 1):
        lo, hi = rings[k], rings[k + 1]
        for i in range(segments):
            j = (i + 1) % segments
            if len(lo) == 1 and len(hi) == 1:
                continue
            if len(lo) == 1:
                faces.append(bm.faces.new((lo[0], hi[i], hi[j])))
            elif len(hi) == 1:
                faces.append(bm.faces.new((lo[i], lo[j], hi[0])))
            else:
                faces.append(bm.faces.new((lo[i], lo[j], hi[j], hi[i])))
    verts = [v for ring in rings for v in ring]
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=verts)
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    _set(faces, material_index)
    return faces


def rounded_profile(radius, height, round_r, steps=4, bottom=0.0):
    """角を丸めた円柱の断面（下面と上面を閉じる）。"""
    pts = [(0.0, bottom)]
    for i in range(steps + 1):
        a = -math.pi / 2 + (math.pi / 2) * i / steps
        pts.append((radius - round_r + math.cos(a) * round_r, bottom + round_r + math.sin(a) * round_r))
    for i in range(steps + 1):
        a = (math.pi / 2) * i / steps
        pts.append(
            (radius - round_r + math.cos(a) * round_r, bottom + height - round_r + math.sin(a) * round_r)
        )
    pts.append((0.0, bottom + height))
    return pts


def capsule_profile(radius, length, steps=6):
    """縦向きのカプセル（下端 0、上端 length）。"""
    pts = []
    for i in range(steps + 1):
        a = -math.pi / 2 + (math.pi / 2) * i / steps
        pts.append((math.cos(a) * radius, radius + math.sin(a) * radius))
    for i in range(steps + 1):
        a = (math.pi / 2) * i / steps
        pts.append((math.cos(a) * radius, length - radius + math.sin(a) * radius))
    return pts


def capsule(bm, radius, start, end, segments=16, material_index=0):
    """start から end へ伸びるカプセル。"""
    start, end = Vector(start), Vector(end)
    axis = end - start
    rot = axis.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
    return lathe(bm, capsule_profile(radius, axis.length), segments, material_index, start, rot)


def ellipsoid(bm, radius, center, scale=(1, 1, 1), segments=(24, 14), material_index=0):
    geom = bmesh.ops.create_uvsphere(bm, u_segments=segments[0], v_segments=segments[1], radius=radius)
    verts = geom["verts"]
    bmesh.ops.scale(bm, vec=Vector(scale), verts=verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=verts)
    faces = _faces_of(verts)
    _set(faces, material_index)
    return faces


def torus(bm, major, minor, center=(0, 0, 0), segments=32, ring_segments=10, material_index=0,
          matrix=None, arc=math.tau):
    """Z 軸の周りの輪。arc を 2π より小さくすると、端が開いた弧になる。"""
    closed = arc >= math.tau - 1e-6
    count = segments if closed else segments + 1
    rings = []
    for i in range(count):
        a = arc * i / segments
        ring = []
        for k in range(ring_segments):
            b = math.tau * k / ring_segments
            r = major + math.cos(b) * minor
            ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, math.sin(b) * minor)))
        rings.append(ring)
    faces = []
    for i in range(count if closed else count - 1):
        lo, hi = rings[i], rings[(i + 1) % count]
        for k in range(ring_segments):
            m = (k + 1) % ring_segments
            faces.append(bm.faces.new((lo[k], hi[k], hi[m], lo[m])))
    if not closed:
        for ring, flip in ((rings[0], True), (rings[-1], False)):
            cap = bm.faces.new(list(reversed(ring)) if flip else ring)
            faces.append(cap)
    verts = [v for ring in rings for v in ring]
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=verts)
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    _set(faces, material_index)
    return faces


def rounded_box(bm, size, center=(0, 0, 0), radius=0.05, segments=3, material_index=0, matrix=None):
    """角を丸めた直方体。"""
    geom = bmesh.ops.create_cube(bm, size=1.0)
    verts = geom["verts"]
    bmesh.ops.scale(bm, vec=Vector(size), verts=verts)
    edges = list({e for v in verts for e in v.link_edges})
    res = bmesh.ops.bevel(
        bm, geom=verts + edges, offset=radius, segments=segments, profile=0.5,
        affect="EDGES", clamp_overlap=True,
    )
    all_verts = list(set(verts) | {v for f in res["faces"] for v in f.verts})
    all_verts = [v for v in all_verts if v.is_valid]
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=all_verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=all_verts)
    faces = _faces_of(all_verts)
    _set(faces, material_index)
    return faces


def extrude_outline(bm, points, depth, z=0.0, material_index=0, bevel=0.01, matrix=None):
    """2D の輪郭 [(x, y), ...] を Z 方向へ depth だけ押し出し、縁を少し丸めた板にする。"""
    verts = [bm.verts.new((x, y, z)) for x, y in points]
    face = bm.faces.new(verts)
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    moved = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=Vector((0, 0, depth)), verts=moved)
    new_verts = verts + moved
    faces = _faces_of(new_verts)
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    if bevel > 0:
        edges = list({e for v in new_verts for e in v.link_edges})
        res = bmesh.ops.bevel(
            bm, geom=edges, offset=bevel, segments=2, affect="EDGES", clamp_overlap=True
        )
        new_verts = list({v for v in new_verts if v.is_valid} | {v for f in res["faces"] for v in f.verts})
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=new_verts)
    faces = _faces_of(new_verts)
    _set(faces, material_index)
    return faces


def rot(deg, axis):
    return Matrix.Rotation(math.radians(deg), 4, axis)
