extends TestCase
## 島の「関所」と詰みを、プレイヤーと同じ操作で壊しにいく試遊（2026-11-20、敵対的な試遊）。
## 結果は docs/reports/2026-11-20-island-playtest-findings.md にまとめた。
## - test_gate_*: 意図した関所が守られていること（壊れたら失敗する）
## - test_accepted_*: 見つかった抜け道のうち、本人が「残してよい」と決めたもの（2026-11-20）。
##   F1 縁ちょうどの幅 4 越え・F2 上昇中のブロックの上で跳ぶ（上手い人の技）・F3 地面のセルの持ち上げ台・
##   F5 採石場の底（V で戻れる）。挙動が変わったら気づけるように残す
## - F4・F6・F7 は直したので test_gate_* にした
## 瞬間移動・状態の直接書き換えはしない（照準の代わりに TerrainCell を狙うのと、台帳の読み取りだけ）。

const JUMP := RuleAction.Kind.JUMP
const DASH := RuleAction.Kind.DASH
const THROW := RuleAction.Kind.THROW
const MOVES: Array[RuleAction.Kind] = [
	RuleAction.Kind.FORWARD,
	RuleAction.Kind.LEFT,
	RuleAction.Kind.BACK,
	RuleAction.Kind.RIGHT,
]
const DASH_SLOT := 6
## 谷の縁から踏み切る位置（m、進む向きに +）。
const OFFSETS: Array[float] = [-0.2, -0.1, 0.0, 0.1, 0.2, 0.3]
const PROFILE := "zz_test_island_probes"

var director: PartyDirector
var w: StageWorld


func before_each() -> void:
	ProgressStore.new().delete(PROFILE)
	director = PartyDirector.new()
	director.profile = PROFILE
	tree.root.add_child(director)


func after_each() -> void:
	director.queue_free()
	await tree.process_frame
	ProgressStore.new().delete(PROFILE)


func _enter(stage_id: String) -> void:
	director.enter_stage(stage_id)
	w = director.world
	await wait_physics_frames(10)


func _me() -> PlayerAvatar:
	return w.player


func _slot_of(action: RuleAction.Kind) -> int:
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(slot, _me().player_id)
		if v != null and w.ledger.token(v.token_id).action == action:
			return slot
	return -1


# --- 操作の部品（test_open_islands.gd と同じ動き） -------------------------------


func _face(target: Vector3) -> Vector3:
	var flat := Vector3(target.x - _me().global_position.x, 0.0, target.z - _me().global_position.z)
	_me().view_yaw = atan2(-flat.x, -flat.z)
	return flat


func _walk_to(target: Vector3, tolerance: float = 0.35, frames: int = 1200) -> bool:
	var stuck := 0
	for i in frames:
		var flat := _face(target)
		if flat.length() <= tolerance and absf(_me().global_position.y - target.y) < 0.7:
			_me().move_intent = Vector2.ZERO
			return true
		_me().move_intent = Vector2(0.0, 1.0)
		var moving := Vector2(_me().velocity.x, _me().velocity.z).length() > 0.5
		stuck = 0 if moving else stuck + 1
		if stuck > 8 and _me().is_on_floor():
			w.press_action(JUMP)
			stuck = 0
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	fail("could not walk to %s (at %s)" % [target, _me().global_position])
	return false


func _walk_route(route: Array[Vector3]) -> void:
	for p in route:
		await _walk_to(p)


func _lend(target: Node3D, slot: int, mode: TriggerMode.Kind) -> void:
	w.select_slot(slot)
	w.set_lend_mode(mode)
	assert_eq(w.lend_to(target, false), RuleLedger.LendResult.OK, "lend to %s" % target.name)


func _block(key: String) -> RuleBlock:
	return w.blocks[int(w.entity_ids[key])]


func _pick_and_wear(at: Vector3, part: RuleVessel.Part) -> void:
	await _walk_to(at, 0.6)
	w.interact(null)
	await wait_physics_frames(2)
	for v in w.ledger.inventory_vessels(_me().player_id):
		if v.part == part:
			assert_true(w.ledger_actions.equip(v.id), "wear %s" % v.item_name)


## 落ちているダッシュを拾い、ホットバーに置く（E で開いて並べるのと同じ操作）。
func _pick_dash(at: Vector3) -> void:
	await _walk_to(at, 0.6)
	w.interact(null)
	await wait_physics_frames(2)
	for v in w.ledger.inventory_vessels(_me().player_id):
		if w.ledger.token(v.token_id).action == DASH:
			assert_true(w.ledger_actions.move_to_hotbar(v.id, DASH_SLOT), "dash on the hotbar")
	assert_true(w.ledger.player_can(DASH, _me().player_id), "can dash")


## 落ちて死んだあと、全員リセットでどこかの床に立つまで待つ。
func _wait_respawn() -> void:
	for i in 400:
		if _me().global_position.y > -0.6 and _me().is_on_floor():
			await wait_physics_frames(4)
			return
		await tree.physics_frame
	fail("did not respawn (at %s)" % _me().global_position)


## 谷の手前から dir（東西南北のどれか）へ全力で走り、谷の縁（進む向きの座標 edge）より offset 先で
## 跳ぶ（床にいる最初のフレームで跳ぶ）。向こう岸（edge + gap より先）に立てたら true。
## 落ちたら false を返し、リセットで戻るまで待つ。
func _running_jump(
	route: Array[Vector3], dir: Vector3, edge: float, gap: float, offset: float, dash: bool = false
) -> bool:
	await _walk_route(route)
	_me().view_yaw = atan2(-dir.x, -dir.z)
	_me().move_intent = Vector2(0.0, 1.0)
	var jumped := false
	var dashed := false
	var result := false
	var floor_y := _me().global_position.y
	for i in 300:
		var p := _me().global_position.dot(dir)
		if not jumped and p >= edge + offset:
			if _me().is_on_floor():
				w.press_action(JUMP)
			else:
				jumped = true
		if jumped and dash and not dashed and _me().velocity.y < 0.0:
			w.press_action(DASH)
			dashed = true
		if jumped and _me().is_on_floor() and p > edge + gap - 0.4:
			result = absf(_me().global_position.y - floor_y) < 0.3
			break
		if _me().global_position.y < floor_y - 2.0:
			break
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	if not result:
		await _wait_respawn()
	return result


## 段の手前 start から、toward へ押しながら床に着くたび跳び続ける。届いた最高の足の高さを返す。
func _jump_against(start: Vector3, toward: Vector3, frames: int = 300) -> float:
	await _walk_to(start)
	var best := _me().global_position.y
	for i in frames:
		_face(toward)
		_me().move_intent = Vector2(0.0, 1.0)
		if _me().is_on_floor():
			w.press_action(JUMP)
		best = maxf(best, _me().global_position.y)
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	return best


## 鐘の真下側 stand から、壁へ押しつけて跳びながら毎フレーム F。鳴ったら true。最短の胸の距離を出す。
func _try_ring_from(bell_key: String, stand: Vector3) -> bool:
	var bell := w.bells_by_key[bell_key]
	await _walk_to(stand, 0.3)
	var closest := 99.0
	for i in 120:
		_face(bell.global_position)
		_me().move_intent = Vector2(0.0, 1.0)
		if _me().is_on_floor():
			w.press_action(JUMP)
		var chest := _me().global_position + Vector3(0.0, 1.0, 0.0)
		closest = minf(closest, chest.distance_to(bell.global_position))
		w.interact(bell)
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	print(
		(
			"    %s from %s: closest chest distance %.2f (touch reach %.2f)"
			% [bell_key, stand, closest, Tuning.TOUCH_REACH + RuleBlock.SIZE * 0.5]
		)
	)
	return w.activated.has(bell_key)


func _cleared(frames: int = 180) -> bool:
	for i in frames:
		if director.last_clear_text != "":
			return true
		await tree.physics_frame
	return false


# --- 1. 関所: 普通のジャンプ（1.3）で 2 段は上がれない -----------------------------


func test_gate_hill_summit_is_not_two_plain_jumps_from_the_terrace() -> void:
	await _enter(StageCatalog.HILL_ID)
	await _walk_route([Vector3(0.5, 1.0, 1.5), Vector3(3.5, 2.0, -1.5)])
	var best := await _jump_against(Vector3(3.5, 2.0, -5.5), Vector3(0.5, 4.0, -5.5))
	assert_lt(best, 3.5, "plain jumps from the terrace (2) never reach the summit (4)")
	assert_eq(director.last_clear_text, "", "not cleared")


func test_gate_quarry_terrace_is_not_a_plain_jump_from_the_floor() -> void:
	await _enter(StageCatalog.QUARRY_ID)
	var best := await _jump_against(Vector3(0.5, 0.0, 5.2), Vector3(0.5, 2.0, 7.5))
	assert_lt(best, 1.5, "floor (0) to terrace (2)")


func test_gate_floating_tower_is_not_a_plain_jump_from_the_ground() -> void:
	await _enter(StageCatalog.FLOATING_ID)
	var best := await _jump_against(Vector3(-3.5, 0.0, -4.5), Vector3(-1.0, 2.0, -4.5))
	assert_lt(best, 1.5, "ground (0) to tower (2)")


func test_gate_three_bells_west_plateau_is_not_a_plain_jump_from_the_skirt() -> void:
	await _enter(StageCatalog.THREE_BELLS_ID)
	await _walk_to(Vector3(-13.5, 1.0, 2.5))
	var best := await _jump_against(Vector3(-14.5, 1.0, 2.5), Vector3(-17.0, 3.0, 2.5))
	assert_lt(best, 2.5, "skirt (1) to plateau (3)")


# --- 1. 谷: 走って跳ぶと幅 4 は越えられる（抜け道）、幅 5 は越えられない（関所） -----
# 縁から offset 先（-0.2〜+0.3）で踏み切る（小さい方から試し、最初に越えた値を出す）。
# 幅 4 は ADR 0011 では「ダッシュ・ブーツ・W×2 で越える」はずだが、普通のジャンプで越えられる。


func test_accepted_hill_west_gap_of_four_only_at_the_exact_edge() -> void:
	await _enter(StageCatalog.HILL_ID)
	# 島の西の端は x = -9（谷は x -13〜-9）。小島には西へ向かって跳ぶ
	var route: Array[Vector3] = [
		Vector3(-7.5, 0.0, 5.5), Vector3(-7.5, 0.0, -4.5), Vector3(-6.8, 0.0, -4.5)
	]
	var crossed := 0
	for offset in OFFSETS:
		if await _running_jump(route, Vector3.LEFT, 9.0, 4.0, offset):
			crossed += 1
			print("    hill_top west gap 4 crossed with a plain jump at offset %.1f" % offset)
			break
	assert_eq(
		crossed, 1, "ACCEPTED: a plain running jump crosses the 4-wide gap to the gloves islet"
	)


func test_accepted_three_bells_east_gap_of_four_only_at_the_exact_edge() -> void:
	await _enter(StageCatalog.THREE_BELLS_ID)
	await _walk_to(Vector3(9.5, 0.0, 3.5))  # チェックポイントを有効にして、落ちたらここへ戻る
	var route: Array[Vector3] = [Vector3(10.0, 0.0, -2.5)]
	var crossed := 0
	for offset in OFFSETS:
		if await _running_jump(route, Vector3.RIGHT, 13.0, 4.0, offset):
			crossed += 1
			print("    three_bells east gap 4 crossed with a plain jump at offset %.1f" % offset)
			break
	assert_eq(crossed, 1, "ACCEPTED: a plain running jump crosses the 4-wide gap to the east islet")


func test_accepted_floating_west_gap_of_four_only_at_the_exact_edge() -> void:
	await _enter(StageCatalog.FLOATING_ID)
	await _walk_to(Vector3(-4.5, 0.0, 4.5))
	var route: Array[Vector3] = [Vector3(-3.5, 0.0, 1.5)]
	var crossed := 0
	for offset in OFFSETS:
		if await _running_jump(route, Vector3.LEFT, 6.0, 4.0, offset):
			crossed += 1
			print("    floating_isles west gap 4 crossed with a plain jump at offset %.1f" % offset)
			break
	assert_eq(crossed, 1, "ACCEPTED: a plain running jump crosses the 4-wide gap to the west isle")


func test_gate_floating_east_gap_of_five_is_not_a_running_jump() -> void:
	await _enter(StageCatalog.FLOATING_ID)
	await _walk_to(Vector3(-4.5, 0.0, 4.5))
	var route: Array[Vector3] = [Vector3(4.5, 0.0, -2.5)]
	var crossed := 0
	for offset in OFFSETS:
		if await _running_jump(route, Vector3.RIGHT, 7.0, 5.0, offset):
			crossed += 1
			break
	assert_eq(crossed, 0, "a plain running jump does not cross the 5-wide gap to the east isle")


# --- 1. 関所: 台地の鐘は下から鳴らせない ----------------------------------------


func test_gate_three_bells_west_bell_is_not_rung_from_below() -> void:
	await _enter(StageCatalog.THREE_BELLS_ID)
	await _walk_to(Vector3(-13.5, 1.0, 1.5))
	for stand: Vector3 in [
		Vector3(-14.6, 1.0, 0.5), Vector3(-17.5, 1.0, 4.4), Vector3(-14.5, 1.0, -5.5)
	]:
		if stand.z < -5.0:
			await _walk_route([Vector3(-14.5, 1.0, 4.5), Vector3(-14.5, 1.0, -5.5)])
			stand = Vector3(-17.5, 1.0, -5.4)
		assert_false(await _try_ring_from("west_bell", stand), "west bell from %s" % stand)


func test_gate_three_bells_north_bell_is_not_rung_from_the_step() -> void:
	await _enter(StageCatalog.THREE_BELLS_ID)
	await _walk_route(
		[
			Vector3(5.5, 0.0, -12.5),
			Vector3(5.5, 1.0, -15.5),
			Vector3(5.5, 2.0, -17.5),
			Vector3(3.5, 3.0, -16.5),
			Vector3(4.4, 3.0, -16.5),
		]
	)
	assert_false(await _try_ring_from("north_bell", Vector3(4.4, 3.0, -22.5)), "from the east")
	await _walk_route([Vector3(3.5, 3.0, -16.0), Vector3(-5.4, 3.0, -16.0)])
	assert_false(await _try_ring_from("north_bell", Vector3(-5.4, 3.0, -22.5)), "from the west")


# --- 1. 抜け道: どの地面のセルも「持ち上げ台」になる --------------------------------


## 窪みのブロック（lift）を使わず、段丘（高さ 2）の好きな所で、足もとの地面のセルにジャンプを
## 単発で貸す。セルが動くブロックになって 2.5 跳び、そのまま頂上（高さ 4）へ移れる。
func test_accepted_any_ground_cell_is_a_lift_on_the_hill() -> void:
	await _enter(StageCatalog.HILL_ID)
	await _walk_route([Vector3(0.5, 1.0, 1.5), Vector3(3.5, 2.0, -1.5), Vector3(3.5, 2.0, -4.5)])
	var lift_cell := Vector3i(3, 1, -5)
	_lend(w.terrain_target(lift_cell), _slot_of(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(JUMP)
	for i in 240:
		_face(Vector3(0.5, 4.0, -4.5))
		_me().move_intent = Vector2(0.0, 1.0) if _me().global_position.y > 4.05 else Vector2.ZERO
		if _me().global_position.x < 2.0 and _me().is_on_floor():
			break
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	await _walk_to(Vector3(0.5, 3.0, -6.0))  # 頂上の奥のゴール（窪み）へ歩いて入る
	assert_true(await _cleared(), "ACCEPTED: reached the summit on a promoted ground cell")
	var pit_lift := _block("lift")
	assert_true(w.ledger.tokens_on(pit_lift.entity_id).is_empty(), "the pit lift was never used")


## 足もとのセルに単発のジャンプを貸して起動し、返ってきたジャンプで、上昇中のセルの上から
## 自分でも跳ぶ。セルの上昇の速さが加わって、どこまで上がるかを測る。
func test_accepted_lift_then_own_jump_stacks() -> void:
	await _enter(StageCatalog.QUARRY_ID)
	await _walk_to(Vector3(0.5, 0.0, 2.5))
	var cell := Vector3i(0, -1, 2)
	_lend(w.terrain_target(cell), _slot_of(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(JUMP)
	var best := 0.0
	var pressed := false
	for i in 120:
		if not pressed and w.ledger.player_can(JUMP, _me().player_id) and _me().is_on_floor():
			if _me().global_position.y > 0.2:
				w.press_action(JUMP)
				pressed = true
		best = maxf(best, _me().global_position.y)
		await tree.physics_frame
	print("    block 2.5 + own jump while riding: feet reached %.2f" % best)
	assert_true(pressed, "the single shot came back while riding")
	assert_gt(best, 3.5, "ACCEPTED: riding jump + own jump goes far above the block's 2.5")


## 上の重ね跳びで、採石場の段丘（高さ 2）から縁（高さ 5）へ、窪み・ブーツ・グローブなしで出る。
func test_accepted_quarry_rim_from_the_terrace_by_stacking() -> void:
	await _enter(StageCatalog.QUARRY_ID)
	await _pick_and_wear(Vector3(-4.5, 0.0, 4.5), RuleVessel.Part.FEET)  # 底 → 段はブーツ
	await _walk_to(Vector3(-5.5, 2.0, 4.5))
	var boots := w.ledger.equipped_vessel(RuleVessel.Part.FEET, _me().player_id)
	assert_true(w.ledger_actions.unequip(boots.id), "take the boots off again")
	await _walk_to(Vector3(-7.5, 2.0, 0.5))
	_lend(w.terrain_target(Vector3i(-8, 1, 0)), _slot_of(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(JUMP)
	var pressed := false
	for i in 240:
		_face(Vector3(-9.5, 5.0, 0.5))
		if not pressed and w.ledger.player_can(JUMP, _me().player_id) and _me().is_on_floor():
			if _me().global_position.y > 2.2:
				w.press_action(JUMP)
				pressed = true
		_me().move_intent = Vector2(0.0, 1.0) if _me().global_position.y > 5.05 else Vector2.ZERO
		if _me().global_position.x < -8.2 and _me().is_on_floor():
			break
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	# 西の縁から、縁づたいに北のゴール（窪み）へ歩いて入る
	await _walk_route([Vector3(-9.5, 5.0, -9.5), Vector3(0.5, 5.0, -9.5), Vector3(0.5, 4.0, -11.5)])
	assert_true(await _cleared(), "ACCEPTED: terrace (2) to rim (5) without pit/boots/gloves")


# --- 2. 詰み -------------------------------------------------------------------


## 採石場の底で、ジャンプを「投げる」の届き方で縁の隅のセルへ繰り返しで貸すと、底から出られない
## （ブーツはジャンプの強化、石の段も 1 段のジャンプが要る、グローブは段の上）。V で始めへ戻れる。
func test_accepted_quarry_floor_without_jump_needs_the_reset_vote() -> void:
	await _enter(StageCatalog.QUARRY_ID)
	await _walk_to(Vector3(-3.5, 0.0, -3.5))
	w.toggle_reach()
	assert_true(w.throw_mode, "throw reach")
	_lend(w.terrain_target(Vector3i(-11, 4, -11)), _slot_of(JUMP), TriggerMode.Kind.REPEAT)
	w.toggle_reach()
	assert_false(w.ledger.player_can(JUMP, _me().player_id), "jump is away")
	# いちばん近い底の隅から F で回収を試みる
	await _walk_to(Vector3(-4.7, 0.0, -4.7), 0.2)
	w.interact(w.terrain_target(Vector3i(-11, 4, -11)))
	await wait_physics_frames(2)
	assert_false(w.ledger.player_can(JUMP, _me().player_id), "out of touch from the floor")
	# ブーツを履いて段（高さ 2）へ跳ぼうとしても跳べない
	await _pick_and_wear(Vector3(-4.5, 0.0, 4.5), RuleVessel.Part.FEET)
	var best := await _jump_against(Vector3(-4.5, 0.0, 5.2), Vector3(-4.5, 2.0, 7.0), 120)
	assert_lt(best, 0.5, "no jump: stuck on the quarry floor")
	director.request_vote()
	await wait_physics_frames(6)
	assert_true(w.ledger.player_can(JUMP, _me().player_id), "the reset vote gave the jump back")


## 歩く能力（W/A/S/D）を全部、遠くのセルへ「信号」で貸すと、歩けない。以前はそのままダッシュで
## チェックポイントに入れて、抜け出せない状態が保存された（F4）。いまはダッシュには W/A/D の
## どれかが要る（2026-11-20 本人の判断）ので突っ込めず、チェックポイントも歩けない状態を保存しない。
## メニューの「島のはじめから」で本当に最初へ戻れる。
func test_gate_no_way_to_walk_cannot_be_saved_and_restart_recovers() -> void:
	await _enter(StageCatalog.THREE_BELLS_ID)
	await _pick_dash(Vector3(2.5, 0.0, 4.5))
	await _walk_to(Vector3(9.5, 0.0, 8.5))
	await _walk_to(Vector3(9.5, 0.0, 5.9), 0.2)  # 北（チェックポイントの方）を向いて止まる
	await wait_physics_frames(10)
	w.toggle_reach()
	var cells: Array[Vector3i] = [
		Vector3i(0, -1, -4), Vector3i(1, -1, -4), Vector3i(2, -1, -4), Vector3i(3, -1, -4)
	]
	for i in MOVES.size():
		_lend(w.terrain_target(cells[i]), _slot_of(MOVES[i]), TriggerMode.Kind.SIGNAL)
	w.toggle_reach()
	_me().move_intent = Vector2(0.0, 1.0)
	w.press_action(DASH)
	assert_false(_me().is_dashing(), "no dash without W, A or D")
	await wait_physics_frames(30)
	_me().move_intent = Vector2.ZERO
	assert_eq(
		director.lifecycle.latest_checkpoint(), PartyLifecycle.STAGE_START, "nothing was saved"
	)
	# 保存の側の守り: 歩けないまま台座の上にいても保存しない（ダッシュ以外の手段で運ばれた場合）
	assert_false(
		CheckpointPolicy.player_can_move(w.ledger, _me().player_id), "still cannot walk here"
	)
	# メニューの「島のはじめから」（ひとり）: ステージを作り直すので歩ける
	w.restart_island()
	w = director.world
	await wait_physics_frames(10)
	var can_walk := true
	for action in MOVES:
		can_walk = can_walk and w.ledger.player_can(action, _me().player_id)
	assert_true(can_walk, "restart from the beginning gives every move back")


# --- 3. ダッシュ ----------------------------------------------------------------


## 地上のダッシュで谷の上に出てから、もう一度空中でダッシュすると、跳ばずに幅 5 の谷を越えられた
## （F6）。いまはダッシュは地上でも空中でも、床に着くまで1回だけ。
func test_gate_ground_dash_does_not_allow_a_second_air_dash() -> void:
	await _enter(StageCatalog.FLOATING_ID)
	await _walk_to(Vector3(0.5, 0.0, 5.7), 0.3)
	_face(Vector3(0.5, 0.0, 10.0))
	_me().move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(6)
	w.press_action(JUMP)
	await _walk_to(Vector3(0.5, 0.0, 10.0), 0.6, 240)
	await _pick_dash(Vector3(-2.5, 0.0, 14.0))
	await _walk_to(Vector3(0.5, 0.0, 9.3), 0.3)
	_face(Vector3(0.5, 0.0, 4.0))
	_me().move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(6)
	w.press_action(JUMP)
	await _walk_to(Vector3(0.5, 0.0, 4.0), 0.6, 240)
	# 東の谷（幅 5）の縁の手前まで歩き、跳ばずにダッシュ → 谷の上でもう一度ダッシュを試す
	await _walk_to(Vector3(6.6, 0.0, -2.5), 0.2)
	_me().view_yaw = atan2(-1.0, 0.0)
	_me().move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(1)
	w.press_action(DASH)
	assert_true(_me().is_dashing(), "ground dash")
	for i in 30:
		if not _me().is_dashing():
			break
		await tree.physics_frame
	w.press_action(DASH)
	assert_false(_me().is_dashing(), "no second dash before touching the floor")
	_me().move_intent = Vector2.ZERO
	await _wait_respawn()
	assert_lt(_me().global_position.x, 7.0, "fell into the gap and came back to the start side")


func test_gate_dash_into_a_cliff_stops_and_does_not_climb() -> void:
	await _enter(StageCatalog.HILL_ID)
	await _pick_dash(Vector3(3.5, 0.0, 5.0))
	# 高さ 1 の段（z = 2 が南の縁）へ、南から突進する
	await _walk_to(Vector3(3.5, 0.0, 4.5), 0.2)
	_me().view_yaw = 0.0
	_me().move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(1)
	w.press_action(DASH)
	await wait_physics_frames(30)
	_me().move_intent = Vector2.ZERO
	await wait_physics_frames(10)
	assert_lt(_me().global_position.y, 0.2, "the dash does not step up a 1-high ledge")
	assert_gt(_me().global_position.z, 3.0 - 0.05, "stopped at the face, not inside it")
	assert_false(_me().is_dashing(), "the dash ended at the wall")


func test_gate_dash_off_the_map_kills_and_resets() -> void:
	await _enter(StageCatalog.HILL_ID)
	await _pick_dash(Vector3(3.5, 0.0, 5.0))
	# 南の浜の端（z = 8 が縁）から海へ空中ダッシュ
	await _walk_to(Vector3(3.5, 0.0, 7.5), 0.2)
	_me().view_yaw = PI
	_me().move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(4)
	w.press_action(JUMP)
	await wait_physics_frames(10)
	w.press_action(DASH)
	assert_true(_me().is_dashing(), "air dash over the sea")
	_me().move_intent = Vector2.ZERO
	await _wait_respawn()
	assert_lt(_me().global_position.z, 7.0, "back on the island after falling")
	# 始めの保存はダッシュを拾う前なので、ダッシュは浜へ戻っている（世界ごと戻る）
	assert_false(w.ledger.player_can(DASH, _me().player_id), "the dash went back to the beach")
	assert_false(_me().is_dashing(), "no dash carried over the reset")


# --- 4. そのほか ----------------------------------------------------------------


## 鳴らした鐘は、全員リセットで世界を戻しても「鳴らした」まま残っていた（F7）。いまは保存の時点に戻る。
func test_gate_rung_bells_are_reset_by_the_vote() -> void:
	await _enter(StageCatalog.THREE_BELLS_ID)
	await _walk_to(Vector3(9.5, 0.0, 1.5))
	_lend(_block("launcher"), _slot_of(THROW), TriggerMode.Kind.NONE)
	for i in 400:
		if w.activated.has("east_bell"):
			break
		await tree.physics_frame
	assert_true(w.activated.has("east_bell"), "the launcher rang the east bell")
	director.request_vote()
	await wait_physics_frames(6)
	assert_eq(director.lifecycle.latest_checkpoint(), PartyLifecycle.STAGE_START, "back to start")
	assert_false(w.bells_by_key["east_bell"].is_ringing(), "the bell itself was reset")
	assert_false(w.activated.has("east_bell"), "no longer counted as rung after the reset")
