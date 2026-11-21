class_name PressurePlate
extends Node3D
## 重さの板（docs/adr/0014）。床に貼りついた薄い板で、当たり判定は持たない（道を変えない）。
## 足もとが板の上にあるもの（プレイヤー・ブロック・生き物）の重さの合計が required_weight 以上の間、押される。
## 押されているかはホストが決め（MechanismSet）、参加者には WorldFrame で届く。
## 見た目は天板が沈むアニメーション「press」（pressure_plate.glb）の位置を、沈み具合に合わせる。

const MODEL := "pressure_plate"
## 足もとの高さが板の面からこの範囲なら「乗っている」（跳んでいる途中は乗っていない）。
const STAND_TOLERANCE: float = 0.35
## 天板が沈む・戻る速さ（1 秒あたりの度合い）。
const PRESS_SPEED: float = 8.0

var spec: MechanismSpecs.PlateSpec
var pressed: bool = false
## いま乗っている重さ（ホストだけが数える。表示用）。
var weight: float = 0.0

var _amount: float = 0.0
var _players: Array[AnimationPlayer] = []
var _pulse_timer: float = 0.0


func setup(p_spec: MechanismSpecs.PlateSpec) -> void:
	spec = p_spec
	name = "Plate_%s" % spec.key
	position = Vector3(
		spec.cell.x + spec.size.x * 0.5, spec.cell.y + 0.005, spec.cell.z + spec.size.y * 0.5
	)


func _ready() -> void:
	for x in spec.size.x:
		for z in spec.size.y:
			var model := ModelLibrary.instantiate(MODEL)
			model.position = Vector3(x + 0.5 - spec.size.x * 0.5, 0.0, z + 0.5 - spec.size.y * 0.5)
			add_child(model)
			_players.append(RigPose.player_of(model))
	var need := "" if spec.required_weight <= 1 else "（%d 人分の重さ）" % spec.required_weight
	PrototypeIsland.add_label(self, Vector3(0.0, 0.9, 0.0), "重さの板%s" % need)
	_show(0.0)


## 足もと feet が板の上か。
func covers(feet: Vector3) -> bool:
	return (
		feet.x >= spec.cell.x
		and feet.x < spec.cell.x + spec.size.x
		and feet.z >= spec.cell.z
		and feet.z < spec.cell.z + spec.size.y
		and absf(feet.y - spec.cell.y) <= STAND_TOLERANCE
	)


## 乗っている重さから、押されているかを決める（ホスト）。変わったら true。
## weights は feet_points と同じ順の重さ（ふつうは 1。「重い」を持つものは BodyTraits.weight_units）。
func evaluate(feet_points: Array[Vector3], weights: Array[float] = []) -> bool:
	weight = 0.0
	for i in feet_points.size():
		if covers(feet_points[i]):
			weight += weights[i] if i < weights.size() else 1.0
	var now := weight >= float(spec.required_weight)
	if now == pressed:
		return false
	pressed = now
	return true


func is_active() -> bool:
	return pressed


## 押されている間、音波が at に届くか（signal_radius が 0 なら届かない）。
func reaches(at: Vector3) -> bool:
	return (
		pressed
		and spec.signal_radius > 0.0
		and global_position.distance_to(at) <= spec.signal_radius
	)


func _process(delta: float) -> void:
	var target := 1.0 if pressed else 0.0
	if not is_equal_approx(_amount, target):
		_show(move_toward(_amount, target, delta * PRESS_SPEED))
	if not reaches(global_position):
		_pulse_timer = Tuning.SIGNAL_PULSE_PERIOD
		return
	_pulse_timer += delta
	if _pulse_timer >= Tuning.SIGNAL_PULSE_PERIOD:
		_pulse_timer = 0.0
		RigPose.pulse(self, spec.signal_radius, UiTheme.HONEY)


func _show(amount: float) -> void:
	_amount = amount
	for player in _players:
		RigPose.hold(player, &"press", amount)
