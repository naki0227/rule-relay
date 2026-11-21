extends "res://tests/integration/island_playthrough.gd"
## 鐘の谷（W2）の新しいステージを、ひとりで最初から最後まで自動で遊ぶ（通しプレイ）。
## 「こだまの鐘」（2-2）・「転がる玉」（2-4）。どれも、ひとりの道 2 通りを通す。
## 「鳴りつづける鐘」（2-5。時の鐘）は test_world2_timed_bells.gd。
## 操作はプレイヤーと同じ（歩く・段差で跳ぶ・渡す・押す・乗る・拾う・回収する・鐘を鳴らす）で、瞬間移動はしない。
## 協力の道は test_world2_coop.gd、関所と詰みの試遊は test_world2_probes.gd。

const BACK := RuleAction.Kind.BACK
const RIGHT := RuleAction.Kind.RIGHT
const ECHO_ID := "w2_echo_bells"
const ROLLING_ID := "w2_rolling_shots"

# --- 共通の部品 -----------------------------------------------------------------


func _inventory_to_hotbar(action: RuleAction.Kind) -> void:
	for v in w.ledger.inventory_vessels(_me().player_id):
		var t := w.ledger.token(v.token_id)
		if t.action == action and not t.is_prohibition:
			assert_true(w.ledger_actions.move_to_hotbar(v.id, _free_slot()), "to the hotbar")


## ホットバーで、action が器に入っている（まだ貸していない）スロット。
func _ready_slot(action: RuleAction.Kind) -> int:
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(slot, _me().player_id)
		if v != null:
			var t := w.ledger.token(v.token_id)
			if t.action == action and not t.is_prohibition and t.is_in_vessel():
				return slot
	return -1


## ブロック（key）の横（offset）へ歩いてから、移動を単発で渡してキーで 1 マス押す。times 回くり返す。
func _push_block(key: String, action: RuleAction.Kind, times: int, offset: Vector3) -> void:
	var block := _block(key)
	for i in times:
		var at := block.global_position + offset
		await _walk_to(Vector3(at.x, _me().global_position.y, at.z), 0.3)
		_lend(block, _slot_of(action), TriggerMode.Kind.SINGLE_SHOT)
		w.press_action(action)
		await wait_physics_frames(40)
		for f in 120:
			if block.is_grounded() and not block.is_moving_horizontally():
				break
			await tree.physics_frame


func _give_kit_a_move() -> void:
	var kit := _creature("kit")
	await _walk_to(kit.global_position + Vector3(-1.4, 0.0, 0.0), 0.4)
	_lend(kit, _slot_of(RIGHT), TriggerMode.Kind.NONE)


func _wait_block_at(key: String, cell: Vector3i, frames: int = 900) -> void:
	var block := _block(key)
	for i in frames:
		if block.cell() == cell and block.is_grounded() and not block.is_moving_horizontally():
			break
		await tree.physics_frame
	assert_eq(block.cell(), cell, "%s came to rest at %s" % [key, cell])


## 足もとの地面のセルにジャンプを単発で貸して乗り、上の段（onto）へ移る（受け入れた技 F3）。
func _ground_cell_lift(cell: Vector3i, onto: Vector3) -> void:
	await _walk_to(Vector3(cell.x + 0.5, cell.y + 1.0, cell.z + 0.5), 0.25)
	_lend(w.terrain_target(cell), _ready_slot(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(JUMP)
	await _ride_up(onto)


func _ride_up(onto: Vector3) -> void:
	for i in 300:
		var flat := _face(onto)
		if flat.length() < 0.4 and _me().global_position.y > onto.y - 0.2:
			break
		_me().move_intent = Vector2(0.0, 1.0) if _me().global_position.y > onto.y else Vector2.ZERO
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	assert_gt(_me().global_position.y, onto.y - 0.3, "rode up onto %s" % onto)


## 鐘に手が届く所で鳴らす（歩いて近づかない。台の上に乗ったまま鳴らすとき用）。
func _ring_here(key: String) -> void:
	var bell := w.bells_by_key[key]
	_face(bell.global_position)
	w.interact(bell)
	await wait_physics_frames(2)
	assert_true(bell.is_ringing(), "rang %s from where I stand" % key)


# --- こだまの鐘 -------------------------------------------------------------------


## ひとりの道 1（信号）: 鐘を鳴らして、信号の持ち上げ台で上がり、信号の石を壁ぎわまで動かす。
func test_echo_bells_ring_and_ride_the_signal_lifts() -> void:
	await _enter(ECHO_ID)
	await _give_kit_a_move()
	var lift_1 := _block("echo_lift_1")
	await _walk_to(lift_1.global_position + Vector3(0.0, 0.5, 0.0), 0.25)
	await _ring_here("echo_bell_1")
	await _ride_up(Vector3(2.5, 2.0, -1.6))
	await _walk_to(Vector3(0.5, 2.0, -1.5))
	await _wait_until_quiet("echo_bell_1")
	await _ring_here("echo_bell_1")
	await _wait_block_at("echo_stone_1", Vector3i(-4, 0, 0))
	var lift_2 := _block("echo_lift_2")
	await _walk_to(lift_2.global_position + Vector3(0.0, 0.5, 0.0), 0.25)
	await _wait_until_quiet("echo_bell_1")
	await _ring_here("echo_bell_2")
	await _ride_up(Vector3(2.5, 4.0, -8.6))
	await _walk_to(Vector3(1.5, 4.0, -8.6))
	await _wait_until_quiet("echo_bell_2")
	await _ring_here("echo_bell_2")
	await _wait_block_at("echo_stone_2", Vector3i(-4, 2, -7))
	assert_true(
		await _wait_creature_in("kit", OpenIslandsW2.ECHO_NEST, 2400),
		"the kit hopped up to its nest"
	)
	await _walk_into_goal()
	assert_true(await _cleared(), "the kit is home and everyone is at the goal")


## ひとりの道 2（鐘を使わない）: 石を自分で単発で押し、地面のセルを持ち上げ台にして上がる。
func test_echo_bells_push_the_stones_by_hand() -> void:
	await _enter(ECHO_ID)
	await _give_kit_a_move()
	await _ground_cell_lift(Vector3i(-1, -1, 0), Vector3(-0.5, 2.0, -1.6))
	await _push_block("echo_stone_1", BACK, 5, Vector3(1.5, -0.5, 0.0))
	await _wait_block_at("echo_stone_1", Vector3i(-4, 0, 0))
	await _ground_cell_lift(Vector3i(-1, 1, -7), Vector3(-0.5, 4.0, -8.6))
	await _push_block("echo_stone_2", BACK, 4, Vector3(1.5, -0.5, 0.0))
	await _wait_block_at("echo_stone_2", Vector3i(-4, 2, -7))
	assert_false(w.activated.has("echo_bell_1") or w.activated.has("echo_bell_2"), "no bells")
	assert_true(
		await _wait_creature_in("kit", OpenIslandsW2.ECHO_NEST, 2400),
		"the kit hopped up to its nest"
	)
	await _walk_into_goal([Vector3(0.5, 4.0, -11.5)])
	assert_true(await _cleared(), "pushed both stones by hand")


func _wait_until_quiet(key: String) -> void:
	var bell := w.bells_by_key[key]
	for i in 400:
		if not bell.is_ringing():
			return
		await tree.physics_frame


# --- 転がる玉 ---------------------------------------------------------------------


## 台地の窪みのブロックで上がり、東の端の「投げる」を拾って、浜へ降りる。
func _fetch_the_second_throw() -> void:
	await _lift_up("plateau_lift", Vector3(0.5, 0.0, -7.5), Vector3(-2.5, 2.0, -8.5))
	await _walk_to(Vector3(-3.5, 2.0, -6.5), 0.6)
	w.interact(null)
	await wait_physics_frames(2)
	_inventory_to_hotbar(THROW)
	assert_eq(w.ledger.ability_count(THROW, _me().player_id), 2, "two throws now")
	await _walk_to(Vector3(0.5, 0.0, -3.5))


## 発射台に「投げる」を 2 つとも渡して、東の小島の鐘を撃つ。
func _double_throw_rings_the_isle_bell() -> void:
	var launcher := _block("launcher")
	await _walk_to(launcher.global_position + Vector3(-1.5, -0.5, 0.0), 0.3)
	_lend(launcher, _ready_slot(THROW), TriggerMode.Kind.NONE)
	_lend(launcher, _ready_slot(THROW), TriggerMode.Kind.NONE)
	assert_true(await _wait_until_rung("isle_bell", 600), "the launcher reached the far bell")


## ひとりの道 1: 発射台を北へ、それから東へ押して小島の鐘の列に合わせ、投げる×2 で撃つ。
## そのあと発射台を北へ押し、台地の南の壁に沿って繰り返しで西へ滑らせ、生き物の足場にする。
func test_rolling_shots_aim_the_launcher_then_make_it_a_step() -> void:
	await _enter(ROLLING_ID)
	await _fetch_the_second_throw()
	await _push_block("launcher", FORWARD, 5, Vector3(-1.5, -0.5, 0.0))
	await _push_block("launcher", RIGHT, 4, Vector3(0.0, -0.5, 1.5))
	assert_eq(_block("launcher").cell(), Vector3i(6, 0, -1), "lined up with the far bell")
	await _double_throw_rings_the_isle_bell()
	await _push_block("launcher", FORWARD, 4, Vector3(-1.5, -0.5, 0.0))
	await _slide_stone("launcher", Vector3(5.5, 0.0, -3.5), LEFT, Vector3i(-1, 0, -5))
	await _give_kit_a_move()
	assert_true(
		await _wait_creature_in("kit", OpenIslandsW2.ROLLING_NEST, 2400),
		"the kit hopped up the launcher to its nest"
	)
	await _walk_to(Vector3(-0.5, 1.0, -4.5))
	await _walk_into_goal([Vector3(-3.5, 2.0, -5.5)])
	assert_true(await _cleared(), "the bell rang, the kit is home and everyone is at the goal")


## ひとりの道 2: 発射台は東へ、それから北へ押す。生き物の段は台地の南の縁のセルを押し落として作り、
## 自分もその階段を跳んで上がる（発射台は小島の鐘の列に置いたまま）。
func test_rolling_shots_carve_stairs_for_the_kit() -> void:
	await _enter(ROLLING_ID)
	await _fetch_the_second_throw()
	await _push_block("launcher", RIGHT, 4, Vector3(0.0, -0.5, 1.5))
	await _push_block("launcher", FORWARD, 5, Vector3(-1.5, -0.5, 0.0))
	await _double_throw_rings_the_isle_bell()
	await _walk_to(Vector3(-2.5, 0.0, -3.5), 0.3)
	_lend(w.terrain_target(Vector3i(-4, 1, -5)), _slot_of(BACK), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(BACK)
	await wait_physics_frames(60)
	await _give_kit_a_move()
	assert_true(
		await _wait_creature_in("kit", OpenIslandsW2.ROLLING_NEST, 2400),
		"the kit hopped up the carved stairs"
	)
	await _walk_to(Vector3(-3.5, 1.0, -3.5))
	await _walk_to(Vector3(-3.5, 2.0, -6.5))
	await _walk_into_goal()
	assert_true(await _cleared(), "carved stairs instead of moving the launcher back")
