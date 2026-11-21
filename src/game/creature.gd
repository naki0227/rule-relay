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

const RADIUS: float = 0.3
const HEIGHT: float = 0.7
const SPEED: float = 2.4
## 次のマスへこの時間進めなければ、その一歩は塞がれているとみなして別の道を探す
const STUCK_TIME: float = 1.2
## 待っている間も、ときどき見回して判断し直す
const LOOK_AROUND_PERIOD: float = 1.5
## 木の実を投げた後に喜ぶ動きを見せる秒数。
const CHEER_TIME: float = 1.6
## 置かれた直後・チェックポイントから戻った直後に、動き出す前に落ち着く秒数（戻した位置がすぐ崩れない）。
const SETTLE_TIME: float = 0.6
## 頭の上のブロックを調べる間隔と、よけるときの速さの倍率。
const DODGE_PERIOD: float = 0.1
const DODGE_SPEED_FACTOR: float = 3.0
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
## 地形だけのマスごとの高さ（同じ形の関数）。巣の無い生き物の行き先の「高い場所」は地形からだけ選び、
## 散歩はブロックや置物の上ではない「ふつうの地形」だけを歩く。
var ground_survey: Callable
## 禁止の付いたブロックのマス {Vector2i: {"top": 上面の高さ, "bans": {Kind: true}}}（FloorBans.survey）。
## 禁止はその上に立つ者にも効くので、そのマスから跳ぶ道・歩き出す道を選ばない（docs/adr/0003 決定 7）。
var floor_ban_survey: Callable
## 生き物が通らないマス（板・ワープの石・扉・レバー・時の鐘）を返す関数（同じ形。WorldQueries.creature_avoid）。
var avoid_survey: Callable
## プレイヤーの位置を返す関数 () -> Array[Vector3]（待っている間に、近くのプレイヤーのほうを見る）。
var peers: Callable
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
## 巣の色（WishMarker が決める。光の柱・吹き出しの巣の絵・画面の縁の案内を同じ色にする）。巣が無ければ透明。
var nest_tint: Color = Color(0, 0, 0, 0)
## 次にすることを決めるビヘイビアツリー（CreatureBrain。乱数の種は entity_id）。
var brain: CreatureBrain
## 散歩の中心（最後に自分で止まった所）。
var anchor: Vector2i = Vector2i.ZERO
## 最後の判断で選んだ葉（CreatureBrain.Choice）。
var choice: CreatureBrain.Choice = CreatureBrain.Choice.STAY
var _remote_target: Vector3 = Vector3.ZERO

var _blocked: Dictionary = {}
## いま足もとのブロックに付いた禁止のうち、自分に効くもの（FloorBans）。
var _floor_bans: Dictionary = {}
var _stuck: float = 0.0
var _since_plan: float = 0.0
var _needs_plan: bool = true
var _searching: bool = false
## 最後の判断で、足りないとわかった能力と「道が要る」（吹き出しに出す）。
var _needs: Array[RuleAction.Kind] = []
var _needs_path: bool = false
## 巣に着いて喜んだか（巣を出たらまた喜べる）。
var _celebrated: bool = false
## 見た目だけの動き（見回す・跳ねる・喜ぶ）の名前と回数（回数が変わったら参加者の画面でも再生する）。
var _act: StringName = CreatureBrain.ACT_NONE
var _act_serial: int = 0
## 見た目だけの動きの残り秒数。
var _act_left: float = 0.0
## 体だけを向ける向き（ラジアン。NAN なら向いている向き facing のまま）。W/A/S/D の基準は変えない。
var _gaze_yaw: float = NAN
## 動き出す前に落ち着く残り秒数。
var _settle_left: float = SETTLE_TIME
## 落ちてくるブロックをよけている途中か（急いで歩く）。
var _dodging: bool = false
var _dodge_left: float = 0.0
## 最初の段階を知らせたか。
var _stage_shown: bool = false
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
	brain = CreatureBrain.new(id)
	anchor = Vector2i(floori(at.x), floori(at.z))


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


## 移動はできるのに、どの能力でもここからは進めない（道が要る）所で止まっているか。
func is_stuck() -> bool:
	return stage == CreatureMind.Stage.WAIT and path.is_empty() and _needs_path and can_walk()


## 吹き出しに巣の絵を出しているか。
func shows_nest_in_bubble() -> bool:
	return _view != null and _view.shows_nest()


## 吹き出しに出している、足りない能力。
func shown_needs() -> Array[RuleAction.Kind]:
	return _view.needs() if _view != null else ([] as Array[RuleAction.Kind])


func can(action: RuleAction.Kind) -> bool:
	return ledger != null and ledger.can_initiate(entity_id, action) and not _floor_bans.has(action)


func jump_height() -> float:
	if can(RuleAction.Kind.HIGH_JUMP):
		return Tuning.BOOTS_JUMP_HEIGHT
	return Tuning.PLAYER_JUMP_HEIGHT


## 次にすることを決め直す（CreatureBrain）。
func replan() -> void:
	_needs_plan = false
	_since_plan = 0.0
	if not is_on_floor() or not survey.is_valid():
		_needs_plan = true
		return
	if brain == null:
		brain = CreatureBrain.new(entity_id)
	var decision := brain.decide(situation())
	_dodging = false
	choice = decision.choice
	path = decision.path
	_needs = decision.needs
	_needs_path = decision.needs_path
	if choice == CreatureBrain.Choice.CELEBRATE:
		_celebrated = true
	elif not is_wish_met():
		_celebrated = false
	if choice != CreatureBrain.Choice.WANDER and choice != CreatureBrain.Choice.NEST_IDLE:
		anchor = cell()
	if not path.is_empty():
		_gaze_yaw = NAN
	elif decision.has_gaze:
		var to := decision.gaze - Vector2(global_position.x, global_position.z)
		if to.length() > 0.2:
			_gaze_yaw = atan2(-to.x, -to.y)
	_start_act(decision.act)
	_set_stage(decision.stage)
	_update_bubble()
	_stuck = 0.0


## 進めなかった一歩に、禁止の付いたブロックから出る一歩を足したもの。ジャンプ禁止のマスからは跳ばないと
## 上がれない段へ進まず、W/A/S/D が全部禁止のマスからはどこへも歩き出さない（向きを自由に変えられるので、
## 1つだけの禁止では道を変えない）。
func _banned_steps(heights: Dictionary) -> Dictionary:
	var steps := _blocked.duplicate()
	if not floor_ban_survey.is_valid():
		return steps
	var banned := floor_ban_survey.call() as Dictionary
	for spot: Vector2i in banned:
		if not heights.has(spot):
			continue
		var info := banned[spot] as Dictionary
		if absf(float(heights[spot]) - float(info["top"])) > 0.3:
			continue  # そのマスの立つ面は、禁止のブロックではない（上に別の物がある）
		var bans := info["bans"] as Dictionary
		var no_walk := true
		for move in CreatureMind.MOVES:
			no_walk = no_walk and bans.has(move)
		for dir: Vector2i in CreatureMind.DIRECTIONS:
			var next := spot + dir
			if not heights.has(next):
				continue
			var rise := float(heights[next]) - float(heights[spot])
			var needs_jump := rise > CreatureMind.STEP_HEIGHT and not can(RuleAction.Kind.CLIMB)
			if no_walk or (needs_jump and bans.has(RuleAction.Kind.JUMP)):
				steps[CreatureMind.step_key(spot, next)] = true
	return steps


## いまの判断の材料。
func situation() -> CreatureBrain.Situation:
	var s := CreatureBrain.Situation.new()
	s.start = cell()
	for action in RuleAction.ALL:
		s.abilities[action] = can(action)
	s.heights = survey.call(cell(), CreatureMind.SEARCH_RADIUS) as Dictionary
	if ground_survey.is_valid():
		s.ground = ground_survey.call(cell(), CreatureMind.SEARCH_RADIUS) as Dictionary
	if avoid_survey.is_valid():
		s.avoid = avoid_survey.call(cell(), CreatureMind.SEARCH_RADIUS) as Dictionary
	s.jump_height = jump_height()
	s.high_jump_height = Tuning.BOOTS_JUMP_HEIGHT
	s.can_climb = can(RuleAction.Kind.CLIMB)
	s.blocked = _banned_steps(s.heights)
	s.searching = _searching
	if wish_box.has_volume():
		s.nest = Rect2(wish_box.position.x, wish_box.position.z, wish_box.size.x, wish_box.size.z)
	s.wish_met = is_wish_met()
	s.celebrated = _celebrated
	s.anchor = anchor
	s.available = available_actions()
	if peers.is_valid():
		for p: Vector3 in peers.call() as Array:
			s.players.append(Vector2(p.x, p.z))
	return s


## このステージにある能力（禁止ではない器・付いている能力のどれかにある行動）。
func available_actions() -> Array:
	var found := {}
	if ledger != null:
		for t in ledger.all_tokens():
			if not t.is_prohibition:
				found[t.action] = true
	return found.keys()


## 見た目だけの動きを始める（喜ぶは CHEER_TIME だけ、見回す・跳ねるは 1 回）。
func _start_act(act: StringName) -> void:
	if act == CreatureBrain.ACT_NONE:
		return
	_act = act
	_act_serial += 1
	_play_act(act)


func _play_act(act: StringName) -> void:
	if act == CreatureBrain.ACT_HAPPY:
		_cheer_left = CHEER_TIME
		return
	_act_left = 1.0
	if _rig != null and _rig.has(act):
		_act_left = _rig.player.get_animation(act).length
		_rig.play_once(act)


func _physics_process(delta: float) -> void:
	_time += delta
	if remote:
		var step := _remote_target - global_position
		global_position = global_position.lerp(_remote_target, minf(1.0, delta * 15.0))
		_animate(Vector3(step.x, 0.0, step.z).limit_length(1.0))
		return
	_since_plan += delta
	var bans := FloorBans.under(ledger, self)
	if bans != _floor_bans:
		_floor_bans = bans
		_needs_plan = true
	if not is_on_floor():
		velocity.y = maxf(velocity.y - Tuning.GRAVITY * delta, -max_fall_speed)
	if not is_nan(surface_hold) and global_position.y < surface_hold:
		var rise := minf((surface_hold - global_position.y) * 8.0, NatureTuning.SURFACE_PUSH)
		velocity.y = maxf(velocity.y, rise)
	var idle := stage == CreatureMind.Stage.WAIT and path.is_empty()
	_settle_left -= delta
	if _settle_left > 0.0:
		pass  # 落ち着くまで判断しない
	elif _needs_plan or (idle and _since_plan > LOOK_AROUND_PERIOD):
		replan()
	_dodge_left -= delta
	if _dodge_left <= 0.0 and is_on_floor():
		_dodge_left = DODGE_PERIOD
		_dodge_falling_block()
	var direction := Vector3.ZERO
	if not path.is_empty():
		direction = _follow(delta)
	elif stage == CreatureMind.Stage.WAIT:
		_maybe_throw()
	var speed := SPEED * (DODGE_SPEED_FACTOR if _dodging else 1.0)
	velocity.x = direction.x * speed + external_velocity.x
	velocity.z = direction.z * speed + external_velocity.z
	move_and_slide()
	_animate(direction)


## 自分のマスの上にブロックが来ている（押されて落ちてくる・置かれる）なら、同じ高さのとなりのマスへ急いでよける。
## ブロックは生き物と衝突しないので、よけないとブロックにめり込む。道が足りずに壁のふもとで待っていると、
## プレイヤーがそこへ足場を落とすことが多い（1-4 の削った階段など）。
func _dodge_falling_block() -> void:
	if not survey.is_valid():
		return
	var here := cell()
	var heights := survey.call(here, 1) as Dictionary
	var feet := global_position.y
	if not heights.has(here) or float(heights[here]) <= feet + 0.5:
		return
	if ground_survey.is_valid():
		var ground := ground_survey.call(here, 0) as Dictionary
		if float(ground.get(here, -INF)) > feet + 0.5:
			return  # 地形の中（壁ぎわでずれただけ）。ブロックではない
	for dir: Vector2i in CreatureMind.DIRECTIONS:
		var next := here + dir
		if heights.has(next) and absf(float(heights[next]) - feet) <= 0.3:
			path = [next]
			_dodging = true
			_stuck = 0.0
			return


## 道の次のマスへ向かう。着いたら次へ。段が高ければ跳ぶ（または登る）。
func _follow(delta: float) -> Vector3:
	var next := path[0]
	var target := Vector3(next.x + 0.5, global_position.y, next.y + 0.5)
	var to := target - global_position
	to.y = 0.0
	if to.length() < 0.12:
		path.pop_front()
		_stuck = 0.0
		_dodging = false
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
	if new_stage == stage and _stage_shown:
		return
	_stage_shown = true
	stage = new_stage
	if new_stage != CreatureMind.Stage.SEARCH:
		_searching = false
	_update_bubble()
	stage_changed.emit(new_stage)


## 頭の上の吹き出し。足りない能力のメダル・道が要る（階段）・願いがかなった（♪）を出す。
func _update_bubble() -> void:
	if _view == null or remote:
		return
	_view.show_key(bubble_key_now())


## いまの吹き出しの鍵（CreatureWishView.KEY_* / key_for）。歩いている間は出さない。
func bubble_key_now() -> String:
	if is_wish_met():
		return CreatureWishView.KEY_HAPPY
	if not path.is_empty() or stage != CreatureMind.Stage.WAIT:
		return CreatureWishView.KEY_NONE
	return CreatureWishView.key_for(_needs, _needs_path)


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


## 巣の色を決める（WishMarker.attach）。吹き出しに、足りないものと並べて小さな巣の絵をこの色で出す。
func set_nest_tint(color: Color) -> void:
	nest_tint = color
	if _view != null:
		_view.set_nest_tint(color)


## 願いの一文を出す・隠す（プレイヤーが近くに来た・狙ったとき。PlayerInput が決める）。
func show_wish(on: bool) -> void:
	if _view != null:
		_view.show_wish(on)


func is_wish_shown() -> bool:
	return _view != null and _view.is_wish_shown()


# --- チェックポイント -------------------------------------------------------


## 見た目だけの動きの状態 [名前, 回数, 体の向き]（WorldFrame で参加者へ配る）。
func act_state() -> Array:
	return [String(_act), _act_serial, _gaze_yaw]


func capture_state() -> Dictionary:
	return {
		"position": global_position,
		"velocity": velocity,
		"facing": facing,
		"held_item": held_item,
	}


## 参加者の画面で、ホストから受け取った状態 [位置, 向き, 持ち物, 頭の上の吹き出し] を目指す。
## act は act_state() と同じ形（見た目だけの動き）。
func set_remote_state(
	at: Vector3, new_facing: Vector2i, item: String, key: String = "", act: Array = []
) -> void:
	if _view != null:
		_view.show_key(key)
	if act.size() >= 3:
		_apply_remote_act(act)
	if at.distance_to(global_position) > 3.0:
		global_position = at
	_remote_target = at
	facing = new_facing
	if item != held_item:
		if item == "":
			_cheer_left = CHEER_TIME  # ホストの画面で投げた
		held_item = item
		_update_held()


func _apply_remote_act(act: Array) -> void:
	var yaw := float(act[2]) if typeof(act[2]) == TYPE_FLOAT else NAN
	_gaze_yaw = yaw if is_nan(yaw) or absf(yaw) <= TAU else NAN
	var serial := int(act[1]) if typeof(act[1]) == TYPE_INT else _act_serial
	if serial == _act_serial:
		return
	_act_serial = serial
	var name_text := String(act[0]) if typeof(act[0]) == TYPE_STRING else ""
	var known: Array[StringName] = [
		CreatureBrain.ACT_LOOK, CreatureBrain.ACT_HOP, CreatureBrain.ACT_HAPPY
	]
	if known.has(StringName(name_text)):
		_act = StringName(name_text)
		_play_act(_act)


func restore_state(state: Dictionary) -> void:
	global_position = state["position"] as Vector3
	velocity = state["velocity"] as Vector3
	facing = state.get("facing", Vector2i(0, -1)) as Vector2i
	held_item = String(state.get("held_item", held_item))
	_update_held()
	path.clear()
	anchor = cell()
	_celebrated = false
	_gaze_yaw = NAN
	_settle_left = SETTLE_TIME
	if brain != null:
		brain.reset()
	notify_environment_changed()


# --- 見た目（付与先の赤い輪郭・持っている能力・考えていること） ---------------


func set_highlight(on: bool) -> void:
	_aimed = on
	_update_outline()


func show_tokens(tokens: Array[RuleToken]) -> void:
	var lent_by_player := false
	for t in tokens:
		lent_by_player = lent_by_player or t.vessel_id != -1
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
	# 体は「向いている向き」を向く（A だけなら横歩き、S だけなら後ろ歩きに見える）。
	# 止まっている間は、見ている先（壁・プレイヤー）へ体だけ向ける（W/A/S/D の基準は変えない）
	var yaw := atan2(-float(facing.x), -float(facing.y))
	var still := direction.length() <= 0.05
	if still and not is_nan(_gaze_yaw):
		yaw = _gaze_yaw
	_body.rotation.y = lerp_angle(_body.rotation.y, yaw, 0.12)
	# 歩き・立ち止まり・喜ぶ・見回す・跳ねるは、骨格のアニメーションで見せる（コードで体を揺らさない）
	var delta := get_physics_process_delta_time()
	_act_left = maxf(0.0, _act_left - delta)
	if _rig != null:
		_cheer_left = maxf(0.0, _cheer_left - delta)
		if _cheer_left > 0.0 and still:
			_rig.play(RigAnimator.HAPPY)
		elif _act_left > 0.0 and still:
			pass  # 見回す・跳ねるを最後まで再生する
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
