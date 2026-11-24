class_name TerrainGrid
extends Node3D
## 動かない地形のセル。見た目は TerrainMesher でつないだメッシュを CHUNK マス四方の区画ごとに分けたもの、
## 当たり判定は東西に続くセルをまとめた箱（行ごと。セルの数だけ箱を作ると島を作るだけで 0.5 秒かかったため）。
## 区画に分けるのは、セルが抜けた・戻ったときに、そのまわりの区画だけを作り直すため（広場は 1 つのメッシュだと
## 作り直しに 1 回 0.15〜0.25 秒かかり、ブロックに能力を渡すたびに画面が止まった。2026-11-24 の性能の測定）。
## 区画ごとのメッシュは、カメラ・影の範囲の外にあれば描かれない（1 つのメッシュだと島の全部を毎回描いた）。
## 島の地面の下の土台も、同じ区画のメッシュに入れる（表と土台を別のメッシュにすると、描画の呼び出しが倍になる）。
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
## まとめて抜く・戻す（begin_batch〜end_batch）ときに、作り直す行がこれより多ければ、当たり判定の体を物理の世界から
## 外して作り直す（体が世界にあると、箱を 1 つ足し引きするたびに物理エンジンが体の形を全部作り直す。広場では
## 1 マスあたり 約 4 ms かかり、範囲付与の 81 マスで 0.3 秒止まった。2026-11-24 の性能の測定）。
const BATCH_DETACH_ROWS: int = 4
## 見た目のメッシュの区画の大きさ（東西・南北のマス。高さは分けない）。
const CHUNK: int = 16
## この高さ以下から始まる列を「島の地面」とみなし、土台を付ける（IslandMap の地面は y = -1 まで埋める）。
const GROUNDED_Y: int = -1

var cells: Dictionary[Vector3i, String] = {}
## 土台のマス → 見た目の種類（TerrainMesher.BASE_COLORS）。当たり判定はあるが、能力は渡せない。
var foundation: Dictionary[Vector3i, String] = {}
## 直前の作り直しで作った区画のメッシュの数（性能の予算のテスト用。tests/integration/test_perf_budget.gd）。
var rebuilt_chunks: int = 0
## 地形から抜けた（動くブロックになった）セル。その下の土台の上面を見せるために覚えておく。
var _removed: Dictionary[Vector3i, bool] = {}

var _body: StaticBody3D
## 行（y, z）ごとの当たり判定の箱。
var _rows: Dictionary[Vector2i, Array] = {}
## 行（y, z）→ その行のセルの x（当たり判定の作り直しで、全セルを調べ直さないため）。
var _row_xs: Dictionary[Vector2i, Dictionary] = {}
## 区画 → その区画のセル（区画だけを作り直すとき、全セルを調べ直さないため）。
var _chunk_cells: Dictionary[Vector2i, Dictionary] = {}
## 区画 → その区画の土台のマス（土台は変わらないので、組み立てるときに一度だけ作る）。
var _chunk_base: Dictionary[Vector2i, Array] = {}
## 区画 → 表のセルと土台のメッシュ（区画の鍵は chunk_of。1 区画で 1 回の描画の呼び出し）。
var _chunks: Dictionary[Vector2i, MeshInstance3D] = {}
## 作り直しを待っている区画。
var _dirty_chunks: Dictionary[Vector2i, bool] = {}
var _visual: Node3D
var _dirty: bool = false
## begin_batch の入れ子の深さと、その間に作り直しを待っている行。
var _batch: int = 0
var _batch_rows: Dictionary[Vector2i, bool] = {}


func _ready() -> void:
	_body = StaticBody3D.new()
	_body.name = "TerrainBody"
	_body.collision_layer = Tuning.LAYER_TERRAIN
	_body.collision_mask = 0
	add_child(_body)
	_visual = Node3D.new()
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
	# 行ごとの x を一度にまとめる（行ごとに全セルを調べ直すと、広い広場で組み立てに 1 秒かかった）。
	# 当たり判定の箱は、物理の世界から外した体に足してから戻す（体が世界にあると、箱を 1 つ足すたびに
	# 物理エンジンが形を作り直し、箱の数の 2 乗の時間がかかる）
	remove_child(_body)
	for cell in cells:
		_index(cell, true)
	for row: Vector2i in _row_xs:
		_build_row(row, _row_xs[row].keys())
	_add_foundation_and_bedrock()
	add_child(_body)
	_index_foundation()
	rebuild()


func has_cell(cell: Vector3i) -> bool:
	return cells.has(cell)


func is_terrain_body(collider: Object) -> bool:
	return collider == _body


## 高さ layer の、center を中心とする半径 radius の円の中のセル（範囲付与。マスの中心で判定する）。
## 円を囲む四角の中のマスだけを調べる（全セルを毎フレーム調べると、広場では 8,000 個を超える）。
func cells_in_disc(center: Vector3, radius: float, layer: int) -> Array[Vector3i]:
	var found: Array[Vector3i] = []
	var span := ceili(radius) + 1
	var cx := floori(center.x)
	var cz := floori(center.z)
	for x in range(cx - span, cx + span + 1):
		for z in range(cz - span, cz + span + 1):
			var cell := Vector3i(x, layer, z)
			var flat := Vector2(x + 0.5 - center.x, z + 0.5 - center.z)
			if flat.length() <= radius + 0.0001 and cells.has(cell):
				found.append(cell)
	return found


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
	_index(cell, false)
	_removed[cell] = true
	_rebuild_row(Vector2i(cell.y, cell.z))
	_mark_dirty(cell)
	return kind


## 抜いたセルを地形に戻す（チェックポイントの復元）。
func restore_cell(cell: Vector3i, kind: String) -> void:
	if cells.has(cell):
		return
	cells[cell] = kind
	_index(cell, true)
	_removed.erase(cell)
	_rebuild_row(Vector2i(cell.y, cell.z))
	_mark_dirty(cell)


## 見た目を全部の区画で作り直す（組み立てたとき）。
func rebuild() -> void:
	for chunk: Vector2i in _chunks:
		_dirty_chunks[chunk] = true
	for chunk: Vector2i in _chunk_cells:
		_dirty_chunks[chunk] = true
	for chunk: Vector2i in _chunk_base:
		_dirty_chunks[chunk] = true
	_rebuild_dirty()


## 区画の鍵（東西・南北の CHUNK マスごと）。
static func chunk_of(cell: Vector3i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / CHUNK), floori(float(cell.z) / CHUNK))


## 作り直しを待っている区画のメッシュを作る。セルの面・丸め・頂点の陰はまわり 1 マスで決まるので、
## 変わったセルのまわり 1 マスにかかる区画だけを作り直せば、全部を作り直したときと同じになる。
func _rebuild_dirty() -> void:
	_dirty = false
	rebuilt_chunks = _dirty_chunks.size()
	if _dirty_chunks.is_empty():
		return
	var emit: Dictionary[Vector2i, Array] = {}
	var floors: Dictionary[Vector2i, Array] = {}
	for chunk: Vector2i in _dirty_chunks:
		emit[chunk] = [] as Array[Vector3i]
		floors[chunk] = [] as Array[Vector3i]
	for chunk: Vector2i in _dirty_chunks:
		for cell: Vector3i in _chunk_cells.get(chunk, {}):
			(emit[chunk] as Array[Vector3i]).append(cell)
	# 抜けたセルの下が土台なら、その上面（窪みの床）を見せる
	for cell in _removed:
		var chunk := chunk_of(cell)
		var below := cell + Vector3i.DOWN
		if emit.has(chunk) and foundation.has(below) and not cells.has(cell):
			(floors[chunk] as Array[Vector3i]).append(below)
	for chunk: Vector2i in emit:
		var list := emit[chunk] as Array[Vector3i]
		var under := floors[chunk] as Array[Vector3i]
		var base: Array[Vector3i] = []
		base.assign(_chunk_base.get(chunk, []))
		var view := _chunks.get(chunk) as MeshInstance3D
		if list.is_empty() and under.is_empty() and base.is_empty():
			if view != null:
				view.mesh = null
			continue
		if view == null:
			view = MeshInstance3D.new()
			view.name = "Chunk_%d_%d" % [chunk.x, chunk.y]
			_visual.add_child(view)
			_chunks[chunk] = view
		view.mesh = TerrainMesher.build_chunk(cells, foundation, under, list, base)
	_dirty_chunks.clear()


## 待っている区画の作り直しを、いま行う（テスト・測定用。ふつうはそのコマの終わりにまとめて行う）。
func flush() -> void:
	_rebuild_dirty()


func _mark_dirty(cell: Vector3i) -> void:
	# 変わったセルと、そのまわり 8 マス（ななめも）の区画。面と丸めは東西南北のとなりで、頂点の陰
	# （TerrainMesher._face_ao）はななめのとなりでも変わる。区画の角なら最大 4 区画
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			_dirty_chunks[chunk_of(cell + Vector3i(dx, 0, dz))] = true
	if not _dirty:
		_dirty = true
		_rebuild_dirty.call_deferred()


## 土台のマスを区画ごとに分けておく（土台は変わらない。見た目は表のセルと同じ区画のメッシュに入れる）。
func _index_foundation() -> void:
	for cell: Vector3i in foundation:
		var chunk := chunk_of(cell)
		if not _chunk_base.has(chunk):
			_chunk_base[chunk] = [] as Array[Vector3i]
		(_chunk_base[chunk] as Array[Vector3i]).append(cell)


## 行ごとの x と、区画ごとのセルの索引を足す・消す。
func _index(cell: Vector3i, present: bool) -> void:
	var row := Vector2i(cell.y, cell.z)
	var chunk := chunk_of(cell)
	if present:
		if not _row_xs.has(row):
			_row_xs[row] = {}
		_row_xs[row][cell.x] = true
		if not _chunk_cells.has(chunk):
			_chunk_cells[chunk] = {}
		_chunk_cells[chunk][cell] = true
		return
	if _chunk_cells.has(chunk):
		_chunk_cells[chunk].erase(cell)
	if _row_xs.has(row):
		_row_xs[row].erase(cell.x)
		if _row_xs[row].is_empty():
			_row_xs.erase(row)


## まとめてセルを抜く・戻す前に呼ぶ（範囲付与・チェックポイントの復元）。当たり判定の作り直しを end_batch まで
## 待つ。その間は物理のコマを進めない（抜いたセルの当たり判定が残っているので、呼び出し側は同じ関数の中で
## end_batch まで呼ぶ）。
func begin_batch() -> void:
	_batch += 1


func end_batch() -> void:
	_batch = maxi(_batch - 1, 0)
	if _batch > 0 or _batch_rows.is_empty():
		return
	var detach := _batch_rows.size() > BATCH_DETACH_ROWS and _body.get_parent() == self
	if detach:
		remove_child(_body)
	for row: Vector2i in _batch_rows:
		_build_row(row, _row_xs[row].keys() if _row_xs.has(row) else [])
	_batch_rows.clear()
	if detach:
		add_child(_body)


## 行（y, z）の当たり判定を、東西に続くセルごとに1つの箱で作り直す（まとめている間は end_batch まで待つ）。
func _rebuild_row(row: Vector2i) -> void:
	if _batch > 0:
		_batch_rows[row] = true
		return
	_build_row(row, _row_xs[row].keys() if _row_xs.has(row) else [])


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
