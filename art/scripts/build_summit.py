"""ワールド 7「空の頂」の最終ステージ（7-6 頂の祭り）のお祝いの置物を作る。

    blender -b --factory-startup --python art/scripts/build_summit.py

方針（docs/art-direction.md・docs/campaign-plan.md の W7）:
- ゆるふわで温かい箱庭。丸い形の部品（palette.py）だけで作り、色は palette.py の定数から取る。
- 祭りの提灯の柱（summit_lantern）: 石の台・木の柱・横木と、横木から下がる 2 つの紙の提灯（はちみつ色と夕日色の
  ほのかな灯り）・柱のてっぺんの小さな旗。原点が足もと、見た目だけ（当たり判定・光線の遮りはゲーム側で持たない）。
- 動く物は部品ごとに作り、骨格とアクションで動かす（2026-11-21 本人の指示）: 柱（b_root）、左右の提灯
  （b_lantern_l・b_lantern_r。横木の吊り金具が関節）、旗（b_flag）の 4 本の骨。アクション「sway」で、提灯が
  互い違いにゆっくり揺れ、旗がなびく（2 秒で 1 往復。最初と最後のキーが同じ＝ループできる）。
- 骨は関節から +Z を向くので、提灯の揺れは骨のローカル X 回転（世界の X 軸まわり＝前後に振る）。
"""

import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_assets as base  # noqa: E402
import palette as pal  # noqa: E402
import rig as rigmod  # noqa: E402

POLE_TOP = 2.1
BAR_Z = 1.86
HOOK_X = 0.42


def mat(name, color, roughness=0.8, emission=None, strength=0.0):
    return base.material(name, color, roughness, 0.0, emission=emission, strength=strength)


def part(name, mats, build, smooth=55):
    bm = bmesh.new()
    build(bm)
    return base.mesh_object(name, bm, mats, smooth_angle=smooth)


def build_summit_lantern():
    """祭りの提灯の柱。"""
    base.reset_scene()
    stone = mat("Stone", pal.STONE, 0.85)
    stone_deep = mat("StoneDeep", pal.STONE_DEEP, 0.9)
    wood = mat("Wood", pal.WOOD, 0.75)
    wood_dark = mat("WoodDark", pal.WOOD_DARK, 0.75)
    paper_honey = mat("PaperHoney", pal.SUN_SOFT, 0.6, emission=pal.LAMP, strength=0.6)
    paper_sun = mat("PaperSun", pal.BLUSH, 0.6, emission=pal.LAMP, strength=0.5)
    rim = mat("Rim", pal.WOOD_DARK, 0.7)
    flag = mat("Flag", pal.SKY, 0.7)
    mats = [stone, stone_deep, wood, wood_dark, paper_honey, paper_sun, rim, flag]
    ST, SD, WD, WK, PH, PS, RM, FL = range(8)

    def pole(bm):
        pal.lathe(bm, pal.rounded_profile(0.3, 0.18, 0.06), 28, ST)
        pal.torus(bm, 0.27, 0.035, (0, 0, 0.18), 28, 8, SD)
        pal.capsule(bm, 0.05, (0, 0, 0.12), (0, 0, POLE_TOP), 14, WD)
        # 横木と、両端の吊り金具（輪）
        pal.capsule(bm, 0.035, (-HOOK_X - 0.06, 0, BAR_Z), (HOOK_X + 0.06, 0, BAR_Z), 12, WK)
        for sx in (-1, 1):
            pal.torus(bm, 0.035, 0.01, (sx * HOOK_X, 0, BAR_Z - 0.04), 12, 6, WK,
                      matrix=pal.rot(90, "X"))
        pal.ellipsoid(bm, 0.07, (0, 0, POLE_TOP + 0.03), (1, 1, 1), (14, 10), WK)

    def lantern(material_index):
        def build(bm):
            # 原点が吊り金具。紐の下に、上下の木の輪にはさまれた丸い紙の提灯
            pal.capsule(bm, 0.008, (0, 0, -0.05), (0, 0, -0.18), 6, RM)
            pal.torus(bm, 0.07, 0.014, (0, 0, -0.2), 16, 6, RM)
            pal.ellipsoid(bm, 0.16, (0, 0, -0.38), (1.0, 1.0, 1.15), (20, 14), material_index)
            pal.torus(bm, 0.07, 0.014, (0, 0, -0.57), 16, 6, RM)
            pal.capsule(bm, 0.012, (0, 0, -0.6), (0, 0, -0.68), 6, RM)
        return build

    def pennant(bm):
        # 原点が柱のてっぺんの横。三角の旗が +X へなびく
        outline = [(0.0, 0.0), (0.34, -0.08), (0.0, -0.18)]
        pal.extrude_outline(bm, outline, 0.012, -0.006, FL, bevel=0.004,
                            matrix=pal.rot(90, "X"))

    pole_obj = part("Pole", mats, pole)
    left = part("LanternL", mats, lantern(PH))
    right = part("LanternR", mats, lantern(PS))
    flag_obj = part("Flag", mats, pennant)
    left.location = (-HOOK_X, 0, BAR_Z - 0.04)
    right.location = (HOOK_X, 0, BAR_Z - 0.04)
    flag_obj.location = (0.04, 0, POLE_TOP - 0.02)
    rig = rigmod.armature("SummitLanternRig", [
        ("b_root", (0, 0, 0), None, 0.3),
        ("b_lantern_l", (-HOOK_X, 0, BAR_Z - 0.04), "b_root", 0.15),
        ("b_lantern_r", (HOOK_X, 0, BAR_Z - 0.04), "b_root", 0.15),
        ("b_flag", (0.04, 0, POLE_TOP - 0.02), "b_root", 0.15),
    ])
    rigmod.bind(pole_obj, rig, "b_root")
    rigmod.bind(left, rig, "b_lantern_l")
    rigmod.bind(right, rig, "b_lantern_r")
    rigmod.bind(flag_obj, rig, "b_flag")
    swing = 0.16
    left_keys = [(f, (v, 0.0, 0.0), None, None) for f, v in rigmod.cycle(48, [swing, 0.0, -swing, 0.0])]
    right_keys = [(f, (v, 0.0, 0.0), None, None) for f, v in rigmod.cycle(48, [-swing, 0.0, swing, 0.0])]
    flag_keys = [
        (f, (0.0, v, 0.0), None, None) for f, v in rigmod.cycle(48, [0.25, -0.1, 0.25, -0.1])
    ]
    rigmod.action(rig, "sway", 48, {
        "b_lantern_l": left_keys, "b_lantern_r": right_keys, "b_flag": flag_keys,
    })
    root = bpy.data.objects.new("SummitLantern", None)
    bpy.context.collection.objects.link(root)
    rig.parent = root
    rigmod.save_and_export_rigged("summit_lantern", [root, rig, pole_obj, left, right, flag_obj])
    print("built summit_lantern (%.2f m)" % (POLE_TOP + 0.1))


def main():
    build_summit_lantern()


if __name__ == "__main__":
    main()
