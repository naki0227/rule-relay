class_name PlayerAvatar
extends CharacterBody3D
## 三人称のプレイヤー。入力そのものは読まず、move_intent と request_jump() で指示を受ける。
## どの方向へ動けるかは、毎フレーム ledger（能力・禁止）に問い合わせて決める。
## 移動はカメラ相対（企画書 4-1）。W を失っても、視点を回して A などで同じ方角へ進めるのは許容する。

## 効果音のための合図。
signal jumped
signal landed(impact_speed: float)
signal footstep
signal dashed
## 足もとのブロックの禁止で、押した行動ができなかった（FloorBans。音と最初の一度だけの知らせに使う）。
signal floor_ban_refused(action: RuleAction.Kind)
## 足もとの禁止が変わった（乗った・降りた・禁止が付いた）。HUD のホットバーの「使えない」表示に使う。
signal floor_bans_changed

const HEIGHT: float = 1.6
const RADIUS: float = 0.3

## x = 右(+)/左(-)、y = 前(+)/後(-)。値は -1〜1。
## 足音の間隔（歩いた距離、m）。
const STEP_DISTANCE: float = 1.7
## 投げる動き（Blender の throw、14 フレーム / 24fps）の長さ。
const THROW_TIME: float = 0.58

var move_intent: Vector2 = Vector2.ZERO
## 移動の基準にするカメラの水平向き（ラジアン、Y軸回り）。
var view_yaw: float = 0.0
var ledger: RuleLedger
## 台帳の上でのプレイヤー ID（1人用は PLAYER_ID）。変えると服の色もその人の色になる（ArtPalette）。
var player_id: int = RuleLedger.PLAYER_ID:
	set = _set_player_id
## 仲間のアバター（操り人形）。入力も物理も使わず、通信で受け取った位置へなめらかに動く。
var puppet: bool = false
## 操り人形が目指す位置・向き（通信で受け取る）。
var remote_position: Vector3 = Vector3.ZERO
var remote_yaw: float = 0.0
var remote_moving: bool = false
var remote_on_floor: bool = true

## 壁を登っている最中（クライミンググローブを装備して壁へ向かって進んでいる）。
var climbing: bool = false
## 自然の仕掛け（風・氷・水。GameWorld.nature）。null なら何も受けない。自分のアバターだけが受ける
## （操り人形は通信で受け取った位置へ動くだけ）。動かし方は NatureMotion（docs/adr/0015）。
var nature: NatureField
## 氷の上ですべっている勢い（m/秒、x = 東、y = 南）。氷を離れて床に着くと 0 に戻る。
var slide: Vector2 = Vector2.ZERO
## 水に浮いている・泳いでいる（水面から跳べる）。
var afloat: bool = false
## 投げた回数（通信で配る。変わったら仲間の画面でも投げる動きを再生する）。
var throw_serial: int = 0
## 足もとのブロックに付いた禁止のうち、立っている自分に効くもの {RuleAction.Kind: true}（FloorBans）。
## 自分のアバターだけが毎フレーム調べる（参加者の画面でも自分で調べるので、跳んでから戻されることはない）。
var floor_bans: Dictionary = {}

var _jump_requested: bool = false
## ダッシュの残りの距離（m）と向き。ダッシュ中は重力を受けない（穴の上も抜けられる）。
var _dash_left: float = 0.0
var _dash_dir: Vector3 = Vector3.ZERO
## 空中のダッシュは、床に着くまで1回だけ。
var _air_dash_used: bool = false
var _walked: float = 0.0
var _visual: Node3D
var _model: Node3D
## 骨格付きのモデルのアニメーション（idle / walk / jump / happy。art/scripts/build_cast.py）。
var _rig: RigAnimator
## 喜ぶ動き（happy）を続ける残り秒数（クリアしたときなど）。
var _cheer_left: float = 0.0
## 投げる動き（throw）を続ける残り秒数。
var _throw_left: float = 0.0
var _facing: float = 0.0
## 足もとの禁止で止められている W/A/S/D（押し始めに一度だけ知らせるため）。
var _refused_moves: Dictionary = {}


func _ready() -> void:
	collision_layer = Tuning.LAYER_AVATARS if puppet else Tuning.LAYER_PLAYER
	collision_mask = 0 if puppet else Tuning.LAYER_TERRAIN | Tuning.LAYER_BLOCKS
	remote_position = position
	floor_snap_length = 0.2
	floor_max_angle = deg_to_rad(50.0)
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_ADD_VELOCITY
	if get_child_count() == 0:
		_build_body()


## 自分のジャンプを要求する。能力・禁止の確認は呼び出し側（InputRouter）で済ませている前提だが、
## 念のためここでも ledger を確認し、床にいるときだけ跳ぶ。
func request_jump() -> void:
	if not puppet:
		_jump_requested = true


## ダッシュ（方向キーの向きへ、まっすぐ 3 マス×持っている数）。W/A/D のどれかが要る。
func request_dash() -> void:
	if puppet or ledger == null or not ledger.player_can(RuleAction.Kind.DASH, player_id):
		return
	if floor_bans.has(RuleAction.Kind.DASH):
		floor_ban_refused.emit(RuleAction.Kind.DASH)
		return
	if not is_on_floor() and _air_dash_used:
		return
	var dir := _dash_direction()
	if dir == Vector3.ZERO:
		return
	_dash_dir = dir
	var count := ledger.ability_count(RuleAction.Kind.DASH, player_id)
	_dash_left = float(Tuning.DASH_CELLS) * Tuning.stack_factor(count)
	# 地上でも空中でも、ダッシュは床に着くまで1回だけ（地上のダッシュで谷へ出てから空中でもう一度、を防ぐ）
	_air_dash_used = true
	dashed.emit()


func is_dashing() -> bool:
	return _dash_left > 0.0


## 通信で受け取った仲間の状態。serial は投げた回数（-1 なら見ない）。
func apply_remote(at: Vector3, yaw: float, moving: bool, on_floor: bool, serial: int = -1) -> void:
	remote_position = at
	remote_yaw = yaw
	remote_moving = moving
	remote_on_floor = on_floor
	if serial >= 0 and serial != throw_serial:
		throw_serial = serial
		_start_throw_animation()


## 送る自分の状態 [位置, 体の向き, 歩いているか, 床にいるか, 投げた回数]。
func remote_state() -> Array:
	var moving := Vector2(velocity.x, velocity.z).length() > 0.1
	return [global_position, _facing, moving, is_on_floor(), throw_serial]


## 投げる動きを始める（docs/adr/0017）。toward（水平の向き）があれば、自分のアバターはそちらへ体を向ける。
func play_throw(toward: Vector3 = Vector3.ZERO) -> void:
	throw_serial += 1
	var flat := Vector3(toward.x, 0.0, toward.z)
	if not puppet and flat.length() > 0.01:
		_facing = atan2(-flat.x, -flat.z)
		if _visual != null:
			_visual.rotation.y = _facing
	_start_throw_animation()


func _start_throw_animation() -> void:
	_throw_left = THROW_TIME
	if _rig != null:
		_rig.play_once(RigAnimator.THROW)


func is_throwing() -> bool:
	return _throw_left > 0.0


## 手を離す瞬間の右手の位置（throw の 7 フレーム目。体の向きから求める）。
func hand_position() -> Vector3:
	var basis := Basis(Vector3.UP, _facing)
	return global_position + basis * Vector3(0.28, 1.5, -0.2)


## 体の向き（ラジアン、Y軸回り）。
func facing() -> float:
	return _facing


## 体をその向きへすぐ向ける（広場でポータルの前に戻ったとき。PartyDirector）。
func face(yaw: float) -> void:
	_facing = yaw
	if _visual != null:
		_visual.rotation.y = _facing


func feet_position() -> Vector3:
	return global_position


## その行動を自分から使えるか（能力があって、自分にも足もとのブロックにも禁止が無い）。
func can(action: RuleAction.Kind) -> bool:
	return ledger != null and ledger.player_can(action, player_id) and not floor_bans.has(action)


## 足もとの禁止で、その能力がいま使えないか（ジャンプ禁止なら、ブーツの高跳びも使えない）。表示用。
func floor_blocks(action: RuleAction.Kind) -> bool:
	if floor_bans.has(action):
		return true
	return action == RuleAction.Kind.HIGH_JUMP and floor_bans.has(RuleAction.Kind.JUMP)


## いまのジャンプの高さ。ジャンプブーツ（高跳び）を装備していれば固定で高くなる（企画書 7）。
## 高跳びはジャンプの強化なので、ジャンプ自体が使えない（貸出中・禁止）なら跳べない。
## 仲間から集めたジャンプが n 個なら、到達高度は n 倍（Tuning.stack_factor）。
func jump_height() -> float:
	var base := Tuning.PLAYER_JUMP_HEIGHT
	if ledger == null:
		return base
	if can(RuleAction.Kind.HIGH_JUMP):
		base = Tuning.BOOTS_JUMP_HEIGHT
	return base * Tuning.stack_factor(ledger.ability_count(RuleAction.Kind.JUMP, player_id))


## クライミンググローブ（登る）: 壁に触れていて、その壁へ向かって進もうとしているあいだ登る。
## 進めない方向（能力が無い・禁止）へは押せないので、移動の能力・禁止も守る。
func _should_climb(direction: Vector3) -> bool:
	if not can(RuleAction.Kind.CLIMB):
		return false
	if not is_on_wall() or direction.length() < 0.1:
		return false
	return get_wall_normal().dot(direction.normalized()) < -0.5


func _physics_process(delta: float) -> void:
	if puppet:
		_follow_remote(delta)
		return
	if _dash_left > 0.0:
		_dash_step(delta)
		return
	if is_on_floor():
		_air_dash_used = false
	var bans := FloorBans.under(ledger, self)
	if bans != floor_bans:
		floor_bans = bans
		floor_bans_changed.emit()
	_notice_refused_moves()
	var direction := _allowed_direction()
	velocity.x = direction.x * Tuning.PLAYER_SPEED
	velocity.z = direction.z * Tuning.PLAYER_SPEED
	if not is_on_floor():
		velocity.y -= Tuning.GRAVITY * delta
	if nature != null:
		NatureMotion.apply(self, delta)
	if _jump_requested:
		_jump_requested = false
		var footing := is_on_floor() or afloat
		if footing and can(RuleAction.Kind.JUMP):
			velocity.y = Tuning.jump_velocity(jump_height())
			jumped.emit()
		elif (
			footing
			and floor_bans.has(RuleAction.Kind.JUMP)
			and ledger.player_can(RuleAction.Kind.JUMP, player_id)
		):
			floor_ban_refused.emit(RuleAction.Kind.JUMP)
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


## ダッシュ中: 重力を受けずにまっすぐ進む。壁に当たったらそこで止まる。
func _dash_step(delta: float) -> void:
	var step := minf(Tuning.DASH_SPEED * delta, _dash_left)
	velocity = _dash_dir * (step / delta)
	var before := global_position
	move_and_slide()
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	_dash_left -= step
	if moved < step * 0.3:
		_dash_left = 0.0  # 壁に当たった
	if _dash_left <= 0.0:
		_dash_left = 0.0
		velocity = Vector3.ZERO
	_animate(delta, _dash_dir)


## 操り人形: 受け取った位置へなめらかに寄せ、歩きの見た目だけ動かす。
func _follow_remote(delta: float) -> void:
	var gap := remote_position - global_position
	if gap.length() > 4.0:
		global_position = remote_position  # 大きくずれたら（復活・瞬間移動）すぐ合わせる
	else:
		global_position = global_position.lerp(remote_position, minf(1.0, delta * 15.0))
	_facing = lerp_angle(_facing, remote_yaw, minf(1.0, delta * 12.0))
	if _visual != null:
		_visual.rotation.y = _facing
	var shown := Vector3(-sin(_facing), 0.0, -cos(_facing)) if remote_moving else Vector3.ZERO
	_animate_limbs(delta, shown, remote_on_floor)


## 能力があり禁止されていない方向だけを合成する。同じ方向の能力を n 個持てば、その方向の速さは n 倍。
## ダッシュの向き。方向キー＋ダッシュで、その向きへ突進する。W/A/D のどれかを持っていないと
## ダッシュできない（後ろ向きのダッシュは無し。2026-11-20 本人の判断「W がある前提」）。
## 方向キーを押していなければ、W を持っているときだけ体の向きへ。できなければ ZERO。
func _dash_direction() -> Vector3:
	var local := Vector2.ZERO
	if move_intent.y > 0.0 and can(RuleAction.Kind.FORWARD):
		local.y = 1.0
	if move_intent.x < 0.0 and can(RuleAction.Kind.LEFT):
		local.x = -1.0
	if move_intent.x > 0.0 and can(RuleAction.Kind.RIGHT):
		local.x = 1.0
	if local != Vector2.ZERO:
		var basis := Basis(Vector3.UP, view_yaw)
		return (basis * Vector3.FORWARD * local.y + basis * Vector3.RIGHT * local.x).normalized()
	if can(RuleAction.Kind.FORWARD):
		return Vector3(-sin(_facing), 0.0, -cos(_facing))
	return Vector3.ZERO


func _allowed_direction() -> Vector3:
	if ledger == null:
		return Vector3.ZERO
	var local := Vector2.ZERO
	if move_intent.y > 0.0:
		local.y += move_intent.y * _speed_factor(RuleAction.Kind.FORWARD)
	if move_intent.y < 0.0:
		local.y += move_intent.y * _speed_factor(RuleAction.Kind.BACK)
	if move_intent.x < 0.0:
		local.x += move_intent.x * _speed_factor(RuleAction.Kind.LEFT)
	if move_intent.x > 0.0:
		local.x += move_intent.x * _speed_factor(RuleAction.Kind.RIGHT)
	var peak := maxf(absf(local.x), absf(local.y))
	if local.length() > peak and local.length() > 0.0:
		local = local.normalized() * peak  # 斜めでも速くならない
	var basis := Basis(Vector3.UP, view_yaw)
	var forward := basis * Vector3.FORWARD
	var right := basis * Vector3.RIGHT
	return forward * local.y + right * local.x


## 低い段差（Tuning.STEP_ASSIST_HEIGHT 以下）を歩いて上がる補助（企画書 4-6）。
## 移動入力があるときだけ働き、隙間を飛び越えたり禁止を無視したりはしない。
## その方向へ進めるときの速さの倍率（進めなければ 0）。
func _speed_factor(action: RuleAction.Kind) -> float:
	if not can(action):
		return 0.0
	return Tuning.stack_factor(ledger.ability_count(action, player_id))


## 足もとの禁止で歩けない向きへ押し始めたら、一度だけ知らせる（押し続けても繰り返さない）。
func _notice_refused_moves() -> void:
	var pressed := {
		RuleAction.Kind.FORWARD: move_intent.y > 0.0,
		RuleAction.Kind.BACK: move_intent.y < 0.0,
		RuleAction.Kind.LEFT: move_intent.x < 0.0,
		RuleAction.Kind.RIGHT: move_intent.x > 0.0,
	}
	for action: RuleAction.Kind in pressed:
		var refused: bool = (
			pressed[action] and floor_bans.has(action) and ledger.player_can(action, player_id)
		)
		if refused and not _refused_moves.has(action):
			floor_ban_refused.emit(action)
		if refused:
			_refused_moves[action] = true
		else:
			_refused_moves.erase(action)


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
	var speed := minf(direction.length(), 1.0)
	if speed > 0.05:
		var target := atan2(-direction.x, -direction.z)
		_facing = lerp_angle(_facing, target, minf(1.0, delta * 12.0))
		_visual.rotation.y = _facing
	_animate_limbs(delta, direction, is_on_floor())


## 歩きの見た目は骨格のアニメーションで出す（コードで手足を振らない。2026-11-21 本人の指示）。
## 進んでいれば walk（速さに合わせて再生を速める）、空中なら jump、止まっていれば idle。
func _animate_limbs(delta: float, direction: Vector3, grounded: bool) -> void:
	if _rig == null:
		return
	if _throw_left > 0.0:
		_throw_left = maxf(0.0, _throw_left - delta)
		return
	if _cheer_left > 0.0:
		_cheer_left = maxf(0.0, _cheer_left - delta)
		if grounded and direction.length() <= 0.05:
			_rig.play(RigAnimator.HAPPY)
			return
	_rig.move(minf(direction.length(), 1.0) * 1.15, grounded)


## 喜ぶ動きをしばらく見せる（クリアしたとき。歩き出したら歩きに戻る）。
func celebrate(seconds: float = 2.5) -> void:
	_cheer_left = seconds


## いま再生しているアニメーションの名前（テスト・見た目の確認用）。
func animation_state() -> StringName:
	return _rig.current if _rig != null else &""


func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	shape.shape = capsule
	shape.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	add_child(shape)

	# 見た目は Blender の骨格付きモデル（art/scripts/build_cast.py）。部品（Body Head ArmL ArmR LegL LegR）を
	# 骨で動かすアニメーションを RigAnimator が切り替える
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_model = ModelLibrary.instantiate("traveler")
	_visual.add_child(_model)
	ArtPalette.tint_player(_model, player_id)
	_rig = RigAnimator.new(_model)


func _set_player_id(value: int) -> void:
	player_id = value
	if _model != null:
		ArtPalette.tint_player(_model, value)
