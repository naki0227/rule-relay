class_name ModelLibrary
extends RefCounted
## Blender から書き出した .glb（assets/models）を読み込む窓口。原本は art/source の .blend で、
## 生成スクリプトは art/scripts/build_assets.py。モデルは見た目だけで、当たり判定はゲーム側の形を使う。

const DIR: String = "res://assets/models/%s.glb"

static var _scenes: Dictionary[String, PackedScene] = {}
static var _meshes: Dictionary[String, Mesh] = {}
static var _parts: Dictionary[String, Array] = {}


static func scene(model_name: String) -> PackedScene:
	if not _scenes.has(model_name):
		_scenes[model_name] = load(DIR % model_name) as PackedScene
		Foliage.prepare(model_name, _scenes[model_name])  # 草花・木の葉のそよぎ（見た目だけ）
	return _scenes[model_name]


static func instantiate(model_name: String) -> Node3D:
	return scene(model_name).instantiate() as Node3D


## 1つのメッシュだけを持つモデルのメッシュ（MultiMesh 用）。
static func mesh(model_name: String) -> Mesh:
	if not _meshes.has(model_name):
		var root := instantiate(model_name)
		var found := root.find_children("*", "MeshInstance3D", true, false)
		assert(not found.is_empty(), "no mesh in %s" % model_name)
		_meshes[model_name] = (found[0] as MeshInstance3D).mesh
		root.free()
	return _meshes[model_name]


## MultiMesh で並べるための部品: [[メッシュ, モデルの根からの変換, 影を落とすか], ...]。
## 動き（AnimationPlayer・骨）や、ノードに付けた上書きのマテリアルがあるモデルは、並べると見た目が変わるので
## 空を返す（そのモデルはノードのまま置く）。
static func parts(model_name: String) -> Array:
	if _parts.has(model_name):
		return _parts[model_name]
	var root := instantiate(model_name)
	var found: Array = []
	var plain := (
		root.find_children("*", "AnimationPlayer", true, false).is_empty()
		and root.find_children("*", "Skeleton3D", true, false).is_empty()
	)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null or mesh_instance.material_override != null:
			plain = false
			break
		for i in mesh_instance.get_surface_override_material_count():
			if mesh_instance.get_surface_override_material(i) != null:
				plain = false
		var offset := Transform3D.IDENTITY
		var walk: Node = mesh_instance
		while walk != root and walk is Node3D:
			offset = (walk as Node3D).transform * offset
			walk = walk.get_parent()
		found.append(
			[
				mesh_instance.mesh,
				offset,
				mesh_instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			]
		)
	root.free()
	_parts[model_name] = found if plain else []
	return _parts[model_name]


## name という名前のマテリアルを、色を変えた複製で上書きする（ブロックのパネルの色分けなど）。
static func tint_material(root: Node, material_name: String, color: Color) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for i in mesh_instance.mesh.get_surface_count():
			var base := mesh_instance.mesh.surface_get_material(i) as StandardMaterial3D
			if base != null and base.resource_name == material_name:
				var tinted := base.duplicate() as StandardMaterial3D
				tinted.albedo_color = color
				mesh_instance.set_surface_override_material(i, tinted)
