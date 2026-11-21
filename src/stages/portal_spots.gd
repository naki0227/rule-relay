class_name PortalSpots
extends RefCounted
## ステージから広場へ戻ったときに立つ場所を、ポータルごとに決める（純粋な計算。Overworld.build が呼ぶ。
## docs/adr/0018）。
##
## - 4 人分の足もとが全部、ポータルと同じ高さの地面（窪み・谷・段ではない）で、壁・ブロックにかからず、
##   どの入口の箱（体の半径ぶん広げた箱）の外。足もとのまわり（RIM）も同じ地面（縁で落ちない）
## - 探す順: ポータルの正面の先 → 斜め前 → 横 → 斜め後ろ → 後ろ。きょりは近い順。並びは出現地点と同じ
##   1 m おきの横一列、狭ければ 2 列（2 人ずつ）。先（LOOKAHEAD）にも地面がある向きを先に選ぶ
##   （広場の側を向いて立つため。崖の縁に向かって立たない）
## - 向きは「ポータルから立ち位置への向き」＝ポータルに背を向けて広場の側を見る
## 建物・住む生き物・置物は当たり判定が無いので見ない。広場が育っても立ち位置は変わらない。

## ポータルの正面からの角度（ラジアン。前から順に試す）
const TURNS: Array[float] = [
	0.0, PI / 4.0, -PI / 4.0, PI / 2.0, -PI / 2.0, PI * 0.75, -PI * 0.75, PI
]
## ポータルからのきょり
const DISTANCES: Array[float] = [3.0, 3.5, 4.0, 2.6, 5.0]
## 並び: [横のずれ, 奥へのずれ] × 4 人（1 列・2 列）
const FORMATIONS: Array = [
	[[-1.5, 0.0], [-0.5, 0.0], [0.5, 0.0], [1.5, 0.0]],
	[[-0.5, 0.0], [0.5, 0.0], [-0.5, 1.0], [0.5, 1.0]],
]
## 戻った人の体（カプセルの半径 0.3）が入口の箱にかからないよう、箱をこれだけ広げて調べる。
const CLEARANCE := 0.45
## 足もとのまわりも地面か調べる幅（体の半径より少し大きく）。
const RIM := 0.35
## 立ち位置の先にも地面がほしいきょり（広場の側を向くため）。
const LOOKAHEAD := 3.0

var _def: StageDef
var _field: HeightField
## 地面の上に地形（庭の壁・まぐさ・岩）かブロックがあるマス
var _blocked: Dictionary[Vector2i, bool] = {}


static func place(def: StageDef, layout: OverworldLayout, field: HeightField) -> void:
	var finder := PortalSpots.new(def, field)
	for p in layout.portals:
		var found := finder.find(p.position, p.facing)
		p.returns = found[0] as Array[Vector3]
		p.return_yaw = float(found[1])


func _init(def: StageDef, field: HeightField) -> void:
	_def = def
	_field = field
	for box: Array in def.terrain_boxes:
		var lo := box[0] as Vector3i
		var hi := box[1] as Vector3i
		for z in range(lo.z, hi.z + 1):
			for x in range(lo.x, hi.x + 1):
				var top := field.top(x, z)
				if hi.y >= top and lo.y <= top + 1:
					_blocked[Vector2i(x, z)] = true
	for b in def.blocks:
		_blocked[Vector2i(b.cell.x, b.cell.z)] = true


## [立ち位置 4 つ（見つからなければ空）, 向き]。先に地面がある向きを先に、無ければどの向きでも。
func find(at: Vector3, facing: float) -> Array:
	for need_view: bool in [true, false]:
		for turn in TURNS:
			var yaw := facing + turn
			var basis := Basis(Vector3.UP, yaw)
			var ahead := basis * Vector3.FORWARD
			var side := basis * Vector3.RIGHT
			for d in DISTANCES:
				if need_view and not _ground(at + ahead * (d + LOOKAHEAD), at.y):
					continue
				for formation: Array in FORMATIONS:
					var spots := _try(at + ahead * d, ahead, side, formation)
					if not spots.is_empty():
						return [spots, yaw]
	var none: Array[Vector3] = []
	return [none, facing]


func _try(center: Vector3, ahead: Vector3, side: Vector3, formation: Array) -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for slot: Array in formation:
		var spot := center + side * float(slot[0]) + ahead * float(slot[1])
		spot.y = center.y
		if not _standable(spot):
			return []
		spots.append(spot)
	return spots


## 立てるか: 足もととまわりが同じ高さの地面で、壁・ブロックにかからず、入口の箱の外。
func _standable(spot: Vector3) -> bool:
	for e in _def.entrances:
		if e.area.grow(CLEARANCE).has_point(spot + Vector3(0.0, 0.1, 0.0)):
			return false
	for dx: float in [0.0, RIM, -RIM]:
		for dz: float in [0.0, RIM, -RIM]:
			if not _ground(spot + Vector3(dx, 0.0, dz), spot.y):
				return false
	return true


## その点の真下が高さ y の地面で、上に地形もブロックも無いか。
func _ground(point: Vector3, y: float) -> bool:
	var cell := Vector2i(floori(point.x), floori(point.z))
	return _field.top(cell.x, cell.y) == roundi(y) and not _blocked.has(cell)
