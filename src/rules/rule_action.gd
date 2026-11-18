class_name RuleAction
extends RefCounted
## 操作キーと一対一に対応する「行動」。能力・禁止はこの行動ごとに存在する。
## ブロックの WASD は世界座標に固定（企画書 4-2）。北 = -Z、東 = +X とする。

enum Kind { FORWARD, LEFT, BACK, RIGHT, JUMP }

const ALL: Array[Kind] = [Kind.FORWARD, Kind.LEFT, Kind.BACK, Kind.RIGHT, Kind.JUMP]


static func label(kind: Kind) -> String:
	match kind:
		Kind.FORWARD:
			return "W"
		Kind.LEFT:
			return "A"
		Kind.BACK:
			return "S"
		Kind.RIGHT:
			return "D"
		Kind.JUMP:
			return "ジャンプ"
	return "?"


## ブロックに渡したときの移動方向（世界座標、1ブロック単位）。ジャンプは水平移動なし。
static func world_direction(kind: Kind) -> Vector3i:
	match kind:
		Kind.FORWARD:
			return Vector3i(0, 0, -1)
		Kind.BACK:
			return Vector3i(0, 0, 1)
		Kind.LEFT:
			return Vector3i(-1, 0, 0)
		Kind.RIGHT:
			return Vector3i(1, 0, 0)
	return Vector3i.ZERO


static func is_horizontal(kind: Kind) -> bool:
	return kind != Kind.JUMP
