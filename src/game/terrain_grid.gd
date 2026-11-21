class_name TerrainGrid
extends Node3D
## 動かない地形のセル。見た目は TerrainMesher でつないだ1つのメッシュ、当たり判定は東西に続くセルを
## まとめた箱（行ごと。セルの数だけ箱を作ると島を作るだけで 0.5 秒かかったため）。
## どのセルも、能力を渡すと地形から抜けて動くブロックになる（GameWorld.promote_cell。
## 2026-11-19 本人の判断: どのブロックにも渡せる）。抜けたセルはチェックポイントで戻る。
## 島の地面（いちばん下のセルが y = -1 以下の列）の下には、厚さ FOUNDATION_DEPTH の土台を置く
## （2026-11-21 本人の試遊「浮島の地面一段しかないからめっちゃすぐ抜ける」）。土台は見える土と岩で、
## 能力は渡せない（セルではない）。上のセルを動くブロックにしても、そこは土台の床が見える浅い窪みになり、
## 島の下の空は見えない。地面の上面・縁の高さは変わらない（土台は今までの一番下のセルより下だけ）。
## 宙に浮いた列（いちばん下のセルが y = 0 以上。台座・壁など）の下は、今までどおり見えない岩盤（当たり判定
## だけ・1 マス）を置く。下のセルを動くブロックにしても、支えを失って島の下へ落ちないようにするため。

## 島の地面の下の土台の厚さ（マス）。表のセル 1 段＋土台 3 段で、地面の島は 4 段の厚さに見える。
const FOUNDATION_DEPTH: int = 3
## この高さ以下から始まる列を「島の地面」とみなし、土台を付ける（IslandMap の地面は y = -1 まで埋める）。
const GROUNDED_Y: int = -1

var cells: Dictionary[Vector3i, String] = {}
## 土台のマス → 見た目の種類（TerrainMesher.BASE_COLORS）。当たり判定はあるが、能力は渡せない。
var foundation: Dictionary[Vector3i, String] = {}
## 地形から抜けた（動くブロックになった）セル。その下の土台の上面を見せるために覚えておく。
var _removed: Dictionary[Vector3i, bool] = {}

var _body: StaticBody3D
## 行（y, z）ごとの当たり判定の箱。
var _rows: Dictionary[Vector2i, Array] = {}
var _visual: MeshInstance3D
## 土台の見た目（変わらないので、組み立てるときに一度だけ作る）。
var _base_visual: MeshInstance3D
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
	_base_visual = MeshInstance3D.new()
	_base_visual.name = "FoundationMesh"
	add_child(_base_visual)


## boxes: [[最小のセル, 最大のセル（両端を含む）, 種類], ...]
func build(boxes: Array) -> void:
	for box: Array in boxes:
		var lo := box[0] as Vector3i
		var hi := box[1] as Vector3i
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					cells[Vector3i(x, y, z)] = String(box[2])
	# 行ごとの x を一度にまとめる（行ごとに全セルを調べ直すと、広い広場で組み立てに 1 秒かかった）。
	# 当たり判定の箱は、物理の世界から外した体に足してから戻す（体が世界にあると、箱を 1 つ足すたびに
	# 物理エンジンが形を作り直し、箱の数の 2 乗の時間がかかる）
	remove_child(_body)
	var rows: Dictionary[Vector2i, Array] = {}
	for cell in cells:
		var row := Vector2i(cell.y, cell.z)
		if not rows.has(row):
			rows[row] = []
		rows[row].append(cell.x)
	for row: Vector2i in rows:
		_build_row(row, rows[row])
	_add_foundation_and_bedrock()
	add_child(_body)
	_base_visual.mesh = TerrainMesher.build_foundation(foundation, cells)
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
	_removed[cell] = true
	_rebuild_row(Vector2i(cell.y, cell.z))
	_mark_dirty()
	return kind


## 抜いたセルを地形に戻す（チェックポイントの復元）。
func restore_cell(cell: Vector3i, kind: String) -> void:
	if cells.has(cell):
		return
	cells[cell] = kind
	_removed.erase(cell)
	_rebuild_row(Vector2i(cell.y, cell.z))
	_mark_dirty()


func rebuild() -> void:
	_dirty = false
	# 抜けたセルの下が土台なら、その上面（窪みの床）を見せる
	var floors: Array[Vector3i] = []
	for cell in _removed:
		var below := cell + Vector3i.DOWN
		if foundation.has(below) and not cells.has(cell):
			floors.append(below)
	_visual.mesh = TerrainMesher.build(cells, foundation, floors)


func _mark_dirty() -> void:
	if not _dirty:
		_dirty = true
		rebuild.call_deferred()


## 行（y, z）の当たり判定を、東西に続くセルごとに1つの箱で作り直す。
func _rebuild_row(row: Vector2i) -> void:
	var xs: Array = []
	for cell in cells:
		if cell.y == row.x and cell.z == row.y:
			xs.append(cell.x)
	_build_row(row, xs)


func _build_row(row: Vector2i, found: Array) -> void:
	for shape: CollisionShape3D in _rows.get(row, []):
		shape.free()
	var xs: Array[int] = []
	xs.assign(found)
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


## 土台（島の地面の列）と岩盤（宙に浮いた列）の当たり判定を作る。どちらも、同じ高さの範囲で東西に続く列を
## まとめて1つの箱にする（列ごとに箱を作ると、広い広場で物理の形が数千個になる）。
func _add_foundation_and_bedrock() -> void:
	var lowest: Dictionary[Vector2i, int] = {}
	for cell in cells:
		var column := Vector2i(cell.x, cell.z)
		lowest[column] = mini(lowest.get(column, cell.y), cell.y)
	# 箱の鍵: Vector3i(一番下の y, 高さ, z) → x の一覧
	var runs := {}
	for column in lowest:
		var low := lowest[column]
		var depth := 1
		if low <= GROUNDED_Y:
			depth = FOUNDATION_DEPTH
			var kind := _base_kind(String(cells[Vector3i(column.x, low, column.y)]))
			for d in FOUNDATION_DEPTH:
				foundation[Vector3i(column.x, low - 1 - d, column.y)] = (
					kind if d == 0 else "base_deep"
				)
		var key := Vector3i(low - depth, depth, column.y)
		if not runs.has(key):
			runs[key] = []
		(runs[key] as Array).append(column.x)
	for key: Vector3i in runs:
		var xs := runs[key] as Array
		xs.sort()
		var i := 0
		while i < xs.size():
			var start := int(xs[i])
			while i + 1 < xs.size() and int(xs[i + 1]) == int(xs[i]) + 1:
				i += 1
			_add_box(Vector3(start, key.x, key.z), Vector3(int(xs[i]) - start + 1, key.y, 1))
			i += 1


## 土台のいちばん上の段の見た目（上のセルの種類に合わせる）。
static func _base_kind(kind: String) -> String:
	match kind:
		"grass":
			return "base_dirt"
		"sand":
			return "base_sand"
	return "base_rock"
