class_name TerrainBuilder
extends RefCounted
## 動かない地形をセル単位の箱で作る。見た目はセルごとの立方体（マス目が読めるように隙間を空ける）、
## 当たり判定は指定した直方体ごとにまとめる。


## min_cell〜max_cell（両端を含む）を埋めた地形を parent に追加する。
static func add_box(parent: Node3D, min_cell: Vector3i, max_cell: Vector3i, color: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Tuning.LAYER_TERRAIN
	body.collision_mask = 0
	var size := Vector3(max_cell - min_cell + Vector3i.ONE)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = Vector3(min_cell) + size * 0.5
	body.add_child(shape)

	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * 0.97
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	cube.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = cube
	multimesh.instance_count = int(size.x * size.y * size.z)
	var index := 0
	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			for z in range(min_cell.z, max_cell.z + 1):
				var origin := Vector3(x, y, z) + Vector3.ONE * 0.5
				multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, origin))
				index += 1
	var visual := MultiMeshInstance3D.new()
	visual.multimesh = multimesh
	body.add_child(visual)
	parent.add_child(body)
