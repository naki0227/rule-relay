class_name ModelLibrary
extends RefCounted
## Blender から書き出した .glb（assets/models）を読み込む窓口。原本は art/source の .blend で、
## 生成スクリプトは art/scripts/build_assets.py。モデルは見た目だけで、当たり判定はゲーム側の形を使う。

const DIR: String = "res://assets/models/%s.glb"

static var _scenes: Dictionary[String, PackedScene] = {}
static var _meshes: Dictionary[String, Mesh] = {}


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
