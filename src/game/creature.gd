class_name Creature
extends CharacterBody3D
## 願いを持つ生き物（企画書 6）。願いは「高いところへ行きたい」。
## 何をするかは CreatureMind が決め、ここでは決めた道を物理で進む。プレイヤーは命令できない。
## 能力は単体でだけ受け取り（範囲は不可）、発動方式は持たない。自分で使うかを願いに沿って選ぶ。
## W/A/S/D は、その生き物が向いている向きが基準（前・左・右・後ろ）。体の向きは自由に変えられる。

signal jumped
signal stage_changed(stage: CreatureMind.Stage)
## 持っている物を投げた（GameWorld が玉を飛ばす）。
signal threw(from: Vector3, velocity: Vector3)
## 移動の能力をもらったのに上がれない所で止まった（一度だけ。GameWorld が短い知らせにする）。
signal stuck_noticed(text: String)

const RADIUS: float = 0.3
const HEIGHT: float = 0.7
const SPEED: float = 2.4
## 次のマスへこの時間進めなければ、その一歩は塞がれているとみなして別の道を探す
const STUCK_TIME: float = 1.2
## 待っている間も、ときどき見回して判断し直す
const LOOK_AROUND_PERIOD: float = 1.5
## 木の実を投げた後に喜ぶ動きを見せる秒数。
const CHEER_TIME: float = 1.6
## 見た目のモデル（art/scripts/build_cast.py）。当たり判定はどちらも同じカプセル。
const MODEL_WISH := "creature_wish"
const MODEL_KIT := "creature_kit"
## 願いの一文の既定（StageDef.CreatureSpec.wish_text が空のとき）。
const WISH_NEST := "高いところの巣へ行きたい"
const WISH_HIGHER := "高いところへ行きたい"

var entity_id: int = -1
## 見た目のモデルの名前（add_child の前に決める）。
var look: String = MODEL_WISH
var ledger: RuleLedger
## マスごとの立てる高さを返す関数（GameWorld が地形とブロックを調べる）。
## (center: Vector2i, radius: int) -> {Vector2i: 高さ}
var survey: Callable
## 地形だけのマスごとの高さ（同じ形の関数）。道が無いときに近づく「高い場所」は地形からだけ選ぶ。
var ground_survey: Callable
var stage: CreatureMind.Stage = CreatureMind.Stage.WAIT
var path: Array[Vector2i] = []
## 向いている世界の方角（x = 東、y = 南）。W はこの向き、A はその左、D は右、S は後ろ。
var facing: Vector2i = Vector2i(0, -1)
## 持っている物（例: 木の実）。空なら何も持っていない。「投げる」があると、立ち止まったときに投げる
## （2026-11-19 本人の判断: 何かを持っているなら投げる）。
var held_item: String = ""
## 参加者の画面では、ホストから受け取った位置へ動くだけ（考えない・物理を計算しない）。
var remote: bool = false
## 外の力（風・流れ）の速さ、落ちる速さの上限（浮く）、水に浮かぶ足の高さ（NAN なら浮かない）。
## ホストの NatureTicks が毎フレーム決める（docs/adr/0015）。
var external_velocity: Vector3 = Vector3.ZERO
var max_fall_speed: float = INF
var surface_hold: float = NAN
## 願いの行き先（クリア条件「巣へ運ぶ」の箱。無ければ大きさ 0）。中に入ったら願いがかなった印を出す。
var wish_box: AABB = AABB()
var _remote_target: Vector3 = Vector3.ZERO

var _blocked: Dictionary = {}
var _stuck: float = 0.0
var _since_plan: float = 0.0
var _needs_plan: bool = true
var _searching: bool = false
## 最後の判断で、行けない高い場所が見えていたか（頭の上の印に使う）。
var _sees_higher: bool = false
## プレイヤーから移動の能力を受け取っているか（上がれない知らせは、このときだけ出す）。
var _lent_move: bool = false
## 上がれない知らせを出したか（島ごとに一度だけ）。
var _stuck_told: bool = false
## 最後の判断で、ジャンプがあれば高い所へ行けたか（足りない能力の印に使う）。
var _missing_jump: bool = false
var _view: CreatureWishView
var _tokens_label: Label3D
var _outline: MeshInstance3D
var _aimed: bool = false
var _time: float = 0.0
var _body: Node3D
var _held_mesh: MeshInstance3D
## 骨格付きのモデルのアニメーション（idle / walk / happy。art/scripts/build_cast.py）。
var _rig: RigAnimator
## 喜ぶ動きを続ける残り秒数（木の実を投げた後など）。
var _cheer_left: float = 0.0


func _ready() -> void:
	collision_layer = Tuning.LAYER_CREATURES
	collision_mask = Tuning.LAYER_TERRAIN | Tuning.LAYER_BLOCKS
	floor_snap_length = 0.2
	if get_child_count() == 0:
		_build()


func setup(id: int, at: Vector3) -> void:
	entity_id = id
	name = "Creature%d" % id
	position = at


func cell() -> Vector2i:
	return Vector2i(floori(global_position.x), floori(global_position.z))


## 能力・地形が変わった（企画書 6 の4段階目: 環境変化で判断を更新して再挑戦する）。
func notify_environment_changed() -> void:
	_needs_plan = true
	_blocked.clear()
	_searching = false


## 移動の能力（W/A/S/D のどれか）を自分から使えるか。
func can_walk() -> bool:
	for move in CreatureMind.MOVES:
		if can(move):
			return true
	return false


## 知らせや案内に出す名前。
func display_name() -> String:
	return "子どもの生き物" if look == MODEL_KIT else "生き物"


## 移動はできるのに、ここからは上がれない（ふもとで止まっている）か。
func is_stuck() -> bool:
	return stage == CreatureMind.Stage.WAIT and path.is_empty() and _sees_higher and can_walk()


func can(action: RuleAction.Kind) -> bool:
	return ledger != null and ledger.can_initiate(entity_id, action)


func jump_height() -> float:
	if can(RuleAction.Kind.HIGH_JUMP):
		return Tuning.BOOTS_JUMP_HEIGHT
	return Tuning.PLAYER_JUMP_HEIGHT


## 道を選び直す。
func replan() -> void:
	_needs_plan = false
	_since_plan = 0.0
	if not is_on_floor() or not survey.is_valid():
		_needs_plan = true
		return
	var abilities := {}
	for action in RuleAction.ALL:
		abilities[action] = can(action)
	var heights := survey.call(cell(), CreatureMind.SEARCH_RADIUS) as Dictionary
	var plan := CreatureMind.plan(
		cell(), heights, abilities, jump_height(), can(RuleAction.Kind.CLIMB), _blocked, _searching
	)
	path = plan.path
	if plan.stage == CreatureMind.Stage.WAIT and _lent_move:
		# プレイヤーから移動をもらったのに道が無いときは、同じ高さのまま高い場所のふもとへ近づいて止まる
		# （動いて見せる）。最初から移動を持っている生き物は、置かれた場所で待つ（ステージの置き方を変えない）
		path = _approach(heights)
	_sees_higher = plan.sees_unreachable_height
	_missing_jump = false
	if plan.stage == CreatureMind.Stage.WAIT and not abilities[RuleAction.Kind.JUMP]:
		abilities[RuleAction.Kind.JUMP] = true
		_missing_jump = not (
			CreatureMind.plan(cell(), heights, abilities, jump_height(), false).path.is_empty()
		)
	_set_stage(plan.stage)
	_update_bubble()
	_stuck = 0.0


## 道が無いときに、同じ高さのまま近づく道（行き先の高い場所は地形だけから選ぶ）。
func _approach(heights: Dictionary) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	if not ground_survey.is_valid():
		return none
	var ground := ground_survey.call(cell(), CreatureMind.SEARCH_RADIUS) as Dictionary
	return CreatureMind.approach_path(cell(), heights, _blocked, ground)


func _physics_process(delta: float) -> void:
	_time += delta
	if remote:
		var step := _remote_target - global_position
		global_position = global_position.lerp(_remote_target, minf(1.0, delta * 15.0))
		_animate(Vector3(step.x, 0.0, step.z).limit_length(1.0))
		return
	_since_plan += delta
	if not is_on_floor():
		velocity.y = maxf(velocity.y - Tuning.GRAVITY * delta, -max_fall_speed)
	if not is_nan(surface_hold) and global_position.y < surface_hold:
		var rise := minf((surface_hold - global_position.y) * 8.0, NatureTuning.SURFACE_PUSH)
		velocity.y = maxf(velocity.y, rise)
	if _needs_plan or (stage == CreatureMind.Stage.WAIT and _since_plan > LOOK_AROUND_PERIOD):
		replan()
	var direction := Vector3.ZERO
	if not path.is_empty():
		direction = _follow(delta)
	elif stage == CreatureMind.Stage.WAIT:
		_maybe_throw()
	velocity.x = direction.x * SPEED + external_velocity.x
	velocity.z = direction.z * SPEED + external_velocity.z
	move_and_slide()
	_animate(direction)


## 道の次のマスへ向かう。着いたら次へ。段が高ければ跳ぶ（または登る）。
func _follow(delta: float) -> Vector3:
	var next := path[0]
	var target := Vector3(next.x + 0.5, global_position.y, next.y + 0.5)
	var to := target - global_position
	to.y = 0.0
	if to.length() < 0.12:
		path.pop_front()
		_stuck = 0.0
		if path.is_empty():
			_needs_plan = true
			_update_bubble()
		return Vector3.ZERO
	if cell() != next:
		var abilities := {}
		for move in CreatureMind.MOVES:
			abilities[move] = can(move)
		var choice := CreatureMind.choose_move(facing, next - cell(), abilities)
		if choice.is_empty():
			# 歩いている途中で能力を失った・禁止を受けた（禁止は願いより優先）
			path.clear()
			_needs_plan = true
			return Vector3.ZERO
		facing = choice["facing"] as Vector2i
	var rise := _rise_to(next)
	if rise > CreatureMind.STEP_HEIGHT and is_on_floor():
		if can(RuleAction.Kind.CLIMB) and is_on_wall():
			velocity.y = Tuning.CLIMB_SPEED
		elif can(RuleAction.Kind.JUMP):
			velocity.y = Tuning.jump_velocity(minf(rise + 0.35, jump_height()))
			jumped.emit()
	elif can(RuleAction.Kind.CLIMB) and is_on_wall() and rise > 0.0:
		velocity.y = Tuning.CLIMB_SPEED
	_stuck += delta
	if _stuck > STUCK_TIME:
		# 進めなかった一歩を除いて、別の道を探す（企画書 6 の2段階目）
		_blocked[CreatureMind.step_key(cell(), next)] = true
		_searching = true
		path.clear()
		_needs_plan = true
	return to.normalized()


## 持っている物を、向いている方へ投げる（投げるを自分から使えるときだけ。禁止は優先）。
func _maybe_throw() -> void:
	if held_item == "" or not is_on_floor() or not can(RuleAction.Kind.THROW):
		return
	held_item = ""
	_update_held()
	_cheer_left = CHEER_TIME
	var dir := Vector3(facing.x, 0.0, facing.y)
	threw.emit(
		global_position + dir * 0.45 + Vector3(0.0, 0.5, 0.0),
		dir * Tuning.THROW_SPEED + Vector3(0.0, 2.0, 0.0)
	)


func _update_held() -> void:
	if _held_mesh != null:
		_held_mesh.visible = held_item != ""


func _rise_to(next: Vector2i) -> float:
	if not survey.is_valid():
		return 0.0
	var heights := survey.call(next, 0) as Dictionary
	if not heights.has(next):
		return 0.0
	return float(heights[next]) - global_position.y


func _set_stage(new_stage: CreatureMind.Stage) -> void:
	if new_stage == stage and _view != null and _view.key() != "":
		return
	stage = new_stage
	if new_stage != CreatureMind.Stage.SEARCH:
		_searching = false
	_update_bubble()
	stage_changed.emit(new_stage)


## 頭の上の印。待っているときは「上がれない（道が要る）」「足りない能力」を見分けられるようにする。
func _update_bubble() -> void:
	if _view == null or remote:
		return
	_view.show_key(bubble_key_now())
	if _view.key() == CreatureWishView.KEY_STUCK and _lent_move and not _stuck_told:
		_stuck_told = true
		stuck_noticed.emit("%s: ここから上がれない…（道が要る）" % display_name())


## いまの印の鍵（CreatureWishView.KEY_*）。
func bubble_key_now() -> String:
	if is_wish_met():
		return CreatureWishView.KEY_HAPPY
	if stage == CreatureMind.Stage.SEARCH:
		return CreatureWishView.KEY_SEARCH
	if stage == CreatureMind.Stage.SEEK or not path.is_empty():
		return CreatureWishView.KEY_SEEK
	return _waiting_key()


## 待っているときの印: 移動が足りない → ジャンプが足りない → 上がれない（道が要る） → 待つ。
func _waiting_key() -> String:
	if _sees_higher and not can_walk():
		return CreatureWishView.KEY_NEED_MOVE
	if _sees_higher and _missing_jump:
		return CreatureWishView.KEY_NEED_JUMP
	return CreatureWishView.KEY_STUCK if is_stuck() else CreatureWishView.KEY_WAIT


## 表示している印の鍵（参加者の画面ではホストから届いた鍵）。
func bubble_key() -> String:
	return _view.key() if _view != null else ""


## 願いがかなったか（行き先の箱の中にいる）。
func is_wish_met() -> bool:
	return wish_box.has_volume() and wish_box.has_point(global_position)


## 願いの一文（StageWorld がステージの定義から入れる）。
func set_wish_text(text: String) -> void:
	_view.set_wish_text(text)


func wish_text() -> String:
	return _view.wish_text() if _view != null else ""


## 願いの一文を出す・隠す（プレイヤーが近くに来た・狙ったとき。PlayerInput が決める）。
func show_wish(on: bool) -> void:
	if _view != null:
		_view.show_wish(on)


func is_wish_shown() -> bool:
	return _view != null and _view.is_wish_shown()


# --- チェックポイント -------------------------------------------------------


func capture_state() -> Dictionary:
	return {
		"position": global_position,
		"velocity": velocity,
		"facing": facing,
		"held_item": held_item,
	}


## 参加者の画面で、ホストから受け取った状態 [位置, 向き, 持ち物, 頭の上の印] を目指す。
func set_remote_state(at: Vector3, new_facing: Vector2i, item: String, key: String = "") -> void:
	if _view != null and key != "":
		_view.show_key(key)
	if at.distance_to(global_position) > 3.0:
		global_position = at
	_remote_target = at
	facing = new_facing
	if item != held_item:
		if item == "":
			_cheer_left = CHEER_TIME  # ホストの画面で投げた
		held_item = item
		_update_held()


func restore_state(state: Dictionary) -> void:
	global_position = state["position"] as Vector3
	velocity = state["velocity"] as Vector3
	facing = state.get("facing", Vector2i(0, -1)) as Vector2i
	held_item = String(state.get("held_item", held_item))
	_update_held()
	path.clear()
	notify_environment_changed()


# --- 見た目（付与先の赤い輪郭・持っている能力・考えていること） ---------------


func set_highlight(on: bool) -> void:
	_aimed = on
	_update_outline()


func show_tokens(tokens: Array[RuleToken]) -> void:
	var lent_by_player := false
	_lent_move = false
	for t in tokens:
		lent_by_player = lent_by_player or t.vessel_id != -1
		var move := CreatureMind.MOVES.has(t.action) and not t.is_prohibition
		_lent_move = _lent_move or (move and t.vessel_id != -1)
	if _tokens_label != null:
		# ブロックと同じく、持っている能力・禁止を器のアイコンで並べる（禁止は赤い輪と斜線）
		for child in _tokens_label.get_children():
			child.queue_free()
		for i in tokens.size():
			var icon := Sprite3D.new()
			icon.texture = ItemIcons.for_token(tokens[i])
			icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			icon.pixel_size = 0.0026
			icon.no_depth_test = true
			icon.render_priority = 1
			icon.position.x = (float(i) - float(tokens.size() - 1) * 0.5) * 0.36
			_tokens_label.add_child(icon)
	_outline.set_meta("assigned", lent_by_player)
	_update_outline()
	notify_environment_changed()


func _update_outline() -> void:
	if _outline == null:
		return
	var assigned := bool(_outline.get_meta("assigned", false))
	_outline.visible = _aimed or assigned
	var mat := _outline.material_override as StandardMaterial3D
	mat.albedo_color = Color("#d9483b") if assigned else UiTheme.SUN


func _animate(direction: Vector3) -> void:
	if _body == null:
		return
	# 体は「向いている向き」を向く（A だけなら横歩き、S だけなら後ろ歩きに見える）
	_body.rotation.y = lerp_angle(_body.rotation.y, atan2(-float(facing.x), -float(facing.y)), 0.2)
	# 歩き・立ち止まり・喜ぶは、骨格のアニメーションで見せる（コードで体を揺らさない）
	if _rig != null:
		_cheer_left = maxf(0.0, _cheer_left - get_physics_process_delta_time())
		if _cheer_left > 0.0 and direction.length() <= 0.05:
			_rig.play(RigAnimator.HAPPY)
		else:
			_rig.move(minf(direction.length() * 1.2, 1.4), true)
	if _view != null:
		_view.position.y = 1.05 + sin(_time * 2.5) * 0.04


func _build() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	shape.shape = capsule
	shape.position.y = HEIGHT * 0.5
	add_child(shape)
	# 見た目: 丸いからだ・小さな羽・頭の芽（art/scripts/build_cast.py）。正面は -Z、原点は足もと
	_body = Node3D.new()
	_body.name = "Body"
	_body.position.y = HEIGHT * 0.5
	add_child(_body)
	var model := ModelLibrary.instantiate(look)
	model.name = "Model"
	model.position.y = -HEIGHT * 0.5
	_body.add_child(model)
	_rig = RigAnimator.new(model)
	_outline = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.42
	ring.outer_radius = 0.5
	_outline.mesh = ring
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline.material_override = mat
	_outline.position.y = 0.03
	_outline.visible = false
	add_child(_outline)
	_held_mesh = _sphere(0.11, Vector3(0.0, -0.05, -0.36), Vector3.ONE, Color("#c97b4a"))
	_body.add_child(_held_mesh)
	_update_held()
	_view = CreatureWishView.new()
	_view.name = "Wish"
	_view.position.y = 1.05
	add_child(_view)
	_tokens_label = _label(1.45, 30)
	_set_stage(CreatureMind.Stage.WAIT)


func _sphere(radius: float, at: Vector3, stretch: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mesh.mesh = sphere
	mesh.position = at
	mesh.scale = stretch
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mesh.material_override = mat
	return mesh


func _label(height: float, font_size: int) -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = height
	label.pixel_size = 0.005
	label.font = UiTheme.font(700, 2)
	label.font_size = font_size
	label.modulate = UiTheme.INK
	label.outline_modulate = Color(UiTheme.CREAM, 0.95)
	label.outline_size = 12
	add_child(label)
	return label
