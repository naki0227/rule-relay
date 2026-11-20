"""広場（ハブ）の置物（街灯・柵・鉢植え・ベンチ）を作る。

    blender -b --factory-startup --python art/scripts/build_hub_props.py              # 全部
    blender -b --factory-startup --python art/scripts/build_hub_props.py -- lamp      # 一部（BUILDERS）

方針: 「人が手入れしている場所」に見えることだけを目的に、特定の文化・時代を示す飾りは付けない。
すべて見た目だけで、当たり判定はゲーム側で付ける（付けない物もある）。原点は足もと、正面は +Y。
柵は 1 区画が長さ 2m（X 方向、中心が原点）で、並べてつなぐ。
"""

import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_assets as base  # noqa: E402
import palette as pal  # noqa: E402


def mat(name, color, roughness=0.8, emission=None, strength=0.0):
    return base.material(name, color, roughness, emission=emission, strength=strength)


def export(file_name, root_name, build, mats, smooth=55):
    base.reset_scene()
    materials = [m() for m in mats]
    bm = bmesh.new()
    build(bm)
    obj = base.mesh_object(root_name, bm, materials, smooth_angle=smooth)
    root = bpy.data.objects.new(root_name + "Root", None)
    bpy.context.collection.objects.link(root)
    obj.parent = root
    base.save_and_export(file_name, [root, obj])


def build_lamp():
    """街灯: 丸い石の台、木の柱、丸い屋根の灯り。"""

    def build(bm):
        pal.lathe(bm, pal.rounded_profile(0.22, 0.14, 0.05), 24, 0)
        pal.capsule(bm, 0.06, (0, 0, 0.1), (0, 0, 1.75), 16, 1)
        pal.torus(bm, 0.065, 0.022, (0, 0, 0.35), 16, 6, 1)
        pal.torus(bm, 0.07, 0.025, (0, 0, 1.68), 16, 6, 1)
        # 灯り: 枠の上下に丸い板、中に光る玉、上に丸い屋根
        pal.lathe(bm, pal.rounded_profile(0.14, 0.04, 0.018, bottom=1.74), 24, 1)
        pal.ellipsoid(bm, 0.13, (0, 0, 1.92), (1, 1, 1.15), (24, 14), 2)
        pal.lathe(bm, pal.rounded_profile(0.13, 0.035, 0.016, bottom=2.07), 24, 1)
        roof = [(0.0, 2.1), (0.2, 2.1), (0.215, 2.125), (0.17, 2.18), (0.08, 2.24), (0.0, 2.26)]
        pal.lathe(bm, roof, 28, 3)
        pal.ellipsoid(bm, 0.035, (0, 0, 2.28), (1, 1, 1), (12, 8), 3)

    export("hub_lamp", "HubLamp", build, [
        lambda: mat("Stone", pal.STONE, 0.85),
        lambda: mat("Wood", pal.WOOD, 0.75),
        lambda: mat("LampGlow", pal.LAMP, 0.4, emission=pal.LAMP, strength=2.2),
        lambda: mat("Roof", pal.WOOD_DARK, 0.7),
    ])


def build_fence():
    """柵の1区画（長さ 2m）: 丸い頭の杭3本と、2本の横木。"""

    def build(bm):
        for x in (-1.0, 0.0, 1.0):
            pal.capsule(bm, 0.07, (x, 0, 0.0), (x, 0, 0.72), 14, 0)
            pal.torus(bm, 0.072, 0.02, (x, 0, 0.12), 14, 6, 1)
        for z in (0.32, 0.56):
            pal.rounded_box(bm, (2.0, 0.06, 0.1), (0, 0.06, z), 0.03, 3, 0)

    export("hub_fence", "HubFence", build, [
        lambda: mat("Wood", pal.WOOD_LIGHT, 0.75),
        lambda: mat("WoodDark", pal.WOOD, 0.75),
    ])


def build_planter():
    """鉢植え: 素焼きの丸い鉢に、こんもりした低木と小さな花。"""

    def build(bm):
        pot = [(0.0, 0.0), (0.18, 0.0), (0.22, 0.03), (0.27, 0.3), (0.3, 0.33), (0.3, 0.38),
               (0.27, 0.4), (0.24, 0.38), (0.0, 0.38)]
        pal.lathe(bm, pot, 28, 0)
        pal.torus(bm, 0.26, 0.025, (0, 0, 0.2), 28, 6, 1)
        for x, y, z, r in ((0, 0, 0.55, 0.26), (0.13, 0.08, 0.5, 0.17), (-0.12, -0.06, 0.52, 0.18),
                           (0.03, -0.1, 0.7, 0.15)):
            pal.ellipsoid(bm, r, (x, y, z), (1, 1, 0.9), (20, 12), 2 if r > 0.2 else 3)
        for x, y, z in ((0.17, 0.15, 0.62), (-0.15, 0.13, 0.6), (0.02, 0.2, 0.72), (-0.05, -0.2, 0.7)):
            pal.ellipsoid(bm, 0.035, (x, y, z), (1, 1, 0.8), (10, 6), 4)

    export("hub_planter", "HubPlanter", build, [
        lambda: mat("Clay", pal.CLAY, 0.85),
        lambda: mat("ClayDeep", "#c0714d", 0.85),
        lambda: mat("Leaves", pal.LEAF, 0.8),
        lambda: mat("LeavesLight", pal.LEAF_LIGHT, 0.8),
        lambda: mat("Bloom", "#f7c6cf", 0.6),
    ], smooth=70)


def build_bench():
    """ベンチ: 丸い角の座板2枚と背もたれ、太い脚。"""

    def build(bm):
        for y in (-0.08, 0.1):
            pal.rounded_box(bm, (1.5, 0.16, 0.07), (0, y, 0.45), 0.03, 3, 0)
        pal.rounded_box(bm, (1.5, 0.06, 0.2), (0, -0.2, 0.78), 0.03, 3, 0)
        for x in (-0.6, 0.6):
            pal.rounded_box(bm, (0.1, 0.42, 0.42), (x, 0.0, 0.21), 0.04, 3, 1)
            pal.capsule(bm, 0.035, (x, -0.2, 0.45), (x, -0.22, 0.8), 10, 1)

    export("hub_bench", "HubBench", build, [
        lambda: mat("Wood", pal.WOOD_LIGHT, 0.75),
        lambda: mat("WoodDark", pal.WOOD, 0.75),
    ])


BUILDERS = {
    "lamp": build_lamp,
    "fence": build_fence,
    "planter": build_planter,
    "bench": build_bench,
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    for name in argv or list(BUILDERS):
        BUILDERS[name]()


if __name__ == "__main__":
    main()
