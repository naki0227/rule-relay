"""Blender で試作用の3Dモデルを生成し、原本 .blend とゲーム用 .glb を書き出す。

使い方（リポジトリのルートで）:
    blender -b --factory-startup --python art/scripts/build_assets.py
    blender -b --factory-startup --python art/scripts/build_assets.py -- block tree   # 一部だけ

方針:
- 1 Blender 単位 = 1 m = ゲームの1ブロック。Z が上、キャラクターの正面は +Y
  （glTF の Y-up 変換で Godot の前方 -Z になる）。
- 地形・ブロックは中心が原点の 1x1x1。当たり判定はゲーム側の箱で、モデルは見た目だけ。
- 乱数は固定シードで、何度実行しても同じ形になる。
- 世界観は未定のため、特定の設定に寄せない中立的な形・色にしている（仮）。
"""

import math
import random
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "art" / "source"
EXPORT_DIR = ROOT / "assets" / "models"


# --- 共通 ---------------------------------------------------------------------


def srgb(hex_color):
    """'#rrggbb' を Blender のリニア色 (r, g, b, 1) にする。"""
    hex_color = hex_color.lstrip("#")
    out = []
    for i in range(0, 6, 2):
        c = int(hex_color[i : i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (*out, 1.0)


def material(name, color, roughness=0.8, metallic=0.0, emission=None, strength=0.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = srgb(color)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission:
        bsdf.inputs["Emission Color"].default_value = srgb(emission)
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mesh_object(name, bm, materials, smooth_angle=None):
    """bmesh からオブジェクトを作る。smooth_angle（度）を指定すると角度で滑らかにする。"""
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for mat in materials:
        mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    if smooth_angle is None:
        for poly in mesh.polygons:
            poly.use_smooth = False
    else:
        mesh.shade_smooth()
        mesh.set_sharp_from_angle(angle=math.radians(smooth_angle))
    return obj


def faces_where(bm, predicate):
    return [f for f in bm.faces if predicate(f)]


def set_material(faces, index):
    for f in faces:
        f.material_index = index


def jitter(bm, amount, seed, keep=lambda v: False):
    rng = random.Random(seed)
    for v in bm.verts:
        if keep(v):
            continue
        v.co += Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * amount


def add_cube(bm, size, center=(0, 0, 0), material_index=0):
    """bm に直方体を足し、追加した面を返す。"""
    geom = bmesh.ops.create_cube(bm, size=1.0)
    verts = geom["verts"]
    bmesh.ops.scale(bm, vec=Vector(size), verts=verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=verts)
    faces = list({f for v in verts for f in v.link_faces})
    set_material(faces, material_index)
    return verts, faces


def add_cylinder(bm, radius1, radius2, depth, segments, center, material_index=0, matrix=None):
    geom = bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        radius1=radius1,
        radius2=radius2,
        depth=depth,
        matrix=matrix or Matrix.Identity(4),
    )
    verts = geom["verts"]
    bmesh.ops.translate(bm, vec=Vector(center), verts=verts)
    faces = list({f for v in verts for f in v.link_faces})
    set_material(faces, material_index)
    return verts, faces


def add_sphere(bm, radius, center, scale=(1, 1, 1), subdiv=2, material_index=0, uv=None):
    if uv:
        geom = bmesh.ops.create_uvsphere(bm, u_segments=uv[0], v_segments=uv[1], radius=radius)
    else:
        geom = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    verts = geom["verts"]
    bmesh.ops.scale(bm, vec=Vector(scale), verts=verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=verts)
    faces = list({f for v in verts for f in v.link_faces})
    set_material(faces, material_index)
    return verts, faces


def bevel_all(bm, offset, segments=2, profile=0.5):
    bmesh.ops.bevel(
        bm,
        geom=list(bm.verts) + list(bm.edges),
        offset=offset,
        segments=segments,
        profile=profile,
        affect="EDGES",
        clamp_overlap=True,
    )


def save_and_export(name, objects):
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_DIR / f"{name}.blend"), compress=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=str(EXPORT_DIR / f"{name}.glb"),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_extras=False,
        export_cameras=False,
        export_lights=False,
    )
    print(f"exported {name}")


# --- 地形 ---------------------------------------------------------------------


def build_grass_cell():
    """草の地面: 土の箱に、縁がギザギザの草の帽子をかぶせる。"""
    reset_scene()
    dirt = material("Dirt", "#b88a5c", 0.95)
    grass = material("Grass", "#84bd5f", 0.85)
    bm = bmesh.new()
    add_cube(bm, (0.985, 0.985, 0.8), (0, 0, -0.1), 0)
    # 草の帽子: 縁の頂点を交互に下げてギザギザにする
    cap = bmesh.new()
    bmesh.ops.create_grid(cap, x_segments=6, y_segments=6, size=0.5)
    bmesh.ops.translate(cap, vec=Vector((0, 0, 0.5)), verts=cap.verts)
    top = list(cap.faces)
    ext = bmesh.ops.extrude_face_region(cap, geom=top)
    side_verts = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(cap, vec=Vector((0, 0, -0.16)), verts=side_verts)
    for v in side_verts:
        on_edge = abs(abs(v.co.x) - 0.5) < 1e-4 or abs(abs(v.co.y) - 0.5) < 1e-4
        if not on_edge:
            continue
        step = round((v.co.x + v.co.y + 1.0) / (1.0 / 6.0))
        if step % 2 == 1:
            v.co.z -= 0.07
    bmesh.ops.reverse_faces(cap, faces=top)  # 押し出しで裏返った上面を戻す
    bmesh.ops.recalc_face_normals(cap, faces=cap.faces)
    bmesh.ops.scale(cap, vec=Vector((1.012, 1.012, 1.0)), verts=cap.verts)
    for f in cap.faces:
        f.material_index = 1
    mesh_tmp = bpy.data.meshes.new("tmp")
    cap.to_mesh(mesh_tmp)
    cap.free()
    bm.from_mesh(mesh_tmp)
    bpy.data.meshes.remove(mesh_tmp)
    obj = mesh_object("GrassCell", bm, [dirt, grass])
    save_and_export("grass_cell", [obj])


def build_stone_cell(name, color, seed):
    """岩: 面取りした箱の頂点を少し揺らして、削り出した石らしくする。"""
    reset_scene()
    stone = material("Stone", color, 0.9)
    bm = bmesh.new()
    add_cube(bm, (0.99, 0.99, 0.99))
    bevel_all(bm, 0.11, segments=3)
    jitter(bm, 0.006, seed)
    obj = mesh_object(name, bm, [stone], smooth_angle=50)
    return obj


def build_rock_cell():
    obj = build_stone_cell("RockCell", "#b3a48e", 11)
    save_and_export("rock_cell", [obj])


def build_sandstone_cell():
    obj = build_stone_cell("SandstoneCell", "#e6c995", 23)
    save_and_export("sandstone_cell", [obj])


def build_island_base():
    """浮かぶ島の底: 上面 1x1、下へすぼまる岩の塊（ゲーム側で島の大きさに拡大する）。"""
    reset_scene()
    dirt = material("Dirt", "#a87b52", 0.95)
    stone = material("Stone", "#b9ab92", 0.9)
    bm = bmesh.new()
    rings = [(0.0, 1.0), (-0.15, 0.98), (-0.35, 0.86), (-0.6, 0.62), (-0.82, 0.36), (-1.0, 0.08)]
    rng = random.Random(5)
    loops = []
    segments = 16
    for z, scale in rings:
        loop = []
        for i in range(segments):
            a = math.tau * i / segments
            # 正方形に近い断面（島が四角いので）
            r = scale * 0.5 / max(abs(math.cos(a)), abs(math.sin(a))) ** 0.6
            wobble = 1.0 if z == 0.0 else rng.uniform(0.9, 1.08)
            loop.append(bm.verts.new((math.cos(a) * r * wobble, math.sin(a) * r * wobble, z)))
        loops.append(loop)
    for k in range(len(loops) - 1):
        for i in range(segments):
            a, b = loops[k][i], loops[k][(i + 1) % segments]
            c, d = loops[k + 1][(i + 1) % segments], loops[k + 1][i]
            f = bm.faces.new((a, d, c, b))
            f.material_index = 0 if k < 1 else 1
    bm.faces.new(loops[-1])
    bm.faces.new(list(reversed(loops[0])))  # 上面も閉じて法線を外向きにそろえる（地面に隠れる）
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = mesh_object("IslandBase", bm, [dirt, stone])
    save_and_export("island_base", [obj])


# --- ブロック -----------------------------------------------------------------


def build_ability_block():
    """能力を受け取るブロック: 面取りした枠と、色を変えられる各面のパネル。
    パネルのマテリアル名 "Panel" をゲーム側で探して、ブロックごとの色に置き換える。"""
    reset_scene()
    frame = material("Frame", "#f6e3bf", 0.75)
    panel = material("Panel", "#ffffff", 0.55)
    rivet = material("Rivet", "#c99a63", 0.6)
    bm = bmesh.new()
    add_cube(bm, (0.98, 0.98, 0.98))
    bevel_all(bm, 0.12, segments=4)
    big = faces_where(bm, lambda f: f.calc_area() > 0.3)
    bmesh.ops.inset_individual(bm, faces=big, thickness=0.11, depth=-0.035, use_even_offset=True)
    set_material(big, 1)
    # パネルの中央に浅い菱形の刻み（向きの手がかりにはしない飾り）
    for f in list(big):
        res = bmesh.ops.inset_individual(bm, faces=[f], thickness=0.2, depth=0.0)
        bmesh.ops.inset_individual(bm, faces=[f], thickness=0.03, depth=-0.012)
        set_material(res["faces"], 1)
    # 四隅の鋲
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                add_sphere(bm, 0.06, (sx * 0.43, sy * 0.43, sz * 0.43), subdiv=2, material_index=2)
    obj = mesh_object("AbilityBlock", bm, [frame, panel, rivet], smooth_angle=35)
    save_and_export("ability_block", [obj])


# --- キャラクター -------------------------------------------------------------


def _join_as(name, objs, pivot):
    """objs を1つにまとめ、原点を pivot（関節）に置く。"""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    bpy.context.scene.cursor.location = pivot
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    return obj


def _part(name, build, mats, smooth=40):
    bm = bmesh.new()
    build(bm)
    return mesh_object(name, bm, mats, smooth_angle=smooth)


def build_traveler():
    """プレイヤー（仮）: フード付きの小柄な旅人。世界観未定のため装飾は控えめ。
    手足・頭は別オブジェクトで、原点を関節に置く（ゲーム側でコードから振る）。"""
    reset_scene()
    cloak = material("Cloak", "#5b8fd1", 0.8)
    cloak_dark = material("CloakLining", "#3f6aa6", 0.85)
    scarf = material("Scarf", "#f09a45", 0.75)
    skin = material("Skin", "#f1d2b4", 0.6)
    eye = material("Eye", "#2a2430", 0.3)
    shine = material("EyeShine", "#ffffff", 0.2, emission="#ffffff", strength=0.6)
    pants = material("Pants", "#6b5a4c", 0.85)
    boot = material("Boot", "#8b5e3c", 0.7)
    mats = [cloak, cloak_dark, scarf, skin, eye, shine, pants, boot]
    objects = []

    # 胴体（ポンチョ）
    def body(bm):
        add_cylinder(bm, 0.33, 0.15, 0.62, 14, (0, 0, 0.73), 0)
        add_cylinder(bm, 0.335, 0.335, 0.04, 14, (0, 0, 0.43), 1)  # 裾の折り返し
        # マフラー
        torus = bmesh.ops.create_cone(
            bm, cap_ends=False, segments=14, radius1=0.17, radius2=0.17, depth=0.09
        )
        bmesh.ops.translate(bm, vec=Vector((0, 0, 1.04)), verts=torus["verts"])
        set_material({f for v in torus["verts"] for f in v.link_faces}, 2)
        add_cube(bm, (0.1, 0.04, 0.32), (0.07, -0.17, 0.9), 2)  # 背中に垂れる端

    objects.append(_join_as("Body", [_part("Body", body, mats)], (0, 0, 0.42)))

    # 頭（顔は +Y 向き）とフード
    def head(bm):
        add_sphere(bm, 0.25, (0, 0, 1.3), subdiv=3, material_index=3)
        for sx in (-1, 1):
            add_sphere(bm, 0.045, (sx * 0.09, 0.225, 1.31), (1, 0.5, 1.3), 2, 4)
            add_sphere(bm, 0.014, (sx * 0.09 + 0.015, 0.247, 1.34), (1, 0.5, 1), 1, 5)
        # フード: 少し大きい球から顔の前を抜き、厚みを付ける
        verts, faces = add_sphere(bm, 0.29, (0, -0.02, 1.33), uv=(20, 12), material_index=0)
        front = [f for f in faces if f.calc_center_median().y > 0.06 and f.calc_center_median().z < 1.5]
        bmesh.ops.delete(bm, geom=front, context="FACES")
        rest = [f for f in bm.faces if f.material_index == 0]
        ext = bmesh.ops.extrude_face_region(bm, geom=rest)
        inner = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
        for v in inner:
            v.co = Vector((0, -0.02, 1.33)) + (v.co - Vector((0, -0.02, 1.33))) * 0.93
        new_faces = {f for v in inner for f in v.link_faces}
        set_material(new_faces, 1)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        # フードの先（後ろに垂れる小さな角）
        add_cylinder(
            bm, 0.08, 0.0, 0.22, 8, (0, -0.27, 1.5), 0,
            matrix=Matrix.Rotation(math.radians(-120), 4, "X"),
        )

    objects.append(_join_as("Head", [_part("Head", head, mats)], (0, 0, 1.06)))

    for side, sx in (("L", -1), ("R", 1)):
        def arm(bm, sx=sx):
            add_cylinder(bm, 0.065, 0.055, 0.34, 10, (sx * 0.22, 0, 0.82), 0)
            add_sphere(bm, 0.06, (sx * 0.22, 0.01, 0.62), subdiv=2, material_index=3)

        objects.append(_join_as("Arm" + side, [_part("Arm" + side, arm, mats)], (sx * 0.2, 0, 0.98)))

        def leg(bm, sx=sx):
            add_cylinder(bm, 0.07, 0.065, 0.32, 10, (sx * 0.11, 0, 0.3), 6)
            verts, faces = add_cube(bm, (0.13, 0.2, 0.12), (sx * 0.11, 0.035, 0.06), 7)
            bmesh.ops.bevel(
                bm, geom=list(verts) + list({e for v in verts for e in v.link_edges}),
                offset=0.04, segments=3, affect="EDGES", clamp_overlap=True, material=7,
            )

        objects.append(_join_as("Leg" + side, [_part("Leg" + side, leg, mats)], (sx * 0.11, 0, 0.44)))

    root = bpy.data.objects.new("Traveler", None)
    bpy.context.collection.objects.link(root)
    for obj in objects:
        obj.parent = root
        obj.matrix_parent_inverse = root.matrix_world.inverted()
    save_and_export("traveler", [root] + objects)


# --- 置物 ---------------------------------------------------------------------


def build_tree(name, file_name, seed, height):
    reset_scene()
    bark = material("Bark", "#a47552", 0.9)
    leaves = material("Leaves", "#86c56a", 0.8)
    leaves_light = material("LeavesLight", "#a9d886", 0.8)
    rng = random.Random(seed)
    bm = bmesh.new()
    add_cylinder(bm, 0.14, 0.08, height, 7, (0, 0, height / 2), 0)
    blobs = [(0.0, 0.0, height + 0.15, 0.62), (0.25, 0.1, height - 0.15, 0.45),
             (-0.22, -0.15, height - 0.05, 0.48), (0.05, -0.05, height + 0.6, 0.42)]
    for i, (x, y, z, r) in enumerate(blobs):
        verts, _ = add_sphere(bm, r, (x, y, z), (1, 1, 0.9), subdiv=3, material_index=1 + i % 2)
        for v in verts:
            v.co += Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * 0.015
    obj = mesh_object(name, bm, [bark, leaves, leaves_light], smooth_angle=60)
    save_and_export(file_name, [obj])


def build_props():
    # 小石
    reset_scene()
    stone = material("Stone", "#d6ccbb", 0.85)
    bm = bmesh.new()
    add_sphere(bm, 0.25, (0, 0, 0.1), (1.2, 0.9, 0.6), subdiv=3)
    add_sphere(bm, 0.14, (0.28, 0.12, 0.05), (1, 0.8, 0.6), subdiv=3)
    jitter(bm, 0.012, 3)
    save_and_export("pebbles", [mesh_object("Pebbles", bm, [stone], smooth_angle=60)])

    # 草むら
    reset_scene()
    blade = material("GrassBlade", "#7dbb5a", 0.85)
    blade_light = material("GrassBladeLight", "#a4d47c", 0.85)
    rng = random.Random(7)
    bm = bmesh.new()
    for i in range(9):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0.0, 0.14)
        h = rng.uniform(0.18, 0.34)
        tilt = Matrix.Rotation(rng.uniform(-0.35, 0.35), 4, "X") @ Matrix.Rotation(a, 4, "Z")
        verts, _ = add_cylinder(bm, 0.03, 0.0, h, 3, (0, 0, 0), i % 2, matrix=tilt)
        bmesh.ops.translate(bm, vec=Vector((math.cos(a) * r, math.sin(a) * r, h / 2)), verts=verts)
    save_and_export("grass_tuft", [mesh_object("GrassTuft", bm, [blade, blade_light])])

    # 花
    reset_scene()
    stem = material("Stem", "#4f8f3c", 0.9)
    petal = material("Petal", "#f7c6cf", 0.6)
    center = material("FlowerCenter", "#f2b84b", 0.6)
    bm = bmesh.new()
    add_cylinder(bm, 0.012, 0.012, 0.22, 5, (0, 0, 0.11), 0)
    for i in range(5):
        a = math.tau * i / 5
        add_sphere(bm, 0.035, (math.cos(a) * 0.04, math.sin(a) * 0.04, 0.23), (1, 1, 0.4), 1, 1)
    add_sphere(bm, 0.025, (0, 0, 0.235), subdiv=1, material_index=2)
    save_and_export("flower", [mesh_object("Flower", bm, [stem, petal, center], smooth_angle=50)])


def build_checkpoint_pad():
    reset_scene()
    stone = material("PadStone", "#e2c08f", 0.8)
    glow = material("PadGlow", "#b6e59a", 0.4, emission="#b6e59a", strength=1.2)
    bm = bmesh.new()
    verts, _ = add_cylinder(bm, 0.95, 0.9, 0.12, 24, (0, 0, 0.06), 0)
    top = [f for f in bm.faces if f.calc_center_median().z > 0.11 and f.normal.z > 0.9]
    bmesh.ops.inset_individual(bm, faces=top, thickness=0.12, depth=0.0)
    ring = bmesh.ops.inset_individual(bm, faces=top, thickness=0.08, depth=-0.02)
    set_material(ring["faces"], 1)
    bmesh.ops.inset_individual(bm, faces=top, thickness=0.05, depth=0.02)
    for i in range(4):
        a = math.tau * i / 4 + math.pi / 4
        add_cube(bm, (0.14, 0.14, 0.22), (math.cos(a) * 0.82, math.sin(a) * 0.82, 0.16), 0)
        add_sphere(bm, 0.05, (math.cos(a) * 0.82, math.sin(a) * 0.82, 0.32), subdiv=1, material_index=1)
    save_and_export("checkpoint_pad", [mesh_object("CheckpointPad", bm, [stone, glow])])


def build_goal_beacon():
    """到達目標の目印: 石の台と、上に浮かぶ光る結晶（結晶は別オブジェクトでゲーム側が回す）。"""
    reset_scene()
    stone = material("BeaconStone", "#e6d8bd", 0.85)
    glow = material("BeaconGlow", "#ffd98a", 0.4, emission="#ffd98a", strength=2.0)
    bm = bmesh.new()
    add_cylinder(bm, 0.32, 0.22, 1.1, 4, (0, 0, 0.55), 0, matrix=Matrix.Rotation(math.pi / 4, 4, "Z"))
    add_cylinder(bm, 0.42, 0.42, 0.12, 4, (0, 0, 0.06), 0, matrix=Matrix.Rotation(math.pi / 4, 4, "Z"))
    pillar = mesh_object("BeaconPillar", bm, [stone])
    bm = bmesh.new()
    add_cylinder(bm, 0.18, 0.0, 0.26, 4, (0, 0, 0.13), 0)
    add_cylinder(bm, 0.0, 0.18, 0.26, 4, (0, 0, -0.13), 0)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    crystal = mesh_object("Crystal", bm, [glow])
    crystal.location = (0, 0, 1.55)
    root = bpy.data.objects.new("GoalBeacon", None)
    bpy.context.collection.objects.link(root)
    pillar.parent = root
    crystal.parent = root
    save_and_export("goal_beacon", [root, pillar, crystal])


BUILDERS = {
    "grass": build_grass_cell,
    "rock": build_rock_cell,
    "sandstone": build_sandstone_cell,
    "island": build_island_base,
    "block": build_ability_block,
    "traveler": build_traveler,
    "tree": lambda: (
        build_tree("TreeRound", "tree_round", 31, 1.3),
        build_tree("TreeTall", "tree_tall", 47, 1.9),
    ),
    "props": build_props,
    "checkpoint": build_checkpoint_pad,
    "goal": build_goal_beacon,
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    names = argv or list(BUILDERS)
    for name in names:
        BUILDERS[name]()


if __name__ == "__main__":
    main()
