"""目印と拾える物（ゴールの旗・チェックポイントの台・入口の門・器のメダル・装備・生き物の巣）を作る。

    blender -b --factory-startup --python art/scripts/build_markers.py              # 全部
    blender -b --factory-startup --python art/scripts/build_markers.py -- goal      # 一部（BUILDERS）

方針（docs/art-direction.md）:
- 役割を色と形の両方で示す。ゴール＝夕日色の旗と「集まる」印（真ん中の丸を4つの丸が囲む）、
  チェックポイント＝若葉色の灯り、入口＝空色の門、能力＝はちみつ色のメダル、禁止＝灰の地に赤い輪と斜線。
- 当たり判定はゲーム側（無いか、箱）で、モデルは見た目だけ。原点は足もと（器は中心）。
- ゴールの旗の布は "Flag" という子オブジェクトで、原点が竿の位置（ゲームで揺らす）。
- 器のメダルは正面が ±Y（Godot の ±Z）。記号はゲームが面の上に絵（assets/icons/glyph_*.png）を重ねる。
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


def mat(name, color, roughness=0.8, emission=None, strength=0.0, metallic=0.0):
    return base.material(name, color, roughness, metallic, emission=emission, strength=strength)


def part(name, mats, build, smooth=55):
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


def export(file_name, root_name, objects):
    root = group(root_name, objects)
    base.save_and_export(file_name, [root] + objects)


def _verts(faces):
    return list({v for f in faces for v in f.verts})


# --- ゴール ------------------------------------------------------------------------


def _flag_wave(x):
    """旗の布のゆるい波（竿から離れるほど大きい）。"""
    return math.sin(x * 5.5) * 0.05 * min(1.0, x / 0.35)


def build_goal_flag():
    """「全員でここに集まる」旗: 丸い石の台、木の竿、夕日色の布に「集まる」印。"""
    base.reset_scene()
    stone = mat("Stone", pal.STONE, 0.85)
    stone_deep = mat("StoneDeep", pal.STONE_DEEP, 0.9)
    wood = mat("Wood", pal.WOOD_LIGHT, 0.75)
    honey = mat("Honey", pal.HONEY, 0.4, emission=pal.SUN_SOFT, strength=0.6)
    cloth = mat("Cloth", pal.SUN, 0.85)
    cloth_deep = mat("ClothDeep", "#d9793a", 0.85)
    mark = mat("Mark", pal.CREAM, 0.8)

    def stand(bm):
        pal.lathe(bm, pal.rounded_profile(0.42, 0.12, 0.05), 32, 1)
        pal.lathe(bm, pal.rounded_profile(0.3, 0.12, 0.05, bottom=0.1), 32, 0)
        pal.capsule(bm, 0.045, (0, 0, 0.15), (0, 0, 2.45), 14, 2)
        pal.ellipsoid(bm, 0.085, (0, 0, 2.5), (1, 1, 1), (18, 12), 3)
        pal.torus(bm, 0.055, 0.02, (0, 0, 2.38), 16, 6, 2)

    pole = part("FlagPole", [stone, stone_deep, wood, honey], stand)

    width, height, top = 0.95, 0.62, 2.36
    cols, rows = 24, 8

    def flag(bm):
        # 布: 格子を波打たせ、裏表に厚みを付ける。端は燕尾（V字の切り欠き）
        def notch(z):
            return width - 0.16 * (1.0 - abs((z - (top - height / 2)) / (height / 2)))

        grid = []
        for i in range(cols + 1):
            column = []
            for k in range(rows + 1):
                z = top - height + height * k / rows
                x = 0.05 + (notch(z) - 0.05) * i / cols
                column.append((x, z))
            grid.append(column)
        sheets = []
        for y_off in (0.014, -0.014):
            sheet = [[bm.verts.new((x, _flag_wave(x) + y_off, z)) for x, z in col] for col in grid]
            sheets.append(sheet)
        faces = []
        front, back = sheets
        for i in range(cols):
            for k in range(rows):
                faces.append(bm.faces.new((front[i][k], front[i + 1][k], front[i + 1][k + 1],
                                           front[i][k + 1])))
                faces.append(bm.faces.new((back[i][k], back[i][k + 1], back[i + 1][k + 1],
                                           back[i + 1][k])))
        # 縁を閉じる
        for i in range(cols):
            for k in (0, rows):
                faces.append(bm.faces.new((front[i][k], back[i][k], back[i + 1][k], front[i + 1][k])))
        for i in (0, cols):
            for k in range(rows):
                faces.append(bm.faces.new((front[i][k], front[i][k + 1], back[i][k + 1], back[i][k])))
        bmesh.ops.recalc_face_normals(bm, faces=faces)
        for f in faces:
            f.material_index = 0
        # 竿に巻く筒
        pal.capsule(bm, 0.06, (0.0, 0.0, top - height - 0.02), (0.0, 0.0, top + 0.02), 14, 1)
        # 「集まる」印: 真ん中の丸を、4つの小さな丸が囲む（両面）
        cx, cz = 0.44, top - height / 2
        spots = [(cx, cz, 0.085)]
        for k in range(4):
            a = math.tau * k / 4 + math.pi / 4
            spots.append((cx + math.cos(a) * 0.17, cz + math.sin(a) * 0.17, 0.045))
        for x, z, r in spots:
            for side in (1, -1):
                y = _flag_wave(x) + side * 0.018
                pal.ellipsoid(bm, r, (x, y, z), (1.0, 0.18, 1.0), (16, 8), 2)

    cloth_obj = part("Flag", [cloth, cloth_deep, mark], flag)
    base._join_as("Flag", [cloth_obj], (0, 0, 0))
    export("goal_flag", "GoalFlag", [pole, cloth_obj])


def build_goal_corner():
    """ゴールの範囲の四隅に立てる、小さな灯りの杭。"""
    base.reset_scene()
    stone = mat("Stone", pal.STONE, 0.85)
    wood = mat("Wood", pal.WOOD, 0.75)
    glow = mat("Glow", pal.SUN_SOFT, 0.4, emission=pal.SUN_SOFT, strength=1.4)

    def build(bm):
        pal.lathe(bm, pal.rounded_profile(0.16, 0.1, 0.04), 20, 0)
        pal.capsule(bm, 0.05, (0, 0, 0.05), (0, 0, 0.5), 12, 1)
        pal.ellipsoid(bm, 0.09, (0, 0, 0.58), (1, 1, 1.1), (16, 10), 2)
        pal.torus(bm, 0.06, 0.02, (0, 0, 0.5), 14, 6, 1)

    export("goal_corner", "GoalCorner", [part("GoalCorner", [stone, wood, glow], build)])


# --- チェックポイント・入口 -------------------------------------------------------


def _pad(bm, ring_index, stone=0, stone_deep=1):
    """丸い石の台（縁が丸い）と、光る輪。"""
    pal.lathe(bm, pal.rounded_profile(0.95, 0.07, 0.035), 40, stone_deep)
    pal.lathe(bm, pal.rounded_profile(0.86, 0.11, 0.045), 40, stone)
    flat = Vector((1.0, 1.0, 0.35))
    faces = pal.torus(bm, 0.62, 0.05, (0, 0, 0), 48, 8, ring_index)
    bmesh.ops.scale(bm, vec=flat, verts=_verts(faces))
    bmesh.ops.translate(bm, vec=Vector((0, 0, 0.11)), verts=_verts(faces))


def build_checkpoint_pad():
    """チェックポイント: 丸い台に若葉の光る輪、中央に四つ葉、奥に小さな灯り。"""
    base.reset_scene()
    stone = mat("PadStone", pal.STONE, 0.85)
    stone_deep = mat("PadStoneDeep", pal.STONE_DEEP, 0.9)
    glow = mat("PadGlow", pal.LEAF_LIGHT, 0.4, emission=pal.LEAF_LIGHT, strength=1.1)
    leaf = mat("PadLeaf", pal.LEAF, 0.7)
    wood = mat("Wood", pal.WOOD, 0.75)
    wood_dark = mat("WoodDark", pal.WOOD_DARK, 0.75)

    def build(bm):
        _pad(bm, 2)
        for k in range(4):
            a = math.tau * k / 4 + math.pi / 4
            faces = pal.ellipsoid(bm, 0.16, (0, 0, 0), (1.0, 0.62, 0.12), (16, 8), 3)
            verts = _verts(faces)
            bmesh.ops.translate(bm, vec=Vector((0.15, 0, 0)), verts=verts)
            bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=rot(math.degrees(a), "Z"))
            bmesh.ops.translate(bm, vec=Vector((0, 0, 0.115)), verts=verts)
        # 奥（+Y。Godot では -Z ＝北。出現地点は南にあることが多い）の灯り
        post = Vector((0.0, 0.74, 0.0))
        pal.capsule(bm, 0.045, post + Vector((0, 0, 0.08)), post + Vector((0, 0, 0.92)), 12, 4)
        pal.capsule(bm, 0.025, post + Vector((0, 0, 0.9)), post + Vector((0, -0.16, 0.9)), 8, 4)
        lamp = post + Vector((0, -0.17, 0.74))
        pal.rounded_box(bm, (0.16, 0.16, 0.03), lamp + Vector((0, 0, 0.12)), 0.012, 2, 5)
        pal.rounded_box(bm, (0.14, 0.14, 0.03), lamp + Vector((0, 0, -0.1)), 0.012, 2, 5)
        pal.ellipsoid(bm, 0.07, lamp, (1, 1, 1.25), (16, 10), 2)

    obj = part("CheckpointPad", [stone, stone_deep, glow, leaf, wood, wood_dark], build)
    export("checkpoint_pad", "CheckpointPadRoot", [obj])


def build_entrance_gate():
    """ハブの入口（と帰り道）: 丸い台に空色の輪、木の丸い門と、何も書いていない吊り札。
    文字はゲームが札の上に浮かべる（世界観が決まるまで札に刻まない）。"""
    base.reset_scene()
    stone = mat("PadStone", pal.STONE, 0.85)
    stone_deep = mat("PadStoneDeep", pal.STONE_DEEP, 0.9)
    glow = mat("GateGlow", pal.SKY, 0.4, emission=pal.SKY, strength=1.1)
    wood = mat("Wood", pal.WOOD_LIGHT, 0.75)
    wood_dark = mat("WoodDark", pal.WOOD, 0.75)
    accent = mat("GateAccent", pal.SKY_DEEP, 0.7)
    leaf = mat("Leaf", pal.LEAF, 0.75)

    def build(bm):
        _pad(bm, 2)
        span, post_h = 0.98, 1.55
        for sx in (-1, 1):
            pal.lathe(bm, pal.rounded_profile(0.14, 0.16, 0.05), 18, 4, (sx * span, 0, 0.05))
            pal.capsule(bm, 0.075, (sx * span, 0, 0.1), (sx * span, 0, post_h + 0.05), 16, 3)
            pal.torus(bm, 0.078, 0.022, (sx * span, 0, 0.28), 16, 6, 5)
        arch = pal.torus(bm, span, 0.075, (0, 0, 0), 28, 12, 3, arc=math.pi)
        verts = _verts(arch)
        bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=rot(90, "X"))
        bmesh.ops.scale(bm, vec=Vector((1.0, 1.0, 0.55)), verts=verts)
        bmesh.ops.translate(bm, vec=Vector((0, 0, post_h)), verts=verts)
        pal.ellipsoid(bm, 0.09, (0, 0, post_h + span * 0.55 + 0.04), (1, 1, 1), (16, 10), 5)
        # 吊り札
        board_z = post_h + 0.05
        for sx in (-1, 1):
            pal.capsule(bm, 0.012, (sx * 0.26, 0, board_z + 0.1), (sx * 0.26, 0, post_h + 0.5), 6, 4)
        pal.rounded_box(bm, (0.66, 0.06, 0.26), (0, 0, board_z), 0.03, 3, 3)
        # 門に絡む小さな葉
        for k, t in enumerate((0.18, 0.32, 0.68, 0.82)):
            a = math.pi * t
            at = Vector((math.cos(a) * span, 0.06, post_h + math.sin(a) * span * 0.55))
            faces = pal.ellipsoid(bm, 0.07, (0, 0, 0), (1.0, 0.35, 0.6), (12, 8), 6)
            lv = _verts(faces)
            bmesh.ops.rotate(bm, verts=lv, cent=(0, 0, 0), matrix=rot(40 + k * 50, "Y"))
            bmesh.ops.translate(bm, vec=at, verts=lv)

    obj = part("EntranceGate", [stone, stone_deep, glow, wood, wood_dark, accent, leaf], build)
    export("entrance_gate", "EntranceGateRoot", [obj])


# --- 器（世界に落ちている物） -------------------------------------------------------


def _coin(bm, radius, thickness, rim_index, face_index):
    """±Y を向いた丸いメダル。縁は太く丸く、面は少しくぼむ。"""
    t = thickness / 2
    profile = [(0.0, -t + 0.012), (radius - 0.06, -t + 0.012), (radius - 0.045, -t),
               (radius - 0.012, -t + 0.004), (radius, -t + 0.02), (radius + 0.004, 0.0),
               (radius, t - 0.02), (radius - 0.012, t - 0.004), (radius - 0.045, t),
               (radius - 0.06, t - 0.012), (0.0, t - 0.012)]
    faces = pal.lathe(bm, profile, 48, rim_index, matrix=rot(-90, "X"))
    for f in faces:
        n = f.normal
        if abs(n.y) > 0.97 and Vector(f.calc_center_median()).length < radius - 0.055:
            f.material_index = face_index
    return faces


def build_vessel_medal():
    """能力の器: はちみつ色のメダル。"""
    base.reset_scene()
    rim = mat("Rim", pal.HONEY_DEEP, 0.4, metallic=0.3)
    face = mat("Face", pal.HONEY, 0.5, metallic=0.15)

    def build(bm):
        _coin(bm, 0.27, 0.08, 0, 1)

    export("vessel_medal", "VesselMedal", [part("Medal", [rim, face], build, smooth=40)])


def build_ban_medal():
    """禁止の器: くすんだ灰のメダルに、赤い輪と斜線（両面）。色だけに頼らず形でも禁止と分かる。"""
    base.reset_scene()
    rim = mat("Rim", pal.PEWTER_DEEP, 0.5, metallic=0.2)
    face = mat("Face", pal.PEWTER, 0.6)
    red = mat("BanRed", pal.BAN, 0.5, emission=pal.BAN, strength=0.25)

    def build(bm):
        _coin(bm, 0.27, 0.08, 0, 1)
        for side in (1, -1):
            y = side * 0.036
            faces = pal.torus(bm, 0.175, 0.022, (0, 0, 0), 40, 8, 2, matrix=rot(-90, "X"))
            bmesh.ops.scale(bm, vec=Vector((1, 0.6, 1)), verts=_verts(faces))
            bmesh.ops.translate(bm, vec=Vector((0, y, 0)), verts=_verts(faces))
            bar = pal.capsule(bm, 0.02, (-0.12, 0, -0.12), (0.12, 0, 0.12), 10, 2)
            bmesh.ops.scale(bm, vec=Vector((1, 0.6, 1)), verts=_verts(bar))
            bmesh.ops.translate(bm, vec=Vector((0, y, 0)), verts=_verts(bar))

    export("ban_medal", "BanMedal", [part("Medal", [rim, face, red], build, smooth=40)])


# --- 装備・ダッシュ ----------------------------------------------------------------


def build_jump_boots():
    """ジャンプブーツ（高跳び）: 夕日色の丸いブーツ、ふかふかの厚い底、すねに山形の印。"""
    base.reset_scene()
    leather = mat("Leather", pal.SUN, 0.75)
    sole = mat("Sole", pal.CREAM, 0.9)
    cuff = mat("Cuff", pal.HONEY, 0.7)
    mark = mat("Mark", pal.CREAM, 0.8)

    def boot(bm, x, angle):
        faces = []
        faces += pal.lathe(bm, pal.rounded_profile(0.11, 0.07, 0.034), 24, 1)  # 底（かかと側）
        faces += pal.lathe(bm, pal.rounded_profile(0.1, 0.07, 0.034), 24, 1, (0, 0.13, 0))  # つま先
        faces += pal.rounded_box(bm, (0.2, 0.14, 0.07), (0, 0.065, 0.035), 0.033, 3, 1)
        faces += pal.ellipsoid(bm, 0.1, (0, 0.11, 0.1), (0.95, 1.1, 0.7), (18, 10), 0)
        faces += pal.capsule(bm, 0.088, (0, 0, 0.07), (0, -0.01, 0.3), 18, 0)
        faces += pal.torus(bm, 0.088, 0.03, (0, -0.01, 0.3), 18, 8, 2)
        for k in range(2):
            z = 0.15 + k * 0.06
            pts = [(-0.045, z), (0.0, z + 0.035), (0.045, z), (0.045, z + 0.02), (0.0, z + 0.055),
                   (-0.045, z + 0.02)]
            chevron = pal.extrude_outline(bm, pts, 0.014, 0.0, 3, 0.003, matrix=rot(90, "X"))
            bmesh.ops.translate(bm, vec=Vector((0, 0.094, 0)), verts=_verts(chevron))
            faces += chevron
        verts = _verts(faces)
        bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=rot(angle, "Z"))
        bmesh.ops.translate(bm, vec=Vector((x, 0, 0)), verts=verts)

    def build(bm):
        boot(bm, -0.13, 8)
        boot(bm, 0.13, -8)

    export("jump_boots", "JumpBoots", [part("Boots", [leather, sole, cuff, mark], build)])


def build_climbing_gloves():
    """クライミンググローブ（登る）: 革の手袋に若葉の袖口、手のひらに滑り止めの当て布。"""
    base.reset_scene()
    leather = mat("Leather", pal.WOOD, 0.75)
    cuff = mat("Cuff", pal.LEAF, 0.8)
    grip = mat("Grip", "#a8784d", 0.95)

    def glove(bm, sx):
        faces = []
        faces += pal.ellipsoid(bm, 0.11, (0, 0, 0.2), (1.0, 0.55, 1.2), (20, 12), 0)
        faces += pal.capsule(bm, 0.038, (sx * 0.085, 0.0, 0.16), (sx * 0.14, 0.0, 0.25), 12, 0)
        faces += pal.capsule(bm, 0.075, (0, 0, 0.02), (0, 0, 0.12), 18, 1)
        faces += pal.torus(bm, 0.075, 0.022, (0, 0, 0.12), 18, 6, 1)
        # 手のひら（-Y）の滑り止め
        faces += pal.ellipsoid(bm, 0.075, (0, -0.05, 0.2), (1.0, 0.3, 1.15), (16, 10), 2)
        verts = _verts(faces)
        bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=rot(sx * -14, "Y"))
        bmesh.ops.translate(bm, vec=Vector((sx * 0.13, 0, 0)), verts=verts)

    def build(bm):
        glove(bm, -1)
        glove(bm, 1)

    export("climbing_gloves", "ClimbingGloves", [part("Gloves", [leather, cuff, grip], build)])


def build_dash_feather():
    """ダッシュ: 空色の大きな羽根と、後ろへ流れる風の筋。"""
    base.reset_scene()
    vane = mat("Vane", pal.SKY, 0.75)
    vane_deep = mat("VaneDeep", pal.SKY_DEEP, 0.75)
    quill = mat("Quill", pal.CREAM, 0.7)
    wind = mat("Wind", "#d8eefa", 0.6, emission="#d8eefa", strength=0.4)

    def build(bm):
        faces = []
        faces += pal.ellipsoid(bm, 0.2, (0, 0, 0.3), (0.42, 0.1, 1.0), (24, 12), 0)
        faces += pal.ellipsoid(bm, 0.12, (0.012, 0.0, 0.42), (0.36, 0.12, 0.7), (18, 10), 1)
        faces += pal.capsule(bm, 0.014, (0, 0, 0.04), (0, 0, 0.5), 8, 2)
        verts = _verts(faces)
        bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0.25), matrix=rot(-28, "Y"))
        for k, (z, length) in enumerate(((0.2, 0.22), (0.32, 0.3), (0.44, 0.18))):
            x0 = -0.16 - k * 0.02
            pal.capsule(bm, 0.016, (x0, 0.0, z), (x0 - length, 0.0, z - 0.04), 8, 3)

    export("dash_feather", "DashFeather", [part("Feather", [vane, vane_deep, quill, wind], build)])


# --- 生き物の巣 ----------------------------------------------------------------------


def build_creature_nest():
    """生き物の巣（2026-11-21 本人「巣がどこかもわかりにくい」。docs/adr/0019）: 小枝を編んだ丸い巣に、
    干し草の寝床と若葉を 3 枚。UI が無くても「動物のおうち」と読めるようにする。
    直径 1 m・高さ約 0.3 m で作り、ゲームが巣の箱の大きさに合わせて広げる。見た目だけ（当たり判定なし）なので、
    生き物はふちをまたいで中へ入れる。原点は足もとの真ん中。"""
    import random

    base.reset_scene()
    twig = mat("Twig", pal.WOOD, 0.9)
    twig_dark = mat("TwigDark", pal.WOOD_DARK, 0.9)
    twig_light = mat("TwigLight", pal.WOOD_LIGHT, 0.85)
    straw = mat("Straw", pal.SUN_SOFT, 0.95)
    leaf = mat("Leaf", pal.LEAF, 0.8)
    rng = random.Random(19)

    def build(bm):
        # ふち: ずんぐりした輪（編んだ小枝の芯。濃い木の色）と、底の浅い皿
        pal.torus(bm, 0.4, 0.075, (0, 0, 0.11), 40, 12, 1)
        pal.ellipsoid(bm, 0.44, (0, 0, 0.04), (1.0, 1.0, 0.1), (32, 8), 1)
        # 干し草の寝床（ふちより少し低い、ふっくらした丸）
        pal.ellipsoid(bm, 0.33, (0, 0, 0.09), (1.0, 1.0, 0.22), (28, 10), 3)

        # 編んだ小枝: 芯の表面を、ふちに沿って斜めに巻く（芯の断面の角度 t を進めながら。3 色を混ぜる）
        def on_rim(a, t, lift=0.0):
            reach = 0.4 + (0.088 + lift) * math.cos(t)
            return (math.cos(a) * reach, math.sin(a) * reach, 0.11 + (0.088 + lift) * math.sin(t))

        count = 64
        for k in range(count):
            a = math.tau * k / count + rng.uniform(-0.03, 0.03)
            t = rng.uniform(-1.2, 2.6)  # 外側・上・内側の上のほう（下は地面に隠れる）
            span = rng.uniform(0.28, 0.4)
            turn = rng.choice((-1.0, 1.0)) * rng.uniform(0.3, 0.6)
            radius = rng.uniform(0.014, 0.02)
            index = rng.choice((0, 0, 0, 2))
            pal.capsule(bm, radius, on_rim(a, t, radius * 0.5),
                        on_rim(a + span, t + turn, radius * 0.5), 6, index)
        # はみ出した小枝を数本（手作りらしさ）
        for k in range(7):
            a = math.tau * k / 7 + 0.3
            r0, r1 = 0.42, 0.56
            pal.capsule(bm, 0.014, (math.cos(a) * r0, math.sin(a) * r0, 0.16),
                        (math.cos(a + 0.25) * r1, math.sin(a + 0.25) * r1, 0.2), 6, 1)
        # 若葉 3 枚（ふちに差してある）
        for k, a in enumerate((0.6, 2.5, 4.4)):
            r = 0.46
            faces = pal.ellipsoid(bm, 0.09, (0, 0, 0), (0.45, 1.0, 0.08), (12, 6), 4)
            verts = _verts(faces)
            bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=rot(25 + k * 8, "X"))
            bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=rot(math.degrees(a) + 90, "Z"))
            bmesh.ops.translate(bm, verts=verts, vec=(math.cos(a) * r, math.sin(a) * r, 0.22))

    export("creature_nest", "CreatureNest", [part("Nest", [twig, twig_dark, twig_light, straw, leaf],
                                                   build)])


BUILDERS = {
    "goal": lambda: (build_goal_flag(), build_goal_corner()),
    "checkpoint": build_checkpoint_pad,
    "entrance": build_entrance_gate,
    "medal": lambda: (build_vessel_medal(), build_ban_medal()),
    "equipment": lambda: (build_jump_boots(), build_climbing_gloves(), build_dash_feather()),
    "nest": build_creature_nest,
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    for name in argv or list(BUILDERS):
        BUILDERS[name]()


if __name__ == "__main__":
    main()
