"""art/source の .blend を1枚ずつ斜め上から描画し、確認用の PNG を書き出す（Cycles・CPU）。

    blender -b --factory-startup --python art/scripts/render_previews.py -- <出力先ディレクトリ>
"""

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]


def render(blend: Path, out_dir: Path) -> None:
    bpy.ops.wm.open_mainfile(filepath=str(blend))
    scene = bpy.context.scene
    objs = [o for o in scene.objects if o.type == "MESH"]
    lo = Vector((min(c[i] for o in objs for c in (o.matrix_world @ Vector(b) for b in o.bound_box)) for i in range(3)))
    hi = Vector((max(c[i] for o in objs for c in (o.matrix_world @ Vector(b) for b in o.bound_box)) for i in range(3)))
    center = (lo + hi) / 2
    size = max((hi - lo).length, 0.5)
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    scene.collection.objects.link(cam)
    # 正面（+Y）寄りの斜め上から
    direction = Vector((0.75, 1.3, 0.8)).normalized()
    cam.location = center + direction * size * 1.9
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 3.0
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(30))
    scene.collection.objects.link(sun)
    world = bpy.data.worlds.new("PreviewWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.65, 0.8, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    scene.world = world
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.render.resolution_x = 420
    scene.render.resolution_y = 420
    scene.render.filepath = str(out_dir / f"{blend.stem}.png")
    bpy.ops.render.render(write_still=True)


def main() -> None:
    out_dir = Path(sys.argv[sys.argv.index("--") + 1])
    out_dir.mkdir(parents=True, exist_ok=True)
    for blend in sorted((ROOT / "art" / "source").glob("*.blend")):
        render(blend, out_dir)


main()
