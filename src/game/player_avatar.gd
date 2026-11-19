class_name PlayerAvatar
extends CharacterBody3D
## 三人称のプレイヤー。入力そのものは読まず、move_intent と request_jump() で指示を受ける。
## どの方向へ動けるかは、毎フレーム ledger（能力・禁止）に問い合わせて決める。
## 移動はカメラ相対（企画書 4-1）。W を失っても、視点を回して A などで同じ方角へ進めるのは許容する。

const HEIGHT: float = 1.6
const RADIUS: float = 0.3

## x = 右(+)/左(-)、y = 前(+)/後(-)。値は -1〜1。
var move_intent: Vector2 = Vector2.ZERO
## 移動の基準にするカメラの水平向き（ラジアン、Y軸回り）。
var view_yaw: float = 0.0
var ledger: RuleLedger

var _jump_requested: bool = false


func _ready() -> void:
	collision_layer = Tuning.LAYER_PLAYER
	collision_mask = Tuning.LAYER_TERRAIN | Tuning.LAYER_BLOCKS
	floor_snap_length = 0.2
	floor_max_angle = deg_to_rad(50.0)
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_ADD_VELOCITY
	if get_child_count() == 0:
		_build_body()


## 自分のジャンプを要求する。能力・禁止の確認は呼び出し側（InputRouter）で済ませている前提だが、
## 念のためここでも ledger を確認し、床にいるときだけ跳ぶ。
func request_jump() -> void:
	_jump_requested = true


func feet_position() -> Vector3:
	return global_position


func _physics_process(delta: float) -> void:
	var direction := _allowed_direction()
	velocity.x = direction.x * Tuning.PLAYER_SPEED
	velocity.z = direction.z * Tuning.PLAYER_SPEED
	if not is_on_floor():
		velocity.y -= Tuning.GRAVITY * delta
	if _jump_requested:
		_jump_requested = false
		if is_on_floor() and ledger != null and ledger.player_can(RuleAction.Kind.JUMP):
			velocity.y = Tuning.jump_velocity(Tuning.PLAYER_JUMP_HEIGHT)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z) * delta
	# 段差補助は「床に立って歩いている」ときだけ。空中で壁に触れても登らせない
	var was_on_floor := is_on_floor() and velocity.y <= 0.0
	move_and_slide()
	if was_on_floor and is_on_wall() and horizontal.length() > 0.0001:
		_try_step_up(horizontal)


## 能力があり禁止されていない方向だけを合成する。
func _allowed_direction() -> Vector3:
	if ledger == null:
		return Vector3.ZERO
	var local := Vector2.ZERO
	if move_intent.y > 0.0 and ledger.player_can(RuleAction.Kind.FORWARD):
		local.y += move_intent.y
	if move_intent.y < 0.0 and ledger.player_can(RuleAction.Kind.BACK):
		local.y += move_intent.y
	if move_intent.x < 0.0 and ledger.player_can(RuleAction.Kind.LEFT):
		local.x += move_intent.x
	if move_intent.x > 0.0 and ledger.player_can(RuleAction.Kind.RIGHT):
		local.x += move_intent.x
	if local.length() > 1.0:
		local = local.normalized()
	var basis := Basis(Vector3.UP, view_yaw)
	var forward := basis * Vector3.FORWARD
	var right := basis * Vector3.RIGHT
	return forward * local.y + right * local.x


## 低い段差（Tuning.STEP_ASSIST_HEIGHT 以下）を歩いて上がる補助（企画書 4-6）。
## 移動入力があるときだけ働き、隙間を飛び越えたり禁止を無視したりはしない。
func _try_step_up(horizontal: Vector3) -> void:
	var up := Vector3.UP * Tuning.STEP_ASSIST_HEIGHT
	# カプセルの丸い底が段の角に引っかからないよう、中心が段の上に乗るまで前へ確かめる
	var probe := horizontal.normalized() * maxf(horizontal.length(), RADIUS + 0.05)
	if test_move(global_transform, up):
		return
	var raised := global_transform.translated(up)
	if test_move(raised, probe):
		return
	var landing := KinematicCollision3D.new()
	var ahead := raised.translated(probe)
	if not test_move(ahead, -up, landing):
		return  # 先に床がない（段差ではなく隙間）
	global_position = ahead.origin + landing.get_travel()
	velocity.y = maxf(velocity.y, 0.0)


func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	shape.shape = capsule
	shape.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	add_child(shape)

	var mesh := MeshInstance3D.new()
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = RADIUS
	capsule_mesh.height = HEIGHT
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.55, 0.95)
	capsule_mesh.material = material
	mesh.mesh = capsule_mesh
	mesh.position = shape.position
	add_child(mesh)

	# 向きが分かるように前方へ小さな鼻を付ける
	var nose := MeshInstance3D.new()
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.15, 0.15, 0.25)
	nose.mesh = nose_mesh
	nose.position = Vector3(0.0, HEIGHT * 0.8, -RADIUS)
	add_child(nose)
