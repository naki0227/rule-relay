class_name PlayerAvatar
extends CharacterBody3D
## 三人称のプレイヤー。入力そのものは読まず、move_intent と request_jump() で指示を受ける。
## どの方向へ動けるかは、毎フレーム ledger（能力・禁止）に問い合わせて決める。
## 移動はカメラ相対（企画書 4-1）。W を失っても、視点を回して A などで同じ方角へ進めるのは許容する。

## 効果音のための合図。
signal jumped
signal landed(impact_speed: float)
signal footstep

const HEIGHT: float = 1.6
const RADIUS: float = 0.3

## x = 右(+)/左(-)、y = 前(+)/後(-)。値は -1〜1。
## 足音の間隔（歩いた距離、m）。
const STEP_DISTANCE: float = 1.7

var move_intent: Vector2 = Vector2.ZERO
## 移動の基準にするカメラの水平向き（ラジアン、Y軸回り）。
var view_yaw: float = 0.0
var ledger: RuleLedger

## 壁を登っている最中（クライミンググローブを装備して壁へ向かって進んでいる）。
var climbing: bool = false

var _jump_requested: bool = false
var _walked: float = 0.0
var _visual: Node3D
var _limbs: Dictionary[String, Node3D] = {}
var _walk_phase: float = 0.0
var _facing: float = 0.0


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


## いまのジャンプの高さ。ジャンプブーツ（高跳び）を装備していれば固定で高くなる（企画書 7）。
## 高跳びはジャンプの強化なので、ジャンプ自体が使えない（貸出中・禁止）なら跳べない。
func jump_height() -> float:
	if ledger != null and ledger.player_can(RuleAction.Kind.HIGH_JUMP):
		return Tuning.BOOTS_JUMP_HEIGHT
	return Tuning.PLAYER_JUMP_HEIGHT


## クライミンググローブ（登る）: 壁に触れていて、その壁へ向かって進もうとしているあいだ登る。
## 進めない方向（能力が無い・禁止）へは押せないので、移動の能力・禁止も守る。
func _should_climb(direction: Vector3) -> bool:
	if ledger == null or not ledger.player_can(RuleAction.Kind.CLIMB):
		return false
	if not is_on_wall() or direction.length() < 0.1:
		return false
	return get_wall_normal().dot(direction.normalized()) < -0.5


func _physics_process(delta: float) -> void:
	var direction := _allowed_direction()
	velocity.x = direction.x * Tuning.PLAYER_SPEED
	velocity.z = direction.z * Tuning.PLAYER_SPEED
	if not is_on_floor():
		velocity.y -= Tuning.GRAVITY * delta
	if _jump_requested:
		_jump_requested = false
		if is_on_floor() and ledger != null and ledger.player_can(RuleAction.Kind.JUMP):
			velocity.y = Tuning.jump_velocity(jump_height())
			jumped.emit()
	climbing = _should_climb(direction)
	if climbing:
		velocity.y = Tuning.CLIMB_SPEED
	_animate(delta, direction)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z) * delta
	# 段差補助は「床に立って歩いている」ときだけ。空中で壁に触れても登らせない
	var was_on_floor := is_on_floor() and velocity.y <= 0.0
	var fall_speed := -velocity.y
	var airborne := not is_on_floor()
	move_and_slide()
	if airborne and is_on_floor() and fall_speed > 4.0:
		landed.emit(fall_speed)
	if is_on_floor() and horizontal.length() > 0.0:
		_walked += horizontal.length()
		if _walked >= STEP_DISTANCE:
			_walked = 0.0
			footstep.emit()
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


## 歩きの見た目: 進む向きへ体を回し、速さに合わせて手足を振る（骨格なしの簡易アニメーション）。
func _animate(delta: float, direction: Vector3) -> void:
	if _visual == null:
		return
	var speed := direction.length()
	if speed > 0.05:
		var target := atan2(-direction.x, -direction.z)
		_facing = lerp_angle(_facing, target, minf(1.0, delta * 12.0))
		_visual.rotation.y = _facing
	var grounded := is_on_floor()
	if grounded and speed > 0.05:
		_walk_phase = fmod(_walk_phase + delta * 11.0 * speed, TAU)
	else:
		_walk_phase = lerpf(_walk_phase, 0.0 if _walk_phase < PI else TAU, minf(1.0, delta * 8.0))
	var swing := sin(_walk_phase) * 0.7 * speed
	if not grounded:
		swing = -0.5  # 空中では足をそろえて腕を少し上げる
	_set_limb("LegL", swing, 0.0)
	_set_limb("LegR", -swing, 0.0)
	_set_limb("ArmL", -swing * 0.8, -0.08)
	_set_limb("ArmR", swing * 0.8, 0.08)
	var bob := absf(sin(_walk_phase)) * 0.04 * speed
	var body := _limbs.get("Body") as Node3D
	var head := _limbs.get("Head") as Node3D
	if body != null:
		body.position.y = 0.42 + bob
	if head != null:
		head.position.y = 1.06 + bob


func _set_limb(limb_name: String, pitch: float, roll: float) -> void:
	var limb := _limbs.get(limb_name) as Node3D
	if limb != null:
		limb.rotation = Vector3(pitch, 0.0, roll)


func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	shape.shape = capsule
	shape.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	add_child(shape)

	# 見た目は Blender のモデル（art/source/traveler.blend）。手足は関節に原点がある
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var model := ModelLibrary.instantiate("traveler")
	_visual.add_child(model)
	for limb_name: String in ["Body", "Head", "ArmL", "ArmR", "LegL", "LegR"]:
		var limb := model.find_child(limb_name, true, false) as Node3D
		if limb != null:
			_limbs[limb_name] = limb
