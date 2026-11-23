class_name CameraRig
extends Node3D
## 三人称カメラ。対象の頭上を中心に、マウスで水平・垂直に回す。壁に埋まらないよう SpringArm3D を使う。
##
## 見上げたときの支点（2026-11-23 本人の判断「カメラの支点を上げる」）: 支点が頭の上 1.5 m のままだと、
## 見上げるほどカメラが足もとより下へ回り込み、ばね（SpringArm3D）が地面に当たって人の顔の前まで寄っていた
## （段の真下で見上げると、壁と顔だけになる。はじめての 10 分の通し・1-4 の縁のセル）。
## カメラが足もとの高さ + MIN_CAMERA_HEIGHT より下へ行く分だけ、支点を上げる（pivot_lift）。
## カメラはその高さを保ったまま、遠ざからずに上を向く。見上げの上限（MAX_PITCH）は変えていない。
## 照準の光線は今までどおりカメラから画面の中央へ投げるので（GameWorld.aimed_block）、支点を上げても
## 照準と狙う先はずれない。支点の真上に地形（天井・張り出し）があれば、そこまでしか上げない。

const SENSITIVITY: float = 0.003
const MIN_PITCH: float = deg_to_rad(-70.0)
const MAX_PITCH: float = deg_to_rad(30.0)
const DISTANCE: float = 5.5
## 回転の中心（支点）の、足もとからの高さ（見上げていないとき）。
const PIVOT_HEIGHT: float = 1.5
## 見上げたとき、カメラが足もとからこれより下へ行かないよう支点を上げる（m。目の高さより少し下。仮の値）。
const MIN_CAMERA_HEIGHT: float = 1.0
## 支点を上げたとき、上の地形との間に残すすき間（m）。
const CEILING_GAP: float = 0.3

var target: Node3D
var yaw: float = 0.0
var pitch: float = deg_to_rad(-20.0)

var _arm: SpringArm3D
var _camera: Camera3D
var _lift: float = 0.0


## 見上げの角度 p で、支点を足もとからどれだけ上げるか（m。上の地形は見ない）。
## カメラはばねの先（支点から DISTANCE 後ろ）なので、高さは PIVOT_HEIGHT - DISTANCE * sin(p)。
static func pivot_lift(p: float) -> float:
	return maxf(0.0, MIN_CAMERA_HEIGHT - (PIVOT_HEIGHT - DISTANCE * sin(p)))


## 見上げの角度 p での、支点の足もとからの高さ（m。上の地形は見ない）。テストの照準合わせにも使う。
static func pivot_height(p: float) -> float:
	return PIVOT_HEIGHT + pivot_lift(p)


func _ready() -> void:
	_arm = SpringArm3D.new()
	_arm.spring_length = DISTANCE
	_arm.collision_mask = Tuning.LAYER_TERRAIN
	_arm.margin = 0.2
	add_child(_arm)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 70.0
	# 肩越しにして、照準（画面中央）がキャラクターに重ならないようにする
	_camera.h_offset = 0.6
	_arm.add_child(_camera)


func camera() -> Camera3D:
	return _camera


## いま支点を上げている高さ（m。上の地形で止めた後）。
func lift() -> float:
	return _lift


func rotate_by(mouse_delta: Vector2) -> void:
	yaw -= mouse_delta.x * SENSITIVITY
	pitch = clampf(pitch - mouse_delta.y * SENSITIVITY, MIN_PITCH, MAX_PITCH)


func _physics_process(_delta: float) -> void:
	if target != null:
		var base := target.global_position + Vector3(0.0, PIVOT_HEIGHT, 0.0)
		_lift = _clear_lift(base, pivot_lift(pitch))
		global_position = base + Vector3(0.0, _lift, 0.0)
	rotation = Vector3(pitch, yaw, 0.0)


## 支点を want だけ上げたいとき、真上の地形に当たらない高さ（当たれば、その手前 CEILING_GAP まで）。
func _clear_lift(base: Vector3, want: float) -> float:
	if want <= 0.0 or not is_inside_tree():
		return want
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		base, base + Vector3(0.0, want + CEILING_GAP, 0.0), Tuning.LAYER_TERRAIN
	)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return want
	return clampf((hit["position"] as Vector3).y - base.y - CEILING_GAP, 0.0, want)
