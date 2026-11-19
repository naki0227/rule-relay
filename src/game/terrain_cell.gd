class_name TerrainCell
extends Node3D
## 照準が地形のセルに当たったときの「狙っているセル」の目印（付与先の代わり）。
## 能力を渡すと、GameWorld がこのセルを動くブロックにしてから渡す。entity_id は -1（まだ付与先ではない）。

var entity_id: int = -1
var cell: Vector3i = Vector3i.ZERO

var _outline: MeshInstance3D


func _ready() -> void:
	_outline = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 1.06
	_outline.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	mat.albedo_color = UiTheme.SUN
	_outline.material_override = mat
	_outline.visible = false
	add_child(_outline)


func point_at(new_cell: Vector3i) -> void:
	cell = new_cell
	global_position = Vector3(cell) + Vector3.ONE * 0.5


func set_highlight(on: bool) -> void:
	if _outline != null:
		_outline.visible = on
