"""動くもの（プレイヤー・生き物）に骨格（Armature）とアニメーション（Action）を付けて書き出す部品。

方針（2026-11-21 本人の指示「生き物とかは部分ごとに作り Rig とかもいるやつは使いながらで」）:
- 体・頭・耳・しっぽ・手足・羽などは別々のオブジェクト（部品）で作る。部品は名前を保ったまま書き出す。
- 部品ごとに 1 本の骨へ重み 1.0 で結ぶ（固い結び方。部品がゆがまず、ブロックの箱庭らしい手触りを保つ）。
- 骨はどれも関節から上（+Z）へ向ける。骨の向きがそろうので、ポーズの回転は次の意味になる:
  - 骨のローカル X 回転 = 世界の X 軸まわり（前後に振る。正で下の先が前 +Y へ出る）
  - 骨のローカル Y 回転 = 世界の Z 軸まわり（左右を向く）
  - 骨のローカル Z 回転 = 世界の -Y 軸まわり（横へ傾ける・腕を横へ上げる）
  - 骨のローカル Y 移動 = 世界の上下
- アニメーションは Action として作り、NLA に積んでから glTF に「アクションごと」で書き出す。
  Godot では AnimationPlayer の idle / walk / happy（プレイヤーは jump も）になる。
- 時間は 24 fps。繰り返す動きは最初と最後のキーを同じにする（ループはゲーム側で付ける）。
"""

import bpy
from mathutils import Vector

import build_assets as base

FPS = 24


def armature(name, bones):
    """骨格を作る。bones は [(骨の名前, 関節の位置, 親の名前 or None, 長さ), ...]。骨は関節から +Z へ伸びる。"""
    data = bpy.data.armatures.new(name + "Armature")
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    made = {}
    for bone_name, head, parent, length in bones:
        bone = data.edit_bones.new(bone_name)
        bone.head = Vector(head)
        bone.tail = Vector(head) + Vector((0.0, 0.0, length))
        bone.roll = 0.0
        if parent is not None:
            bone.parent = made[parent]
            bone.use_connect = False
        made[bone_name] = bone
    bpy.ops.object.mode_set(mode="OBJECT")
    for pose_bone in obj.pose.bones:
        pose_bone.rotation_mode = "XYZ"
    return obj


def bind(part, rig, bone_name):
    """部品 part を骨 bone_name に重み 1.0 で結ぶ（Armature モディファイア＋頂点グループ）。"""
    group = part.vertex_groups.new(name=bone_name)
    group.add(list(range(len(part.data.vertices))), 1.0, "REPLACE")
    modifier = part.modifiers.new("Armature", "ARMATURE")
    modifier.object = rig
    world = part.matrix_world.copy()
    part.parent = rig
    part.matrix_world = world


def action(rig, name, frames, keys):
    """アクションを1つ作り、NLA のトラックに積む。

    keys は {骨の名前: [(フレーム, 回転(x, y, z) or None, 移動(x, y, z) or None, 拡大 or None), ...]}。
    回転はラジアン（骨のローカル軸。上の説明）、移動は骨のローカル（Y が上）、拡大は (x, y, z)。
    指定しなかった骨は、最初と最後のフレームに休みの姿勢を打つ（別のアクションの姿勢が残らないように）。
    """
    rig.animation_data_create()
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data.action = act
    for pose_bone in rig.pose.bones:
        _rest(pose_bone)
    for pose_bone in rig.pose.bones:
        if pose_bone.name in keys:
            continue
        for frame in (1, frames + 1):
            _key(pose_bone, frame)
    for bone_name, entries in keys.items():
        pose_bone = rig.pose.bones[bone_name]
        for frame, rotation, location, scale in entries:
            _rest(pose_bone)
            if rotation is not None:
                pose_bone.rotation_euler = rotation
            if location is not None:
                pose_bone.location = location
            if scale is not None:
                pose_bone.scale = scale
            _key(pose_bone, frame)
    for curve in _curves(act):
        for point in curve.keyframe_points:
            point.interpolation = "BEZIER"
            point.easing = "AUTO"
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, 1, act)
    strip.action_frame_end = frames + 1
    track.mute = True
    rig.animation_data.action = None
    for pose_bone in rig.pose.bones:
        _rest(pose_bone)
    return act


def _curves(act):
    """アクションの F カーブ（Blender 4.4 以降のスロット付きアクションにも対応）。"""
    if hasattr(act, "fcurves") and len(act.fcurves) > 0:
        return list(act.fcurves)
    found = []
    for layer in getattr(act, "layers", []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                found.extend(bag.fcurves)
    return found


def _rest(pose_bone):
    pose_bone.rotation_euler = (0.0, 0.0, 0.0)
    pose_bone.location = (0.0, 0.0, 0.0)
    pose_bone.scale = (1.0, 1.0, 1.0)


def _key(pose_bone, frame):
    pose_bone.keyframe_insert("rotation_euler", frame=frame)
    pose_bone.keyframe_insert("location", frame=frame)
    pose_bone.keyframe_insert("scale", frame=frame)


def cycle(frames, values):
    """繰り返す動きのキー: values を等間隔に並べ、最後に最初の値を足す。[(フレーム, 値), ...]"""
    step = frames / len(values)
    out = [(1 + round(step * i), v) for i, v in enumerate(values)]
    out.append((frames + 1, values[0]))
    return out


def save_and_export_rigged(name, objects):
    """骨格付きのモデルを .blend と .glb（骨・皮・アクションごとのアニメーション）に書き出す。"""
    base.SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    base.EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    bpy.context.scene.render.fps = FPS
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(base.SOURCE_DIR / f"{name}.blend"), compress=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=str(base.EXPORT_DIR / f"{name}.glb"),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_extras=False,
        export_cameras=False,
        export_lights=False,
        export_skins=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_anim_slide_to_zero=True,
        export_reset_pose_bones=True,
        export_def_bones=False,
    )
    print(f"exported {name} (rigged)")
