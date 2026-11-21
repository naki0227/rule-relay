class_name IslandMap
extends RefCounted
## 開けた島の地形を、文字の地図から作る（Human: Fall Flat のような、ひとつながりの島。docs/adr/0011）。
## 1文字が1マス（1m）。上の行ほど北（-Z）。
## - "0"〜"9": その列の上面の高さ（0 が普通の地面。地面の下は y = -1 から埋める）
## - "." と " ": 何もない（底なし。落ちたら死亡）
## 窪み（pits）に指定した列は、上面を1段下げる。そこにブロックを置くと、上面がまわりと同じ高さになり、
## 跳べなくても乗れる「持ち上げ台」になる。

var rows: PackedStringArray
## 地図の左上（1行目の1文字目）のマス（x, z）。
var origin: Vector2i
var pits: Dictionary[Vector2i, bool] = {}


func _init(p_rows: PackedStringArray, p_origin: Vector2i) -> void:
	rows = p_rows
	origin = p_origin


## 何もない（底なし）地図。左上のマスが origin、幅 width・奥行き depth。
static func blank(p_origin: Vector2i, width: int, depth: int) -> IslandMap:
	var empty := PackedStringArray()
	for i in depth:
		empty.append(".".repeat(width))
	return IslandMap.new(empty, p_origin)


## (x0, z0)〜(x1, z1)（両端を含む）を高さ h にする。h が -1 なら何もない（底なし）にする。
func fill(x0: int, z0: int, x1: int, z1: int, h: int) -> void:
	var ch := "." if h < 0 else str(h)
	for z in range(mini(z0, z1), maxi(z0, z1) + 1):
		var row := z - origin.y
		if row < 0 or row >= rows.size():
			continue
		var line := rows[row]
		for x in range(mini(x0, x1), maxi(x0, x1) + 1):
			var col := x - origin.x
			if col >= 0 and col < line.length():
				line[col] = ch
		rows[row] = line


## マス（x, z）の上面の高さ。何もなければ -100。窪みは下げる前の高さ。
func height(x: int, z: int) -> int:
	var row := z - origin.y
	var col := x - origin.x
	if row < 0 or row >= rows.size() or col < 0 or col >= rows[row].length():
		return -100
	var ch := rows[row][col]
	return int(ch) if ch.is_valid_int() else -100


## 窪みを作り、そこに置くブロックのマスを返す（上面がまわりと同じ高さになる位置）。
func pit(x: int, z: int) -> Vector3i:
	pits[Vector2i(x, z)] = true
	return Vector3i(x, height(x, z) - 1, z)


## 地形の箱（StageDef.terrain_boxes の形）。同じ行で同じ高さが続くところは1つの箱にまとめる。
func boxes() -> Array:
	var result: Array = []
	for row in rows.size():
		var z := origin.y + row
		var run_start := -1
		var run_top := -100
		for col in rows[row].length() + 1:
			var x := origin.x + col
			var top := _top(x, z) if col < rows[row].length() else -100
			if top == run_top:
				continue
			if run_top > -100:
				result.append(_box(origin.x + run_start, x - 1, z, run_top))
			run_start = col
			run_top = top
	return result


## 上面の高さ（窪みは1段下げる。何もなければ -100）。
func top_at(x: int, z: int) -> int:
	return _top(x, z)


## 上面の高さ（窪みは1段下げる）。
func _top(x: int, z: int) -> int:
	var h := height(x, z)
	if h > -100 and pits.has(Vector2i(x, z)):
		return h - 1
	return h


static func _box(x0: int, x1: int, z: int, top: int) -> Array:
	var kind := "grass"
	if top >= 4:
		kind = "rock"
	elif top >= 2:
		kind = "sand"
	return [Vector3i(x0, mini(-1, top - 1), z), Vector3i(x1, top - 1, z), kind]
