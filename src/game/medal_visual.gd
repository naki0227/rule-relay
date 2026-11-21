class_name MedalVisual
extends Node3D
## 投げたメダルの見た目（docs/adr/0017）: 器のメダル（vessel_medal / ban_medal と行動の記号）を小さくして、
## 飛びながら縦に回す。後ろに短い点の尾を引く。当たり判定はない（飛び方はホストの ThrownMedal が決める）。
## 参加者の画面では、ホストから届く位置と速さで間を埋める（WorldFrame の "medals"）。

## メダルの大きさ（落ちている器のメダルに対する倍率）。
const SCALE: float = 0.75
## 尾の点の数と、点を置く間隔（m）。目立ちすぎないよう少なく、薄く。
const TRAIL_DOTS: int = 7
const TRAIL_SPACING: float = 0.32
const TRAIL_ALPHA: float = 0.42
const SPIN_SPEED: float = 16.0
## 参加者の画面で、ホストの値を受け取ってから先読みする最長の秒数。
const MAX_EXTRAPOLATE: float = 0.15

## 参加者の画面: 外れて手元へ戻る途中（消えたときに当たった輪を出さない）。
var returning: bool = false

var _model: Node3D
var _trail: Array[MeshInstance3D] = []
var _history: Array[Vector3] = []
var _spin: float = 0.0
## 参加者の画面: 最後に受け取った位置・速さと、そこからの経過秒数。
var _base_position: Vector3 = Vector3.ZERO
var _base_velocity: Vector3 = Vector3.ZERO
var _since: float = 0.0
var _remote: bool = false


func setup(action: RuleAction.Kind, is_prohibition: bool) -> void:
	var t := RuleToken.new()
	t.action = action
	t.is_prohibition = is_prohibition
	_model = Node3D.new()
	_model.name = "Spin"
	_model.add_child(WorldItem.medal_model(t))
	_model.scale = Vector3.ONE * SCALE
	add_child(_model)
	var color := UiTheme.BAN if is_prohibition else UiTheme.HONEY
	for i in TRAIL_DOTS:
		var dot := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		var radius := 0.07 * (1.0 - float(i) / float(TRAIL_DOTS + 1))
		sphere.radius = radius
		sphere.height = radius * 2.0
		sphere.radial_segments = 8
		sphere.rings = 4
		dot.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(color, TRAIL_ALPHA * (1.0 - float(i) / float(TRAIL_DOTS)))
		dot.material_override = mat
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dot.top_level = true
		dot.visible = false
		add_child(dot)
		_trail.append(dot)


## 飛んでいる向きに合わせて回し、尾を伸ばす（ホストの ThrownMedal が毎フレーム呼ぶ）。
func advance(delta: float, at: Vector3) -> void:
	global_position = at
	_spin += delta * SPIN_SPEED
	if _model != null:
		_model.rotation = Vector3(_spin, _spin * 0.35, 0.0)
	_record(at)


## 参加者の画面: ホストから届いた位置と速さ。大きくずれたらすぐ合わせ、そうでなければ先読みから寄せる。
func apply_remote(at: Vector3, velocity: Vector3) -> void:
	if not _remote or global_position.distance_to(at) > 1.5:
		global_position = at
	_remote = true
	_base_position = at
	_base_velocity = velocity
	_since = 0.0


func _process(delta: float) -> void:
	if not _remote:
		return
	_since = minf(_since + delta, MAX_EXTRAPOLATE)
	var guess := (
		_base_position
		+ _base_velocity * _since
		+ Vector3(0.0, -0.5 * MedalThrow.GRAVITY * _since * _since, 0.0)
	)
	advance(delta, global_position.lerp(guess, minf(1.0, delta * 20.0)))


func _record(at: Vector3) -> void:
	if _history.is_empty() or _history[0].distance_to(at) >= TRAIL_SPACING:
		_history.push_front(at)
		if _history.size() > TRAIL_DOTS + 1:
			_history.pop_back()
	for i in _trail.size():
		var dot := _trail[i]
		dot.visible = i + 1 < _history.size()
		if dot.visible:
			dot.global_position = _history[i + 1]


## 当たったところに小さく広がって消える輪（1 つだけ。散らかさない）。
static func puff(parent: Node, at: Vector3, color: Color = UiTheme.HONEY) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var node := MedalPuff.new()
	node.tint = color
	parent.add_child(node)
	node.global_position = at
