class_name ThrownMedal
extends Node3D
## 「投げる」で投げたメダル（docs/adr/0017）。ホストだけが動かす。
## 1. 振りかぶり（RELEASE_DELAY 秒）: 見えない。投げた人の動きに合わせて待つ
## 2. 飛ぶ: 手の位置から、狙った点を通る放物線（位置は時間の式で決めるので、フレームの長さでずれない）。
##    前のフレームの位置から今の位置までの光線で、最初に当たった物を MedalThrow.land に渡す
## 3. 外れた（届く距離・時間を超えた・島の下へ落ちた）ら、投げた人の手元へ短く戻って消える
## 能力は飛んでいる間も器（手元）にあり、当たった瞬間に当たった物へ付与する。保存はしない（復元で消える）。

enum Phase { WINDUP, FLYING, RETURNING }

## 戻る見た目の秒数。
const RETURN_TIME: float = 0.3

## 運ぶトークンと、投げた人。
var token_id: int = -1
var thrower_id: int = -1
var mode: TriggerMode.Kind = TriggerMode.Kind.SINGLE_SHOT
var use_range: bool = false
## 狙った点（世界座標）と、投げた時点の胸の位置・届く距離。
var aim: Vector3 = Vector3.ZERO
## 狙った相手（弧を選ぶときに使う。地形のセルなら aimed は null で、セルを aimed_cell に持つ）。
var aimed: Node3D
var aimed_cell: Vector3i = Vector3i.MAX
## 狙った点の、相手の位置からのずれ（手を離すときに、動いた相手に合わせ直す）。
var aim_offset: Vector3 = Vector3.ZERO
var chest: Vector3 = Vector3.ZERO
var reach: float = Tuning.THROW_REACH
## 投げた人へのメッセージの送り先（参加者の代わりに投げたとき）。
var sink: Callable = Callable()
## 通信で見分ける番号。
var serial: int = 0
var phase: Phase = Phase.WINDUP

var _thrower: PlayerAvatar
var _windup_left: float = 0.0
var _origin: Vector3 = Vector3.ZERO
var _launch: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _flight_time: float = 0.0
var _return_from: Vector3 = Vector3.ZERO
var _visual: MedalVisual
var _world: GameWorld


func setup(world: GameWorld, thrower: PlayerAvatar, t: RuleToken) -> void:
	_world = world
	_thrower = thrower
	_windup_left = MedalThrow.RELEASE_DELAY
	_visual = MedalVisual.new()
	_visual.name = "Visual"
	_visual.setup(t.action, t.is_prohibition)
	_visual.visible = false
	add_child(_visual)


## 投げた人のアバター（抜けていれば null）。
func thrower() -> PlayerAvatar:
	return _thrower if is_instance_valid(_thrower) else null


func is_released() -> bool:
	return phase != Phase.WINDUP


## いまの速さ（通信で配る）。
func velocity() -> Vector3:
	if phase != Phase.FLYING:
		return Vector3.ZERO
	return _launch + Vector3(0.0, -MedalThrow.GRAVITY * _age, 0.0)


func action() -> RuleAction.Kind:
	var t := _world.ledger.token(token_id)
	return t.action if t != null else RuleAction.Kind.THROW


func is_prohibition() -> bool:
	var t := _world.ledger.token(token_id)
	return t != null and t.is_prohibition


func _physics_process(delta: float) -> void:
	match phase:
		Phase.WINDUP:
			_windup_left -= delta
			if _windup_left <= 0.0:
				_release()
		Phase.FLYING:
			_fly(delta)
		Phase.RETURNING:
			_return(delta)


func _release() -> void:
	_origin = _thrower.hand_position() if is_instance_valid(_thrower) else chest
	global_position = _origin
	if not is_instance_valid(aimed):
		aimed = null
	if aimed != null:
		aim = aimed.global_position + aim_offset  # 振りかぶっている間に動いた相手に合わせ直す
	var arc := MedalThrow.choose_arc(_world, self, _origin)
	_flight_time = float(arc["time"])
	aim = arc["aim"] as Vector3
	_launch = MedalThrow.launch_velocity(_origin, aim, _flight_time)
	phase = Phase.FLYING
	_visual.visible = true
	_visual.advance(0.0, _origin)
	_world.sound_requested.emit(&"dash", _origin, true)


func _point_at(time: float) -> Vector3:
	return _origin + _launch * time + Vector3(0.0, -0.5 * MedalThrow.GRAVITY * time * time, 0.0)


func _fly(delta: float) -> void:
	var from := _point_at(_age)
	_age += delta
	var to := _point_at(_age)
	var hit := MedalThrow.cast(_world, from, to, _thrower)
	if not hit.is_empty():
		global_position = hit["position"] as Vector3
		_visual.advance(delta, global_position)
		MedalThrow.land(_world, self, hit)
		return
	global_position = to
	_visual.advance(delta, to)
	var too_far := to.distance_to(chest) > reach + MedalThrow.REACH_MARGIN
	var too_long := _age > _flight_time + MedalThrow.EXTRA_TIME
	if too_far or too_long or to.y < Tuning.FALL_LIMIT_Y:
		MedalThrow.miss(_world, self)


## 外れた: 投げた人の手元へ戻る見た目（能力はもともと手元にある）。
func start_return() -> void:
	phase = Phase.RETURNING
	_return_from = global_position
	_age = 0.0


func _return(delta: float) -> void:
	_age += delta
	var k := clampf(_age / RETURN_TIME, 0.0, 1.0)
	var home := _thrower.hand_position() if is_instance_valid(_thrower) else chest
	var at := _return_from.lerp(home, k * k)
	global_position = at
	_visual.advance(delta, at)
	if k >= 1.0:
		queue_free()
