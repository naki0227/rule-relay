class_name SwitchDoor
extends Node3D
## スイッチの扉（docs/adr/0014）。板・レバー・鐘（時の鐘も）につながり、開くと床へ沈む。
## 当たり判定は地形と同じ層の箱（AnimatableBody3D）なので、プレイヤー・ブロック・生き物の道を
## 地形として塞ぐ（ルールで止めない。開かない扉は地形）。ブロックの「登る」・生き物の道探しにも見える。
## 開き具合 open_amount（0 = 閉じている、1 = 開いている）はホストが決め（MechanismSet）、
## 参加者には WorldFrame で届く。見た目は扉板が沈むアニメーション「open」（switch_door.glb）の位置を合わせる。
##
## 挟まない: 閉じようとしたとき、閉じた箱の中に誰かいれば、出るまでその高さで待つ（MechanismSet.occupied）。

signal started_moving(opening: bool)

const MODEL := "switch_door"
## 開く・閉じるのにかかる秒数（高さによらない）。
const MOVE_TIME: float = 0.6
## モデルの扉板の高さ（高い扉はモデルを縦に伸ばす）。
const MODEL_HEIGHT: float = 2.0

var spec: MechanismSpecs.DoorSpec
var open_amount: float = 0.0
## 切り替えの扉（TOGGLE）の、いまの向き（true = 開ける側）。
var toggled: bool = false
## 前のフレームで入力があったか（切り替えの扉が「作動し始め」を見分けるため）。
var was_active: bool = false
## 開こうとしている向き（音の合図に使う）。
var heading_open: bool = false
var body: AnimatableBody3D
## 参加者の画面: ホストから届いた開き具合へ、なめらかに近づける。
var remote: bool = false

var _remote_target: float = 0.0

var _players: Array[AnimationPlayer] = []


func setup(p_spec: MechanismSpecs.DoorSpec) -> void:
	spec = p_spec
	name = "Door_%s" % spec.key
	position = Vector3(spec.cell) + Vector3(spec.size.x * 0.5, 0.0, spec.size.z * 0.5)


func _ready() -> void:
	body = AnimatableBody3D.new()
	body.name = "Body"
	body.sync_to_physics = true
	body.collision_layer = Tuning.LAYER_TERRAIN
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(spec.size)
	shape.shape = box
	shape.position.y = spec.size.y * 0.5
	body.add_child(shape)
	add_child(body)
	for x in spec.size.x:
		for z in spec.size.z:
			var model := ModelLibrary.instantiate(MODEL)
			model.position = Vector3(x + 0.5 - spec.size.x * 0.5, 0.0, z + 0.5 - spec.size.z * 0.5)
			model.scale.y = spec.size.y / MODEL_HEIGHT
			# 扉板の面（Blender の ±Y）を、扉の薄い向きにそろえる
			if spec.size.x < spec.size.z:
				model.rotation.y = PI * 0.5
			add_child(model)
			_players.append(RigPose.player_of(model))
	if spec.inverted:
		open_amount = 1.0
		heading_open = true
	apply_amount()


## 入力（つながった源が作動しているか）から、開けたいかを決める。切り替えの扉は作動し始めで向きを変える。
func wants_open(active: bool) -> bool:
	if spec.mode == MechanismSpecs.DoorMode.TOGGLE:
		if active and not was_active:
			toggled = not toggled
		was_active = active
		return toggled != spec.inverted
	was_active = active
	return active != spec.inverted


## 1 フレーム進める（ホスト）。occupied なら閉じる向きには動かない。端に着いたフレームだけ true。
func step(delta: float, open: bool, occupied: bool) -> bool:
	if open != heading_open:
		heading_open = open
		started_moving.emit(open)
	var target := 1.0 if open else 0.0
	if (target < open_amount and occupied) or is_equal_approx(open_amount, target):
		return false
	open_amount = move_toward(open_amount, target, delta / MOVE_TIME)
	apply_amount()
	return is_equal_approx(open_amount, target)


## 参加者の画面: ホストの開き具合を受け取る（大きくずれたらすぐ合わせる）。
func set_remote_amount(amount: float) -> void:
	remote = true
	_remote_target = clampf(amount, 0.0, 1.0)
	if absf(_remote_target - open_amount) > 0.5:
		open_amount = _remote_target
		apply_amount()


func _physics_process(delta: float) -> void:
	if remote and not is_equal_approx(open_amount, _remote_target):
		open_amount = move_toward(open_amount, _remote_target, delta / MOVE_TIME * 1.25)
		apply_amount()


func is_open() -> bool:
	return open_amount >= 0.999


func is_closed() -> bool:
	return open_amount <= 0.001


## 閉じたときに扉が占める箱（世界の座標）。
func closed_box() -> AABB:
	return AABB(Vector3(spec.cell), Vector3(spec.size))


## 開き具合を当たり判定と見た目に反映する。
func apply_amount() -> void:
	if body != null:
		body.position = Vector3(0.0, -open_amount * spec.size.y, 0.0)
	for player in _players:
		RigPose.hold(player, &"open", open_amount)


func capture_state() -> Array:
	return [open_amount, toggled, was_active, heading_open]


func restore_state(state: Array) -> void:
	if state.size() < 4:
		return
	open_amount = clampf(float(state[0]), 0.0, 1.0)
	toggled = bool(state[1])
	was_active = bool(state[2])
	heading_open = bool(state[3])
	apply_amount()
