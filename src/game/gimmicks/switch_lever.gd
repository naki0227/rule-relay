class_name SwitchLever
extends Node3D
## レバー（docs/adr/0014）。近くで F を押すと、入る ↔ 切れるが切り替わる（持続）。
## 当たり判定は持たない（チェックポイントの台座と同じく、近くに立って F）。
## 入っているかはホストが決め（MechanismSet）、参加者には WorldFrame で届く。
## 見た目は柄が倒れるアニメーション「flip」（switch_lever.glb）の位置を、倒れ具合に合わせる。

const MODEL := "switch_lever"
## F が届く距離（足もとの水平距離と高さの差）。
const REACH: float = 1.4
const FLIP_SPEED: float = 6.0

var spec: MechanismSpecs.LeverSpec
var on: bool = false

var _amount: float = 0.0
var _player: AnimationPlayer
var _pulse_timer: float = 0.0


func setup(p_spec: MechanismSpecs.LeverSpec) -> void:
	spec = p_spec
	name = "Lever_%s" % spec.key
	position = spec.position
	on = spec.start_on
	_amount = 1.0 if on else 0.0


func _ready() -> void:
	var model := ModelLibrary.instantiate(MODEL)
	add_child(model)
	_player = RigPose.player_of(model)
	PrototypeIsland.add_label(
		self, Vector3(0.0, 1.25, 0.0), "レバー（%s で倒す）" % InputMode.token(&"interact")
	)
	RigPose.hold(_player, &"flip", _amount)


## 足もと feet から F が届くか。
func within_reach(feet: Vector3) -> bool:
	var flat := feet - global_position
	var dy := flat.y
	flat.y = 0.0
	return flat.length() <= REACH and absf(dy) < 1.2


func toggle() -> void:
	on = not on


func is_active() -> bool:
	return on


func reaches(at: Vector3) -> bool:
	return on and spec.signal_radius > 0.0 and global_position.distance_to(at) <= spec.signal_radius


func _process(delta: float) -> void:
	var target := 1.0 if on else 0.0
	if not is_equal_approx(_amount, target):
		_amount = move_toward(_amount, target, delta * FLIP_SPEED)
		RigPose.hold(_player, &"flip", _amount)
	if not reaches(global_position):
		_pulse_timer = Tuning.SIGNAL_PULSE_PERIOD
		return
	_pulse_timer += delta
	if _pulse_timer >= Tuning.SIGNAL_PULSE_PERIOD:
		_pulse_timer = 0.0
		RigPose.pulse(self, spec.signal_radius, UiTheme.HONEY)
