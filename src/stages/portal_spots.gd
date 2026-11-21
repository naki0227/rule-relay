class_name PortalSpots
extends RefCounted
## ステージから広場へ戻ったときに立つ場所を、ポータルごとに決める（純粋な計算。Overworld.build が呼ぶ。
## docs/adr/0020）。
##
## - 4 人分の足もとが全部、ポータルと同じ高さの地面（窪み・谷・段ではない）で、壁・ブロックにかからず、
##   どの入口の箱（体の半径ぶん広げた箱）の外。足もとのまわり（RIM）も同じ地面（縁で落ちない）
## - 探す順: ポータルの正面の先 → 斜め前 → 横 → 斜め後ろ → 後ろ。きょりは近い順。並びは出現地点と同じ
##   1 m おきの横一列、狭ければ 2 列（2 人ずつ）。先（LOOKAHEAD）にも地面がある向きを先に選ぶ
##   （広場の側を向いて立つため。崖の縁に向かって立たない）
## - 並ぶ向き（return_yaw）は「ポータルから立ち位置への向き」＝ポータルに背を向けて広場の側
## - 体と視点の向き（return_view_yaw）: 三人称のカメラは人の DISTANCE（5.5 m）後ろにあるので、まっすぐ広場を
##   向くとカメラがポータルの門の中・すぐ後ろに入り、門が画面をふさぐ。並ぶ向きから斜めに回して、どの人の
##   カメラも門から CAMERA_CLEAR 以上離れ、カメラから人への視線も門から SIGHT_CLEAR 以上離れる向きにする。
##   門は人の横に見える（「いまこの門から出てきた」）。カメラの下が高い壁なら（ばねで引き寄せられる）避ける
## 建物・住む生き物・置物は当たり判定が無いので見ない。広場が育っても立ち位置は変わらない。

## ポータルの正面からの角度（ラジアン。前から順に試す）
const TURNS: Array[float] = [
	0.0, PI / 4.0, -PI / 4.0, PI / 2.0, -PI / 2.0, PI * 0.75, -PI * 0.75, PI
]
## ポータルからのきょり
const DISTANCES: Array[float] = [3.0, 3.5, 4.0, 2.6, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
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
## 体と視点を並ぶ向きから回す角度（ラジアン。前から順に試す。0 はポータルから十分遠いときだけ通る）
const VIEW_TURNS: Array[float] = [
	0.0,
	PI / 3.0,
	-PI / 3.0,
	PI * 0.4,
	-PI * 0.4,
	PI / 2.0,
	-PI / 2.0,
	PI / 4.0,
	-PI / 4.0,
]
## カメラの中心（頭の高さ）から人の後ろへの水平のきょり（CameraRig.DISTANCE と既定の見下ろし 20 度）
const CAMERA_BACK := CameraRig.DISTANCE * 0.94
## カメラとポータルの中心の水平のきょり（門の台の半径 1.15 m ＋ 門の奥行き ＋ ゆとり）
const CAMERA_CLEAR := 5.5
## カメラから人への視線と、ポータルの中心の水平のきょり（門が手前を横切らない）
const SIGHT_CLEAR := 2.5
## 門が画面に入っているとみなす、視線とポータルへの向きの角度（横の視野の半分より少し内側）
const VISIBLE_ANGLE := deg_to_rad(45.0)

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
		p.return_view_yaw = float(found[2])


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


## [立ち位置 4 つ（見つからなければ空）, 並ぶ向き, 体と視点の向き]。
## 試す順: 先に地面があり、カメラが門に入らず門が見える → 門が見えなくてもよい → 先に地面が無くてもよい
## → （それでも無ければ）カメラを見ない。どれも、きょりの近い順・前の向きから。
func find(at: Vector3, facing: float) -> Array:
	for need_view: bool in [true, false]:
		for camera: int in [2, 1]:
			var found := _search(at, facing, need_view, camera)
			if not found.is_empty():
				return found
	var last := _search(at, facing, false, 0)
	if not last.is_empty():
		return last
	var none: Array[Vector3] = []
	return [none, facing, facing]


## camera: 2 = カメラが門から離れ門も見える、1 = 離れていればよい、0 = 見ない。
func _search(at: Vector3, facing: float, need_view: bool, camera: int) -> Array:
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
				if spots.is_empty():
					continue
				var view := (
					yaw + PI / 2.0 if camera == 0 else _view_turn(at, spots, yaw, camera == 2)
				)
				if not is_nan(view):
					return [spots, yaw, view]
	return []


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


## 戻ったときの体と視点の向き（どの人のカメラも門に入り込まない向き。strict なら門が見える）。無ければ NAN。
func _view_turn(portal: Vector3, spots: Array[Vector3], out_yaw: float, strict: bool) -> float:
	for turn in VIEW_TURNS:
		if _clear_view(portal, spots, out_yaw + turn, strict):
			return out_yaw + turn
	return NAN


## その向きで、どの人のカメラも門から離れているか（strict なら門が見えて、カメラの下に高い壁も無い）。
func _clear_view(portal: Vector3, spots: Array[Vector3], yaw: float, strict: bool) -> bool:
	var view := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	var center := Vector2(portal.x, portal.z)
	var flat := Vector2(view.x, view.z)
	for spot in spots:
		var at := Vector2(spot.x, spot.z)
		var cam := camera_point(spot, yaw)
		var cam2 := Vector2(cam.x, cam.z)
		if not camera_clear_of_gates(cam, _def):
			return false
		if (
			Geometry2D.get_closest_point_to_segment(center, cam2, at).distance_to(center)
			< SIGHT_CLEAR
		):
			return false
		if strict:
			if absf(flat.angle_to(center - cam2)) > VISIBLE_ANGLE:
				return false
			if _field.top(floori(cam.x), floori(cam.z)) > roundi(spot.y) + 2:
				return false
	return true


## カメラがどの門（入口）からも CAMERA_CLEAR 以上離れているか（高さが近い門だけ見る）。
static func camera_clear_of_gates(cam: Vector3, def: StageDef) -> bool:
	for e in def.entrances:
		var gap := Vector2(cam.x - e.position.x, cam.z - e.position.z).length()
		if gap < CAMERA_CLEAR and absf(cam.y - e.position.y) < 4.0:
			return false
	return true


## その人のカメラの場所（水平。高さは頭の高さ）。
static func camera_point(spot: Vector3, yaw: float) -> Vector3:
	var view := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	return spot + Vector3(0.0, 1.5, 0.0) - view * CAMERA_BACK


## その点の真下が高さ y の地面で、上に地形もブロックも無いか。
func _ground(point: Vector3, y: float) -> bool:
	var cell := Vector2i(floori(point.x), floori(point.z))
	return _field.top(cell.x, cell.y) == roundi(y) and not _blocked.has(cell)
