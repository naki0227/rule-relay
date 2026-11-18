class_name GameWorld
extends Node3D
## ルール（RuleLedger）と、物理世界のノード（プレイヤー・ブロック）をつなぐ。
## 入力デバイスは知らない。PlayerInput などの UI 側が、ここにある操作メソッドを呼ぶ。
## テストも同じメソッドを呼んで、キー入力なしでゲームを進める。

signal message_posted(text: String)
signal state_changed
signal goal_reached

const FIRST_BLOCK_ID: int = 100

var ledger: RuleLedger = RuleLedger.new()
var player: PlayerAvatar
var camera_rig: CameraRig
var blocks: Dictionary[int, RuleBlock] = {}
var selected_slot: int = 0
var lend_mode: TriggerMode.Kind = TriggerMode.Kind.SINGLE_SHOT
var throw_mode: bool = false
var goal_cleared: bool = false
## F でチェックポイントを保存できる場所（中心と半径）。
var checkpoint_center: Vector3 = Vector3.ZERO
var checkpoint_radius: float = 1.5
## 到達判定の高台（AABB）。
var goal_box: AABB = AABB()

var _next_block_id: int = FIRST_BLOCK_ID
var _repeat_cursors: Dictionary[int, RepeatCursor] = {}
var _repeat_timers: Dictionary[int, float] = {}
var _checkpoint: Dictionary = {}
var _spawn_point: Vector3 = Vector3.ZERO
var _highlighted: RuleBlock


func _ready() -> void:
	ledger.changed.connect(_on_ledger_changed)


# --- 構築 -------------------------------------------------------------------


func spawn_player(at: Vector3) -> PlayerAvatar:
	player = PlayerAvatar.new()
	player.name = "Player"
	player.ledger = ledger
	player.position = at
	_spawn_point = at
	add_child(player)
	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	camera_rig.target = player
	add_child(camera_rig)
	return player


func add_block(cell: Vector3i, color: Color = Color(0.85, 0.65, 0.35)) -> RuleBlock:
	var block := RuleBlock.new()
	var id := _next_block_id
	_next_block_id += 1
	block.setup(id, cell, color)
	add_child(block)
	blocks[id] = block
	ledger.register_entity(id, EntityKind.Kind.BLOCK)
	_repeat_cursors[id] = RepeatCursor.new()
	_repeat_timers[id] = 0.0
	return block


# --- プレイヤーの操作 -------------------------------------------------------


func selected_vessel() -> RuleVessel:
	return ledger.hotbar_vessel(selected_slot)


func select_slot(slot: int) -> void:
	selected_slot = clampi(slot, 0, RuleLedger.HOTBAR_SIZE - 1)
	state_changed.emit()


## 単発 ↔ 繰り返し。信号は P1。中央の円形 UI ができるまでの仮操作（Q／ホイール押し込み）。
func cycle_mode() -> void:
	if lend_mode == TriggerMode.Kind.SINGLE_SHOT:
		lend_mode = TriggerMode.Kind.REPEAT
	else:
		lend_mode = TriggerMode.Kind.SINGLE_SHOT
	_post("付与方式: %s" % TriggerMode.label(lend_mode))
	state_changed.emit()


func toggle_reach() -> void:
	throw_mode = not throw_mode
	_post("付与の届き方: %s" % ("投げる" if throw_mode else "触る"))
	state_changed.emit()


func reach() -> float:
	return Tuning.THROW_REACH if throw_mode else Tuning.TOUCH_REACH


## W/A/S/D/Space を押した瞬間。自分の行動と、貸し出した単発の起動に振り分ける。
func press_action(action: RuleAction.Kind) -> void:
	var route := InputRouter.route_press(ledger, action)
	if route.player_acts and action == RuleAction.Kind.JUMP:
		player.request_jump()
	for token_id in route.single_shot_token_ids:
		_fire_single_shot(token_id)


## 選択中のホットバーの器から、target へ付与する。use_range なら target の層の円内の全ブロックへ。
func lend_to(target: RuleBlock, use_range: bool) -> RuleLedger.LendResult:
	var v := selected_vessel()
	if v == null:
		_post("ホットバー %d は空です" % (selected_slot + 1))
		return RuleLedger.LendResult.NO_SUCH_VESSEL
	if target == null or not _within_reach(target):
		_post("届きません（%s: %.1fブロック）" % ["投げる" if throw_mode else "触る", reach()])
		return RuleLedger.LendResult.NO_TARGETS
	var t := ledger.token(v.token_id)
	var mode := TriggerMode.Kind.NONE if t.is_prohibition else lend_mode
	var result: RuleLedger.LendResult
	if use_range:
		var layer := target.cell().y
		var center := target.global_position
		var spec := {"center": center, "radius": BlockRules.DEFAULT_RANGE_RADIUS, "layer": layer}
		var ids := BlockRules.select_in_range(center, spec["radius"], layer, _block_cells())
		result = ledger.lend(v.id, ids, mode, spec)
	else:
		result = ledger.lend(v.id, PackedInt32Array([target.entity_id]), mode)
	_post(_describe_lend(t, result, use_range))
	if result == RuleLedger.LendResult.OK and mode == TriggerMode.Kind.REPEAT:
		for holder in t.holder_ids:
			# 付与してすぐ動き出すように、最初の周期を短くする
			_repeat_timers[holder] = Tuning.REPEAT_PERIOD - 0.25
	return result


## F: チェックポイント上なら保存。そうでなければ狙ったブロックから1つ回収し、
## 無ければ立っている範囲付与を一括回収する。
func interact(target: RuleBlock) -> void:
	if is_on_checkpoint():
		save_checkpoint()
		_post("チェックポイントを保存しました")
		return
	if target != null and _within_reach(target):
		var picked := _recall_one(target.entity_id)
		if picked != null:
			_post("%s を回収しました" % picked.describe())
			return
	var zone := ledger.range_tokens_at(player.global_position)
	if not zone.is_empty():
		var t := zone[0]
		ledger.recall(t.id)
		_post("範囲の %s を回収しました" % t.describe())
		return
	_post("回収できるものがありません")


func is_on_checkpoint() -> bool:
	var flat := player.global_position - checkpoint_center
	flat.y = 0.0
	return (
		flat.length() <= checkpoint_radius
		and absf(player.global_position.y - checkpoint_center.y) < 1.0
	)


## 画面中央の先にあるブロック（カメラからの光線）。
func aimed_block() -> RuleBlock:
	if camera_rig == null or camera_rig.camera() == null:
		return null
	var cam := camera_rig.camera()
	var from := cam.global_position
	var to := from + -cam.global_basis.z * (Tuning.THROW_REACH + CameraRig.DISTANCE)
	var query := PhysicsRayQueryParameters3D.create(
		from, to, Tuning.LAYER_TERRAIN | Tuning.LAYER_BLOCKS
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit["collider"] as RuleBlock


func update_highlight(target: RuleBlock) -> void:
	if _highlighted == target:
		return
	if _highlighted != null:
		_highlighted.set_highlight(false)
	_highlighted = target
	if target != null:
		target.set_highlight(true)


# --- チェックポイント（企画書 9） ------------------------------------------


func save_checkpoint() -> void:
	var block_states := {}
	for id in blocks:
		var state := blocks[id].capture_state()
		state["cursor"] = _repeat_cursors[id].get_index()
		state["timer"] = _repeat_timers[id]
		block_states[id] = state
	_checkpoint = {
		"ledger": ledger.snapshot(),
		"player_position": player.global_position,
		"blocks": block_states,
		"selected_slot": selected_slot,
		"lend_mode": lend_mode,
		"goal_cleared": goal_cleared,
	}


## 世界を丸ごと保存時点へ戻す。能力だけを戻すのではない。
func restore_checkpoint() -> void:
	if _checkpoint.is_empty():
		return
	ledger.restore(_checkpoint["ledger"] as Dictionary)
	player.global_position = _checkpoint["player_position"] as Vector3
	player.velocity = Vector3.ZERO
	var block_states := _checkpoint["blocks"] as Dictionary
	for id: int in block_states:
		var state := block_states[id] as Dictionary
		blocks[id].teleport(state["position"] as Vector3, float(state["velocity_y"]))
		_repeat_cursors[id].set_index(int(state["cursor"]))
		_repeat_timers[id] = float(state["timer"])
	selected_slot = int(_checkpoint["selected_slot"])
	lend_mode = int(_checkpoint["lend_mode"]) as TriggerMode.Kind
	goal_cleared = bool(_checkpoint["goal_cleared"])
	_post("チェックポイントへ戻りました")
	state_changed.emit()


# --- 毎フレーム -------------------------------------------------------------


func _physics_process(delta: float) -> void:
	_tick_repeats(delta)
	if player == null:
		return
	if player.global_position.y < Tuning.FALL_LIMIT_Y:
		restore_checkpoint()
	if not goal_cleared and goal_box.has_volume() and goal_box.has_point(player.global_position):
		goal_cleared = true
		_post("高台に到達しました！")
		goal_reached.emit()


func _tick_repeats(delta: float) -> void:
	for id in blocks:
		var actions := ledger.repeat_actions(id)
		if actions.is_empty():
			_repeat_timers[id] = 0.0
			continue
		_repeat_timers[id] += delta
		if _repeat_timers[id] < Tuning.REPEAT_PERIOD:
			continue
		_repeat_timers[id] -= Tuning.REPEAT_PERIOD
		var action := _repeat_cursors[id].next_action(actions) as RuleAction.Kind
		var block := blocks[id]
		var result := BlockRules.attempt(ledger, id, action, block.is_ready_for(action))
		if result == BlockRules.Attempt.SUCCESS:
			block.perform(action)


func _fire_single_shot(token_id: int) -> void:
	var t := ledger.token(token_id)
	var results: Array[BlockRules.Attempt] = []
	for holder in t.holder_ids:
		var block := blocks[holder]
		var result := BlockRules.attempt(ledger, holder, t.action, block.is_ready_for(t.action))
		if result == BlockRules.Attempt.SUCCESS:
			block.perform(t.action)
		results.append(result)
	var label := t.describe()
	if ledger.complete_single_shot(token_id, results):
		_post("単発の %s が成功して戻りました" % label)
	else:
		_post("単発の %s は動けませんでした（付与されたまま）" % label)


# --- 内部 -------------------------------------------------------------------


## 回収の順番: 自分が貸したもの → レベルに置かれた禁止 → レベルに置かれた能力（仮の方針）。
func _recall_one(entity_id: int) -> RuleToken:
	var tokens := ledger.tokens_on(entity_id)
	var ordered: Array[RuleToken] = []
	for t in tokens:
		if t.vessel_id != -1:
			ordered.append(t)
	for t in tokens:
		if t.vessel_id == -1 and t.is_prohibition:
			ordered.append(t)
	for t in tokens:
		if t.vessel_id == -1 and not t.is_prohibition:
			ordered.append(t)
	if ordered.is_empty():
		return null
	ledger.recall(ordered[0].id)
	return ordered[0]


func _within_reach(target: RuleBlock) -> bool:
	var chest := player.global_position + Vector3(0.0, 1.0, 0.0)
	return chest.distance_to(target.global_position) <= reach() + RuleBlock.SIZE * 0.5


func _block_cells() -> Dictionary:
	var cells := {}
	for id in blocks:
		cells[id] = blocks[id].cell()
	return cells


func _describe_lend(t: RuleToken, result: RuleLedger.LendResult, use_range: bool) -> String:
	match result:
		RuleLedger.LendResult.OK:
			var how := "範囲（%d個）" % t.holder_ids.size() if use_range else "単体"
			var mode := "" if t.mode == TriggerMode.Kind.NONE else "・%s" % TriggerMode.label(t.mode)
			return "%s を%s%sで付与しました" % [t.describe(), how, mode]
		RuleLedger.LendResult.ALREADY_LENT:
			return "%s は貸出中です（F で回収）" % t.describe()
		RuleLedger.LendResult.RANGE_PROHIBITION_UNSUPPORTED:
			return "禁止の範囲付与は未実装です（P0）"
		RuleLedger.LendResult.NO_TARGETS:
			return "範囲内にブロックがありません"
	return "付与できません（%s）" % RuleLedger.LendResult.keys()[result]


func _post(text: String) -> void:
	message_posted.emit(text)


func _on_ledger_changed() -> void:
	for id in blocks:
		blocks[id].show_tokens(ledger.tokens_on(id))
	state_changed.emit()
