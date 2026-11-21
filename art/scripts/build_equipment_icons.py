"""装備（ジャンプブーツ・クライミンググローブ）のアイコンを、ゲームの 3D モデルから描画する。

    blender -b --factory-startup --python art/scripts/build_equipment_icons.py

ホットバーと持ち物の画面で、装備を「能力のメダル」ではなく装備そのものの姿で見せるため（docs/adr/0018）。
モデルは build_markers.py が書き出した assets/models/jump_boots.glb・climbing_gloves.glb をそのまま読み込み、
build_icons.py と同じ明かり・斜め上からの正射影で、透明背景の 128px に描く。
書き出し先は assets/icons/equipment_<行動>.png。能力が抜けた「空」の見た目はゲーム側で薄くして印を重ねる
（ItemPainter）ので、ここでは満ちた姿の1枚だけを作る。
"""

import math
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
MODELS = ROOT / "assets" / "models"
OUT_DIR = ROOT / "assets" / "icons"
SIZE = 128

# アイコン名（行動のキー）→ (モデル, カメラの見下ろす角度, 横へ回す角度)。手袋は親指と滑り止めが見えるよう正面寄り
EQUIPMENT = {
    "high_jump": ("jump_boots.glb", 30.0, -28.0),
    "climb": ("climbing_gloves.glb", 18.0, -15.0),
}


def setup_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.render.film_transparent = True
    scene.render.resolution_x = SIZE
    scene.render.resolution_y = SIZE
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    key = bpy.data.lights.new("Key", "AREA")
    key.energy = 120
    key.size = 2.0
    key_obj = bpy.data.objects.new("Key", key)
    key_obj.location = (-1.2, -1.2, 2.5)
    key_obj.rotation_euler = (math.radians(40), math.radians(-30), 0)
    scene.collection.objects.link(key_obj)
    world = bpy.data.worlds.new("IconWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
    scene.world = world
    return scene


def bounds(objects):
    lo = Vector((math.inf,) * 3)
    hi = Vector((-math.inf,) * 3)
    for obj in objects:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            p = obj.matrix_world @ Vector(corner)
            lo = Vector(map(min, lo, p))
            hi = Vector(map(max, hi, p))
    return lo, hi


def render(scene, key, file_name, tilt_deg, turn_deg):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(MODELS / file_name))
    imported = [o for o in bpy.data.objects if o not in before]
    bpy.context.view_layer.update()
    lo, hi = bounds(imported)
    center = (lo + hi) * 0.5
    extent = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z)
    # 斜め上・やや横から（build_icons.py に近い向き）。モデルの大きさに合わせて枠を決める
    cam_data = bpy.data.cameras.new("Cam_" + key)
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = extent * 1.3
    cam = bpy.data.objects.new("Cam_" + key, cam_data)
    tilt = math.radians(tilt_deg)
    turn = math.radians(turn_deg)
    direction = Vector(
        (math.sin(turn) * math.cos(tilt), -math.cos(turn) * math.cos(tilt), math.sin(tilt))
    )
    cam.location = center + direction * (extent * 4.0)
    cam.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.filepath = str(OUT_DIR / f"equipment_{key}.png")
    bpy.ops.render.render(write_still=True)
    for obj in imported + [cam]:
        bpy.data.objects.remove(obj, do_unlink=True)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    scene = setup_scene()
    for key, (file_name, tilt, turn) in EQUIPMENT.items():
        render(scene, key, file_name, tilt, turn)
    print("equipment icons done")


main()
