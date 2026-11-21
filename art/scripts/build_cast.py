"""登場するもの（プレイヤー・願いを持つ生き物・その子ども・広場の生き物 2 種）を作る。

    blender -b --factory-startup --python art/scripts/build_cast.py              # 全部
    blender -b --factory-startup --python art/scripts/build_cast.py -- player    # 一部（BUILDERS）

方針（docs/art-direction.md）:
- ゆるふわで温かい、丸いシルエット。子どもっぽくしすぎない（目は小さめ・口は描かない）。
- 世界観が未定なので、特定の設定（職業・種族・時代）を示す飾りは付けない。色は palette.py から取る。
- プレイヤーは1つのモデルを4色で使う。布の部分はマテリアル "Accent"・"AccentDeep" で、
  ゲーム側（ArtPalette.tint_player）が色を差し替える。
- 部品（プレイヤーは Body Head ArmL ArmR LegL LegR）は別オブジェクトで、原点を関節に置く。
- 動きは骨格とアニメーション（rig.py。2026-11-21 本人の指示）。部品は 1 本の骨に重み 1.0 で結ぶ。
  アニメーションは idle / walk / happy（プレイヤーは jump も）。ゲーム側の RigAnimator が状態で切り替える。
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
import rig as rigmod  # noqa: E402
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

    rig = _traveler_rig(objects)
    root = group("Traveler", [rig])
    rigmod.save_and_export_rigged("traveler", [root, rig] + objects)


def _traveler_rig(objects):
    """旅の人の骨格（腰・胴・頭・腕・脚）と動き（idle / walk / jump / happy）。"""
    rig = rigmod.armature("TravelerRig", [
        ("b_root", (0, 0, 0), None, 0.2),
        ("b_torso", (0, 0, 0.42), "b_root", 0.4),
        ("b_head", (0, 0, 1.06), "b_torso", 0.3),
        ("b_arm_l", (-0.23, 0, 0.92), "b_torso", 0.1),
        ("b_arm_r", (0.23, 0, 0.92), "b_torso", 0.1),
        ("b_leg_l", (-0.105, 0, 0.44), "b_root", 0.1),
        ("b_leg_r", (0.105, 0, 0.44), "b_root", 0.1),
    ])
    bones = {"Body": "b_torso", "Head": "b_head", "ArmL": "b_arm_l", "ArmR": "b_arm_r",
             "LegL": "b_leg_l", "LegR": "b_leg_r"}
    for obj in objects:
        rigmod.bind(obj, rig, bones[obj.name])
    c = rigmod.cycle

    def rot_keys(frames, values, axis=0):
        out = []
        for f, v in c(frames, values):
            r = [0.0, 0.0, 0.0]
            r[axis] = v
            out.append((f, tuple(r), None, None))
        return out

    def up_keys(frames, values):
        return [(f, None, (0.0, v, 0.0), None) for f, v in c(frames, values)]

    # 立ち止まり: ゆっくり息をする（胴が少し上下し、頭がわずかに傾く）
    rigmod.action(rig, "idle", 48, {
        "b_torso": up_keys(48, [0.0, 0.012]),
        "b_head": [(f, (v, 0.0, 0.0), None, None) for f, v in c(48, [0.0, -0.03])],
        "b_arm_l": rot_keys(48, [0.0, 0.05], 2),
        "b_arm_r": rot_keys(48, [0.0, -0.05], 2),
    })
    # 歩き: 脚を前後に振り、腕は逆に。1 歩ごとに胴が弾む（16 フレームで 2 歩）
    rigmod.action(rig, "walk", 16, {
        "b_leg_l": rot_keys(16, [0.0, 0.7, 0.0, -0.7]),
        "b_leg_r": rot_keys(16, [0.0, -0.7, 0.0, 0.7]),
        "b_arm_l": rot_keys(16, [0.0, -0.55, 0.0, 0.55]),
        "b_arm_r": rot_keys(16, [0.0, 0.55, 0.0, -0.55]),
        "b_root": up_keys(16, [0.0, 0.04, 0.0, 0.04]),
        "b_head": [(f, (v, 0.0, 0.0), None, None) for f, v in c(16, [0.0, 0.04, 0.0, 0.04])],
    })
    # 空中: 脚を少したたみ、腕を横へ上げる（1 つの姿勢）
    jump_pose = {
        "b_leg_l": (0.45, 0.0, 0.0), "b_leg_r": (-0.2, 0.0, 0.0),
        "b_arm_l": (0.0, 0.0, -0.9), "b_arm_r": (0.0, 0.0, 0.9),
        "b_head": (-0.1, 0.0, 0.0),
    }
    rigmod.action(rig, "jump", 12, {
        b: [(1, r, None, None), (13, r, None, None)] for b, r in jump_pose.items()
    })
    # 喜ぶ: その場で小さく跳ね、両腕を上げて振る
    rigmod.action(rig, "happy", 24, {
        "b_root": up_keys(24, [0.0, 0.16, 0.0, 0.0]),
        "b_arm_l": [(f, (0.0, 0.0, v), None, None) for f, v in c(24, [-2.3, -2.7])],
        "b_arm_r": [(f, (0.0, 0.0, v), None, None) for f, v in c(24, [2.3, 2.7])],
        "b_head": [(f, (0.0, 0.0, v), None, None) for f, v in c(24, [0.12, -0.12])],
        "b_leg_l": rot_keys(24, [0.0, 0.25, 0.0, 0.0]),
        "b_leg_r": rot_keys(24, [0.0, -0.1, 0.0, 0.0]),
    })
    return rig


# --- 願いを持つ生き物とその子ども -------------------------------------------------


def _face(bm, s, y, z, gap, ink, shine, blush, eye=0.042):
    """目（ハイライト付き）と頬。y は顔の前面、z は目の高さ、gap は目の間の半分（どれも s 倍済み）。"""
    for sx in (-1, 1):
        at = (sx * gap, y, z)
        pal.ellipsoid(bm, eye * s, at, (1.0, 0.55, 1.3), (14, 10), ink)
        pal.ellipsoid(bm, eye * 0.31 * s, (at[0] + 0.012 * s, y + 0.02 * s, z + 0.025 * s),
                      (1, 0.5, 1), (8, 6), shine)
        pal.ellipsoid(bm, 0.045 * s, (sx * (gap + 0.085 * s), y - 0.045 * s, z - 0.07 * s),
                      (1.2, 0.4, 0.7), (12, 8), blush)


def _keys_rot(frames, values, axis):
    """1 つの軸だけを回す繰り返しのキー。"""
    out = []
    for f, v in rigmod.cycle(frames, values):
        r = [0.0, 0.0, 0.0]
        r[axis] = v
        out.append((f, tuple(r), None, None))
    return out


def _keys_up(frames, values):
    return [(f, None, (0.0, v, 0.0), None) for f, v in rigmod.cycle(frames, values)]


def _keys_puff(frames, values, thin=1.0):
    """息をするようにふくらむ（横に広がって、少し低くなる）。"""
    return [(f, None, None, (1.0 + v, 1.0 - v * thin, 1.0 + v))
            for f, v in rigmod.cycle(frames, values)]


def _creature(name, file_name, size, sprout_open, body_color, wing_color):
    """丸いからだに小さな羽と足、頭に芽。願いの「高いところへ」を、上へ伸びる芽で示す。
    size はからだの高さ（m）。正面は +Y、原点は足もと。
    部品（Body・WingL/R・FootL/R・Sprout）を別々に作り、骨格で動かす（idle / walk / happy）。"""
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
    objects = []

    def body(bm):
        profile = [(0.0, 0.05), (0.2, 0.055), (0.29, 0.12), (0.33, 0.24), (0.325, 0.36),
                   (0.28, 0.48), (0.19, 0.57), (0.09, 0.615), (0.0, 0.62)]
        pal.lathe(bm, [(r * s, z * s) for r, z in profile], 32, FU)
        pal.ellipsoid(bm, 0.22 * s, (0, 0.2 * s, 0.25 * s), (1.0, 0.55, 0.95), (24, 14), BE)
        _face(bm, s, 0.285 * s, 0.4 * s, 0.115 * s, INK, SH, BL)

    objects.append(base._join_as("Body", [part("Body", mats, body)], (0, 0, 0.05 * s)))
    for side, sx in (("L", -1), ("R", 1)):

        def wing_part(bm, sx=sx):
            pal.ellipsoid(bm, 0.12 * s, (sx * 0.31 * s, -0.02 * s, 0.3 * s), (0.45, 0.85, 1.0),
                          (16, 10), WI)

        objects.append(base._join_as("Wing" + side, [part("Wing" + side, mats, wing_part)],
                                     (sx * 0.29 * s, -0.02 * s, 0.38 * s)))

        def foot_part(bm, sx=sx):
            pal.ellipsoid(bm, 0.07 * s, (sx * 0.12 * s, 0.09 * s, 0.045 * s), (1.0, 1.4, 0.6),
                          (12, 8), FO)

        objects.append(base._join_as("Foot" + side, [part("Foot" + side, mats, foot_part)],
                                     (sx * 0.12 * s, 0.06 * s, 0.06 * s)))
    top = 0.6 * s

    def sprout(bm):
        # 頭の芽: 茎と、開いた2枚の葉（子どもはまだ閉じたつぼみ）
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

    objects.append(base._join_as("Sprout", [part("Sprout", mats, sprout)], (0, 0, top)))
    rig = rigmod.armature(name + "Rig", [
        ("b_root", (0, 0, 0), None, 0.1 * s),
        ("b_body", (0, 0, 0.05 * s), "b_root", 0.3 * s),
        ("b_wing_l", (-0.29 * s, -0.02 * s, 0.38 * s), "b_body", 0.08 * s),
        ("b_wing_r", (0.29 * s, -0.02 * s, 0.38 * s), "b_body", 0.08 * s),
        ("b_foot_l", (-0.12 * s, 0.06 * s, 0.06 * s), "b_root", 0.05 * s),
        ("b_foot_r", (0.12 * s, 0.06 * s, 0.06 * s), "b_root", 0.05 * s),
        ("b_sprout", (0, 0, top), "b_body", 0.12 * s),
    ])
    bones = {"Body": "b_body", "WingL": "b_wing_l", "WingR": "b_wing_r", "FootL": "b_foot_l",
             "FootR": "b_foot_r", "Sprout": "b_sprout"}
    for obj in objects:
        rigmod.bind(obj, rig, bones[obj.name])
    c = rigmod.cycle
    rigmod.action(rig, "idle", 48, {
        # 息をするように、からだがふくらむ。芽はゆっくり揺れ、羽はときどき動く
        "b_body": _keys_puff(48, [0.0, 0.025]),
        "b_sprout": _keys_rot(48, [0.12, -0.12], 2),
        "b_wing_l": _keys_rot(48, [0.0, 0.0, -0.3, 0.0], 2),
        "b_wing_r": _keys_rot(48, [0.0, 0.0, 0.3, 0.0], 2),
    })
    tilt = c(16, [0.0, 0.12, 0.0, -0.12])
    bob = c(16, [0.0, 0.04, 0.0, 0.04])
    step_l = c(16, [0.0, 0.07, 0.0, -0.07])
    lift_l = c(16, [0.0, 0.04, 0.0, 0.0])
    lift_r = c(16, [0.0, 0.0, 0.0, 0.04])
    rigmod.action(rig, "walk", 16, {
        # よちよち: 左右に体を傾け、足を交互に前へ。1 歩ごとに少し弾む
        "b_body": [(f, (0.0, 0.0, r), (0.0, u * s, 0.0), None)
                   for (f, r), (_, u) in zip(tilt, bob)],
        "b_foot_l": [(f, None, (0.0, u * s, -v * s), None)
                     for (f, v), (_, u) in zip(step_l, lift_l)],
        "b_foot_r": [(f, None, (0.0, u * s, v * s), None)
                     for (f, v), (_, u) in zip(step_l, lift_r)],
        "b_sprout": _keys_rot(16, [0.0, -0.15, 0.0, -0.15], 0),
        "b_wing_l": _keys_rot(16, [0.0, -0.2], 2),
        "b_wing_r": _keys_rot(16, [0.0, 0.2], 2),
    })
    rigmod.action(rig, "happy", 20, {
        # 喜ぶ: ぴょんと跳ね、羽をぱたぱた、芽がくるりと揺れる
        "b_root": _keys_up(20, [0.0, 0.22 * s, 0.0, 0.0]),
        "b_body": _keys_puff(20, [0.06, -0.04, 0.0, 0.06], 1.5),
        "b_wing_l": _keys_rot(20, [-0.2, -1.0, -0.2, -1.0], 2),
        "b_wing_r": _keys_rot(20, [0.2, 1.0, 0.2, 1.0], 2),
        "b_sprout": _keys_rot(20, [0.3, -0.3], 2),
    })
    root = group(name + "Root", [rig])
    rigmod.save_and_export_rigged(file_name, [root, rig] + objects)


def build_creature():
    _creature("WishCreature", "creature_wish", 0.62, True, "#f3cd92", pal.HONEY)


def build_kit():
    _creature("Kit", "creature_kit", 0.44, False, "#f8dcb6", pal.SUN_SOFT)


def build_bunny():
    """広場に住む生き物の1種（ころんとした耳の長い生き物）。部品: Body・Head・EarL/R・Tail・FootL/R。
    実在の動物に寄せすぎず、丸い形と色で「やわらかい生き物」に見せる。正面は +Y、原点は足もと。"""
    base.reset_scene()
    fur = mat("Fur", "#f6ead8", 0.9)
    inner = mat("Inner", pal.BLUSH, 0.85)
    belly = mat("Belly", pal.CREAM, 0.9)
    ink = mat("Ink", pal.INK, 0.35)
    shine = mat("Shine", "#ffffff", 0.2, emission="#ffffff", strength=0.5)
    blush = mat("Blush", pal.BLUSH, 0.8)
    mats = [fur, inner, belly, ink, shine, blush]
    FU, IN, BE, INK, SH, BL = range(6)
    s = 0.8
    objects = []

    def body(bm):
        pal.ellipsoid(bm, 0.26 * s, (0, -0.02 * s, 0.24 * s), (1.0, 1.08, 0.9), (28, 16), FU)
        pal.ellipsoid(bm, 0.17 * s, (0, 0.12 * s, 0.2 * s), (1.0, 0.6, 0.95), (20, 12), BE)

    objects.append(base._join_as("Body", [part("Body", mats, body)], (0, 0, 0.12 * s)))

    def head(bm):
        pal.ellipsoid(bm, 0.22 * s, (0, 0.1 * s, 0.56 * s), (1.08, 0.95, 0.92), (28, 16), FU)
        _face(bm, s, 0.3 * s, 0.58 * s, 0.09 * s, INK, SH, BL, eye=0.036)
        pal.ellipsoid(bm, 0.025 * s, (0, 0.31 * s, 0.53 * s), (1.2, 0.7, 0.8), (10, 6), BL)

    objects.append(base._join_as("Head", [part("Head", mats, head)], (0, 0.06 * s, 0.42 * s)))
    for side, sx in (("L", -1), ("R", 1)):

        def ear(bm, sx=sx):
            pal.capsule(bm, 0.06 * s, (sx * 0.1 * s, 0.06 * s, 0.7 * s),
                        (sx * 0.16 * s, 0.02 * s, 1.0 * s), 14, FU)
            pal.capsule(bm, 0.035 * s, (sx * 0.105 * s, 0.1 * s, 0.74 * s),
                        (sx * 0.155 * s, 0.065 * s, 0.96 * s), 10, IN)

        objects.append(base._join_as("Ear" + side, [part("Ear" + side, mats, ear)],
                                     (sx * 0.1 * s, 0.06 * s, 0.7 * s)))

        def foot(bm, sx=sx):
            pal.ellipsoid(bm, 0.08 * s, (sx * 0.13 * s, 0.06 * s, 0.05 * s), (0.9, 1.5, 0.6),
                          (14, 8), FU)

        objects.append(base._join_as("Foot" + side, [part("Foot" + side, mats, foot)],
                                     (sx * 0.13 * s, 0.0, 0.08 * s)))

    def tail(bm):
        pal.ellipsoid(bm, 0.08 * s, (0, -0.29 * s, 0.2 * s), (1, 1, 1), (14, 10), BE)

    objects.append(base._join_as("Tail", [part("Tail", mats, tail)], (0, -0.26 * s, 0.2 * s)))
    rig = rigmod.armature("BunnyRig", [
        ("b_root", (0, 0, 0), None, 0.1),
        ("b_body", (0, 0, 0.12 * s), "b_root", 0.2),
        ("b_head", (0, 0.06 * s, 0.42 * s), "b_body", 0.2),
        ("b_ear_l", (-0.1 * s, 0.06 * s, 0.7 * s), "b_head", 0.15),
        ("b_ear_r", (0.1 * s, 0.06 * s, 0.7 * s), "b_head", 0.15),
        ("b_tail", (0, -0.26 * s, 0.2 * s), "b_body", 0.05),
        ("b_foot_l", (-0.13 * s, 0.0, 0.08 * s), "b_root", 0.05),
        ("b_foot_r", (0.13 * s, 0.0, 0.08 * s), "b_root", 0.05),
    ])
    bones = {"Body": "b_body", "Head": "b_head", "EarL": "b_ear_l", "EarR": "b_ear_r",
             "Tail": "b_tail", "FootL": "b_foot_l", "FootR": "b_foot_r"}
    for obj in objects:
        rigmod.bind(obj, rig, bones[obj.name])
    rigmod.action(rig, "idle", 48, {
        "b_body": _keys_puff(48, [0.0, 0.02]),
        "b_ear_l": _keys_rot(48, [0.0, 0.0, 0.0, -0.35], 0),
        "b_ear_r": _keys_rot(48, [0.0, -0.1, 0.0, 0.0], 0),
        "b_head": _keys_rot(48, [0.0, 0.15, 0.0, -0.1], 1),
        "b_tail": _keys_rot(48, [0.0, 0.3, 0.0, 0.0], 2),
    })
    rigmod.action(rig, "walk", 16, {
        # ぴょこぴょこ: 2 回はねる。はねる間は足をそろえて後ろへ
        "b_root": _keys_up(16, [0.0, 0.12 * s, 0.0, 0.12 * s]),
        "b_body": _keys_rot(16, [0.0, 0.18, 0.0, 0.18], 0),
        "b_foot_l": _keys_rot(16, [0.0, -0.5, 0.0, -0.5], 0),
        "b_foot_r": _keys_rot(16, [0.0, -0.5, 0.0, -0.5], 0),
        "b_ear_l": _keys_rot(16, [0.0, -0.4, 0.0, -0.4], 0),
        "b_ear_r": _keys_rot(16, [0.0, -0.4, 0.0, -0.4], 0),
    })
    rigmod.action(rig, "happy", 20, {
        "b_root": _keys_up(20, [0.0, 0.3 * s, 0.0, 0.0]),
        "b_ear_l": _keys_rot(20, [0.0, -0.5, 0.0, -0.5], 2),
        "b_ear_r": _keys_rot(20, [0.0, 0.5, 0.0, 0.5], 2),
        "b_head": _keys_rot(20, [0.15, -0.15], 2),
        "b_tail": _keys_rot(20, [0.4, -0.4], 2),
    })
    root = group("BunnyRoot", [rig])
    rigmod.save_and_export_rigged("critter_bunny", [root, rig] + objects)


LAMB_LEGS = {"LegFL": (-0.12, 0.13), "LegFR": (0.12, 0.13), "LegBL": (-0.12, -0.13),
             "LegBR": (0.12, -0.13)}


def build_lamb():
    """広場に住む生き物の1種（もこもこの毛の4本足の生き物）。部品: Body・Head・EarL/R・Tail・脚4本。
    正面は +Y、原点は足もと。"""
    base.reset_scene()
    wool = mat("Wool", "#fbf4e6", 0.95)
    face = mat("Face", "#e9c9a6", 0.8)
    hoof = mat("Hoof", pal.WOOD_DARK, 0.7)
    ink = mat("Ink", pal.INK, 0.35)
    shine = mat("Shine", "#ffffff", 0.2, emission="#ffffff", strength=0.5)
    blush = mat("Blush", pal.BLUSH, 0.8)
    mats = [wool, face, hoof, ink, shine, blush]
    WO, FA, HO, INK, SH, BL = range(6)
    objects = []

    def body(bm):
        # 小さな毛の玉を集めて、ふわふわの雲のようなからだにする
        puffs = [(0, 0, 0.42, 0.24), (0.14, 0.1, 0.44, 0.16), (-0.14, 0.1, 0.44, 0.16),
                 (0.15, -0.12, 0.43, 0.16), (-0.15, -0.12, 0.43, 0.16), (0, 0.17, 0.47, 0.15),
                 (0, -0.2, 0.46, 0.15), (0, 0, 0.58, 0.16)]
        for x, y, z, r in puffs:
            pal.ellipsoid(bm, r, (x, y, z), (1, 1, 0.92), (18, 10), WO)

    objects.append(base._join_as("Body", [part("Body", mats, body)], (0, 0, 0.3)))

    def head(bm):
        pal.ellipsoid(bm, 0.14, (0, 0.3, 0.6), (0.95, 1.0, 1.05), (22, 14), FA)
        pal.ellipsoid(bm, 0.11, (0, 0.27, 0.72), (1.2, 1.0, 0.7), (18, 10), WO)
        _face(bm, 0.8, 0.42, 0.62, 0.06, INK, SH, BL, eye=0.04)

    objects.append(base._join_as("Head", [part("Head", mats, head)], (0, 0.22, 0.55)))
    for side, sx in (("L", -1), ("R", 1)):

        def ear(bm, sx=sx):
            pal.ellipsoid(bm, 0.07, (sx * 0.16, 0.28, 0.64), (1.0, 0.45, 0.4), (12, 8), FA)

        objects.append(base._join_as("Ear" + side, [part("Ear" + side, mats, ear)],
                                     (sx * 0.11, 0.28, 0.65)))
    for leg_name, (x, y) in LAMB_LEGS.items():

        def leg(bm, x=x, y=y):
            pal.capsule(bm, 0.045, (x, y, 0.05), (x, y, 0.32), 10, FA)
            pal.ellipsoid(bm, 0.055, (x, y + 0.01, 0.04), (1.0, 1.15, 0.7), (12, 8), HO)

        objects.append(base._join_as(leg_name, [part(leg_name, mats, leg)], (x, y, 0.3)))

    def tail(bm):
        pal.ellipsoid(bm, 0.07, (0, -0.36, 0.5), (1, 1, 1), (12, 8), WO)

    objects.append(base._join_as("Tail", [part("Tail", mats, tail)], (0, -0.33, 0.5)))
    bone_list = [
        ("b_root", (0, 0, 0), None, 0.1),
        ("b_body", (0, 0, 0.3), "b_root", 0.2),
        ("b_head", (0, 0.22, 0.55), "b_body", 0.15),
        ("b_ear_l", (-0.11, 0.28, 0.65), "b_head", 0.05),
        ("b_ear_r", (0.11, 0.28, 0.65), "b_head", 0.05),
        ("b_tail", (0, -0.33, 0.5), "b_body", 0.05),
    ]
    bones = {"Body": "b_body", "Head": "b_head", "EarL": "b_ear_l", "EarR": "b_ear_r",
             "Tail": "b_tail"}
    for leg_name, (x, y) in LAMB_LEGS.items():
        bone_list.append(("b_" + leg_name.lower(), (x, y, 0.3), "b_root", 0.05))
        bones[leg_name] = "b_" + leg_name.lower()
    rig = rigmod.armature("LambRig", bone_list)
    for obj in objects:
        rigmod.bind(obj, rig, bones[obj.name])

    def legs_keys(frames, a, b):
        # 対角の脚をそろえて振る（左前と右後ろ、右前と左後ろ）
        swing = {"b_legfl": a, "b_legbr": a, "b_legfr": b, "b_legbl": b}
        return {k: _keys_rot(frames, vals, 0) for k, vals in swing.items()}

    rigmod.action(rig, "idle", 48, {
        "b_body": _keys_puff(48, [0.0, 0.02], 0.0),
        "b_head": _keys_rot(48, [0.0, 0.0, 0.25, 0.0], 0),
        "b_ear_l": _keys_rot(48, [0.0, -0.3], 2),
        "b_ear_r": _keys_rot(48, [0.0, 0.3], 2),
        "b_tail": _keys_rot(48, [0.0, 0.5, 0.0, -0.5], 1),
    })
    walk = legs_keys(16, [0.0, 0.5, 0.0, -0.5], [0.0, -0.5, 0.0, 0.5])
    walk["b_body"] = _keys_up(16, [0.0, 0.03, 0.0, 0.03])
    walk["b_head"] = _keys_rot(16, [0.0, 0.06, 0.0, 0.06], 0)
    rigmod.action(rig, "walk", 16, walk)
    happy = legs_keys(20, [0.0, -0.4, 0.0, 0.0], [0.0, 0.4, 0.0, 0.0])
    happy["b_root"] = _keys_up(20, [0.0, 0.2, 0.0, 0.0])
    happy["b_head"] = _keys_rot(20, [0.2, -0.2], 2)
    happy["b_tail"] = _keys_rot(20, [0.7, -0.7], 1)
    rigmod.action(rig, "happy", 20, happy)
    root = group("LambRoot", [rig])
    rigmod.save_and_export_rigged("critter_lamb", [root, rig] + objects)


BUILDERS = {
    "player": build_player,
    "creature": build_creature,
    "kit": build_kit,
    "bunny": build_bunny,
    "lamb": build_lamb,
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    for name in argv or list(BUILDERS):
        BUILDERS[name]()


if __name__ == "__main__":
    main()
