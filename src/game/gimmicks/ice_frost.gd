class_name IceFrost
extends Node3D
## 氷のセルの見た目の仕上げ: 上面に、透けてつやのある霜の板を重ねる（地形のメッシュの色は淡い水色）。
## 氷のセルを動くブロックにすると地形から抜けるので、抜けた・戻ったときに霜の板も並べ直す
## （動くブロックは ice_cell のモデル自体が霜の見た目）。当たり判定は持たない。

## 霜の色（art/scripts/build_nature.py の ice_cell の霜と同じ）。
const FROST := Color("#f2fbff")
## 並べ直すかを確かめる間隔（秒）。セルを抜くのは能力を渡したときだけなので、毎フレームは見ない。
const CHECK_PERIOD: float = 0.25

var terrain: TerrainGrid
var plates: MultiMeshInstance3D
var _shown: Array[Vector3i] = []
var _wait: float = 0.0


func _ready() -> void:
	name = "IceFrost"
	plates = MultiMeshInstance3D.new()
	plates.name = "Plates"
	plates.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var slab := BoxMesh.new()
	slab.size = Vector3(0.9, 0.035, 0.9)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(FROST, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.05
	mat.metallic_specular = 0.9
	mat.clearcoat_enabled = true
	mat.rim_enabled = true
	mat.rim = 0.6
	slab.material = mat
	multimesh.mesh = slab
	plates.multimesh = multimesh
	add_child(plates)
	refresh()


func _process(delta: float) -> void:
	_wait += delta
	if _wait >= CHECK_PERIOD:
		_wait = 0.0
		refresh()


## 上が空いている氷のセルに霜の板を並べる（並びが変わったときだけ作り直す）。
func refresh() -> void:
	var tops: Array[Vector3i] = []
	for cell: Vector3i in terrain.cells:
		if terrain.cells[cell] == "ice" and not terrain.cells.has(cell + Vector3i.UP):
			tops.append(cell)
	tops.sort()
	if tops == _shown:
		return
	_shown = tops
	plates.multimesh.instance_count = tops.size()
	for i in tops.size():
		var at := Vector3(tops[i]) + Vector3(0.5, 1.0 + 0.012, 0.5)
		plates.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, at))


func plate_count() -> int:
	return _shown.size()
