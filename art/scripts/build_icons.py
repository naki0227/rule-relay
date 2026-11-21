"""能力・禁止の「器」のアイコンを Blender で描画し、assets/icons/*.png（透明背景）に書き出す。

    blender -b --factory-startup --python art/scripts/build_icons.py

器は丸いメダル型。中央の記号で行動を示す（W/A/S/D は矢印、ジャンプは二重の山形、投げるは玉と斜めの矢印、
高跳び（ジャンプブーツ）は三重の山形、登る（クライミンググローブ）ははしご、ダッシュは矢印と流れる線、
重いは取っ手の付いたおもり、浮くは風船、泳ぐは二本の波）。
禁止は同じ記号を灰色にし、赤い輪と斜線を重ねる（色だけに頼らない）。
矢印の向きはアイコン上の向きで、ゲーム内ではプレイヤーはカメラ相対、ブロックは世界の方角になる。
原本は art/source/item_icons.blend（全アイコンを並べたシーン）。

記号だけの白い絵（glyph_*.png、真上から・透明背景）も書き出す。世界に落ちている器の3Dメダル
（build_markers.py）の面に、ゲームが色を付けて重ねる。
"""

import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art" / "source" / "item_icons.blend"
OUT_DIR = ROOT / "assets" / "icons"
SIZE = 128

ACTIONS = {
    "forward": 0.0,  # 記号の回転（度）。0 = 上向き
    "left": 90.0,
    "back": 180.0,
    "right": -90.0,
    "jump": "jump",
    "throw": "throw",
    "high_jump": "high_jump",
    "climb": "climb",
    "dash": "dash",
    "heavy": "heavy",
    "float": "float",
    "swim": "swim",
}


def srgb(hex_color):
    hex_color = hex_color.lstrip("#")
    out = []
    for i in range(0, 6, 2):
        c = int(hex_color[i : i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (*out, 1.0)


def material(name, color, roughness=0.5, metallic=0.0, emission=None, strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = srgb(color)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission:
        bsdf.inputs["Emission Color"].default_value = srgb(emission)
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def to_object(name, bm, mats, smooth=True):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for m in mats:
        mesh.materials.append(m)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    if smooth:
        mesh.shade_smooth()
        mesh.set_sharp_from_angle(angle=math.radians(40))
    return obj


def medal(name, rim_color, face_color):
    """丸いメダル（縁が太く、面が少しくぼむ）。"""
    rim = material(name + "Rim", rim_color, 0.35, metallic=0.5)
    face = material(name + "Face", face_color, 0.6)
    bm = bmesh.new()
    geom = bmesh.ops.create_cone(
        bm, cap_ends=True, segments=48, radius1=0.46, radius2=0.46, depth=0.14
    )
    bmesh.ops.bevel(
        bm, geom=list(bm.verts) + list(bm.edges), offset=0.03, segments=3,
        affect="EDGES", clamp_overlap=True,
    )
    top = [f for f in bm.faces if f.normal.z > 0.99 and f.calc_center_median().z > 0.06]
    bmesh.ops.inset_individual(bm, faces=top, thickness=0.07, depth=-0.025)
    for f in bm.faces:
        f.material_index = 1 if f in top else 0
    return to_object(name, bm, [rim, face])


def extruded_polygon(name, points, depth, mat, rotation_deg=0.0, z=0.06):
    bm = bmesh.new()
    verts = [bm.verts.new((x, y, z)) for x, y in points]
    face = bm.faces.new(verts)
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    moved = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=Vector((0, 0, depth)), verts=moved)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.bevel(
        bm, geom=list(bm.edges), offset=0.008, segments=2, affect="EDGES", clamp_overlap=True
    )
    bmesh.ops.rotate(
        bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(rotation_deg), 3, "Z")
    )
    return to_object(name, bm, [mat], smooth=False)


ARROW = [(-0.07, -0.24), (0.07, -0.24), (0.07, 0.02), (0.18, 0.02), (0.0, 0.25), (-0.18, 0.02),
         (-0.07, 0.02)]


def chevron(y, width=0.2, thickness=0.085, height=0.12):
    return [(-width, y), (0.0, y + height), (width, y), (width, y + thickness),
            (0.0, y + height + thickness), (-width, y + thickness)]


def rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def ngon(cx, cy, radius, sides=12):
    return [(cx + radius * math.cos(2 * math.pi * i / sides), cy + radius * math.sin(2 * math.pi * i / sides))
            for i in range(sides)]


def symbol(name, action, mat):
    kind = ACTIONS[action]
    if kind == "jump":
        return [extruded_polygon(name + "A", chevron(-0.2), 0.05, mat),
                extruded_polygon(name + "B", chevron(0.0), 0.05, mat)]
    if kind == "high_jump":
        return [extruded_polygon(name + "A", chevron(-0.27, height=0.1, thickness=0.07), 0.05, mat),
                extruded_polygon(name + "B", chevron(-0.1, height=0.1, thickness=0.07), 0.05, mat),
                extruded_polygon(name + "C", chevron(0.07, height=0.1, thickness=0.07), 0.05, mat)]
    if kind == "throw":
        small = [(x * 0.75, y * 0.75) for x, y in ARROW]
        arrow = extruded_polygon(name + "Arrow", small, 0.05, mat, -45.0)
        for v in arrow.data.vertices:
            v.co.x += 0.06
            v.co.y += 0.06
        return [extruded_polygon(name + "Ball", ngon(-0.15, -0.15, 0.085), 0.05, mat), arrow]
    if kind == "climb":
        parts = [rect(-0.16, -0.25, -0.1, 0.25), rect(0.1, -0.25, 0.16, 0.25)]
        parts += [rect(-0.1, y - 0.03, 0.1, y + 0.03) for y in (-0.15, 0.0, 0.15)]
        return [extruded_polygon(f"{name}{i}", pts, 0.05, mat) for i, pts in enumerate(parts)]
    if kind == "dash":
        arrow = extruded_polygon(name + "Arrow", [(x * 0.85, y * 0.85) for x, y in ARROW], 0.05, mat, -90.0)
        for v in arrow.data.vertices:
            v.co.x += 0.08
        lines = [rect(-0.3, y - 0.025, -0.3 + w, y + 0.025) for y, w in ((-0.1, 0.14), (0.0, 0.2), (0.1, 0.14))]
        return [arrow] + [extruded_polygon(f"{name}Line{i}", pts, 0.05, mat) for i, pts in enumerate(lines)]
    if kind in ("heavy", "float", "swim"):
        return [extruded_polygon(f"{name}{i}", pts, 0.05, mat) for i, pts in enumerate(nature_parts(kind))]
    return [extruded_polygon(name, ARROW, 0.05, mat, kind)]


def wave(y, amplitude=0.04, thickness=0.06, half=0.25, steps=12):
    """横に伸びる波の帯（上の縁と下の縁を同じ波で結ぶ）。"""
    top = []
    for i in range(steps + 1):
        x = -half + 2 * half * i / steps
        top.append((x, y + thickness / 2 + amplitude * math.sin(x * math.tau / 0.25)))
    bottom = [(x, yy - thickness) for x, yy in reversed(top)]
    return top + bottom


def nature_parts(kind):
    """重い・浮く・泳ぐの記号の部品（どれも単純な多角形）。"""
    if kind == "heavy":
        body = [(-0.2, -0.24), (0.2, -0.24), (0.23, -0.16), (0.16, 0.08), (-0.16, 0.08), (-0.23, -0.16)]
        return [body, rect(-0.12, 0.06, -0.06, 0.24), rect(0.06, 0.06, 0.12, 0.24), rect(-0.12, 0.19, 0.12, 0.25)]
    if kind == "float":
        knot = [(-0.045, -0.13), (0.045, -0.13), (0.0, -0.08)]
        return [ngon(0.0, 0.08, 0.17, 24), knot, rect(-0.012, -0.28, 0.012, -0.12)]
    return [wave(0.1), wave(-0.1)]


def prohibition_mark(name):
    red = material(name + "Red", "#d8342c", 0.4, emission="#d8342c", strength=0.3)
    bm = bmesh.new()
    ring = bmesh.ops.create_circle(bm, cap_ends=False, segments=48, radius=0.36)
    inner = bmesh.ops.create_circle(bm, cap_ends=False, segments=48, radius=0.29)
    bmesh.ops.bridge_loops(bm, edges=list(bm.edges))
    bmesh.ops.translate(bm, vec=Vector((0, 0, 0.13)), verts=bm.verts)
    ring_obj = to_object(name + "Ring", bm, [red], smooth=False)
    slash = extruded_polygon(
        name + "Slash", [(-0.035, -0.31), (0.035, -0.31), (0.035, 0.31), (-0.035, 0.31)],
        0.02, red, -45.0, z=0.13,
    )
    _ = ring, inner
    return [ring_obj, slash]


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
    cam_data = bpy.data.cameras.new("IconCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 1.08
    cam = bpy.data.objects.new("IconCam", cam_data)
    cam.location = (0, -0.9, 2.2)
    cam.rotation_euler = (math.radians(22), 0, 0)
    scene.collection.objects.link(cam)
    scene.camera = cam
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


def build_icon(scene, kind, action):
    """1枚分のオブジェクトを作って描画し、描画後は非表示にする（原本の .blend に全部残す）。"""
    name = f"{kind}_{action}"
    if kind == "ability":
        base = medal(name + "Medal", "#c99a3c", "#f3dfa2")
        mark = material(name + "Symbol", "#7a4e16", 0.5)
        objs = [base] + symbol(name + "Symbol", action, mark)
    else:
        base = medal(name + "Medal", "#6c6a70", "#c9c6c2")
        mark = material(name + "Symbol", "#55525a", 0.6)
        objs = [base] + symbol(name + "Symbol", action, mark) + prohibition_mark(name)
    for other in scene.objects:
        if other.type == "MESH":
            other.hide_render = other not in objs
    scene.render.filepath = str(OUT_DIR / f"{name}.png")
    bpy.ops.render.render(write_still=True)
    # 原本のシーンでは、横に並べて全部見えるようにする
    index = list(ACTIONS).index(action) + (0 if kind == "ability" else len(ACTIONS))
    for obj in objs:
        obj.location.x += 1.2 * (index % len(ACTIONS))
        obj.location.y += -1.2 * (index // len(ACTIONS))


def render_glyphs(scene):
    """記号だけを真上から白で描く（器の3Dメダルの面に重ねる絵）。描いた物は原本に残さない。"""
    cam = scene.camera
    saved = (cam.location.copy(), cam.rotation_euler.copy())
    cam.location = (0, 0, 2.2)
    cam.rotation_euler = (0, 0, 0)
    white = material("GlyphWhite", "#ffffff", 1.0, emission="#ffffff", strength=1.0)
    for action in ACTIONS:
        objs = symbol(f"glyph_{action}", action, white)
        for other in scene.objects:
            if other.type == "MESH":
                other.hide_render = other not in objs
        scene.render.filepath = str(OUT_DIR / f"glyph_{action}.png")
        bpy.ops.render.render(write_still=True)
        for obj in objs:
            bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.materials.remove(white)
    cam.location, cam.rotation_euler = saved


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    scene = setup_scene()
    for kind in ("ability", "prohibition"):
        for action in ACTIONS:
            build_icon(scene, kind, action)
    render_glyphs(scene)
    for obj in scene.objects:
        obj.hide_render = False
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE), compress=True)
    print("icons done")


main()
