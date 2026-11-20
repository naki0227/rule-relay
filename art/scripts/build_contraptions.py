"""仕掛けのモデル（発射台・鐘）を、手続きテクスチャを焼き込んだ glTF で作る。

    blender -b --factory-startup --python art/scripts/build_contraptions.py

本人の要望（2026-11-19）: 発射台などは、ひと目で分かるように、Blender でテクスチャまでこだわって作る。
- 発射台: 木箱の正面（+X。ゲームでは撃つ方角へ回す）に真鍮の筒、上面に撃つ向きの矢印、後ろに玉の入った受け口
- 鐘: 石の台・木の柱と梁・小さな屋根、本物の鐘の断面を回転させた金色の鐘と舌（ぜつ）、引き綱。
  鐘の本体は "BellCup" という子オブジェクトで、原点が吊り下げ点（ゲームで揺らす）
テクスチャは手続き（木目・石・金属のくすみ）を Cycles で 512px の画像に焼き込み、GLB に埋め込む。
"""

import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_assets as base  # noqa: E402

TEXTURE_SIZE = 512


# --- 手続きテクスチャ ----------------------------------------------------------


def _nodes(mat):
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    return nt, bsdf


def wood_material(name, light, dark, scale=6.0, roughness=0.75):
    """木目: 引き伸ばした雑音を帯状にし、明るい色と暗い色の間で塗る。"""
    mat = bpy.data.materials.new(name)
    nt, bsdf = _nodes(mat)
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (scale * 0.25, scale * 0.25, scale * 3.0)
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "RINGS"
    wave.inputs["Scale"].default_value = 2.5
    wave.inputs["Distortion"].default_value = 6.0
    wave.inputs["Detail"].default_value = 3.0
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 30.0
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "FLOAT"
    mix.inputs["Factor"].default_value = 0.25
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = base.srgb(dark)
    ramp.color_ramp.elements[1].color = base.srgb(light)
    ramp.color_ramp.elements[0].position = 0.25
    ramp.color_ramp.elements[1].position = 0.8
    links = nt.links
    links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], wave.inputs["Vector"])
    links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    links.new(wave.outputs["Fac"], mix.inputs["A"])
    links.new(noise.outputs["Fac"], mix.inputs["B"])
    links.new(mix.outputs["Result"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def speckled_material(name, color_a, color_b, scale=18.0, roughness=0.85, metallic=0.0):
    """石・金属のくすみ: 細かい雑音で2色をまだらにする。"""
    mat = bpy.data.materials.new(name)
    nt, bsdf = _nodes(mat)
    coord = nt.nodes.new("ShaderNodeTexCoord")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = 6.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = base.srgb(color_a)
    ramp.color_ramp.elements[1].color = base.srgb(color_b)
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[1].position = 0.7
    nt.links.new(coord.outputs["Object"], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


def bake_to_image(obj, image_name):
    """オブジェクトの全材質の色を1枚の画像に焼き込み、材質を「画像を読むだけ」に置き換える。"""
    bpy.context.view_layer.objects.active = obj
    for o in bpy.context.selected_objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")
    image = bpy.data.images.new(image_name, TEXTURE_SIZE, TEXTURE_SIZE)
    for mat in obj.data.materials:
        node = mat.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = image
        node.name = "BakeTarget"
        mat.node_tree.nodes.active = node
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 8
    scene.render.bake.use_pass_direct = False
    scene.render.bake.use_pass_indirect = False
    scene.render.bake.margin = 4
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
    image.pack()
    for mat in obj.data.materials:
        nt = mat.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        target = nt.nodes["BakeTarget"]
        for link in list(bsdf.inputs["Base Color"].links):
            nt.links.remove(link)
        nt.links.new(target.outputs["Color"], bsdf.inputs["Base Color"])
        for node in list(nt.nodes):
            if node not in (bsdf, target) and node.type not in ("OUTPUT_MATERIAL",):
                nt.nodes.remove(node)


# --- 形 -----------------------------------------------------------------------


def arrow_shape():
    return [(-0.22, -0.06), (0.05, -0.06), (0.05, -0.15), (0.25, 0.0), (0.05, 0.15),
            (0.05, 0.06), (-0.22, 0.06)]


def build_launcher():
    base.reset_scene()
    wood = wood_material("LauncherWood", "#d9a46a", "#a8743f")
    frame = wood_material("LauncherFrame", "#9a6a3f", "#6e4826", scale=8.0)
    brass = speckled_material("Brass", "#e2b04a", "#b98a2f", scale=40.0, roughness=0.35, metallic=0.7)
    paint = speckled_material("ArrowPaint", "#f09a45", "#e07e2c", scale=60.0, roughness=0.6)
    ball = speckled_material("BallClay", "#c97b4a", "#a85f35", scale=30.0)
    bm = bmesh.new()
    # 木箱（1マスより少し小さい）
    base.add_cube(bm, (0.86, 0.86, 0.8), (0, 0, -0.06), 0)
    base.bevel_all(bm, 0.05, segments=2)
    # 四隅の柱（濃い木）
    for sx in (-1, 1):
        for sy in (-1, 1):
            base.add_cube(bm, (0.12, 0.12, 0.86), (sx * 0.43, sy * 0.43, -0.03), 1)
    # 正面の筒（+X）と、口の輪
    base.add_cylinder(bm, 0.17, 0.17, 0.42, 20, (0.55, 0, 0.02), 2,
                      matrix=Matrix.Rotation(math.radians(90), 4, "Y"))
    base.add_cylinder(bm, 0.22, 0.22, 0.08, 20, (0.74, 0, 0.02), 2,
                      matrix=Matrix.Rotation(math.radians(90), 4, "Y"))
    # 上面の矢印（撃つ向き）
    verts = [bm.verts.new((x, y, 0.345)) for x, y in arrow_shape()]
    face = bm.faces.new(verts)
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    moved = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=Vector((0, 0, 0.03)), verts=moved)
    for f in {f for v in verts + moved for f in v.link_faces}:
        f.material_index = 3
    # 後ろの受け口と玉
    base.add_cylinder(bm, 0.2, 0.13, 0.22, 16, (-0.3, 0, 0.45), 1)
    for i, (x, y) in enumerate([(-0.3, 0.05), (-0.25, -0.06)]):
        base.add_sphere(bm, 0.075, (x, y, 0.55 + i * 0.03), subdiv=2, material_index=4)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = base.mesh_object("Launcher", bm, [wood, frame, brass, paint, ball], smooth_angle=35)
    bake_to_image(obj, "launcher_baked")
    base.save_and_export("launcher", [obj])


def bell_profile():
    """鐘の断面（半径, 高さ）。上が頂、下が口。外側をなぞって内側へ戻る。"""
    outer = [(0.0, 0.0), (0.12, 0.0), (0.16, -0.04), (0.17, -0.12), (0.19, -0.24),
             (0.24, -0.34), (0.3, -0.4), (0.31, -0.43)]
    inner = [(0.27, -0.43), (0.25, -0.38), (0.2, -0.32), (0.15, -0.22), (0.13, -0.1),
             (0.1, -0.04), (0.0, -0.04)]
    return outer + inner


def spin_profile(bm, profile, segments, material_index):
    rings = []
    for i in range(segments):
        a = 2 * math.pi * i / segments
        rings.append([bm.verts.new((r * math.cos(a), r * math.sin(a), z)) for r, z in profile])
    for i in range(segments):
        ring, nxt = rings[i], rings[(i + 1) % segments]
        for j in range(len(profile) - 1):
            quad = [ring[j], ring[j + 1], nxt[j + 1], nxt[j]]
            if len({v.co.to_tuple(5) for v in quad}) < 3:
                continue
            try:
                f = bm.faces.new(quad)
                f.material_index = material_index
            except ValueError:
                pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)


def build_bell():
    base.reset_scene()
    wood = wood_material("BellWood", "#b98454", "#8a5a33", scale=7.0)
    stone = speckled_material("BellStone", "#cfc3ad", "#a99b84", scale=14.0, roughness=0.95)
    roof = wood_material("BellRoof", "#c7684c", "#9c4a35", scale=10.0)
    rope = speckled_material("Rope", "#e3cfa1", "#b89d6a", scale=80.0)
    gold = speckled_material("BellGold", "#e8b84e", "#b98a2f", scale=25.0, roughness=0.3, metallic=0.75)
    height = 1.6
    frame_bm = bmesh.new()
    base.add_cube(frame_bm, (0.95, 0.75, 0.12), (0, 0, 0.06), 1)  # 石の台
    base.bevel_all(frame_bm, 0.03, segments=2)
    for sx in (-1, 1):
        base.add_cube(frame_bm, (0.12, 0.12, height), (sx * 0.38, 0, height / 2 + 0.06), 0)
    base.add_cube(frame_bm, (0.96, 0.14, 0.12), (0, 0, height + 0.06), 0)  # 梁
    # 小さな切妻屋根
    for sy in (-1, 1):
        verts, faces = base.add_cube(frame_bm, (1.1, 0.42, 0.05), (0, sy * 0.17, height + 0.24), 2)
        bmesh.ops.rotate(frame_bm, verts=verts, cent=(0, sy * 0.17, height + 0.24),
                         matrix=Matrix.Rotation(math.radians(-30 * sy), 3, "X"))
    # 引き綱（梁から右の柱の脇へ）
    base.add_cylinder(frame_bm, 0.015, 0.015, 0.9, 6, (0.2, 0.05, height - 0.4), 3)
    bmesh.ops.recalc_face_normals(frame_bm, faces=frame_bm.faces)
    frame = base.mesh_object("BellFrame", frame_bm, [wood, stone, roof, rope], smooth_angle=35)

    cup_bm = bmesh.new()
    spin_profile(cup_bm, bell_profile(), 32, 0)
    base.add_cylinder(cup_bm, 0.035, 0.035, 0.32, 8, (0, 0, -0.2), 0)  # 舌の棒
    base.add_sphere(cup_bm, 0.06, (0, 0, -0.38), subdiv=2, material_index=0)  # 舌の玉
    base.add_cube(cup_bm, (0.08, 0.08, 0.08), (0, 0, 0.03), 0)  # 吊り金具
    bmesh.ops.recalc_face_normals(cup_bm, faces=cup_bm.faces)
    cup = base.mesh_object("BellCup", cup_bm, [gold], smooth_angle=50)
    cup.location = (0, 0, height - 0.02)
    cup.parent = frame
    bake_to_image(frame, "bell_frame_baked")
    bake_to_image(cup, "bell_cup_baked")
    base.save_and_export("bell", [frame, cup])


def main():
    build_launcher()
    build_bell()


if __name__ == "__main__":
    main()
