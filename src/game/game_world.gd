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
## 参加者の画面で操作したとき。ホストへ送る依頼（NetWorld が受け取って送る）。
signal action_requested(op: Dictionary)

const FIRST_BLOCK_ID: int = 100
const FIRST_CREATURE_ID: int = 500
## 地形のセルを動くブロックにしたときの ID（セルの並び順で決まるので、復元しても同じ ID になる）
const FIRST_TERRAIN_ID: int = 2000

var ledger: RuleLedger = RuleLedger.new()
var player: PlayerAvatar
var camera_rig: CameraRig
var blocks: Dictionary[int, RuleBlock] = {}
var creatures: Dictionary[int, Creature] = {}
## 鐘（音源）。F で鳴らすと、しばらく音波を出す。
var bells: Array[Bell] = []
## 動かない地形（どのセルも、能力を渡すと動くブロックになる）
var terrain: TerrainGrid
## 地形から動くブロックにしたセル → ブロックの ID
var promoted: Dictionary[Vector3i, int] = {}
var selected_slot: int = 0
var lend_mode: TriggerMode.Kind = TriggerMode.Kind.SINGLE_SHOT
var throw_mode: bool = false
var goal_cleared: bool = false
## F でチェックポイントを保存できる場所（中心と半径）。
var checkpoint_center: Vector3 = Vector3.ZERO
var checkpoint_radius: float = 1.5
## 到達判定の高台（AABB）。
var goal_box: AABB = AABB()

## 通信対戦中か（ホストでも参加者でも true）。参加者は replica も true。
var networked: bool = false
## 参加者の画面: ルールと物理はホストが決める。ここでは自分のアバターだけを動かし、操作は依頼として送る。
var replica: bool = false
## 仲間のアバター（操り人形）。キーはプレイヤー ID。
var avatars: Dictionary[int, PlayerAvatar] = {}
## メッセージの送り先を差し替える（ホストが参加者の代わりに操作するとき、その人へ返すため）。
var post_sink: Callable = Callable()
## 持ち物の画面からの操作の窓口（参加者ならホストへの依頼になる）。
var ledger_actions: LedgerActions = LedgerActions.new()

var _next_block_id: int = FIRST_BLOCK_ID
var _repeat_cursors: Dictionary[int, RepeatCursor] = {}
var _repeat_timers: Dictionary[int, float] = {}
var _signal_cursors: Dictionary[int, RepeatCursor] = {}
var _signal_timers: Dictionary[int, float] = {}
## 発射台のブロック（ID → 撃つ方角）。「投げる」を持っている間だけ玉を撃つ。
var _launchers: Dictionary[int, Vector3i] = {}
var _launch_timers: Dictionary[int, float] = {}
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
var _terrain_ids: Dictionary[Vector3i, int] = {}
var _terrain_kinds: Dictionary[Vector3i, String] = {}
var _terrain_target: TerrainCell


func _ready() -> void:
	ledger_actions.ledger = ledger
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
	# 跳躍と同じく自分の世界の音として鳴らす（ホストの音は NetWorld が参加者へ配る）
	player.dashed.connect(func() -> void: _sound(&"dash", player.global_position))
	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	camera_rig.target = player
	add_child(camera_rig)
	return player


## プレイヤー ID のアバター（自分なら player、仲間なら操り人形。いなければ null）。
func avatar_of(player_id: int) -> PlayerAvatar:
	if player != null and player.player_id == player_id:
		return player
	return avatars.get(player_id) as PlayerAvatar


## いま操作している人のプレイヤー ID。
func acting_id() -> int:
	return player.player_id if player != null else RuleLedger.PLAYER_ID


func add_block(
	cell: Vector3i,
	color: Color = Color(0.85, 0.65, 0.35),
	model_name: String = "ability_block",
	fixed_id: int = -1
) -> RuleBlock:
	var block := RuleBlock.new()
	var id := fixed_id
	if id < 0:
		id = _next_block_id
		_next_block_id += 1
	block.setup(id, cell, color, model_name)
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


## 地形のセルを狙ったことにする（照準の代わり。テストや別の入力から使う）。
func terrain_target(cell: Vector3i) -> TerrainCell:
	_terrain_target.point_at(cell)
	return _terrain_target


## 動かない地形を作る。boxes: [[最小のセル, 最大のセル, 種類], ...]（種類は grass / rock / sand）。
## どのセルも、能力を渡すと動くブロックになる（TerrainPromotion）。
func build_terrain(boxes: Array) -> void:
	TerrainPromotion.build(self, boxes)


## 鐘を置く（企画書 5.4 の音源。2026-11-19 本人の判断: 音源は基本、鐘で、F で鳴らす）。
func add_bell(at: Vector3) -> Bell:
	var bell := Bell.new()
	bell.position = at
	add_child(bell)
	bells.append(bell)
	bell.rang.connect(func() -> void: _sound(&"bell", bell.global_position))
	return bell


## 発射台（2026-11-19 本人の判断）: 「投げる」が来ないと撃たない仕掛け。持っている間、周期ごとに
## direction（世界の方角）へ玉を撃つ。玉が鐘に当たると鐘が鳴る。
func add_launcher(cell: Vector3i, direction: Vector3i) -> RuleBlock:
	var block := add_block(cell, Color.WHITE, "launcher")
	block.make_launcher(direction)
	_launchers[block.entity_id] = direction
	_launch_timers[block.entity_id] = 0.0
	return block


## 玉を投げる（発射台・生き物）。thrower には当たらない。
func throw_ball(from: Vector3, velocity: Vector3, thrower: CollisionObject3D = null) -> ThrownBall:
	var ball := ThrownBall.new()
	ball.velocity = velocity
	ball.ignore(thrower)
	add_child(ball)
	ball.global_position = from
	ball.add_to_group(&"thrown_balls")
	_sound(&"player_jump", from)
	return ball


## その位置に音波が届いているか（鳴っている鐘からの距離が半径以内）。
## 伝わる距離だけで判定する（2026-11-19 本人の判断。遮る物体は追加するときに足す）。
func is_receiving_signal(entity_id: int) -> bool:
	if not blocks.has(entity_id):
		return false
	var at := blocks[entity_id].global_position
	for bell in bells:
		if bell.reaches(at):
			return true
	return MechanismSet.signal_reaches(self, at)  # 押されている重さの板・入ったレバー（docs/adr/0014）


## 願いを持つ生き物を置く（企画書 6）。
func add_creature(at: Vector3, look: String = Creature.MODEL_WISH) -> Creature:
	var creature := Creature.new()
	creature.look = look
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
	creature.threw.connect(
		func(from: Vector3, velocity: Vector3) -> void: throw_ball(from, velocity, creature)
	)
	return creature


## マスごとの立てる高さ（地形とブロックの上面）。生き物の判断とブロックの登るに使う。穴のマスは入れない。
func survey_heights(center: Vector2i, radius: int) -> Dictionary:
	return WorldQueries.survey(get_world_3d().direct_space_state, center, radius)


func _notify_creatures() -> void:
	for creature: Creature in creatures.values():
		creature.notify_environment_changed()


# --- プレイヤーの操作 -------------------------------------------------------


func selected_vessel() -> RuleVessel:
	return ledger.hotbar_vessel(selected_slot, acting_id())


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
		var why := WorldQueries.throw_unavailable_reason(ledger, acting_id())
		_post("「投げる」が使えません（%s）" % why)
		_ui_sound(&"ui_error")
		return
	throw_mode = not throw_mode
	_post("付与の届き方: %s" % ("投げる" if throw_mode else "触る"))
	state_changed.emit()


func can_throw() -> bool:
	return ledger.player_can(RuleAction.Kind.THROW, acting_id())


## 投げるを n 個持てば射程も n 倍（2026-11-19 本人確定）。
func reach() -> float:
	if not (throw_mode and can_throw()):
		return Tuning.TOUCH_REACH
	return (
		Tuning.THROW_REACH
		* Tuning.stack_factor(ledger.ability_count(RuleAction.Kind.THROW, acting_id()))
	)


## W/A/S/D/Space を押した瞬間。自分の行動と、貸し出した単発の起動に振り分ける。
## 同じ行動の単発が同じブロックに n 個あれば、まとめて1回 n 倍で試みる。
func press_action(action: RuleAction.Kind) -> void:
	var route := InputRouter.route_press(ledger, action, acting_id())
	if route.player_acts and action == RuleAction.Kind.JUMP:
		player.request_jump()
	elif route.player_acts and action == RuleAction.Kind.DASH:
		player.request_dash()
	if replica:
		action_requested.emit({"op": "press", "action": action})
		return
	if not route.single_shot_token_ids.is_empty():
		WorldTicks.fire_single_shots(self, route.single_shot_token_ids)


## 選択中のホットバーの器から、target へ付与する。use_range なら target の層の円内の全ブロックへ。
func lend_to(target: Node3D, use_range: bool) -> RuleLedger.LendResult:
	if replica:
		var ref := WorldQueries.target_ref(self, target)
		action_requested.emit({"op": "lend", "target": ref, "range": use_range})
		return RuleLedger.LendResult.OK
	return _give_to(target as PlayerAvatar) if target is PlayerAvatar else _lend(target, use_range)


func _lend(target: Node3D, use_range: bool) -> RuleLedger.LendResult:
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
	if target is Bell:
		_post("鐘には渡せません（%s で鳴らす）" % InputMode.token(&"interact"))
		_ui_sound(&"ui_error")
		return RuleLedger.LendResult.UNKNOWN_TARGET
	if target is TerrainCell:
		target = TerrainPromotion.promote(self, (target as TerrainCell).cell)
	if use_range and not (target is RuleBlock or target is TerrainCell):
		_post("生き物には範囲で渡せません（%s で1匹に渡す）" % InputMode.token(&"lend_single"))
		_ui_sound(&"ui_error")
		return RuleLedger.LendResult.RANGE_ONLY_FOR_BLOCKS
	if use_range:
		var selection := range_selection(target)
		var ids := selection["ids"] as PackedInt32Array
		for cell: Vector3i in selection["cells"] as Array:
			# 範囲内の地形のセルも、全部ブロックとして受け取る
			ids.append(TerrainPromotion.promote(self, cell).entity_id)
		selection["ids"] = ids
		result = ledger.lend(v.id, ids, mode, selection)
	else:
		result = ledger.lend(v.id, PackedInt32Array([_entity_of(target)]), mode)
	_post(WorldQueries.describe(t, result, use_range))
	if result == RuleLedger.LendResult.OK:
		# 法則の音（能力ごとの音程）と、受け取った物が自分の材質の声で応える音
		var motif := (
			"%s@%d" % ["lend_range" if use_range else "lend", RuleAction.motif_semitone(t.action)]
		)
		_sound(StringName(motif), target.global_position)
		_sound(WorldQueries.receive_sound(target), target.global_position)
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


## 仲間へ能力を渡す（受け手の承認なし。2026-11-19 本人確定）。選んでいる枠の能力から渡す。
## 枠の器が空なら、受け取って持っている同じ種類の能力を渡す。
func _give_to(target: PlayerAvatar) -> RuleLedger.LendResult:
	var token_id := WorldQueries.giveable_token(ledger, acting_id(), selected_slot)
	if token_id == -1 or not _within_reach(target):
		_post("渡せる能力がないか、届きません")
		_ui_sound(&"ui_error")
		return RuleLedger.LendResult.NO_TARGETS
	var result := ledger.give_to_player(token_id, acting_id(), target.player_id)
	var t := ledger.token(token_id)
	if result == RuleLedger.LendResult.OK:
		_post("%s を仲間に渡しました" % t.describe())
		_sound(&"lend", target.global_position)
	else:
		_post(WorldQueries.describe(t, result, false))
		_ui_sound(&"ui_error")
	return result


## 範囲付与で選ばれるブロック（プレビューと付与で同じ計算）。動くブロックの ID と、地形のままのセル
## （渡すときに動くブロックになる）を分けて返す。range_spec にも使える {center, radius, layer, ids, cells}。
func range_selection(target: Node3D) -> Dictionary:
	var center := target.global_position
	var layer := floori(center.y - 0.5 + 0.001)
	var radius := BlockRules.DEFAULT_RANGE_RADIUS
	var ids := BlockRules.select_in_range(center, radius, layer, _block_cells())
	var cells: Array[Vector3i] = []
	for cell: Vector3i in terrain.cells if terrain != null else {}:
		var flat := Vector2(cell.x + 0.5 - center.x, cell.z + 0.5 - center.z)
		if cell.y == layer and flat.length() <= radius + 0.0001:
			cells.append(cell)
	return {"center": center, "radius": radius, "layer": layer, "ids": ids, "cells": cells}


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
	var selection := range_selection(target)
	selection["reason"] = ""
	return selection


## 範囲に渡せない理由（渡せるなら空）。
func _range_refusal(target: Node3D) -> String:
	var v := selected_vessel()
	if v == null:
		return "ホットバー %d は空です" % (selected_slot + 1)
	var t := ledger.token(v.token_id)
	if not t.is_in_vessel():
		return "%s は貸出中です" % t.describe()
	return _range_target_refusal(target)


func _range_target_refusal(target: Node3D) -> String:
	if target == null:
		return "ブロックを狙ってください"
	if not (target is RuleBlock or target is TerrainCell):
		return "生き物には範囲で渡せません"
	if not _within_reach(target):
		return "届きません（%.1fブロック）" % reach()
	return ""


## 毎フレーム、狙っているブロックでプレビューの表示を更新する。
func update_range_preview(target: Node3D) -> Dictionary:
	var preview := preview_range(target) if _range_preview_active else {}
	var ids := preview.get("ids", PackedInt32Array()) as PackedInt32Array
	var cell_count := (preview.get("cells", []) as Array).size()
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
	if ids.is_empty() and cell_count == 0:
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
## 付いているものを全部回収し、無ければ立っている範囲付与を全部回収する。回収は「投げる」の有無によらず触る距離。
## 全部回収（2026-11-19 本人の判断）: 自分が貸したものは器へ、最初から置かれていたものは拾ったものとして通常インベントリへ。
func interact(target: Node3D) -> void:
	if replica:
		action_requested.emit({"op": "interact", "target": WorldQueries.target_ref(self, target)})
		return
	var dropped := WorldQueries.nearest_dropped(ledger, player.global_position)
	if dropped == -1:
		_interact(target)
		return
	ledger.pickup_token(dropped, acting_id())
	_post("落ちていた %s を拾いました" % ledger.token(dropped).describe())
	_sound(&"ui_pick", player.global_position)


func _interact(target: Node3D) -> void:
	var item := nearest_world_item()
	if item != null:
		_pick_up(item)
		return
	if is_on_checkpoint() and not networked:
		save_checkpoint()
		return
	if target is Bell and _within_touch(target):
		(target as Bell).ring()
		_post("鐘を鳴らしました")
		return
	if target != null and _within_touch(target):
		var picked := _recall_all(ledger.tokens_on(_entity_of(target)))
		if not picked.is_empty():
			_post("%s を回収しました" % _describe_tokens(picked))
			var only_bans := picked.all(func(t: RuleToken) -> bool: return t.is_prohibition)
			var back := "recall@%d" % RuleAction.motif_semitone(picked[0].action)
			_sound(&"prohibit" if only_bans else StringName(back), target.global_position)
			return
	var zone := _recall_all(ledger.range_tokens_at(player.global_position))
	if not zone.is_empty():
		_post("範囲の %s を回収しました" % _describe_tokens(zone))
		_sound(&"recall", player.global_position)
		return
	_post("回収できるものがありません")
	_ui_sound(&"ui_error")


## 拾える距離にある、いちばん近い器（無ければ null）。
func nearest_world_item() -> RuleVessel:
	return WorldItem.nearest(ledger, player.global_position)


func _pick_up(v: RuleVessel) -> void:
	var at := v.world_position
	ledger.pickup(v.id, acting_id())
	var t := ledger.token(v.token_id)
	var item_label := v.item_name if v.item_name != "" else t.describe()
	_post("%s を拾いました（通常インベントリ。%s で開いて使う）" % [item_label, InputMode.token(&"inventory")])
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
	var mask := Tuning.LAYER_TERRAIN | Tuning.LAYER_BLOCKS | Tuning.LAYER_CREATURES
	var query := PhysicsRayQueryParameters3D.create(from, to, mask | Tuning.LAYER_AVATARS)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider := hit["collider"] as Node3D
	if (
		collider is RuleBlock
		or collider is Creature
		or collider is Bell
		or collider is PlayerAvatar
	):
		return collider
	if terrain != null and terrain.is_terrain_body(collider):
		var cell := TerrainGrid.cell_at_hit(hit["position"] as Vector3, hit["normal"] as Vector3)
		if terrain.has_cell(cell):
			_terrain_target.point_at(cell)
			return _terrain_target
	return null


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
	return WorldSnapshot.capture(self)


func _apply(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	cancel_range_preview()
	WorldSnapshot.apply(self, snapshot)
	state_changed.emit()


## 島から落ちていく途中のブロック（いちばん低い床＝谷底より下）。
func _falling_blocks() -> Array[RuleBlock]:
	var result: Array[RuleBlock] = []
	for block: RuleBlock in blocks.values():
		if block.global_position.y < Tuning.LOWEST_FLOOR_Y - 0.6:
			result.append(block)
	return result


# --- 毎フレーム -------------------------------------------------------------


func _physics_process(delta: float) -> void:
	if replica:
		return  # ルールと物理はホストが決める
	WorldTicks.climbers(self)
	WorldTicks.repeats(self, delta)
	WorldTicks.signals(self, delta)
	WorldTicks.launchers(self, delta)
	if player == null:
		return
	WorldTicks.rescue_lost(self)
	if player.global_position.y < Tuning.FALL_LIMIT_Y and not networked:
		restore_checkpoint()
	if not goal_cleared and goal_box.has_volume() and goal_box.has_point(player.global_position):
		goal_cleared = true
		_post("高台に到達しました！")
		_ui_sound(&"goal")
		goal_reached.emit()


func _high(id: int) -> bool:
	return ledger.can_initiate(id, RuleAction.Kind.HIGH_JUMP)


# --- 内部 -------------------------------------------------------------------


## まとめて回収し、回収できたものを返す。
func _recall_all(tokens: Array[RuleToken]) -> Array[RuleToken]:
	var picked: Array[RuleToken] = []
	for t in tokens:
		if ledger.recall(t.id, acting_id()):
			picked.append(t)
	return picked


func _describe_tokens(tokens: Array[RuleToken]) -> String:
	var names := PackedStringArray()
	for t in tokens:
		names.append(t.describe())
	return "・".join(names)


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
	if post_sink.is_valid():
		post_sink.call("", event)
		return
	sound_requested.emit(event, Vector3.ZERO, false)


func _post(text: String) -> void:
	if post_sink.is_valid():
		post_sink.call(text, &"")
		return
	message_posted.emit(text)


func _on_ledger_changed() -> void:
	for id in blocks:
		blocks[id].show_tokens(ledger.tokens_on(id))
	for id in creatures:
		creatures[id].show_tokens(ledger.tokens_on(id))
	WorldItem.sync_all(self, ledger, _world_items)
	if throw_mode and not can_throw():
		# 「投げる」を渡した・禁止を拾ったら、その場で「触る」に戻る（最後の1回は投げられる）
		throw_mode = false
		_post("「投げる」を手放したので、届き方は「触る」になりました")
	state_changed.emit()
