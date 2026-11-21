class_name MedalThrow
extends RefCounted
## 「投げる」で渡すとき、メダルを本当に投げる（2026-11-21 本人「投擲部つなげて実際に当たったところから付与にしてよ」。
## docs/adr/0017）。狙った相手ではなく、メダルが実際に当たった物へ付与する。
## - 投げる: 狙った点（照準の光線が当たった点、または補助で選んだ相手の真ん中）を通る放物線。届く距離は今までどおり。
##   手を離す瞬間に、狙う点を相手のいまの位置に合わせ直し（歩いている生き物は着くころの位置を見越す）、低い弧から
##   順に ARC_LIFTS の高さを試して、いまの地形・ブロックに遮られずに狙った相手へ届く最初の弧で投げる
##   （人が崖の上へは山なりに投げるのと同じ。肩越しのカメラと手の位置の差で、見えている相手に届かないことを防ぐ）。
##   どれも遮られるなら低い弧で投げ、手前の物が受け取る。手を離した後に動いた物・入ってきた物も、当たれば受け取る
## - 当たった物: ブロック（地形から作ったものも）・生き物・仲間（渡せる能力なら）・地形のセル（その場で動くブロックに）
##   範囲で投げたら、当たったブロック・セルを中心に範囲で付与する。禁止が上位なのは今までどおり（台帳が決める）
## - 鐘は付与先にならないので、当たったら戻る（鳴らさない。遠くから鐘を鳴らせると関所が変わるため）
## - 外れたら、メダルは投げた人の手元へ戻る（能力は飛んでいる間も手元にあり、台帳は変わらない）
## GameWorld が長くならないよう、投げる処理はここと ThrownMedal に置く。

## 振りかぶってから手を離すまで（Blender の throw の 7 フレーム目 = 6/24 秒）。
const RELEASE_DELAY: float = 0.25
## 飛ぶ速さ（m/秒。狙った点までの距離をこの速さで割った時間で着く）と重力（m/秒²）。
## 20 m 先で山の高さはおよそ 2 m（重力 × 時間² / 8）。
const SPEED: float = 16.0
const GRAVITY: float = 10.0
## 近すぎるときも、少しは弧を描く最短の時間。
const MIN_FLIGHT_TIME: float = 0.12
## 試す弧の山の高さ（m。手と狙った点を結ぶ線から、真ん中でどれだけ上か）。いちばん低い弧（距離 / SPEED の時間）より
## 低いものは飛ばす。
const ARC_LIFTS: Array[float] = [0.0, 1.0, 2.0, 3.2]
## 届く距離（投げた時点の胸から）を、どれだけ越えたら外れにするか。狙った点は届く距離の中なので、余裕だけ。
const REACH_MARGIN: float = 1.0
## 着くはずの時間をどれだけ過ぎたら外れにするか（秒）。
const EXTRA_TIME: float = 0.6
## メダルが当たる物。投げた本人は除く。
const HIT_MASK: int = (
	Tuning.LAYER_TERRAIN
	| Tuning.LAYER_BLOCKS
	| Tuning.LAYER_CREATURES
	| Tuning.LAYER_AVATARS
	| Tuning.LAYER_PLAYER
)
const GROUP: StringName = &"thrown_medals"

static var _next_serial: int = 1


## token_id のメダルを、w.player（参加者の代わりならその人のアバター）が target へ投げる。
## 付与は当たったときに land が行う。ここでは届く距離・付与先の確認を済ませた前提。
static func start(w: GameWorld, target: Node3D, use_range: bool, token_id: int) -> ThrownMedal:
	var t := w.ledger.token(token_id)
	var thrower := w.player
	var medal := ThrownMedal.new()
	medal.name = "ThrownMedal%d" % _next_serial
	medal.serial = _next_serial
	_next_serial += 1
	medal.token_id = token_id
	medal.thrower_id = w.acting_id()
	medal.mode = w.lend_mode
	medal.use_range = use_range
	medal.chest = thrower.global_position + Vector3(0.0, 1.0, 0.0)
	medal.reach = w.reach()
	medal.sink = w.post_sink
	medal.aim = aim_point(w, target, thrower.hand_position())
	medal.aimed = target if not (target is TerrainCell) else null
	medal.aimed_cell = (target as TerrainCell).cell if target is TerrainCell else Vector3i.MAX
	if medal.aimed != null:
		medal.aim_offset = medal.aim - medal.aimed.global_position
	medal.setup(w, thrower, t)
	medal.add_to_group(GROUP)
	w.add_child(medal)
	medal.global_position = medal.chest
	thrower.play_throw(medal.aim - thrower.global_position)
	return medal


## token_id のメダルがまだ飛んでいる（振りかぶり・戻る途中も含む）か。
static func in_flight(w: GameWorld, token_id: int) -> bool:
	return (
		w.get_tree() != null
		and _medals(w).any(func(m: ThrownMedal) -> bool: return m.token_id == token_id)
	)


## 飛んでいるメダル（消える予定のものを除く）。
static func flying(w: GameWorld) -> Array[ThrownMedal]:
	return _medals(w)


static func _medals(w: GameWorld) -> Array[ThrownMedal]:
	var result: Array[ThrownMedal] = []
	if not w.is_inside_tree():
		return result
	for node in w.get_tree().get_nodes_in_group(GROUP):
		var m := node as ThrownMedal
		if m != null and not m.is_queued_for_deletion() and w.is_ancestor_of(m):
			result.append(m)
	return result


## チェックポイントの復元・全員リセット: 飛んでいるメダルは保存しないので消す（能力は台帳の復元で手元にある）。
static func clear(w: GameWorld) -> void:
	for m in _medals(w):
		m.queue_free()


## from から to までの、いちばん低い弧の飛ぶ時間（距離 / SPEED）。
static func base_flight_time(from: Vector3, to: Vector3) -> float:
	return maxf((to - from).length() / SPEED, MIN_FLIGHT_TIME)


## from から time 秒で to に着く放物線の初速（重力 GRAVITY）。
static func launch_velocity(from: Vector3, to: Vector3, time: float) -> Vector3:
	return (to - from) / time + Vector3(0.0, 0.5 * GRAVITY * time, 0.0)


## 手を離す瞬間に選ぶ弧 {"time": 飛ぶ時間, "aim": 着く点}: ARC_LIFTS を低い順に試し、狙った相手に最初に当たる弧。
## 歩いている生き物は、着くころの位置（水平の速さ × 時間）を狙う。
## どれも途中で別の物に当たるなら、いちばん低い弧（手前の物が受け取る）。
static func choose_arc(w: GameWorld, medal: ThrownMedal, from: Vector3) -> Dictionary:
	var base := base_flight_time(from, medal.aim)
	var lead := Vector3.ZERO
	var body := medal.aimed as CharacterBody3D
	if body != null and not (body is PlayerAvatar):
		lead = Vector3(body.velocity.x, 0.0, body.velocity.z)
	var tried := {}
	for lift in ARC_LIFTS:
		var time := maxf(base, sqrt(8.0 * lift / GRAVITY))
		if tried.has(time):
			continue
		tried[time] = true
		var aim := medal.aim + lead * time
		if _arc_reaches(w, medal, from, aim, time):
			return {"time": time, "aim": aim}
	return {"time": base, "aim": medal.aim + lead * base}


## その弧が、ほかの物に遮られずに狙った相手（または狙った点）まで届くか。
static func _arc_reaches(
	w: GameWorld, medal: ThrownMedal, from: Vector3, aim: Vector3, time: float
) -> bool:
	var launch := launch_velocity(from, aim, time)
	var step := 1.0 / 60.0
	var t := 0.0
	var last := from
	while t < time + EXTRA_TIME:
		t += step
		var next := from + launch * t + Vector3(0.0, -0.5 * GRAVITY * t * t, 0.0)
		var hit := cast(w, last, next, medal.thrower())
		if not hit.is_empty():
			return _is_aimed(w, medal, hit)
		if t >= time and next.distance_to(aim) < 0.05:
			return true  # 何にも当たらずに狙った点を通った（狙った点が空中）
		last = next
	return false


## 当たった物が、狙った相手か（地形のセルならそのセル）。
static func _is_aimed(w: GameWorld, medal: ThrownMedal, hit: Dictionary) -> bool:
	var collider := hit.get("collider") as Node3D
	if medal.aimed != null:
		return collider == medal.aimed
	if collider == null or w.terrain == null or not w.terrain.is_terrain_body(collider):
		return false
	var cell := TerrainGrid.cell_at_hit(hit["position"] as Vector3, hit["normal"] as Vector3)
	return cell == medal.aimed_cell


## 狙う点。照準の光線がその相手に当たっていれば、その点（GameWorld.aim_hint）。
## そうでなければ、生き物・仲間・鐘は体の真ん中、ブロック・地形のセルは上が空いていれば上面の真ん中、
## 塞がっていれば投げる人の側の面の真ん中（放物線は上から落ちてくるので、上面を狙うと手前の面に当たりにくい）。
static func aim_point(w: GameWorld, target: Node3D, from: Vector3) -> Vector3:
	var hinted: Variant = w.aim_hint_for(target)
	if hinted != null:
		return hinted as Vector3
	if not (target is RuleBlock or target is TerrainCell):
		return AimAssist.aim_point(target)
	var center := target.global_position
	var half := RuleBlock.SIZE * 0.5
	if not _occupied(w, center + Vector3(0.0, RuleBlock.SIZE, 0.0), target):
		return center + Vector3(0.0, half, 0.0)
	var flat := Vector3(from.x - center.x, 0.0, from.z - center.z)
	if absf(flat.x) >= absf(flat.z):
		return center + Vector3(signf(flat.x) * half, 0.0, 0.0)
	return center + Vector3(0.0, 0.0, signf(flat.z) * half)


## そのセルに地形かブロックがあるか（target 自身は除く）。
static func _occupied(w: GameWorld, at: Vector3, target: Node3D) -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = at
	query.collision_mask = Tuning.LAYER_TERRAIN | Tuning.LAYER_BLOCKS
	if target is CollisionObject3D:
		query.exclude = [(target as CollisionObject3D).get_rid()]
	return not w.get_world_3d().direct_space_state.intersect_point(query, 1).is_empty()


## from から to までで、メダルが最初に当たる物（無ければ空）。投げた本人は除く。
static func cast(w: GameWorld, from: Vector3, to: Vector3, thrower: PlayerAvatar) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, HIT_MASK)
	if is_instance_valid(thrower):
		query.exclude = [thrower.get_rid()]
	return w.get_world_3d().direct_space_state.intersect_ray(query)


## 当たった物（光線の結果）から、付与先を決める。付与先にならない物なら null。
static func target_of_hit(w: GameWorld, hit: Dictionary) -> Node3D:
	var collider := hit.get("collider") as Node3D
	if (
		collider is RuleBlock
		or collider is Creature
		or collider is PlayerAvatar
		or collider is Bell
	):
		return collider
	if collider != null and w.terrain != null and w.terrain.is_terrain_body(collider):
		var cell := TerrainGrid.cell_at_hit(hit["position"] as Vector3, hit["normal"] as Vector3)
		if w.terrain.has_cell(cell):
			return w.terrain_target(cell)
	return null


## 当たった: 当たった物へ付与する（できなければ手元へ戻る）。
static func land(w: GameWorld, medal: ThrownMedal, hit: Dictionary) -> void:
	var at := hit["position"] as Vector3
	var target := target_of_hit(w, hit)
	var color := UiTheme.BAN if medal.is_prohibition() else UiTheme.HONEY
	MedalVisual.puff(w, at, color)
	var result := RuleLedger.LendResult.UNKNOWN_TARGET
	var saved_sink := w.post_sink
	w.post_sink = medal.sink
	if target is Bell:
		w.notify("鐘には渡せません（%s で鳴らす）" % InputMode.token(&"interact"))
	elif target is PlayerAvatar:
		result = WorldLending.give_token(
			w, medal.token_id, medal.thrower_id, target as PlayerAvatar
		)
	elif target != null:
		result = WorldLending.lend_token(
			w, medal.token_id, medal.thrower_id, target, medal.use_range, medal.mode
		)
	w.post_sink = saved_sink
	if result == RuleLedger.LendResult.OK:
		medal.queue_free()
		return
	_send_back(w, medal, "")


## 外れた（届く距離・時間を超えた・島の下へ落ちた）: 手元へ戻る。
static func miss(w: GameWorld, medal: ThrownMedal) -> void:
	_send_back(w, medal, "どこにも当たらず、メダルが手元へ戻りました")


static func _send_back(w: GameWorld, medal: ThrownMedal, text: String) -> void:
	var saved_sink := w.post_sink
	w.post_sink = medal.sink
	if text != "":
		w.notify(text)
	w.post_sink = saved_sink
	w.sound_requested.emit(&"recall", medal.global_position, true)
	medal.start_return()


## 通信で配る、飛んでいるメダルの様子 [[番号, 位置, 速さ, 行動, 禁止か, 戻る途中か], ...]（振りかぶり中は出さない）。
static func capture_frame(w: GameWorld) -> Array:
	var out := []
	for m in _medals(w):
		if m.is_released():
			var back := m.phase == ThrownMedal.Phase.RETURNING
			out.append(
				[m.serial, m.global_position, m.velocity(), m.action(), m.is_prohibition(), back]
			)
	return out


## 参加者の画面に、飛んでいるメダルの見た目を合わせる。消えたメダルは、戻る途中でなければ小さな輪を出す。
## ghosts は番号 → MedalVisual（NetWorld が持つ）。通信から来た値なので、形が違うものは無視する。
static func apply_frame(w: GameWorld, data: Array, ghosts: Dictionary) -> void:
	var present := {}
	for value: Variant in data:
		var row := value as Array
		if row == null or row.size() < 5:
			continue
		if typeof(row[1]) != TYPE_VECTOR3 or typeof(row[2]) != TYPE_VECTOR3:
			continue
		var serial := int(row[0])
		present[serial] = true
		if not ghosts.has(serial):
			var action := clampi(int(row[3]), 0, RuleAction.Kind.size() - 1) as RuleAction.Kind
			var ghost := MedalVisual.new()
			ghost.setup(action, bool(row[4]))
			w.add_child(ghost)
			ghosts[serial] = ghost
		var shown := ghosts[serial] as MedalVisual
		shown.apply_remote(row[1] as Vector3, row[2] as Vector3)
		shown.returning = row.size() >= 6 and bool(row[5])
	for serial: int in ghosts.keys():
		if present.has(serial):
			continue
		var ghost := ghosts[serial] as MedalVisual
		if is_instance_valid(ghost):
			if not ghost.returning:
				MedalVisual.puff(w, ghost.global_position)
			ghost.queue_free()
		ghosts.erase(serial)
