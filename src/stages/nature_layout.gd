class_name NatureLayout
extends RefCounted
## ステージの自然の仕掛け（風・水と流れ）の置き方。純粋なデータで、StageDef.nature に入れる。
## 氷はここではなく地形の種類 "ice"（StageDef.terrain_boxes）で置く（どのセルも能力を渡せる、のまま）。
## 座標はセル（1ブロック = 1m、北 = -Z、地面の上面が y = 0）。範囲は両端のセルを含む。
## 動き方の決まりは docs/adr/0015、調整値は NatureTuning。

var winds: Array[WindSpec] = []
var waters: Array[WaterSpec] = []


## 風の吹く範囲。範囲の中のプレイヤー・生き物・ブロック・落ちている器を direction へ押す
## （重いものは押さない）。period が 0 なら吹き続け、正なら period 秒ごとに on_time 秒だけ吹く。
class WindSpec:
	var min_cell: Vector3i
	var max_cell: Vector3i
	## 東西南北のどれか（ブロックはマス単位で運ぶので斜めは無し）
	var direction: Vector3i
	var strength: float = NatureTuning.WIND_STRENGTH
	var period: float = 0.0
	var on_time: float = 0.0
	## 脈打つ風の始まりのずらし（秒）。並べた風を順に吹かせるのに使う
	var phase: float = 0.0

	func _init(p_min: Vector3i, p_max: Vector3i, p_direction: Vector3i) -> void:
		min_cell = p_min
		max_cell = p_max
		direction = p_direction

	func area() -> AABB:
		return AABB(Vector3(min_cell), Vector3(max_cell - min_cell + Vector3i.ONE))

	## いま吹いているか（clock は仕掛けの時計。全員の画面で同じ値になる）。
	func is_blowing(clock: float) -> bool:
		if period <= 0.0:
			return true
		return fposmod(clock + phase, period) < on_time

	## 押す速さ（m/秒）。
	func velocity() -> Vector3:
		return Vector3(direction) * strength


## 水。セルの範囲が水で満ち、その下には何も無い（底なし。沈んだら落ちたのと同じ）。
## current が ZERO でなければ、水の中のものを current_speed（m/秒）で流す。
class WaterSpec:
	var min_cell: Vector3i
	var max_cell: Vector3i
	var current: Vector3i = Vector3i.ZERO
	var current_speed: float = 0.0

	func _init(p_min: Vector3i, p_max: Vector3i) -> void:
		min_cell = p_min
		max_cell = p_max

	## 水面の高さ（水のいちばん上のセルの上面より少し下）。
	func surface_y() -> float:
		return float(max_cell.y + 1) - NatureTuning.WATER_FREEBOARD

	## 浮いたブロックの底面の高さ（いちばん上の水のセルに収まる。上面は岸の地面とそろう）。
	func float_bottom() -> float:
		return float(max_cell.y)

	## p が水の中か（水の範囲の真上から見て内側で、水面より下。底なしなので下の限りは無い）。
	func contains(p: Vector3) -> bool:
		if p.x < min_cell.x or p.x >= max_cell.x + 1 or p.z < min_cell.z or p.z >= max_cell.z + 1:
			return false
		return p.y < surface_y()

	## 流れの速さ（m/秒）。
	func flow() -> Vector3:
		return Vector3(current) * current_speed


## 吹き続ける風を足す。
func add_wind(
	min_cell: Vector3i,
	max_cell: Vector3i,
	direction: Vector3i,
	strength: float = NatureTuning.WIND_STRENGTH
) -> WindSpec:
	var spec := WindSpec.new(min_cell, max_cell, direction)
	spec.strength = strength
	winds.append(spec)
	return spec


## 脈打つ風（period 秒ごとに on_time 秒だけ吹く）を足す。
func add_pulsing_wind(
	min_cell: Vector3i,
	max_cell: Vector3i,
	direction: Vector3i,
	period: float,
	on_time: float,
	phase: float = 0.0
) -> WindSpec:
	var spec := add_wind(min_cell, max_cell, direction)
	spec.period = period
	spec.on_time = on_time
	spec.phase = phase
	return spec


## 止まった水を足す。
func add_water(min_cell: Vector3i, max_cell: Vector3i) -> WaterSpec:
	var spec := WaterSpec.new(min_cell, max_cell)
	waters.append(spec)
	return spec


## 流れのある水を足す。
func add_current(
	min_cell: Vector3i,
	max_cell: Vector3i,
	direction: Vector3i,
	speed: float = NatureTuning.CURRENT_SPEED
) -> WaterSpec:
	var spec := add_water(min_cell, max_cell)
	spec.current = direction
	spec.current_speed = speed
	return spec


func is_empty() -> bool:
	return winds.is_empty() and waters.is_empty()


## 置き方の矛盾（テスト用。空なら正常）。terrain_boxes は StageDef と同じ形式。
## 水の下に地形があると「沈んだら落ちる」が成り立たないので、水の列の下は空けておく（地形で決める）。
func problems(terrain_boxes: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	for spec in winds:
		if not _is_cardinal(spec.direction):
			errors.append("wind direction must be north, south, east or west")
		if spec.strength <= 0.0:
			errors.append("wind strength must be positive")
		if spec.period > 0.0 and (spec.on_time <= 0.0 or spec.on_time >= spec.period):
			errors.append("a pulsing wind needs 0 < on_time < period")
	for spec in waters:
		if spec.current != Vector3i.ZERO and not _is_cardinal(spec.current):
			errors.append("current direction must be north, south, east or west")
		if spec.current != Vector3i.ZERO and spec.current_speed <= 0.0:
			errors.append("current speed must be positive")
		if _has_ground_under(spec, terrain_boxes):
			errors.append("water must be bottomless (terrain found under the water)")
	return errors


static func _is_cardinal(direction: Vector3i) -> bool:
	return direction.y == 0 and absi(direction.x) + absi(direction.z) == 1


static func _has_ground_under(spec: WaterSpec, terrain_boxes: Array) -> bool:
	for box: Array in terrain_boxes:
		var lo := box[0] as Vector3i
		var hi := box[1] as Vector3i
		var overlaps := (
			lo.x <= spec.max_cell.x
			and hi.x >= spec.min_cell.x
			and lo.z <= spec.max_cell.z
			and hi.z >= spec.min_cell.z
		)
		if overlaps and lo.y <= spec.max_cell.y:
			return true
	return false
