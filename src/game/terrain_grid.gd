class_name TerrainGrid
extends Node3D
## 動かない地形のセル。見た目は TerrainMesher でつないだ1つのメッシュ、当たり判定は東西に続くセルを
## まとめた箱（行ごと。セルの数だけ箱を作ると島を作るだけで 0.5 秒かかったため）。
## どのセルも、能力を渡すと地形から抜けて動くブロックになる（GameWorld.promote_cell。
## 2026-11-19 本人の判断: どのブロックにも渡せる）。抜けたセルはチェックポイントで戻る。
## 各列のいちばん下のセルの下には、見えない岩盤（当たり判定だけ）を置く。下のセルを動くブロックにしても、
## 支えを失って島の下へ落ちないようにするため。

var cells: Dictionary[Vector3i, String] = {}

var _body: StaticBody3D
## 行（y, z）ごとの当たり判定の箱。
var _rows: Dictionary[Vector2i, Array] = {}
var _visual: MeshInstance3D
var _dirty: bool = false


func _ready() -> void:
	_body = StaticBody3D.new()
	_body.name = "TerrainBody"
	_body.collision_layer = Tuning.LAYER_TERRAIN
	_body.collision_mask = 0
	add_child(_body)
	_visual = MeshInstance3D.new()
	_visual.name = "TerrainMesh"
	add_child(_visual)


## boxes: [[最小のセル, 最大のセル（両端を含む）, 種類], ...]
func build(boxes: Array) -> void:
	for box: Array in boxes:
		var lo := box[0] as Vector3i
		var hi := box[1] as Vector3i
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					cells[Vector3i(x, y, z)] = String(box[2])
	var rows := {}
	for cell in cells:
		rows[Vector2i(cell.y, cell.z)] = true
	for row: Vector2i in rows:
		_rebuild_row(row)
	_add_bedrock()
	rebuild()


func has_cell(cell: Vector3i) -> bool:
	return cells.has(cell)


func is_terrain_body(collider: Object) -> bool:
	return collider == _body


## 光線が当たった点と面の向きから、当たったセル。
static func cell_at_hit(hit_position: Vector3, hit_normal: Vector3) -> Vector3i:
	var inside := hit_position - hit_normal * 0.05
	return Vector3i(floori(inside.x), floori(inside.y), floori(inside.z))


## セルを地形から抜く（動くブロックにするため）。種類を返す。
func remove_cell(cell: Vector3i) -> String:
	var kind := String(cells.get(cell, ""))
	if kind == "":
		return ""
	cells.erase(cell)
	_rebuild_row(Vector2i(cell.y, cell.z))
	_mark_dirty()
	return kind


## 抜いたセルを地形に戻す（チェックポイントの復元）。
func restore_cell(cell: Vector3i, kind: String) -> void:
	if cells.has(cell):
		return
	cells[cell] = kind
	_rebuild_row(Vector2i(cell.y, cell.z))
	_mark_dirty()


func rebuild() -> void:
	_dirty = false
	_visual.mesh = TerrainMesher.build(cells)


func _mark_dirty() -> void:
	if not _dirty:
		_dirty = true
		rebuild.call_deferred()


## 行（y, z）の当たり判定を、東西に続くセルごとに1つの箱で作り直す。
func _rebuild_row(row: Vector2i) -> void:
	for shape: CollisionShape3D in _rows.get(row, []):
		shape.free()
	var xs: Array[int] = []
	for cell in cells:
		if cell.y == row.x and cell.z == row.y:
			xs.append(cell.x)
	xs.sort()
	var shapes: Array[CollisionShape3D] = []
	var i := 0
	while i < xs.size():
		var start := xs[i]
		while i + 1 < xs.size() and xs[i + 1] == xs[i] + 1:
			i += 1
		shapes.append(_add_box(Vector3(start, row.x, row.y), Vector3(xs[i] - start + 1, 1, 1)))
		i += 1
	_rows[row] = shapes


func _add_box(corner: Vector3, size: Vector3) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = corner + size * 0.5
	_body.add_child(shape)
	return shape


func _add_bedrock() -> void:
	var lowest: Dictionary[Vector2i, int] = {}
	for cell in cells:
		var column := Vector2i(cell.x, cell.z)
		lowest[column] = mini(lowest.get(column, cell.y), cell.y)
	# 岩盤も、同じ高さで東西に続く列をまとめて1つの箱にする
	var runs := {}
	for column in lowest:
		var key := Vector2i(lowest[column] - 1, column.y)
		if not runs.has(key):
			runs[key] = []
		(runs[key] as Array).append(column.x)
	for key: Vector2i in runs:
		var xs := runs[key] as Array
		xs.sort()
		var i := 0
		while i < xs.size():
			var start := int(xs[i])
			while i + 1 < xs.size() and int(xs[i + 1]) == int(xs[i]) + 1:
				i += 1
			_add_box(Vector3(start, key.x, key.y), Vector3(int(xs[i]) - start + 1, 1, 1))
			i += 1
