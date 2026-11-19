class_name GameWorld
extends Node3D
## ルール（RuleLedger）と、物理世界のノード（プレイヤー・ブロック）をつなぐ。
## 入力デバイスは知らない。PlayerInput などの UI 側が、ここにある操作メソッドを呼ぶ。
## テストも同じメソッドを呼んで、キー入力なしでゲームを進める。

signal message_posted(text: String)
signal state_changed
signal goal_reached
signal checkpoint_changed
## 効果音の依頼。positional なら at から鳴らし、そうでなければ画面の音として鳴らす。
signal sound_requested(event: StringName, at: Vector3, positional: bool)

const FIRST_BLOCK_ID: int = 100
const FIRST_CREATURE_ID: int = 500

var ledger: RuleLedger = RuleLedger.new()
var player: PlayerAvatar
var camera_rig: CameraRig
var blocks: Dictionary[int, RuleBlock] = {}
var creatures: Dictionary[int, Creature] = {}
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
var _signal_cursors: Dictionary[int, RepeatCursor] = {}
var _signal_timers: Dictionary[int, float] = {}
## 音波を出しているブロック（音源）の ID。
var _sources: Dictionary[int, bool] = {}
var _pulse_timer: float = 0.0
var _history: CheckpointHistory = CheckpointHistory.new()
var _home_cells: Dictionary[int, Vector3i] = {}
var _spawn_point: Vector3 = Vector3.ZERO
## 狙っている付与先（ブロックか生き物。どちらも entity_id・set_highlight を持つ）。
var _highlighted: Node3D
var _next_creature_id: int = FIRST_CREATURE_ID
var _creature_homes: Dictionary[int, Vector3] = {}
var _range_preview_active: bool = false
var _previewed: Array[RuleBlock] = []
var _range_preview_visual: RangePreview
## 世界に落ちている器の見た目（vessel_id → ノード）。台帳が変わるたびに合わせる。
var _world_items: Dictionary[int, WorldItem] = {}


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
	player.jumped.connect(func() -> void: _sound(&"player_jump", player.global_position))
	player.landed.connect(func(_s: float) -> void: _sound(&"player_land", player.global_position))
	player.footstep.connect(func() -> void: _sound(&"footstep", player.global_position))
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
	block.jumped.connect(func() -> void: _sound(&"block_jump", block.global_position))
	block.landed.connect(func(_s: float) -> void: _sound(&"block_land", block.global_position))
	block.stepped.connect(func() -> void: _sound(&"block_step", block.global_position))
	block.stepped.connect(_notify_creatures)
	block.landed.connect(func(_s: float) -> void: _notify_creatures())
	_home_cells[id] = cell
	ledger.register_entity(id, EntityKind.Kind.BLOCK)
	_repeat_cursors[id] = RepeatCursor.new()
	_repeat_timers[id] = 0.0
	_signal_cursors[id] = RepeatCursor.new()
	_signal_timers[id] = 0.0
	return block


## 音源（企画書 5.4）: 周りへ音波を出し続けるブロック。ふつうのブロックと同じく能力を受け取って
## 動けるので、W などを渡して「移動する音源」にもできる。
func add_sound_source(cell: Vector3i) -> RuleBlock:
	var block := add_block(cell, Color(0.62, 0.8, 0.95))
	block.make_sound_source(Tuning.SIGNAL_RADIUS)
	_sources[block.entity_id] = true
	return block


## その位置に音波が届いているか（音源からの距離が半径以内。自分自身の音は数えない）。
## 伝わる距離・遮るもの・音の種類は要検証（企画書 5.4）で、P1 は距離だけで判定する（仮）。
func is_receiving_signal(entity_id: int) -> bool:
	if not blocks.has(entity_id):
		return false
	var at := blocks[entity_id].global_position
	for source_id in _sources:
		if source_id == entity_id:
			continue
		if blocks[source_id].global_position.distance_to(at) <= Tuning.SIGNAL_RADIUS:
			return true
	return false


## 願いを持つ生き物を置く（企画書 6）。
func add_creature(at: Vector3) -> Creature:
	var creature := Creature.new()
	var id := _next_creature_id
	_next_creature_id += 1
	creature.setup(id, at)
	creature.ledger = ledger
	creature.survey = survey_heights
	add_child(creature)
	creatures[id] = creature
	_creature_homes[id] = at
	ledger.register_entity(id, EntityKind.Kind.CREATURE)
	creature.jumped.connect(func() -> void: _sound(&"player_jump", creature.global_position))
	return creature


## マスごとの立てる高さ（地形とブロックの上面）。生き物の判断とブロックの登るに使う。穴のマスは入れない。
func survey_heights(center: Vector2i, radius: int) -> Dictionary:
	return WorldQueries.survey(get_world_3d().direct_space_state, center, radius)


func _notify_creatures() -> void:
	for creature: Creature in creatures.values():
		creature.notify_environment_changed()


# --- プレイヤーの操作 -------------------------------------------------------


func selected_vessel() -> RuleVessel:
	return ledger.hotbar_vessel(selected_slot)


func select_slot(slot: int) -> void:
	selected_slot = clampi(slot, 0, RuleLedger.HOTBAR_SIZE - 1)
	state_changed.emit()


## 円形 UI で選んだ発動方式にする。まだ使えない方式（信号）は選ばず false を返す。
func set_lend_mode(mode: TriggerMode.Kind) -> bool:
	if not TriggerMode.is_supported(mode):
		_post("%s は音波と一緒に実装予定です（P1）" % TriggerMode.label(mode))
		return false
	lend_mode = mode
	_post("付与方式: %s" % TriggerMode.label(lend_mode))
	state_changed.emit()
	return true


## 単発 → 繰り返し → 信号 → 単発。円形 UI の代わりに使える代替キー（Q）。
func cycle_mode() -> void:
	match lend_mode:
		TriggerMode.Kind.SINGLE_SHOT:
			set_lend_mode(TriggerMode.Kind.REPEAT)
		TriggerMode.Kind.REPEAT:
			set_lend_mode(TriggerMode.Kind.SIGNAL)
		_:
			set_lend_mode(TriggerMode.Kind.SINGLE_SHOT)


## C: 触る ↔ 投げる（企画書 5.1）。「投げる」は能力なので、ホットバーにあって貸出中・禁止で
## ないときだけ選べる。渡したあとも「触る」と F の回収は残る。
func toggle_reach() -> void:
	if not throw_mode and not can_throw():
		_post("「投げる」が使えません（%s）" % _throw_unavailable_reason())
		_ui_sound(&"ui_error")
		return
	throw_mode = not throw_mode
	_post("付与の届き方: %s" % ("投げる" if throw_mode else "触る"))
	state_changed.emit()


func can_throw() -> bool:
	return ledger.player_can(RuleAction.Kind.THROW)


func reach() -> float:
	return Tuning.THROW_REACH if throw_mode and can_throw() else Tuning.TOUCH_REACH


func _throw_unavailable_reason() -> String:
	if ledger.player_prohibited(RuleAction.Kind.THROW):
		return "投げる禁止を持っています"
	for t: RuleToken in _player_tokens(RuleAction.Kind.THROW):
		if t.is_lent():
			return "貸出中です（F で回収）"
	return "ホットバーにありません"


func _player_tokens(action: RuleAction.Kind) -> Array[RuleToken]:
	var result: Array[RuleToken] = []
	for v: RuleVessel in ledger.inventory_vessels():
		result.append(ledger.token(v.token_id))
	for slot in RuleLedger.HOTBAR_SIZE:
		var hv := ledger.hotbar_vessel(slot)
		if hv != null:
			result.append(ledger.token(hv.token_id))
	return result.filter(func(t: RuleToken) -> bool: return t.action == action)


## W/A/S/D/Space を押した瞬間。自分の行動と、貸し出した単発の起動に振り分ける。
func press_action(action: RuleAction.Kind) -> void:
	var route := InputRouter.route_press(ledger, action)
	if route.player_acts and action == RuleAction.Kind.JUMP:
		player.request_jump()
	for token_id in route.single_shot_token_ids:
		_fire_single_shot(token_id)


## 選択中のホットバーの器から、target へ付与する。use_range なら target の層の円内の全ブロックへ。
func lend_to(target: Node3D, use_range: bool) -> RuleLedger.LendResult:
	var v := selected_vessel()
	if v == null:
		_post("ホットバー %d は空です" % (selected_slot + 1))
		_ui_sound(&"ui_error")
		return RuleLedger.LendResult.NO_SUCH_VESSEL
	if target == null or not _within_reach(target):
		_post("届きません（%s: %.1fブロック）" % ["投げる" if throw_mode else "触る", reach()])
		_ui_sound(&"ui_error")
		return RuleLedger.LendResult.NO_TARGETS
	var t := ledger.token(v.token_id)
	var mode := TriggerMode.Kind.NONE if t.is_prohibition else lend_mode
	var result: RuleLedger.LendResult
	if use_range and not target is RuleBlock:
		_post("生き物には範囲で渡せません（左クリックで1匹に渡す）")
		_ui_sound(&"ui_error")
		return RuleLedger.LendResult.RANGE_ONLY_FOR_BLOCKS
	if use_range:
		var selection := range_selection(target as RuleBlock)
		result = ledger.lend(v.id, selection["ids"] as PackedInt32Array, mode, selection)
	else:
		result = ledger.lend(v.id, PackedInt32Array([_entity_of(target)]), mode)
	_post(WorldQueries.describe(t, result, use_range))
	if result == RuleLedger.LendResult.OK:
		_sound(&"lend_range" if use_range else &"lend", target.global_position)
	else:
		_ui_sound(&"ui_error")
	if result == RuleLedger.LendResult.OK and mode == TriggerMode.Kind.SIGNAL:
		for holder in t.holder_ids:
			_signal_timers[holder] = Tuning.REPEAT_PERIOD - 0.25
	if result == RuleLedger.LendResult.OK and mode == TriggerMode.Kind.REPEAT:
		for holder in t.holder_ids:
			# 付与してすぐ動き出すように、最初の周期を短くする
			_repeat_timers[holder] = Tuning.REPEAT_PERIOD - 0.25
	return result


## 範囲付与で選ばれるブロック。プレビューと実際の付与で同じ計算を使う。
## 戻り値は RuleLedger.lend の range_spec としてもそのまま使える
## {"center": Vector3, "radius": float, "layer": int, "ids": PackedInt32Array}。
func range_selection(target: RuleBlock) -> Dictionary:
	var layer := target.cell().y
	var center := target.global_position
	var radius := BlockRules.DEFAULT_RANGE_RADIUS
	var ids := BlockRules.select_in_range(center, radius, layer, _block_cells())
	return {"center": center, "radius": radius, "layer": layer, "ids": ids}


## 右クリックを押している間の範囲プレビュー（企画書 8 の要検証項目）。離すと付与、Esc で取り消し。
func begin_range_preview() -> void:
	_range_preview_active = true
	state_changed.emit()


func is_range_preview_active() -> bool:
	return _range_preview_active


## プレビューの内容。付与できない理由があれば "reason" に入れ、"ids" は空にする。
## ledger は変更しない。
func preview_range(target: Node3D) -> Dictionary:
	var reason := _range_refusal(target)
	if reason != "":
		return {"ids": PackedInt32Array(), "reason": reason}
	var selection := range_selection(target as RuleBlock)
	selection["reason"] = ""
	return selection


## 範囲に渡せない理由（渡せるなら空）。
func _range_refusal(target: Node3D) -> String:
	var v := selected_vessel()
	if v == null:
		return "ホットバー %d は空です" % (selected_slot + 1)
	var t := ledger.token(v.token_id)
	if t.is_lent():
		return "%s は貸出中です" % t.describe()
	if t.is_prohibition:
		return "禁止の範囲付与は未実装です（P0）"
	return _range_target_refusal(target)


func _range_target_refusal(target: Node3D) -> String:
	if target == null:
		return "ブロックを狙ってください"
	if not target is RuleBlock:
		return "生き物には範囲で渡せません"
	if not _within_reach(target):
		return "届きません（%.1fブロック）" % reach()
	return ""


## 毎フレーム、狙っているブロックでプレビューの表示を更新する。
func update_range_preview(target: Node3D) -> Dictionary:
	var preview := preview_range(target) if _range_preview_active else {}
	var ids := preview.get("ids", PackedInt32Array()) as PackedInt32Array
	for block in _previewed:
		block.set_preview(false)
	_previewed.clear()
	for id in ids:
		blocks[id].set_preview(true)
		_previewed.append(blocks[id])
	if _range_preview_visual == null:
		_range_preview_visual = RangePreview.new()
		_range_preview_visual.name = "RangePreview"
		add_child(_range_preview_visual)
	if ids.is_empty():
		_range_preview_visual.visible = false
	else:
		_range_preview_visual.show_at(
			preview["center"] as Vector3, float(preview["radius"]), int(preview["layer"])
		)
	return preview


func commit_range_preview(target: Node3D) -> RuleLedger.LendResult:
	_range_preview_active = false
	update_range_preview(null)
	return lend_to(target, true)


func cancel_range_preview() -> void:
	if not _range_preview_active:
		return
	_range_preview_active = false
	update_range_preview(null)
	_post("範囲付与を取り消しました")


## F: 足もとに器が落ちていれば拾う。チェックポイント上なら保存。そうでなければ狙ったブロックから
## 1つ回収し、無ければ立っている範囲付与を一括回収する。回収は「投げる」の有無によらず触る距離。
func interact(target: Node3D) -> void:
	var item := nearest_world_item()
	if item != null:
		_pick_up(item)
		return
	if is_on_checkpoint():
		save_checkpoint()
		return
	if target != null and _within_touch(target):
		var picked := _recall_one(_entity_of(target))
		if picked != null:
			_post("%s を回収しました" % picked.describe())
			_sound(&"prohibit" if picked.is_prohibition else &"recall", target.global_position)
			return
	var zone := ledger.range_tokens_at(player.global_position)
	if not zone.is_empty():
		var t := zone[0]
		ledger.recall(t.id)
		_post("範囲の %s を回収しました" % t.describe())
		_sound(&"recall", player.global_position)
		return
	_post("回収できるものがありません")
	_ui_sound(&"ui_error")


## 拾える距離にある、いちばん近い器（無ければ null）。
func nearest_world_item() -> RuleVessel:
	var best: RuleVessel = null
	var best_distance := Tuning.PICKUP_REACH
	for v in ledger.world_vessels():
		var d := player.global_position.distance_to(v.world_position)
		if d <= best_distance:
			best = v
			best_distance = d
	return best


func _pick_up(v: RuleVessel) -> void:
	var at := v.world_position
	ledger.pickup(v.id)
	var t := ledger.token(v.token_id)
	var item_label := v.item_name if v.item_name != "" else t.describe()
	_post("%s を拾いました（通常インベントリ。E で開いて使う）" % item_label)
	_sound(&"ui_pick", at)


func is_on_checkpoint() -> bool:
	var flat := player.global_position - checkpoint_center
	flat.y = 0.0
	return (
		flat.length() <= checkpoint_radius
		and absf(player.global_position.y - checkpoint_center.y) < 1.0
	)


## 画面中央の先にある付与先（ブロックか生き物。カメラからの光線）。
func aimed_block() -> Node3D:
	if camera_rig == null or camera_rig.camera() == null:
		return null
	var cam := camera_rig.camera()
	var from := cam.global_position
	var to := from + -cam.global_basis.z * (Tuning.THROW_REACH + CameraRig.DISTANCE)
	var query := PhysicsRayQueryParameters3D.create(
		from, to, Tuning.LAYER_TERRAIN | Tuning.LAYER_BLOCKS | Tuning.LAYER_CREATURES
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider := hit["collider"] as Node3D
	return collider if collider is RuleBlock or collider is Creature else null


func update_highlight(target: Node3D) -> void:
	if _highlighted == target:
		return
	if is_instance_valid(_highlighted):
		_highlighted.call(&"set_highlight", false)
	_highlighted = target
	if target != null:
		target.call(&"set_highlight", true)


# --- チェックポイント（企画書 9） ------------------------------------------


## 島に入った時点の状態を記録する（いつでも「最初からやり直す」で戻れる）。
func set_initial_checkpoint() -> void:
	_history.set_initial(_capture())
	checkpoint_changed.emit()


## F でチェックポイントに保存する。詰みにつながる状態なら保存せず、理由を表示して false を返す。
func save_checkpoint() -> bool:
	var blockers := CheckpointPolicy.save_blockers(
		ledger, player.is_on_floor(), _falling_blocks().size()
	)
	if not blockers.is_empty():
		var reasons := PackedStringArray()
		for b in blockers:
			reasons.append(CheckpointPolicy.describe(b))
		_post("保存できません: %s" % "／".join(reasons))
		_ui_sound(&"ui_error")
		return false
	_history.push(_capture())
	_post("チェックポイントを保存しました")
	_ui_sound(&"save")
	checkpoint_changed.emit()
	return true


## 最後に保存した時点へ、世界を丸ごと戻す。能力だけを戻すのではない。
func restore_checkpoint() -> void:
	_apply(_history.latest())
	_post("チェックポイントへ戻りました")


## 最後の保存を取り消して、ひとつ前の保存（無ければ島に入った時点）へ戻る。
## 詰んだ状態で保存してしまったときの逃げ道。能力が何も無くてもメニューから使える。
func restore_previous_checkpoint() -> bool:
	if not _history.can_discard_latest():
		return false
	_apply(_history.discard_latest())
	_post("最後の保存を取り消して、ひとつ前へ戻りました")
	checkpoint_changed.emit()
	return true


func restart_island() -> void:
	_apply(_history.reset_to_initial())
	_post("島の最初からやり直します")
	checkpoint_changed.emit()


func checkpoint_save_count() -> int:
	return _history.save_count()


func can_restore_previous_checkpoint() -> bool:
	return _history.can_discard_latest()


func _capture() -> Dictionary:
	var block_states := {}
	for id in blocks:
		var state := blocks[id].capture_state()
		state["cursor"] = _repeat_cursors[id].get_index()
		state["timer"] = _repeat_timers[id]
		state["signal_cursor"] = _signal_cursors[id].get_index()
		state["signal_timer"] = _signal_timers[id]
		block_states[id] = state
	var creature_states := {}
	for id in creatures:
		creature_states[id] = creatures[id].capture_state()
	return {
		"ledger": ledger.snapshot(),
		"creatures": creature_states,
		"player_position": player.global_position,
		"blocks": block_states,
		"selected_slot": selected_slot,
		"lend_mode": lend_mode,
		"goal_cleared": goal_cleared,
	}


func _apply(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	cancel_range_preview()
	ledger.restore(snapshot["ledger"] as Dictionary)
	player.global_position = snapshot["player_position"] as Vector3
	player.velocity = Vector3.ZERO
	var block_states := snapshot["blocks"] as Dictionary
	for id: int in block_states:
		var state := block_states[id] as Dictionary
		blocks[id].restore_state(state)
		_repeat_cursors[id].set_index(int(state["cursor"]))
		_repeat_timers[id] = float(state["timer"])
		_signal_cursors[id].set_index(int(state.get("signal_cursor", 0)))
		_signal_timers[id] = float(state.get("signal_timer", 0.0))
	var creature_states := snapshot.get("creatures", {}) as Dictionary
	for id: int in creature_states:
		creatures[id].restore_state(creature_states[id] as Dictionary)
	selected_slot = int(snapshot["selected_slot"])
	lend_mode = int(snapshot["lend_mode"]) as TriggerMode.Kind
	goal_cleared = bool(snapshot["goal_cleared"])
	state_changed.emit()


## 島から落ちていく途中のブロック（いちばん低い床＝谷底より下）。
func _falling_blocks() -> Array[RuleBlock]:
	var result: Array[RuleBlock] = []
	for block: RuleBlock in blocks.values():
		if block.global_position.y < Tuning.LOWEST_FLOOR_Y - 0.6:
			result.append(block)
	return result


## 島の外へ落ちきったブロックを救済する（仮の方針、docs/TODO.md）: 自分が貸していた
## 能力・禁止は器へ戻し、ブロックは最初の位置に戻す。レベルに置かれていた能力・禁止はブロックに残る。
func _rescue_lost_blocks() -> void:
	for id in blocks:
		var block := blocks[id]
		if block.global_position.y >= Tuning.FALL_LIMIT_Y:
			continue
		var returned := 0
		for t in ledger.tokens_on(id):
			if t.vessel_id != -1 and ledger.recall(t.id):
				returned += 1
		block.teleport(RuleBlock.cell_center(_home_cells[id]), 0.0)
		var note := "（貸していた %d 個は手元に戻りました）" % returned if returned > 0 else ""
		_post("島から落ちたブロックを元の位置に戻しました%s" % note)
	for id in creatures:
		var creature := creatures[id]
		if creature.global_position.y >= Tuning.FALL_LIMIT_Y:
			continue
		for t in ledger.tokens_on(id):
			if t.vessel_id != -1:
				ledger.recall(t.id)
		creature.restore_state({"position": _creature_homes[id], "velocity": Vector3.ZERO})
		_post("島から落ちた生き物を元の場所に戻しました")


# --- 毎フレーム -------------------------------------------------------------


func _physics_process(delta: float) -> void:
	_tick_climbers()
	_tick_repeats(delta)
	_tick_signals(delta)
	_tick_pulses(delta)
	if player == null:
		return
	_rescue_lost_blocks()
	if player.global_position.y < Tuning.FALL_LIMIT_Y:
		restore_checkpoint()
	if not goal_cleared and goal_box.has_volume() and goal_box.has_point(player.global_position):
		goal_cleared = true
		_post("高台に到達しました！")
		_ui_sound(&"goal")
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
			block.perform(action, ledger.can_initiate(id, RuleAction.Kind.HIGH_JUMP))


## 信号方式: 音波が届いている間だけ、繰り返しと同じ周期で行動を試みる。途絶えると次の動作は
## 休止し（周期の途中で止まる）、再び届くと続きから再開する。トークンは自動では戻らない（企画書 5.2）。
func _tick_signals(delta: float) -> void:
	for id in blocks:
		var actions := ledger.signal_actions(id)
		var receiving := not actions.is_empty() and is_receiving_signal(id)
		blocks[id].set_signal_state(not actions.is_empty(), receiving)
		if actions.is_empty():
			_signal_timers[id] = 0.0
			continue
		if not receiving:
			continue
		_signal_timers[id] += delta
		if _signal_timers[id] < Tuning.REPEAT_PERIOD:
			continue
		_signal_timers[id] -= Tuning.REPEAT_PERIOD
		var action := _signal_cursors[id].next_action(actions) as RuleAction.Kind
		var block := blocks[id]
		var result := BlockRules.attempt(ledger, id, action, block.is_ready_for(action))
		if result == BlockRules.Attempt.SUCCESS:
			block.perform(action, ledger.can_initiate(id, RuleAction.Kind.HIGH_JUMP))


## 登るを持つブロック: 東西南北の隣でいちばん高い上面に、自分の上面がそろうまで登る（rule_block.gd）。
## 禁止は優先（登る禁止を持てば登らない）。
func _tick_climbers() -> void:
	for id in blocks:
		var block := blocks[id]
		if not ledger.can_initiate(id, RuleAction.Kind.CLIMB):
			block.set_climb_target(NAN)
			continue
		var c := block.cell()
		var heights := survey_heights(Vector2i(c.x, c.z), 1)
		var top := -INF
		for dir: Vector2i in CreatureMind.DIRECTIONS:
			var n := Vector2i(c.x, c.z) + dir
			if heights.has(n):
				top = maxf(top, float(heights[n]))
		block.set_climb_target(NAN if top == -INF else top - RuleBlock.SIZE)


## 音源の音波の見た目と音（周期ごとに輪が広がる）。
func _tick_pulses(delta: float) -> void:
	if _sources.is_empty():
		return
	_pulse_timer += delta
	if _pulse_timer < Tuning.SIGNAL_PULSE_PERIOD:
		return
	_pulse_timer = 0.0
	for source_id in _sources:
		blocks[source_id].emit_pulse()
		_sound(&"radial_open", blocks[source_id].global_position)


func _fire_single_shot(token_id: int) -> void:
	var t := ledger.token(token_id)
	var results: Array[BlockRules.Attempt] = []
	for holder in t.holder_ids:
		var block := blocks[holder]
		var result := BlockRules.attempt(ledger, holder, t.action, block.is_ready_for(t.action))
		if result == BlockRules.Attempt.SUCCESS:
			block.perform(t.action, ledger.can_initiate(holder, RuleAction.Kind.HIGH_JUMP))
		results.append(result)
	var label := t.describe()
	if ledger.complete_single_shot(token_id, results):
		_post("単発の %s が成功して戻りました" % label)
	else:
		_post("単発の %s は動けませんでした（付与されたまま）" % label)
		var blocked := results.has(BlockRules.Attempt.PROHIBITED)
		_ui_sound(&"prohibit" if blocked else &"ui_error")


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


## いまの届き方（触る／投げる）で target に届くか。照準の色分けにも使う。
func is_within_reach(target: Node3D) -> bool:
	return target != null and _within_reach(target)


## 付与先の ID（ブロック・生き物）。
func _entity_of(target: Node3D) -> int:
	return int(target.get("entity_id"))


func _within_reach(target: Node3D) -> bool:
	return _distance_from_chest(target) <= reach() + RuleBlock.SIZE * 0.5


func _within_touch(target: Node3D) -> bool:
	return _distance_from_chest(target) <= Tuning.TOUCH_REACH + RuleBlock.SIZE * 0.5


func _distance_from_chest(target: Node3D) -> float:
	var chest := player.global_position + Vector3(0.0, 1.0, 0.0)
	return chest.distance_to(target.global_position)


func _block_cells() -> Dictionary:
	var cells := {}
	for id in blocks:
		cells[id] = blocks[id].cell()
	return cells


func _sound(event: StringName, at: Vector3) -> void:
	sound_requested.emit(event, at, true)


func _ui_sound(event: StringName) -> void:
	sound_requested.emit(event, Vector3.ZERO, false)


func _post(text: String) -> void:
	message_posted.emit(text)


func _on_ledger_changed() -> void:
	for id in blocks:
		blocks[id].show_tokens(ledger.tokens_on(id))
	for id in creatures:
		creatures[id].show_tokens(ledger.tokens_on(id))
	_sync_world_items()
	if throw_mode and not can_throw():
		# 「投げる」を渡した・禁止を拾ったら、その場で「触る」に戻る（最後の1回は投げられる）
		throw_mode = false
		_post("「投げる」を手放したので、届き方は「触る」になりました")
	state_changed.emit()


func _sync_world_items() -> void:
	var present := {}
	for v in ledger.world_vessels():
		present[v.id] = true
		if not _world_items.has(v.id):
			var node := WorldItem.new()
			node.setup(v, ledger.token(v.token_id))
			add_child(node)
			_world_items[v.id] = node
		_world_items[v.id].position = v.world_position
	for id: int in _world_items.keys():
		if not present.has(id):
			_world_items[id].queue_free()
			_world_items.erase(id)
