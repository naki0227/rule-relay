class_name TerrainBuilder
extends RefCounted
## 動かない地形をセル単位の箱で作る。見た目はセルごとの立方体（マス目が読めるように隙間を空ける）、
## 当たり判定は指定した直方体ごとにまとめる。


## min_cell〜max_cell（両端を含む）を埋めた地形を parent に追加する。
## model_name を指定すると、そのモデル（1x1x1、中心が原点）を各セルに並べる。セルごとに
## 90度単位で向きを変えて、同じ形の繰り返しを目立たなくする（向きは座標から決まり毎回同じ）。
## with_visual を false にすると当たり判定だけを作る（見た目は別のモデルで出すとき）。
static func add_box(
	parent: Node3D,
	min_cell: Vector3i,
	max_cell: Vector3i,
	color: Color,
	model_name: String = "",
	with_visual: bool = true
) -> void:
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
	if not with_visual:
		parent.add_child(body)
		return

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	if model_name.is_empty():
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE * 0.97
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		cube.material = material
		multimesh.mesh = cube
	else:
		multimesh.mesh = ModelLibrary.mesh(model_name)
	multimesh.instance_count = int(size.x * size.y * size.z)
	var index := 0
	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			for z in range(min_cell.z, max_cell.z + 1):
				var origin := Vector3(x, y, z) + Vector3.ONE * 0.5
				var turns := absi((x * 73856093) ^ (z * 19349663)) % 4
				var basis := Basis(Vector3.UP, float(turns) * PI * 0.5)
				multimesh.set_instance_transform(index, Transform3D(basis, origin))
				index += 1
	var visual := MultiMeshInstance3D.new()
	visual.multimesh = multimesh
	body.add_child(visual)
	parent.add_child(body)
