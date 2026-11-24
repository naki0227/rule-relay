class_name Foliage
extends RefCounted
## 草花・木の葉のそよぎ（docs/adr/0022-visual-direction-and-quality.md）。頂点シェーダーで、根もとは動かさず
## 先だけを揺らす。見た目だけで当たり判定は無い（草花はもとから当たり判定なし、木は幹の円柱のまま）。
## モデルを初めて読んだとき（ModelLibrary.scene）に、揺らす部分のマテリアルを同じ色のシェーダーに置きかえる。
## メッシュはモデルの全部の複製で共有されるので、置きかえは 1 回だけ。画質の低では揺れを 0 にする。

const SHADER := preload("res://assets/shaders/foliage_sway.gdshader")

## 揺らすモデル → { マテリアルの名前: 揺れの大きさ（高さに対する割合） }。幹・鉢・花の芯は揺らさない。
const MODELS := {
	"flower": {"Stem": 0.16, "Petal": 0.16, "FlowerCenter": 0.16},
	"grass_tuft": {"GrassBlade": 0.2, "GrassBladeLight": 0.2},
	"tree_round": {"Leaves": 0.03, "LeavesLight": 0.03},
	"tree_tall": {"Leaves": 0.028, "LeavesLight": 0.028},
	"hub_planter": {"Leaves": 0.05, "LeavesLight": 0.05, "Bloom": 0.05},
}

static var _materials: Array[ShaderMaterial] = []
static var _enabled: bool = true


## モデルを読んだときに呼ぶ（揺らさないモデルなら何もしない）。
static func prepare(model_name: String, packed: PackedScene) -> void:
	if not MODELS.has(model_name) or packed == null:
		return
	var parts: Dictionary = MODELS[model_name]
	var root := packed.instantiate() as Node3D
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		var height := maxf(mesh.get_aabb().end.y, 0.05)
		for i in mesh.get_surface_count():
			var base := mesh.surface_get_material(i) as StandardMaterial3D
			if base == null or not parts.has(base.resource_name):
				continue
			var sway := ShaderMaterial.new()
			sway.resource_name = base.resource_name
			sway.shader = SHADER
			sway.set_shader_parameter(&"albedo", base.albedo_color)
			sway.set_shader_parameter(&"roughness", base.roughness)
			sway.set_shader_parameter(&"height", height)
			sway.set_shader_parameter(&"amount", float(parts[base.resource_name]))
			sway.set_shader_parameter(&"strength", 1.0 if _enabled else 0.0)
			mesh.surface_set_material(i, sway)
			_materials.append(sway)
	root.free()


## 揺れの入り切り（画質）。読んだ後のモデルにもすぐ効く。
static func set_enabled(on: bool) -> void:
	if on == _enabled:
		return
	_enabled = on
	for material in _materials:
		material.set_shader_parameter(&"strength", 1.0 if on else 0.0)


static func is_enabled() -> bool:
	return _enabled
