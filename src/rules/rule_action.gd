class_name RuleAction
extends RefCounted
## 操作キーと一対一に対応する「行動」。能力・禁止はこの行動ごとに存在する。
## ブロックの WASD は世界座標に固定（企画書 4-2）。北 = -Z、東 = +X とする。

## THROW: 遠くの対象へ付与できる（企画書 5.1。渡すと自分は「触る」の距離だけになる）。
## HIGH_JUMP / CLIMB: 装備（ジャンプブーツ / クライミンググローブ）に宿る強化（企画書 7）。
## DASH: 向いている方へ、マス単位でまっすぐ水平に突進する。途中に穴があっても落ちずに抜けられる
## （2026-11-20 本人確定の方向。基礎 3 マス、n 個で 3n マス。数値・キーは仮）。
enum Kind { FORWARD, LEFT, BACK, RIGHT, JUMP, THROW, HIGH_JUMP, CLIMB, DASH }

## 開始時からの基本の行動（W/A/S/D・ジャンプ）。
const BASIC: Array[Kind] = [Kind.FORWARD, Kind.LEFT, Kind.BACK, Kind.RIGHT, Kind.JUMP]
const ALL: Array[Kind] = [
	Kind.FORWARD,
	Kind.LEFT,
	Kind.BACK,
	Kind.RIGHT,
	Kind.JUMP,
	Kind.THROW,
	Kind.HIGH_JUMP,
	Kind.CLIMB,
	Kind.DASH,
]


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
		Kind.THROW:
			return "投げる"
		Kind.HIGH_JUMP:
			return "高跳び"
		Kind.CLIMB:
			return "登る"
		Kind.DASH:
			return "ダッシュ"
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
	return world_direction(kind) != Vector3i.ZERO


## 法則の音の音程（半音）。能力ごとに決まっていて、渡す・回収するときに鳴らす（ハ長調の五音で上がる）。
## どの能力が動いたかを、耳でも分かるようにする（docs/sound-design.md）。
static func motif_semitone(kind: Kind) -> int:
	return [0, 2, 4, 7, 9, 12, 14, 16, 19][int(kind)]


## ブロックが自分から「1回の行動」として起こす行動（発動方式が要る）。
## それ以外（投げる・高跳び・登る）は持っているだけで効く／効果のない性質で、方式を持たない。
static func is_triggered(kind: Kind) -> bool:
	return kind in [Kind.FORWARD, Kind.LEFT, Kind.BACK, Kind.RIGHT, Kind.JUMP, Kind.DASH]
