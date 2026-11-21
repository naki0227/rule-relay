"""スイッチの仕掛けのモデル: 重さの板・スイッチの扉・レバー・ワープの石・時の鐘の砂時計（docs/adr/0014）。

    blender -b --factory-startup --python art/scripts/build_switches.py              # 全部
    blender -b --factory-startup --python art/scripts/build_switches.py -- plate     # 一部（BUILDERS）

方針（docs/art-direction.md・docs/adr/0013・0014）:
- ゆるふわで温かい箱庭。丸い形の部品（palette.py）だけで作り、色は palette.py の定数から取る。
- 原点は足もと（セルの床の中心）、正面は +Y（Godot の -Z）。当たり判定はゲーム側（扉だけ箱を持つ）。
- 動く部分は部品ごとに作り、骨（rig.py）に重み 1.0 で結んでアクションで動かす（2026-11-21 本人の指示）。
  - 重さの板: 天板（Top）が b_top で沈む「press」。ゲームは押されている度合いで再生位置を合わせる。
  - スイッチの扉: 扉板（Gate）が b_gate で床へ沈む「open」（高さ 2 の扉。高い扉はゲームで縦に伸ばす）。
  - レバー: 柄（Handle）が b_handle で倒れる「flip」。
  - ワープの石: 浮かぶ結晶（Crystal）が b_crystal でゆれる「hover」（繰り返し）と、光って跳ねる「warp」。
  - 時の鐘の砂時計: 砂時計（Glass）が b_glass でひっくり返る「flip」。鐘の台の脇に置く。
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


def mat(name, color, roughness=0.8, emission=None, strength=0.0):
    return base.material(name, color, roughness, emission=emission, strength=strength)


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


def _rigged(file_name, rig_name, bones, parts, actions):
    """parts（{部品の名前: (オブジェクト, 骨の名前)}）を骨に結び、actions を積んで書き出す。"""
    rig = rigmod.armature(rig_name, bones)
    for obj, bone in parts.values():
        rigmod.bind(obj, rig, bone)
    for name, frames, keys in actions:
        rigmod.action(rig, name, frames, keys)
    root = group(rig_name + "Root", [rig])
    rigmod.save_and_export_rigged(file_name, [root, rig] + [o for o, _b in parts.values()])


def _move(frames, start, end):
    """1 回だけの動き（始め → 終わり）。ゲームが再生位置を合わせるので、繰り返さない。"""
    return [(1, None, start, None), (frames + 1, None, end, None)]


def _turn(frames, start, end):
    return [(1, start, None, None), (frames + 1, end, None, None)]


# --- 重さの板 -----------------------------------------------------------------------


def build_plate():
    """重さの板: 石の縁の中に、木の天板（真ん中にはちみつ色の花の印）。乗ると天板が沈む。"""
    base.reset_scene()
    mats = [
        mat("PlateStone", pal.STONE_DEEP, 0.9),
        mat("PlateWood", pal.WOOD_LIGHT, 0.75),
        mat("PlateWoodDeep", pal.WOOD, 0.8),
        mat("PlateMark", pal.HONEY, 0.45, emission=pal.HONEY, strength=0.35),
        mat("PlateLeaf", pal.LEAF, 0.8),
    ]
    SD, WL, WD, MK, LF = range(5)

    def rim(bm):
        # 床に埋めた低い石の縁（四隅を丸めた額縁）
        for sx, sy, w, d in ((0, 0.45, 0.96, 0.08), (0, -0.45, 0.96, 0.08),
                             (0.45, 0, 0.08, 0.82), (-0.45, 0, 0.08, 0.82)):
            pal.rounded_box(bm, (w, d, 0.07), (sx, sy, 0.035), 0.03, 2, SD)
        # 縁の角に小さな葉
        for sx in (-1, 1):
            for sy in (-1, 1):
                faces = pal.ellipsoid(bm, 0.06, (0, 0, 0), (1.0, 0.5, 0.35), (10, 6), LF)
                fv = list({v for f in faces for v in f.verts})
                bmesh.ops.rotate(bm, verts=fv, cent=(0, 0, 0), matrix=rot(45 * sx * sy, "Z"))
                bmesh.ops.translate(bm, vec=(sx * 0.43, sy * 0.43, 0.08), verts=fv)

    def top(bm):
        # 天板: 3 枚の板を並べ、真ん中に 5 枚の花びらの印
        for k in range(3):
            pal.rounded_box(bm, (0.26, 0.8, 0.06), ((k - 1) * 0.27, 0, 0.05), 0.025, 2,
                            WL if k != 1 else WD)
        for k in range(5):
            a = math.tau * k / 5
            pal.ellipsoid(bm, 0.07, (math.cos(a) * 0.08, math.sin(a) * 0.08, 0.085),
                          (1.0, 1.0, 0.25), (10, 6), MK)
        pal.ellipsoid(bm, 0.05, (0, 0, 0.09), (1, 1, 0.4), (10, 6), LF)

    rim_obj = part("Rim", mats, rim)
    top_obj = part("Top", mats, top)
    bones = [("b_root", (0, 0, 0), None, 0.1), ("b_top", (0, 0, 0.02), "b_root", 0.1)]
    _rigged("pressure_plate", "PlateRig", bones,
            {"Rim": (rim_obj, "b_root"), "Top": (top_obj, "b_top")},
            [("press", 12, {"b_top": _move(12, (0, 0, 0), (0, -0.05, 0))})])


# --- スイッチの扉 -------------------------------------------------------------------


def build_door():
    """スイッチの扉（幅 1・高さ 2）: 丸い木の板を石の帯でとめ、空色の丸い印。床の敷居は動かない。"""
    base.reset_scene()
    mats = [
        mat("DoorWood", pal.WOOD, 0.75),
        mat("DoorWoodLight", pal.WOOD_LIGHT, 0.75),
        mat("DoorStone", pal.STONE, 0.85),
        mat("DoorEmblem", pal.SKY, 0.4, emission=pal.SKY, strength=0.6),
        mat("DoorSill", pal.STONE_DEEP, 0.9),
    ]
    WD, WL, ST, EM, SL = range(5)

    def gate(bm):
        # 縦の板 3 枚（角を丸める）と、上下の石の帯
        for k in range(3):
            pal.rounded_box(bm, (0.3, 0.84, 1.92), ((k - 1) * 0.31, 0, 0.98), 0.06, 3,
                            WD if k != 1 else WL)
        for z in (0.35, 1.6):
            pal.rounded_box(bm, (0.98, 0.9, 0.16), (0, 0, z), 0.05, 3, ST)
        # 両面の丸い印（輪と中の点）
        for sy in (-1, 1):
            pal.torus(bm, 0.16, 0.035, (0, sy * 0.45, 1.0), 24, 8, EM, matrix=rot(90, "X"))
            pal.ellipsoid(bm, 0.06, (0, sy * 0.45, 1.0), (1, 0.4, 1), (12, 8), EM)

    def sill(bm):
        # 床の敷居（扉が沈む溝の縁）
        for sy in (-1, 1):
            pal.rounded_box(bm, (1.0, 0.07, 0.04), (0, sy * 0.47, 0.02), 0.02, 2, SL)

    gate_obj = part("Gate", mats, gate)
    sill_obj = part("Sill", mats, sill)
    bones = [("b_root", (0, 0, 0), None, 0.1), ("b_gate", (0, 0, 0.0), "b_root", 0.3)]
    _rigged("switch_door", "DoorRig", bones,
            {"Gate": (gate_obj, "b_gate"), "Sill": (sill_obj, "b_root")},
            [("open", 24, {"b_gate": _move(24, (0, 0, 0), (0, -2.0, 0))})])


# --- レバー -------------------------------------------------------------------------


def build_lever():
    """レバー: 苔の付いた石の台と、はちみつ色の握りの木の柄。F で倒すと柄が反対側へ倒れる。"""
    base.reset_scene()
    mats = [
        mat("LeverStone", pal.STONE, 0.85),
        mat("LeverStoneDeep", pal.STONE_DEEP, 0.9),
        mat("LeverWood", pal.WOOD_DARK, 0.75),
        mat("LeverKnob", pal.HONEY, 0.45),
        mat("LeverMoss", pal.LEAF, 0.85),
    ]
    ST, SD, WD, KN, MS = range(5)

    def stand(bm):
        pal.rounded_box(bm, (0.62, 0.46, 0.3), (0, 0, 0.15), 0.08, 3, ST)
        pal.rounded_box(bm, (0.5, 0.36, 0.08), (0, 0, 0.33), 0.03, 2, SD)
        pal.ellipsoid(bm, 0.14, (-0.2, 0.12, 0.3), (1.0, 0.7, 0.3), (12, 8), MS)
        # 左右の目盛り（倒した向きがわかる小さな印）
        pal.ellipsoid(bm, 0.035, (0, 0.2, 0.38), (1, 1, 0.5), (8, 6), KN)
        pal.ellipsoid(bm, 0.035, (0, -0.2, 0.38), (1, 1, 0.5), (8, 6), SD)

    def handle(bm):
        pal.capsule(bm, 0.035, (0, 0, 0.0), (0, 0, 0.52), 12, WD)
        pal.ellipsoid(bm, 0.075, (0, 0, 0.56), (1, 1, 1), (14, 10), KN)
        pal.torus(bm, 0.05, 0.018, (0, 0, 0.05), 16, 6, SD)

    stand_obj = part("Stand", mats, stand)
    handle_obj = part("Handle", mats, handle)
    handle_obj.location = (0, 0, 0.36)
    bones = [("b_root", (0, 0, 0), None, 0.1), ("b_handle", (0, 0, 0.36), "b_root", 0.4)]
    _rigged("switch_lever", "LeverRig", bones,
            {"Stand": (stand_obj, "b_root"), "Handle": (handle_obj, "b_handle")},
            [("flip", 10, {"b_handle": _turn(10, (-0.6, 0, 0), (0.6, 0, 0))})])


# --- ワープの石 ---------------------------------------------------------------------


def build_warp_stone():
    """ワープの石: 平たい丸い石に空色の輪の彫り、上に浮かぶ空色の結晶（ゆれ、移すときに光って跳ねる）。"""
    base.reset_scene()
    mats = [
        mat("WarpStone", pal.STONE, 0.85),
        mat("WarpStoneDeep", pal.STONE_DEEP, 0.9),
        mat("WarpRune", pal.SKY, 0.4, emission=pal.SKY, strength=0.9),
        mat("WarpCrystal", "#d6eefa", 0.25, emission=pal.SKY, strength=0.8),
        mat("WarpLeaf", pal.LEAF, 0.8),
    ]
    ST, SD, RN, CR, LF = range(5)

    def slab(bm):
        pal.lathe(bm, pal.rounded_profile(0.47, 0.07, 0.03), 32, SD)
        pal.lathe(bm, pal.rounded_profile(0.42, 0.05, 0.02, bottom=0.04), 32, ST)
        pal.torus(bm, 0.3, 0.022, (0, 0, 0.095), 32, 6, RN)
        for k in range(4):
            a = math.tau * k / 4 + math.pi / 4
            pal.ellipsoid(bm, 0.04, (math.cos(a) * 0.3, math.sin(a) * 0.3, 0.1), (1, 1, 0.4),
                          (8, 6), RN)
        pal.ellipsoid(bm, 0.07, (0.36, -0.22, 0.08), (1.0, 0.6, 0.35), (10, 6), LF)

    def crystal(bm):
        # 上下にとがった丸い結晶（8 角の回転体）
        profile = [(0.0, -0.16), (0.09, -0.06), (0.11, 0.0), (0.09, 0.07), (0.0, 0.2)]
        pal.lathe(bm, profile, 8, CR)

    slab_obj = part("Slab", mats, slab)
    crystal_obj = part("Crystal", mats, crystal, smooth=20)
    crystal_obj.location = (0, 0, 0.55)
    bones = [("b_root", (0, 0, 0), None, 0.1), ("b_crystal", (0, 0, 0.55), "b_root", 0.2)]
    c = rigmod.cycle
    hover = {"b_crystal": [(f, (0.0, v, 0.0), (0.0, v * 0.12, 0.0), None)
                           for f, v in c(48, [0.0, 0.5, 0.0, -0.5])]}
    warp = {"b_crystal": [(1, None, None, None),
                          (5, (0.0, 1.2, 0.0), (0.0, 0.15, 0.0), (1.6, 1.6, 1.6)),
                          (13, None, None, None)]}
    _rigged("warp_stone", "WarpRig", bones,
            {"Slab": (slab_obj, "b_root"), "Crystal": (crystal_obj, "b_crystal")},
            [("hover", 48, hover), ("warp", 12, warp)])


# --- 時の鐘の砂時計 -----------------------------------------------------------------


def build_bell_timer():
    """時の鐘の砂時計: 木の枠のガラスに夕日色の砂。鐘を鳴らすとひっくり返る（鳴る時間の目印）。"""
    base.reset_scene()
    mats = [
        mat("TimerWood", pal.WOOD, 0.75),
        mat("TimerGlass", "#e8f4fb", 0.15, emission="#e8f4fb", strength=0.15),
        mat("TimerSand", pal.SUN_SOFT, 0.7),
        mat("TimerStone", pal.STONE_DEEP, 0.9),
    ]
    WD, GL, SA, SD = range(4)

    def foot(bm):
        pal.rounded_box(bm, (0.34, 0.34, 0.1), (0, 0, 0.05), 0.04, 2, SD)
        for sx in (-1, 1):
            pal.capsule(bm, 0.025, (sx * 0.12, 0, 0.1), (sx * 0.12, 0, 0.28), 8, WD)

    def glass(bm):
        # 原点は砂時計の真ん中（回る軸）。上下に木の蓋、間に 2 つのガラスの玉
        for sz in (-1, 1):
            pal.lathe(bm, pal.rounded_profile(0.11, 0.03, 0.012, bottom=sz * 0.17 - 0.015), 16, WD)
            pal.ellipsoid(bm, 0.085, (0, 0, sz * 0.085), (1, 1, 1.0), (16, 10), GL)
        pal.ellipsoid(bm, 0.06, (0, 0, -0.1), (1, 1, 0.55), (14, 8), SA)
        for sx in (-1, 1):
            pal.capsule(bm, 0.015, (sx * 0.1, 0, -0.17), (sx * 0.1, 0, 0.17), 8, WD)

    foot_obj = part("Foot", mats, foot)
    glass_obj = part("Glass", mats, glass)
    glass_obj.location = (0, 0, 0.42)
    bones = [("b_root", (0, 0, 0), None, 0.1), ("b_glass", (0, 0, 0.42), "b_root", 0.2)]
    _rigged("bell_timer", "TimerRig", bones,
            {"Foot": (foot_obj, "b_root"), "Glass": (glass_obj, "b_glass")},
            [("flip", 12, {"b_glass": _turn(12, (0, 0, 0), (math.pi, 0, 0))})])


BUILDERS = {
    "plate": build_plate,
    "door": build_door,
    "lever": build_lever,
    "warp": build_warp_stone,
    "timer": build_bell_timer,
}


def main():
    argv = sys.argv
    names = argv[argv.index("--") + 1:] if "--" in argv else list(BUILDERS)
    for name in names:
        BUILDERS[name]()


if __name__ == "__main__":
    main()
