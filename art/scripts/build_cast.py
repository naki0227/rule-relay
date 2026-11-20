"""登場するもの（プレイヤー・願いを持つ生き物・その子ども）を作る。

    blender -b --factory-startup --python art/scripts/build_cast.py              # 全部
    blender -b --factory-startup --python art/scripts/build_cast.py -- player    # 一部（BUILDERS）

方針（docs/art-direction.md）:
- ゆるふわで温かい、丸いシルエット。子どもっぽくしすぎない（目は小さめ・口は描かない）。
- 世界観が未定なので、特定の設定（職業・種族・時代）を示す飾りは付けない。色は palette.py から取る。
- プレイヤーは1つのモデルを4色で使う。布の部分はマテリアル "Accent"・"AccentDeep" で、
  ゲーム側（ArtPalette.tint_player）が色を差し替える。
- プレイヤーの手足・頭は別オブジェクトで、原点を関節に置く（Body Head ArmL ArmR LegL LegR）。
  PlayerAvatar._animate_limbs がこの名前で探して振る。Body の原点は高さ 0.42、Head は 1.06。
"""

import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_assets as base  # noqa: E402
import palette as pal  # noqa: E402
from palette import rot  # noqa: E402


def mat(name, color, roughness=0.8, emission=None, strength=0.0):
    return base.material(name, color, roughness, emission=emission, strength=strength)


def part(name, mats, build, smooth=60):
    bm = bmesh.new()
    build(bm)
    return base.mesh_object(name, bm, mats, smooth_angle=smooth)


def group(name, children):
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    for obj in children:
        obj.parent = root
        obj.matrix_parent_inverse = root.matrix_world.inverted()
    return root


# --- プレイヤー ------------------------------------------------------------------


def build_player():
    """フードをかぶった小柄な旅の人。大きめの頭・丸い胴・背中の小さな荷物で、遠くからでも人と分かる。"""
    base.reset_scene()
    accent = mat(pal.ACCENT, pal.PLAYER_COLORS[0], 0.85)
    accent_deep = mat(pal.ACCENT_DEEP, pal.PLAYER_COLORS_DEEP[0], 0.85)
    cream = mat("Cream", pal.CREAM, 0.9)
    skin = mat("Skin", pal.SKIN, 0.65)
    ink = mat("Ink", pal.INK, 0.35)
    shine = mat("Shine", "#ffffff", 0.2, emission="#ffffff", strength=0.5)
    blush = mat("Blush", pal.BLUSH, 0.8)
    wood = mat("Wood", pal.WOOD, 0.75)
    wood_light = mat("WoodLight", pal.WOOD_LIGHT, 0.8)
    pants = mat("Pants", pal.INK_SOFT, 0.9)
    boot = mat("Boot", pal.WOOD_DARK, 0.7)
    mats = [accent, accent_deep, cream, skin, ink, shine, blush, wood, wood_light, pants, boot]
    A, AD, CR, SK, INK, SH, BL, WD, WL, PA, BO = range(11)
    objects = []

    def body(bm):
        # 裾が広がった丸い上着
        profile = [(0.0, 0.37), (0.25, 0.375), (0.285, 0.43), (0.282, 0.56), (0.25, 0.74),
                   (0.2, 0.88), (0.13, 0.97), (0.0, 0.99)]
        pal.lathe(bm, profile, 28, A)
        pal.torus(bm, 0.262, 0.035, (0, 0, 0.405), 28, 10, AD)  # 裾の折り返し
        pal.torus(bm, 0.268, 0.026, (0, 0, 0.6), 28, 8, WD)  # 腰ひも
        pal.rounded_box(bm, (0.08, 0.04, 0.07), (0.0, 0.272, 0.6), 0.015, 2, WL)
        # えり巻き（ふんわりした輪）と背中に垂れる端
        pal.torus(bm, 0.135, 0.062, (0, 0, 0.955), 24, 12, CR)
        pal.capsule(bm, 0.045, (0.06, -0.14, 0.93), (0.09, -0.2, 0.74), 10, CR)
        # 背中の小さな荷物（丸い箱とふた）
        pal.rounded_box(bm, (0.3, 0.15, 0.3), (0, -0.29, 0.69), 0.06, 3, WL)
        pal.rounded_box(bm, (0.31, 0.17, 0.1), (0, -0.29, 0.83), 0.045, 3, AD)
        pal.rounded_box(bm, (0.05, 0.03, 0.08), (0, -0.375, 0.78), 0.012, 2, WD)

    objects.append(base._join_as("Body", [part("Body", mats, body)], (0, 0, 0.42)))

    def head(bm):
        pal.ellipsoid(bm, 0.29, (0, 0, 1.3), (1.05, 1.0, 0.95), (32, 18), SK)
        for sx in (-1, 1):
            pal.ellipsoid(bm, 0.038, (sx * 0.1, 0.262, 1.3), (1.0, 0.55, 1.4), (16, 10), INK)
            pal.ellipsoid(bm, 0.012, (sx * 0.1 + 0.012, 0.285, 1.33), (1, 0.5, 1), (8, 6), SH)
            pal.ellipsoid(bm, 0.045, (sx * 0.17, 0.222, 1.235), (1.3, 0.4, 0.7), (12, 8), BL)
        # フード: 少し大きい球の前を丸く抜いて厚みを付け、縁に太い輪を回す
        center = Vector((0, -0.03, 1.33))
        geom = bmesh.ops.create_uvsphere(bm, u_segments=36, v_segments=20, radius=0.335)
        bmesh.ops.translate(bm, vec=center, verts=geom["verts"])
        hood_faces = list({f for v in geom["verts"] for f in v.link_faces})
        front = [f for f in hood_faces if f.calc_center_median().y > 0.11]
        bmesh.ops.delete(bm, geom=front, context="FACES")
        hood = [f for f in hood_faces if f.is_valid]
        for f in hood:
            f.material_index = A
        ext = bmesh.ops.extrude_face_region(bm, geom=hood)
        inner = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
        for v in inner:
            v.co = center + (v.co - center) * 0.92
        for f in {f for v in inner for f in v.link_faces}:
            f.material_index = AD
        bmesh.ops.recalc_face_normals(bm, faces=[f for f in bm.faces])
        opening = math.sqrt(0.335**2 - 0.14**2)
        pal.torus(bm, opening - 0.01, 0.042, (0, 0.11, 1.33), 36, 10, AD, matrix=rot(-90, "X"))
        # 頭の上から後ろへ通る縫い目（後ろ姿がただの球に見えないように）
        seam = pal.torus(bm, 0.338, 0.016, (0, 0, 0), 30, 6, AD, arc=math.radians(140))
        seam_verts = list({v for f in seam for v in f.verts})
        bmesh.ops.rotate(bm, verts=seam_verts, cent=(0, 0, 0), matrix=rot(155, "Z"))
        bmesh.ops.rotate(bm, verts=seam_verts, cent=(0, 0, 0), matrix=rot(90, "Y"))
        bmesh.ops.translate(bm, vec=center, verts=seam_verts)
        # てっぺんの丸い房（シルエットの目印）
        pal.ellipsoid(bm, 0.085, (0, -0.07, 1.68), (1, 1, 0.92), (16, 10), CR)

    objects.append(base._join_as("Head", [part("Head", mats, head)], (0, 0, 1.06)))

    for side, sx in (("L", -1), ("R", 1)):

        def arm(bm, sx=sx):
            pal.capsule(bm, 0.072, (sx * 0.25, 0, 0.92), (sx * 0.3, 0.01, 0.68), 14, A)
            pal.torus(bm, 0.07, 0.022, (sx * 0.298, 0.01, 0.69), 14, 6, AD, matrix=rot(sx * 12, "Y"))
            pal.ellipsoid(bm, 0.078, (sx * 0.305, 0.015, 0.625), (1, 1, 1.05), (14, 10), CR)

        objects.append(
            base._join_as("Arm" + side, [part("Arm" + side, mats, arm)], (sx * 0.23, 0, 0.92))
        )

        def leg(bm, sx=sx):
            pal.capsule(bm, 0.078, (sx * 0.105, 0, 0.12), (sx * 0.105, 0, 0.44), 12, PA)
            pal.ellipsoid(bm, 0.1, (sx * 0.105, 0.035, 0.078), (1.0, 1.35, 0.78), (18, 10), BO)
            pal.torus(bm, 0.082, 0.026, (sx * 0.105, 0.0, 0.16), 14, 6, CR)

        objects.append(
            base._join_as("Leg" + side, [part("Leg" + side, mats, leg)], (sx * 0.105, 0, 0.44))
        )

    root = group("Traveler", objects)
    base.save_and_export("traveler", [root] + objects)


# --- 願いを持つ生き物とその子ども -------------------------------------------------


def _creature(name, file_name, size, sprout_open, body_color, wing_color):
    """丸いからだに小さな羽と足、頭に芽。願いの「高いところへ」を、上へ伸びる芽で示す。
    size はからだの高さ（m）。正面は +Y、原点は足もと。"""
    base.reset_scene()
    fur = mat("Fur", body_color, 0.9)
    belly = mat("Belly", pal.CREAM, 0.9)
    wing = mat("Wing", wing_color, 0.85)
    foot = mat("Foot", pal.SUN, 0.7)
    ink = mat("Ink", pal.INK, 0.35)
    shine = mat("Shine", "#ffffff", 0.2, emission="#ffffff", strength=0.5)
    blush = mat("Blush", pal.BLUSH, 0.8)
    leaf = mat("Leaf", pal.LEAF, 0.75)
    stem = mat("Stem", pal.LEAF_DEEP, 0.8)
    mats = [fur, belly, wing, foot, ink, shine, blush, leaf, stem]
    FU, BE, WI, FO, INK, SH, BL, LF, ST = range(9)
    s = size / 0.62

    def build(bm):
        profile = [(0.0, 0.05), (0.2, 0.055), (0.29, 0.12), (0.33, 0.24), (0.325, 0.36),
                   (0.28, 0.48), (0.19, 0.57), (0.09, 0.615), (0.0, 0.62)]
        pal.lathe(bm, [(r * s, z * s) for r, z in profile], 32, FU)
        pal.ellipsoid(bm, 0.22 * s, (0, 0.2 * s, 0.25 * s), (1.0, 0.55, 0.95), (24, 14), BE)
        for sx in (-1, 1):
            # 目（少し離して、やさしい表情に）
            eye = (sx * 0.115 * s, 0.285 * s, 0.4 * s)
            pal.ellipsoid(bm, 0.042 * s, eye, (1.0, 0.55, 1.3), (14, 10), INK)
            shine_at = (eye[0] + 0.012 * s, eye[1] + 0.02 * s, eye[2] + 0.025 * s)
            pal.ellipsoid(bm, 0.013 * s, shine_at, (1, 0.5, 1), (8, 6), SH)
            pal.ellipsoid(bm, 0.045 * s, (sx * 0.2 * s, 0.24 * s, 0.33 * s), (1.2, 0.4, 0.7),
                          (12, 8), BL)
            # 小さな羽（少し持ち上げる）
            pal.ellipsoid(bm, 0.12 * s, (sx * 0.31 * s, -0.02 * s, 0.3 * s), (0.45, 0.85, 1.0),
                          (16, 10), WI)
            # 足
            pal.ellipsoid(bm, 0.07 * s, (sx * 0.12 * s, 0.09 * s, 0.045 * s), (1.0, 1.4, 0.6),
                          (12, 8), FO)
        # 頭の芽: 茎と、開いた2枚の葉（子どもはまだ閉じたつぼみ）
        top = 0.6 * s
        pal.capsule(bm, 0.022 * s, (0, 0, top), (0.01 * s, 0.0, top + 0.13 * s), 8, ST)
        if sprout_open:
            for sx in (-1, 1):
                leaf_at = (sx * 0.075 * s, 0.0, top + 0.15 * s)
                faces = pal.ellipsoid(bm, 0.075 * s, (0, 0, 0), (1.0, 0.45, 0.32), (14, 8), LF)
                verts = list({v for f in faces for v in f.verts})
                bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=rot(sx * -28, "Y"))
                bmesh.ops.translate(bm, vec=Vector(leaf_at), verts=verts)
        else:
            pal.ellipsoid(bm, 0.05 * s, (0.01 * s, 0, top + 0.16 * s), (0.8, 0.8, 1.25), (12, 8), LF)

    obj = part(name, mats, build)
    root = group(name + "Root", [obj])
    base.save_and_export(file_name, [root, obj])


def build_creature():
    _creature("WishCreature", "creature_wish", 0.62, True, "#f3cd92", pal.HONEY)


def build_kit():
    _creature("Kit", "creature_kit", 0.44, False, "#f8dcb6", pal.SUN_SOFT)


BUILDERS = {
    "player": build_player,
    "creature": build_creature,
    "kit": build_kit,
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    for name in argv or list(BUILDERS):
        BUILDERS[name]()


if __name__ == "__main__":
    main()
