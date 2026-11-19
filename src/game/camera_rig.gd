class_name CameraRig
extends Node3D
## 三人称カメラ。対象の頭上を中心に、マウスで水平・垂直に回す。壁に埋まらないよう SpringArm3D を使う。

const SENSITIVITY: float = 0.003
const MIN_PITCH: float = deg_to_rad(-70.0)
const MAX_PITCH: float = deg_to_rad(30.0)
const DISTANCE: float = 5.5

var target: Node3D
var yaw: float = 0.0
var pitch: float = deg_to_rad(-20.0)

var _arm: SpringArm3D
var _camera: Camera3D


func _ready() -> void:
	_arm = SpringArm3D.new()
	_arm.spring_length = DISTANCE
	_arm.collision_mask = Tuning.LAYER_TERRAIN
	_arm.margin = 0.2
	add_child(_arm)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 70.0
	_arm.add_child(_camera)


func camera() -> Camera3D:
	return _camera


func rotate_by(mouse_delta: Vector2) -> void:
	yaw -= mouse_delta.x * SENSITIVITY
	pitch = clampf(pitch - mouse_delta.y * SENSITIVITY, MIN_PITCH, MAX_PITCH)


func _physics_process(_delta: float) -> void:
	if target != null:
		global_position = target.global_position + Vector3(0.0, 1.5, 0.0)
	rotation = Vector3(pitch, yaw, 0.0)
