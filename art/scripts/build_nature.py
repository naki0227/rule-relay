"""自然の仕掛け（風・氷・水）と、新しい能力（重い・浮く・泳ぐ）の拾える物のモデルを作る。

    blender -b --factory-startup --python art/scripts/build_nature.py              # 全部
    blender -b --factory-startup --python art/scripts/build_nature.py -- fan       # 一部（BUILDERS）

方針（docs/art-direction.md・docs/adr/0015）:
- ゆるふわで温かい箱庭。丸い形の部品（palette.py）だけで作り、色は palette.py の定数から取る
  （氷と水の淡い水色だけ、ここで決める。ゲーム側の IceFrost・WaterVisual と同じ値）。
- 動く物は骨格とアクションで動かす（2026-11-21 本人の指示）: かざぐるま（wind_fan）は柱（b_root）と
  羽根（b_rotor）の 2 本の骨で、羽根は「spin」のアクションで回る。骨は関節から +Z を向くので、
  羽根の回転は骨のローカル Z（世界の -Y 軸＝正面の軸）まわりにする。
- 拾える物（heavy_weight・float_balloon・swim_fins）は原点が足もと、見た目だけ（当たり判定はゲーム側）。
  WorldItem が浮かべて回すので、モデル自体は動かない。
- 木の葉（wind_leaf）は風の粒（CPUParticles3D）の形。1 つのメッシュで、原点が中心。
- 氷のセル（ice_cell）は地形の 1 セル（1x1x1、中心が原点）。氷のセルを動くブロックにしたときの見た目。
"""

import math
import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_assets as base  # noqa: E402
import palette as pal  # noqa: E402
import rig as rigmod  # noqa: E402
from palette import rot  # noqa: E402

ICE = "#cfe9f5"  # 氷（地形のメッシュの色と同じ。src/game/terrain_mesher.gd）
FROST = "#f2fbff"  # 霜（src/game/gimmicks/ice_frost.gd）


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
        if obj.parent is None:
            obj.parent = root
    return root


# --- 風 ---------------------------------------------------------------------------


def build_wind_fan():
    """かざぐるまの柱: 石の台・木の柱・後ろへ伸びる風見の尾。羽根（Rotor）は 4 色の巻いた花びら。"""
    base.reset_scene()
    stone = mat("Stone", pal.STONE, 0.85)
    stone_deep = mat("StoneDeep", pal.STONE_DEEP, 0.9)
    wood = mat("Wood", pal.WOOD, 0.75)
    wood_dark = mat("WoodDark", pal.WOOD_DARK, 0.75)
    petal_sun = mat("PetalSun", pal.SUN_SOFT, 0.7)
    petal_sky = mat("PetalSky", pal.SKY, 0.7)
    petal_leaf = mat("PetalLeaf", pal.LEAF_LIGHT, 0.7)
    petal_blush = mat("PetalBlush", pal.BLUSH, 0.7)
    honey = mat("Hub", pal.HONEY, 0.4)
    mats = [stone, stone_deep, wood, wood_dark, petal_sun, petal_sky, petal_leaf, petal_blush, honey]
    ST, SD, WD, WK, P0, P1, P2, P3, HB = range(9)
    hub_z = 1.32

    def post(bm):
        pal.lathe(bm, pal.rounded_profile(0.34, 0.16, 0.06), 28, ST)
        pal.torus(bm, 0.3, 0.035, (0, 0, 0.16), 28, 8, SD)
        pal.capsule(bm, 0.055, (0, 0, 0.1), (0, 0, hub_z + 0.05), 14, WD)
        # 風見の尾（後ろ -Y へ伸びる腕と、丸い羽板）
        pal.capsule(bm, 0.03, (0, 0.02, hub_z - 0.12), (0, -0.48, hub_z - 0.12), 10, WK)
        pal.ellipsoid(bm, 0.16, (0, -0.52, hub_z - 0.08), (0.12, 1.0, 0.8), (16, 10), WD)
        pal.capsule(bm, 0.035, (0, 0.0, hub_z), (0, 0.12, hub_z), 10, WK)

    def rotor(bm):
        # 原点が軸。花びらは XZ 面に広がり、正面（+Y）を向く
        pal.ellipsoid(bm, 0.07, (0, 0.03, 0), (1, 0.8, 1), (14, 10), HB)
        for k, color in enumerate((P0, P1, P2, P3)):
            m = rot(k * 90, "Y")
            # 外へ伸びる丸い花びら（少しひねって、風を受ける形）
            faces = pal.ellipsoid(bm, 0.2, (0.0, 0.0, 0.24), (0.55, 0.08, 1.0), (18, 10), color)
            verts = list({v for f in faces for v in f.verts})
            bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0.24), matrix=rot(28, "Z"))
            bmesh.ops.transform(bm, matrix=m, verts=verts)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))

    post_obj = part("Post", mats, post)
    rotor_obj = part("Rotor", mats, rotor)
    rotor_obj.location = (0, 0.14, hub_z)
    rig = rigmod.armature("WindFanRig", [
        ("b_root", (0, 0, 0), None, 0.3),
        ("b_rotor", (0, 0.14, hub_z), "b_root", 0.2),
    ])
    rigmod.bind(post_obj, rig, "b_root")
    rigmod.bind(rotor_obj, rig, "b_rotor")
    # 1 秒で 1 回り（ゲームが風の強さに合わせて再生の速さを変える）。等速にするため線形にする
    turn = [(1 + 6 * i, (0.0, 0.0, -math.tau * i / 4), None, None) for i in range(5)]
    act = rigmod.action(rig, "spin", 24, {"b_rotor": turn})
    for curve in rigmod._curves(act):
        for point in curve.keyframe_points:
            point.interpolation = "LINEAR"
    root = group("WindFan", [rig])
    rigmod.save_and_export_rigged("wind_fan", [root, rig, post_obj, rotor_obj])


def build_wind_leaf():
    """風に流れる木の葉（若葉色、真ん中に葉脈）。原点が中心、長さ約 0.16 m。"""
    base.reset_scene()
    leaf = mat("Leaf", pal.LEAF_LIGHT, 0.8)
    vein = mat("Vein", pal.LEAF_DEEP, 0.8)

    def build(bm):
        outline = []
        for i in range(16):
            t = i / 16 * math.tau
            outline.append((math.cos(t) * 0.08, math.sin(t) * 0.045 * (1.0 + 0.3 * math.cos(t))))
        pal.extrude_outline(bm, outline, 0.008, -0.004, 0, bevel=0.002)
        pal.capsule(bm, 0.006, (-0.09, 0, 0.004), (0.07, 0, 0.004), 6, 1)

    obj = part("WindLeaf", [leaf, vein], build)
    base.save_and_export("wind_leaf", [obj])


# --- 氷 ---------------------------------------------------------------------------


def build_ice_cell():
    """氷のセル: 角の丸い淡い水色の塊に、上面の霜の板と、中に光る小さな筋。"""
    base.reset_scene()
    ice = mat("Ice", ICE, 0.12)
    frost = mat("Frost", FROST, 0.3)
    glint = mat("Glint", "#ffffff", 0.1, emission="#ffffff", strength=0.4)

    def build(bm):
        pal.rounded_box(bm, (0.985, 0.985, 0.985), (0, 0, 0), 0.1, 3, 0)
        pal.rounded_box(bm, (0.86, 0.86, 0.05), (0, 0, 0.49), 0.02, 2, 1)
        for x, y, dx in ((-0.2, 0.15, 0.07), (0.22, -0.18, -0.06)):
            pal.capsule(bm, 0.012, (x - dx, y - 0.05, 0.515), (x + dx, y + 0.05, 0.515), 6, 2)

    obj = part("IceCell", [ice, frost, glint], build, smooth=40)
    base.save_and_export("ice_cell", [obj])


# --- 拾える物（新しい能力） ------------------------------------------------------


def build_heavy_weight():
    """重い: 取っ手の付いた丸い石のおもりと、はちみつ色の帯。"""
    base.reset_scene()
    stone = mat("Stone", pal.STONE_DEEP, 0.9)
    band = mat("Band", pal.HONEY, 0.5)
    handle = mat("Handle", pal.WOOD_DARK, 0.75)

    def build(bm):
        pal.ellipsoid(bm, 0.22, (0, 0, 0.2), (1, 1, 0.85), (24, 14), 0)
        pal.torus(bm, 0.205, 0.03, (0, 0, 0.2), 28, 8, 1)
        pal.torus(bm, 0.11, 0.035, (0, 0, 0.42), 24, 8, 2, matrix=rot(90, "X"))
        pal.lathe(bm, pal.rounded_profile(0.12, 0.04, 0.015), 20, 0)

    obj = part("HeavyWeight", [stone, band, handle], build)
    base.save_and_export("heavy_weight", [group("HeavyWeightRoot", [obj]), obj])


def build_float_balloon():
    """浮く: 空色の風船（つやの光）と結び目、生成りの糸。"""
    base.reset_scene()
    skin = mat("Balloon", pal.SKY, 0.35)
    shine = mat("Shine", "#ffffff", 0.2, emission="#ffffff", strength=0.3)
    string = mat("String", pal.CREAM, 0.9)

    def build(bm):
        pal.ellipsoid(bm, 0.18, (0, 0, 0.48), (1, 1, 1.15), (24, 14), 0)
        pal.lathe(bm, [(0.0, 0.25), (0.035, 0.27), (0.02, 0.29), (0.0, 0.3)], 12, 0)
        pal.ellipsoid(bm, 0.04, (-0.07, 0.12, 0.58), (1, 0.4, 1.6), (10, 8), 1)
        prev = (0.0, 0.0, 0.26)
        for i in range(1, 5):
            z = 0.26 - i * 0.065
            cur = (0.025 * math.sin(i * 1.7), 0.0, z)
            pal.capsule(bm, 0.008, prev, cur, 6, 2)
            prev = cur

    obj = part("FloatBalloon", [skin, shine, string], build)
    base.save_and_export("float_balloon", [group("FloatBalloonRoot", [obj]), obj])


def build_swim_fins():
    """泳ぐ: 空色の足ひれ 2 つ（丸い足入れと、先の広がった羽根）と、生成りのベルト。"""
    base.reset_scene()
    fin = mat("Fin", pal.SKY_DEEP, 0.6)
    pocket = mat("Pocket", pal.SKY, 0.6)
    strap = mat("Strap", pal.CREAM, 0.85)

    def one(bm, sx, angle):
        m = rot(angle, "Z")
        outline = [(-0.07, 0.0), (0.07, 0.0), (0.11, 0.26), (0.05, 0.3), (0.0, 0.27), (-0.05, 0.3),
                   (-0.11, 0.26)]
        faces = pal.extrude_outline(bm, outline, 0.025, 0.02, 0, bevel=0.008)
        faces += pal.ellipsoid(bm, 0.075, (0, 0.0, 0.06), (1.0, 1.35, 0.7), (16, 10), 1)
        faces += pal.torus(bm, 0.068, 0.014, (0, -0.06, 0.07), 16, 6, 2, matrix=rot(80, "X"))
        verts = list({v for f in faces for v in f.verts})
        bmesh.ops.transform(bm, matrix=m, verts=verts)
        bmesh.ops.translate(bm, vec=(sx * 0.11, 0.0, 0.0), verts=verts)

    def build(bm):
        one(bm, -1, 10)
        one(bm, 1, -10)

    obj = part("SwimFins", [fin, pocket, strap], build)
    base.save_and_export("swim_fins", [group("SwimFinsRoot", [obj]), obj])


BUILDERS = {
    "fan": build_wind_fan,
    "leaf": build_wind_leaf,
    "ice": build_ice_cell,
    "items": lambda: (build_heavy_weight(), build_float_balloon(), build_swim_fins()),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    for name in argv or list(BUILDERS):
        BUILDERS[name]()


if __name__ == "__main__":
    main()
