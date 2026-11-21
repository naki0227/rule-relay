class_name HeightField
extends RefCounted
## 文字の地図（IslandMap）の上面の高さを、数の配列に写したもの（広い広場で何度も高さを調べるため。
## 文字を毎回読み直すと遅い）。窪み（pit）は 1 段下げた高さ。何もないマスは EMPTY。

const EMPTY := -100

var origin: Vector2i
var width: int
var depth: int
var tops: PackedInt32Array = PackedInt32Array()


static func from_map(map: IslandMap) -> HeightField:
	var field := HeightField.new()
	field.origin = map.origin
	field.depth = map.rows.size()
	field.width = map.rows[0].length() if field.depth > 0 else 0
	field.tops.resize(field.width * field.depth)
	for row in field.depth:
		for col in field.width:
			field.tops[row * field.width + col] = map.top_at(map.origin.x + col, map.origin.y + row)
	return field


func top(x: int, z: int) -> int:
	var col := x - origin.x
	var row := z - origin.y
	if col < 0 or row < 0 or col >= width or row >= depth:
		return EMPTY
	return tops[row * width + col]
