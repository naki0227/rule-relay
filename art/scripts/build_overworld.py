"""広場（オーバーワールド）のモデル: ワープの門（ポータル）と、クリアで増える建物 6 種を作る。

    blender -b --factory-startup --python art/scripts/build_overworld.py              # 全部
    blender -b --factory-startup --python art/scripts/build_overworld.py -- portal    # 一部（BUILDERS）

方針（docs/art-direction.md・docs/adr/0013）:
- ゆるふわで温かい箱庭。丸い形の部品（palette.py）だけで作り、色は palette.py の定数から取る。
- 原点は足もと、正面は +Y（Godot の -Z）。当たり判定はゲーム側（建物は無し。見た目だけ）。
- ポータル: 石の台・木と石のアーチ・中の渦（Swirl）・てっぺんのクリアの印（ClearedMark）。
  ゲーム側（OverworldPortal）が、鍵のかかった門は渦を暗く、クリア済みは印を出す。渦は「swirl」の
  アニメーション（オブジェクトの回転）で回る。
- 風車の羽根（Sails）は「spin」のアニメーションで回る。動く部分は、コードで回さずアニメーションにする
  （2026-11-21 本人の指示）。
- 特定の作品の建物に寄せない。屋根・窓・扉の形は一般的な丸い小屋のもの。
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


def part(name, mats, build, smooth=55):
    bm = bmesh.new()
    build(bm)
    return base.mesh_object(name, bm, mats, smooth_angle=smooth)


def _verts(faces):
    return list({v for f in faces for v in f.verts})


def _root(name, children):
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    for obj in children:
        if obj.parent is None:
            obj.parent = root
    return root


def spin(obj, name, frames, axis_index, turns=1.0):
    """オブジェクトを軸 axis_index（0=X, 1=Y, 2=Z）まわりに一定の速さで回すアクション（NLA に積む）。"""
    obj.rotation_mode = "XYZ"
    obj.animation_data_create()
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    obj.animation_data.action = act
    start = list(obj.rotation_euler)
    obj.keyframe_insert("rotation_euler", frame=1)
    end = list(start)
    end[axis_index] += math.tau * turns
    obj.rotation_euler = end
    obj.keyframe_insert("rotation_euler", frame=frames + 1)
    for curve in rigmod._curves(act):
        for point in curve.keyframe_points:
            point.interpolation = "LINEAR"
    obj.rotation_euler = start
    track = obj.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 1, act)
    track.mute = True
    obj.animation_data.action = None


# --- ポータル ---------------------------------------------------------------------


def build_portal():
    """ワープの門: 丸い石の台、葉の絡んだアーチ、中で回る空色の渦、てっぺんにクリアの印。"""
    base.reset_scene()
    stone = mat("PortalStone", pal.STONE, 0.85)
    stone_deep = mat("PortalStoneDeep", pal.STONE_DEEP, 0.9)
    wood = mat("Wood", pal.WOOD, 0.75)
    leaf = mat("Leaf", pal.LEAF, 0.75)
    lamp = mat("Lamp", pal.LAMP, 0.4, emission=pal.LAMP, strength=1.6)
    swirl_deep = mat("SwirlDeep", pal.SKY_DEEP, 0.4, emission=pal.SKY_DEEP, strength=1.2)
    swirl_light = mat("SwirlLight", "#d6eefa", 0.3, emission="#d6eefa", strength=1.6)
    honey = mat("Mark", pal.HONEY, 0.4, emission=pal.HONEY, strength=0.8)
    ring_glow = mat("PortalGlow", pal.SKY, 0.4, emission=pal.SKY, strength=1.0)
    mats = [stone, stone_deep, wood, leaf, lamp, swirl_deep, swirl_light, honey, ring_glow]
    ST, SD, WD, LF, LA, SW, SL, MK, RG = range(9)
    span, post_h, depth = 1.05, 1.5, -0.55

    def arch(bm):
        pal.lathe(bm, pal.rounded_profile(1.15, 0.16, 0.06), 36, SD)
        pal.lathe(bm, pal.rounded_profile(1.0, 0.08, 0.03, bottom=0.12), 36, ST)
        pal.torus(bm, 0.93, 0.03, (0, 0, 0.2), 40, 8, RG)
        for sx in (-1, 1):
            # 石を積んだ柱（下ほど太い）
            for k, (r, h) in enumerate(((0.22, 0.34), (0.19, 0.34), (0.17, 0.34), (0.16, 0.36))):
                z = 0.16 + k * 0.34
                pal.lathe(bm, pal.rounded_profile(r, h - 0.02, 0.07, bottom=z), 18,
                          ST if k % 2 == 0 else SD, (sx * span, depth, 0))
            pal.ellipsoid(bm, 0.09, (sx * span, depth + 0.16, 1.2), (1, 1, 1.2), (14, 10), LA)
        # 半円のアーチ（石の輪＋木の縁）
        ring = pal.torus(bm, span, 0.16, (0, 0, 0), 36, 12, ST, arc=math.pi)
        rv = _verts(ring)
        bmesh.ops.rotate(bm, verts=rv, cent=(0, 0, 0), matrix=rot(90, "X"))
        bmesh.ops.translate(bm, vec=Vector((0, depth, post_h)), verts=rv)
        trim = pal.torus(bm, span - 0.17, 0.045, (0, 0, 0), 36, 8, WD, arc=math.pi)
        tv = _verts(trim)
        bmesh.ops.rotate(bm, verts=tv, cent=(0, 0, 0), matrix=rot(90, "X"))
        bmesh.ops.translate(bm, vec=Vector((0, depth + 0.05, post_h)), verts=tv)
        # アーチに絡む葉
        for k in range(9):
            a = math.pi * (0.08 + 0.84 * k / 8)
            at = Vector((math.cos(a) * (span + 0.08), depth + 0.12, post_h + math.sin(a) * (span + 0.08)))
            faces = pal.ellipsoid(bm, 0.09 if k % 2 else 0.07, (0, 0, 0), (1.0, 0.4, 0.62), (12, 8), LF)
            lv = _verts(faces)
            bmesh.ops.rotate(bm, verts=lv, cent=(0, 0, 0), matrix=rot(30 + k * 41, "Y"))
            bmesh.ops.translate(bm, vec=at, verts=lv)

    def swirl(bm):
        # 渦: 奥の円盤と、手前に重ねた細い腕（回して渦に見せる）。原点は渦の中心
        disc = pal.ellipsoid(bm, span - 0.17, (0, 0, 0), (1.0, 1.0, 0.04), (36, 8), SW)
        bmesh.ops.rotate(bm, verts=_verts(disc), cent=(0, 0, 0), matrix=rot(90, "X"))
        for k in range(3):
            arm = pal.torus(bm, 0.18 + 0.2 * k, 0.035, (0, 0, 0), 24, 6, SL, arc=math.radians(200))
            av = _verts(arm)
            bmesh.ops.rotate(bm, verts=av, cent=(0, 0, 0), matrix=rot(k * 130, "Z"))
            bmesh.ops.rotate(bm, verts=av, cent=(0, 0, 0), matrix=rot(90, "X"))
            bmesh.ops.translate(bm, vec=Vector((0, 0.05, 0)), verts=av)
        pal.ellipsoid(bm, 0.12, (0, 0.06, 0), (1, 0.4, 1), (14, 8), SL)

    def mark(bm):
        # クリアの印: 5 枚の花びらの金色の花（てっぺんの上）
        for k in range(5):
            a = math.tau * k / 5 + math.pi / 2
            faces = pal.ellipsoid(bm, 0.11, (0, 0, 0), (1.0, 0.35, 0.6), (12, 8), MK)
            fv = _verts(faces)
            bmesh.ops.translate(bm, vec=Vector((0, 0, 0.12)), verts=fv)
            bmesh.ops.rotate(bm, verts=fv, cent=(0, 0, 0), matrix=rot(math.degrees(a) - 90, "Y"))
        pal.ellipsoid(bm, 0.07, (0, 0.03, 0), (1, 0.6, 1), (12, 8), LA)

    arch_obj = part("PortalArch", mats, arch)
    swirl_obj = part("Swirl", mats, swirl)
    swirl_obj.location = (0, depth + 0.02, post_h - 0.05)
    # 渦は門の中で縦に立つ。円盤の面は XZ なので、Y 軸まわりに回すと渦巻いて見える
    mark_obj = part("ClearedMark", mats, mark)
    mark_obj.location = (0, depth, post_h + span + 0.38)
    spin(swirl_obj, "swirl", 72, 1, -1.0)
    root = _root("PortalRoot", [arch_obj, swirl_obj, mark_obj])
    rigmod.save_and_export_rigged("portal_arch", [root, arch_obj, swirl_obj, mark_obj])


# --- 建物 -------------------------------------------------------------------------


def _export_static(file_name, root_name, build, mats, smooth=55):
    base.reset_scene()
    materials = [m() for m in mats]
    obj = part(root_name, materials, build, smooth)
    root = _root(root_name + "Root", [obj])
    base.save_and_export(file_name, [root, obj])


def _gable_roof(bm, width, depth, base_z, height, overhang, mat_index, ridge_index):
    """丸みのある切妻屋根（2 枚の厚い板と棟）。"""
    half = width / 2 + overhang
    slope = math.atan2(height, half)
    length = math.hypot(half, height) + 0.05
    for sx in (-1, 1):
        m = rot(sx * math.degrees(slope), "Y")
        center = (sx * half / 2, 0, base_z + height / 2)
        pal.rounded_box(bm, (length, depth + overhang * 2, 0.14), center, 0.06, 3, mat_index, matrix=m)
    pal.capsule(bm, 0.09, (0, -depth / 2 - overhang, base_z + height + 0.03),
                (0, depth / 2 + overhang, base_z + height + 0.03), 14, ridge_index)


def build_house():
    """丸い小屋: 生成りの壁、夕日色の屋根、丸い窓の灯り、木の扉、煙突。"""

    def build(bm):
        pal.rounded_box(bm, (2.2, 1.8, 0.25), (0, 0, 0.12), 0.08, 3, 4)
        pal.rounded_box(bm, (2.0, 1.6, 1.35), (0, 0, 0.9), 0.14, 4, 0)
        _gable_roof(bm, 2.0, 1.6, 1.5, 0.85, 0.22, 1, 2)
        pal.rounded_box(bm, (0.52, 0.12, 0.9), (0.35, 0.8, 0.62), 0.12, 4, 3)
        pal.ellipsoid(bm, 0.04, (0.52, 0.87, 0.62), (1, 1, 1), (8, 6), 6)
        for x in (-0.5,):
            pal.torus(bm, 0.22, 0.04, (x, 0.82, 1.0), 24, 8, 3, matrix=rot(90, "X"))
            pal.ellipsoid(bm, 0.2, (x, 0.8, 1.0), (1, 0.15, 1), (20, 8), 5)
        for y in (-0.35, 0.35):
            pal.torus(bm, 0.18, 0.035, (1.02, y, 1.0), 20, 8, 3, matrix=rot(90, "Y"))
            pal.ellipsoid(bm, 0.16, (1.0, y, 1.0), (0.15, 1, 1), (16, 8), 5)
        pal.rounded_box(bm, (0.3, 0.3, 0.7), (-0.55, -0.3, 2.15), 0.06, 3, 4)
        pal.rounded_box(bm, (0.38, 0.38, 0.1), (-0.55, -0.3, 2.5), 0.04, 3, 4)
        # 扉の前の小さな花
        for x, c in ((-0.15, 7), (0.9, 7), (-0.9, 8)):
            pal.ellipsoid(bm, 0.13, (x, 0.95, 0.12), (1, 0.8, 0.7), (12, 8), 8)
            pal.ellipsoid(bm, 0.05, (x + 0.04, 1.0, 0.24), (1, 1, 0.8), (8, 6), c)

    _export_static("ow_house", "OwHouse", build, [
        lambda: mat("Wall", pal.CREAM, 0.9),
        lambda: mat("Roof", pal.SUN, 0.8),
        lambda: mat("Ridge", "#d97b3a", 0.8),
        lambda: mat("Wood", pal.WOOD, 0.75),
        lambda: mat("Stone", pal.STONE_DEEP, 0.9),
        lambda: mat("Window", pal.LAMP, 0.4, emission=pal.LAMP, strength=1.4),
        lambda: mat("Knob", pal.HONEY, 0.4),
        lambda: mat("Bloom", "#f7c6cf", 0.6),
        lambda: mat("Leaves", pal.LEAF, 0.8),
    ], smooth=50)


def build_windmill():
    """風車: 石積みの丸い塔、とんがり屋根、空色の扉。羽根（Sails）は「spin」で回る。"""
    base.reset_scene()
    stone = mat("Stone", pal.STONE, 0.85)
    stone_deep = mat("StoneDeep", pal.STONE_DEEP, 0.9)
    roof = mat("Roof", pal.WOOD_DARK, 0.75)
    wood = mat("Wood", pal.WOOD_LIGHT, 0.75)
    cloth = mat("Cloth", pal.CREAM, 0.9)
    door = mat("Door", pal.SKY_DEEP, 0.7)
    window = mat("Window", pal.LAMP, 0.4, emission=pal.LAMP, strength=1.4)
    mats = [stone, stone_deep, roof, wood, cloth, door, window]
    ST, SD, RF, WD, CL, DR, WI = range(7)

    def tower(bm):
        profile = [(0.0, 0.0), (0.95, 0.0), (1.0, 0.08), (0.92, 1.2), (0.78, 2.6), (0.72, 2.75),
                   (0.0, 2.75)]
        pal.lathe(bm, profile, 32, ST)
        for z in (0.6, 1.35, 2.1):
            r = 0.95 - z * 0.08
            pal.torus(bm, r, 0.05, (0, 0, z), 32, 8, SD)
        cap = [(0.0, 2.7), (0.9, 2.7), (0.92, 2.78), (0.6, 3.25), (0.25, 3.55), (0.0, 3.65)]
        pal.lathe(bm, cap, 32, RF)
        pal.ellipsoid(bm, 0.1, (0, 0, 3.7), (1, 1, 1), (12, 8), WD)
        pal.rounded_box(bm, (0.55, 0.2, 0.9), (0, 0.9, 0.5), 0.2, 4, DR)
        pal.ellipsoid(bm, 0.16, (0, 0.82, 1.75), (1, 0.2, 1), (16, 8), WI)
        pal.capsule(bm, 0.09, (0, 0.6, 2.4), (0, 1.05, 2.4), 12, WD)

    def sails(bm):
        # 原点が軸。4 枚の羽根は XZ 面に広がり、Y 軸まわりに回る
        pal.ellipsoid(bm, 0.14, (0, 0, 0), (1, 0.8, 1), (14, 10), WD)
        for k in range(4):
            m = rot(k * 90 + 20, "Y")
            pal.rounded_box(bm, (0.08, 0.07, 1.6), (0, 0, 0.85), 0.02, 2, WD, matrix=m)
            pal.rounded_box(bm, (0.42, 0.04, 1.15), (0.22, 0.03, 1.0), 0.015, 2, CL, matrix=m)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))

    tower_obj = part("Windmill", mats, tower)
    sails_obj = part("Sails", mats, sails, smooth=None)
    sails_obj.location = (0, 1.1, 2.4)
    spin(sails_obj, "spin", 144, 1, 1.0)
    root = _root("OwWindmillRoot", [tower_obj, sails_obj])
    rigmod.save_and_export_rigged("ow_windmill", [root, tower_obj, sails_obj])


def build_fountain():
    """噴水: 丸い石の水盤、真ん中の柱と小さな皿、光る水。"""

    def build(bm):
        basin = [(0.0, 0.0), (1.1, 0.0), (1.18, 0.06), (1.2, 0.42), (1.12, 0.5), (1.02, 0.46),
                 (1.0, 0.18), (0.0, 0.18)]
        pal.lathe(bm, basin, 40, 0)
        pal.torus(bm, 1.15, 0.05, (0, 0, 0.5), 40, 8, 1)
        pal.lathe(bm, pal.rounded_profile(1.0, 0.06, 0.02, bottom=0.3), 40, 2)
        pal.lathe(bm, [(0.0, 0.3), (0.2, 0.3), (0.16, 0.9), (0.12, 1.2), (0.0, 1.2)], 24, 0)
        bowl = [(0.0, 1.05), (0.15, 1.05), (0.45, 1.18), (0.48, 1.25), (0.42, 1.27), (0.0, 1.2)]
        pal.lathe(bm, bowl, 28, 1)
        pal.lathe(bm, pal.rounded_profile(0.4, 0.04, 0.015, bottom=1.21), 28, 2)
        pal.ellipsoid(bm, 0.12, (0, 0, 1.42), (1, 1, 1.6), (16, 10), 2)
        for k in range(8):
            a = math.tau * k / 8
            pal.ellipsoid(bm, 0.05, (math.cos(a) * 0.6, math.sin(a) * 0.6, 0.42), (1, 1, 1.6), (8, 6), 2)
        for k in range(6):
            a = math.tau * k / 6 + 0.3
            pal.ellipsoid(bm, 0.14, (math.cos(a) * 1.35, math.sin(a) * 1.35, 0.1), (1, 1, 0.7),
                          (12, 8), 3)

    _export_static("ow_fountain", "OwFountain", build, [
        lambda: mat("Stone", pal.STONE, 0.85),
        lambda: mat("StoneDeep", pal.STONE_DEEP, 0.9),
        lambda: mat("Water", pal.SKY, 0.15, emission=pal.SKY, strength=0.6),
        lambda: mat("Leaves", pal.LEAF, 0.8),
    ], smooth=60)


def build_garden():
    """畑と花壇: 木の枠の土に、丸い野菜と花を並べ、小さな柵と案山子のない支柱。"""

    def build(bm):
        pal.rounded_box(bm, (2.4, 1.6, 0.3), (0, 0, 0.15), 0.08, 3, 0)
        pal.rounded_box(bm, (2.2, 1.4, 0.1), (0, 0, 0.28), 0.04, 2, 1)
        for i, x in enumerate((-0.8, -0.27, 0.27, 0.8)):
            for j, y in enumerate((-0.4, 0.0, 0.4)):
                if (i + j) % 2 == 0:
                    pal.ellipsoid(bm, 0.15, (x, y, 0.42), (1, 1, 0.85), (14, 10), 2)
                    pal.ellipsoid(bm, 0.07, (x, y, 0.56), (1, 1, 0.8), (10, 6), 3)
                else:
                    pal.capsule(bm, 0.02, (x, y, 0.32), (x, y, 0.62), 6, 2)
                    pal.ellipsoid(bm, 0.08, (x, y, 0.66), (1, 1, 0.7), (10, 6), 4 + (i % 2))
        for x in (-1.25, 1.25):
            pal.capsule(bm, 0.05, (x, 0.85, 0.0), (x, 0.85, 0.6), 10, 0)
        pal.rounded_box(bm, (2.5, 0.05, 0.08), (0, 0.85, 0.45), 0.02, 2, 0)
        pal.rounded_box(bm, (0.5, 0.05, 0.28), (0.0, 0.88, 0.5), 0.03, 2, 6)

    _export_static("ow_garden", "OwGarden", build, [
        lambda: mat("Wood", pal.WOOD, 0.75),
        lambda: mat("Soil", "#9a6b45", 0.95),
        lambda: mat("Leaves", pal.LEAF, 0.8),
        lambda: mat("LeavesLight", pal.LEAF_LIGHT, 0.8),
        lambda: mat("Bloom", "#f7c6cf", 0.6),
        lambda: mat("BloomSun", pal.SUN_SOFT, 0.6),
        lambda: mat("Sign", pal.WOOD_LIGHT, 0.75),
    ], smooth=60)


def build_lookout():
    """見晴らし台: 太い木の脚と板の台、丸い屋根、てっぺんの小旗。"""

    def build(bm):
        for x, y in ((-0.6, -0.6), (0.6, -0.6), (-0.6, 0.6), (0.6, 0.6)):
            pal.lathe(bm, pal.rounded_profile(0.16, 0.2, 0.06), 16, 3, (x, y, 0))
            pal.capsule(bm, 0.09, (x, y, 0.1), (x * 0.85, y * 0.85, 2.0), 12, 0)
        for z in (0.8,):
            pal.rounded_box(bm, (1.3, 0.06, 0.1), (0, 0.55, z), 0.03, 2, 1)
            pal.rounded_box(bm, (1.3, 0.06, 0.1), (0, -0.55, z), 0.03, 2, 1)
        pal.rounded_box(bm, (1.6, 1.6, 0.14), (0, 0, 2.0), 0.06, 3, 1)
        for x in (-0.72, 0.72):
            pal.rounded_box(bm, (0.06, 1.5, 0.08), (x, 0, 2.45), 0.03, 2, 0)
        for y in (-0.72, 0.72):
            pal.rounded_box(bm, (1.5, 0.06, 0.08), (0, y, 2.45), 0.03, 2, 0)
        for x, y in ((-0.72, -0.72), (0.72, -0.72), (-0.72, 0.72), (0.72, 0.72)):
            pal.capsule(bm, 0.05, (x, y, 2.0), (x, y, 2.95), 10, 0)
        roof = [(0.0, 2.9), (1.15, 2.9), (1.2, 2.96), (0.7, 3.35), (0.0, 3.55)]
        pal.lathe(bm, roof, 6, 2)
        pal.capsule(bm, 0.025, (0, 0, 3.5), (0, 0, 4.0), 6, 0)
        pal.rounded_box(bm, (0.35, 0.03, 0.2), (0.18, 0, 3.88), 0.02, 2, 4)
        for k in range(5):
            pal.rounded_box(bm, (0.5, 0.07, 0.06), (0.0, 0.62 - k * 0.0, 0.3 + k * 0.38), 0.02, 2, 1,
                            matrix=rot(0, "Z"))

    _export_static("ow_lookout", "OwLookout", build, [
        lambda: mat("Wood", pal.WOOD, 0.75),
        lambda: mat("WoodLight", pal.WOOD_LIGHT, 0.75),
        lambda: mat("Roof", pal.LEAF_DEEP, 0.8),
        lambda: mat("Stone", pal.STONE_DEEP, 0.9),
        lambda: mat("Flag", pal.SUN, 0.7),
    ], smooth=45)


def build_stall():
    """小さな屋台: 縞の日よけ、木のカウンター、丸い果物のかご。"""

    def build(bm):
        pal.rounded_box(bm, (1.8, 0.8, 0.85), (0, 0.1, 0.43), 0.08, 3, 0)
        pal.rounded_box(bm, (1.95, 0.95, 0.08), (0, 0.1, 0.9), 0.03, 2, 1)
        for x in (-0.85, 0.85):
            for y in (-0.3, 0.45):
                pal.capsule(bm, 0.05, (x, y, 0.85), (x, y, 1.9), 10, 1)
        for k in range(6):
            x = -0.9 + 0.3 * k + 0.15
            pal.rounded_box(bm, (0.3, 1.2, 0.08), (x, 0.12, 2.0), 0.03, 2, 2 if k % 2 == 0 else 3,
                            matrix=rot(-12, "X"))
            pal.ellipsoid(bm, 0.15, (x, 0.75, 1.88), (1, 0.6, 0.8), (12, 8), 2 if k % 2 == 0 else 3)
        for x, c in ((-0.55, 4), (0.0, 5), (0.55, 4)):
            pal.lathe(bm, [(0.0, 0.94), (0.2, 0.94), (0.24, 1.08), (0.0, 1.08)], 16, 1, (x, 0.15, 0))
            for k in range(4):
                a = math.tau * k / 4
                pal.ellipsoid(bm, 0.08, (x + math.cos(a) * 0.09, 0.15 + math.sin(a) * 0.09, 1.12),
                              (1, 1, 1), (10, 6), c)

    _export_static("ow_stall", "OwStall", build, [
        lambda: mat("Wood", pal.WOOD, 0.75),
        lambda: mat("WoodLight", pal.WOOD_LIGHT, 0.75),
        lambda: mat("Awning", pal.SUN, 0.85),
        lambda: mat("AwningLight", pal.CREAM, 0.9),
        lambda: mat("Fruit", pal.BAN, 0.6),
        lambda: mat("FruitSun", pal.HONEY, 0.6),
    ], smooth=50)


BUILDERS = {
    "portal": build_portal,
    "house": build_house,
    "windmill": build_windmill,
    "fountain": build_fountain,
    "garden": build_garden,
    "lookout": build_lookout,
    "stall": build_stall,
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    for name in argv or list(BUILDERS):
        BUILDERS[name]()


if __name__ == "__main__":
    main()
