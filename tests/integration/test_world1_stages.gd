extends "res://tests/integration/island_playthrough.gd"
## はじまりの草原（W1）の新しいステージを、ひとりで最初から最後まで自動で遊ぶ（通しプレイ）。
## 「持ち上げ台の段々」（1-3 ★）と「押し石の小道」（1-4）。どちらも、ひとりの道 2 通りを通す。
## 操作はプレイヤーと同じ（歩く・段差で跳ぶ・渡す・押す・乗る・拾う・回収する）で、瞬間移動はしない。
## 協力の道（2 人のオンライン協力）は test_world1_coop.gd、関所と詰みの試遊は test_world1_probes.gd。

const BACK := RuleAction.Kind.BACK
const RIGHT := RuleAction.Kind.RIGHT
const STEPS_ID := "w1_lift_steps"
const PATH_ID := "w1_push_path"

# --- 共通の部品 -----------------------------------------------------------------


## ブロックか地形のセルに移動を単発で渡し、キーで 1 マス動かす（渡した能力はすぐ戻る）。
func _push_once(target: Node3D, action: RuleAction.Kind) -> void:
	_lend(target, _slot_of(action), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(action)
	await wait_physics_frames(40)


## 地形のセル（上面のセル）を action の向きへ 1 マス押し、落ちて止まるまで待つ。止まったセルを返す。
func _push_cell(cell: Vector3i, action: RuleAction.Kind) -> Vector3i:
	await _push_once(w.terrain_target(cell), action)
	var block := w.blocks[w.promoted[cell]]
	for i in 120:
		if block.is_grounded() and not block.is_moving_horizontally():
			break
		await tree.physics_frame
	return block.cell()


## 石を action の向きへ times 回、単発で押す（1 回ごとに止まるまで待つ）。
func _push_stone(key: String, action: RuleAction.Kind, times: int) -> void:
	var stone := _block(key)
	for i in times:
		await _push_once(stone, action)
		for f in 120:
			if stone.is_grounded() and not stone.is_moving_horizontally():
				break
			await tree.physics_frame


## 生き物の近くへ歩いて、能力を触って渡す（生き物は発動方式を持たない）。
func _give_creature(key: String, near: Vector3, slots: Array[int]) -> void:
	await _walk_to(near, 0.4)
	for slot in slots:
		_lend(_creature(key), slot, TriggerMode.Kind.NONE)


## 回収して通常インベントリに入った能力（action）を、ホットバーの空きへ移す（E で開いて並べるのと同じ）。
func _inventory_to_hotbar(action: RuleAction.Kind) -> void:
	for v in w.ledger.inventory_vessels(_me().player_id):
		var t := w.ledger.token(v.token_id)
		if t.action == action and not t.is_prohibition:
			assert_true(w.ledger_actions.move_to_hotbar(v.id, _free_slot()), "to the hotbar")


## 持っているジャンプのスロットを全部（同じ行動が 2 つあれば 2 つとも）。
func _jump_slots() -> Array[int]:
	var result: Array[int] = []
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(slot, _me().player_id)
		if v != null and w.ledger.token(v.token_id).action == JUMP:
			result.append(slot)
	return result


# --- 持ち上げ台の段々 -------------------------------------------------------------


## 動物のジャンプを F で借りる（器ごと手元に来る）。
func _borrow_the_critters_jump() -> void:
	var critter := _creature("critter")
	await _walk_to(critter.global_position + Vector3(1.4, 0.0, 0.0), 0.4)
	w.interact(critter)
	await wait_physics_frames(2)
	_inventory_to_hotbar(JUMP)
	assert_true(w.ledger.player_can(JUMP, _me().player_id), "borrowed the critter's jump")
	assert_false(w.ledger.entity_has_ability(critter.entity_id, JUMP), "the critter has none now")


## 頂の東の隅のジャンプを拾ってホットバーへ。
func _pick_the_summit_jump() -> void:
	await _walk_to(Vector3(4.5, 4.0, -11.5), 0.6)
	w.interact(null)
	await wait_physics_frames(2)
	_inventory_to_hotbar(JUMP)
	assert_eq(w.ledger.ability_count(JUMP, _me().player_id), 2, "two jumps now")


## 頂の石 2 を南へ 3 回押して、段の壁ぎわへ落とす。
func _drop_the_high_stone() -> void:
	await _walk_to(Vector3(-2.5, 4.0, -10.5))
	await _push_stone("stone_high", BACK, 3)
	assert_eq(
		_block("stone_high").cell(), Vector3i(-4, 2, -7), "the high stone fell beside the wall"
	)


## 動物にジャンプ 1 つと移動（D）を渡し、巣まで上がるのを待つ。
func _send_the_critter_home() -> void:
	var critter := _creature("critter")
	var slots: Array[int] = [_jump_slots()[-1], _slot_of(RIGHT)]
	await _give_creature("critter", critter.global_position + Vector3(1.4, 0.0, 0.0), slots)
	assert_true(w.ledger.player_can(JUMP, _me().player_id), "kept one jump for myself")
	assert_true(
		await _wait_creature_in("critter", OpenIslandsW1.STEPS_NEST, 2400),
		"the critter hopped up the stone steps to its nest"
	)


## ひとりの道 1: 窪みのブロックで上がり、石を 2 つとも上から押し落とし、動物を送ってから窪みのブロックで戻る。
func test_lift_steps_pit_lifts_and_stones_from_above() -> void:
	await _enter(STEPS_ID)
	assert_false(w.ledger.player_can(JUMP, _me().player_id), "nobody starts with a jump")
	await _borrow_the_critters_jump()
	await _lift_up("shore_lift", Vector3(5.5, 0.0, 1.5), Vector3(4.5, 2.0, -1.5))
	await _lift_up("terrace_lift", Vector3(5.5, 2.0, -5.5), Vector3(4.5, 4.0, -8.6))
	await _pick_the_summit_jump()
	await _drop_the_high_stone()
	await _walk_to(Vector3(-2.5, 2.0, -5.5))
	await _walk_to(Vector3(-2.5, 2.0, -3.3), 0.25)
	await _push_stone("stone_low", BACK, 3)
	assert_eq(_block("stone_low").cell(), Vector3i(-4, 0, 0), "the low stone fell beside the wall")
	await _walk_to(Vector3(-1.5, 0.0, 2.5))
	await _send_the_critter_home()
	assert_eq(director.last_clear_text, "", "the critter alone does not clear")
	await _lift_up("shore_lift", Vector3(5.5, 0.0, 1.5), Vector3(4.5, 2.0, -1.5))
	await _lift_up("terrace_lift", Vector3(5.5, 2.0, -5.5), Vector3(4.5, 4.0, -8.6))
	await _walk_into_goal()
	assert_true(await _cleared(), "the critter is home and everyone is at the goal")


## ひとりの道 2: 浜から段の上の石 1 を押し落とし（ジャンプが無くても届く）、石の段を跳んで上がる。
## 頂へは足もとの地面のセルを持ち上げ台にする。最後も動物と同じ石の段で上がる（窪みのブロックを使わない）。
func test_lift_steps_low_stone_from_the_shore_and_the_critters_stairs() -> void:
	await _enter(STEPS_ID)
	await _walk_to(Vector3(-2.5, 0.0, 0.4))
	await _push_stone("stone_low", BACK, 3)
	assert_eq(_block("stone_low").cell(), Vector3i(-4, 0, 0), "pushed down from the shore")
	await _borrow_the_critters_jump()
	await _walk_to(Vector3(-3.5, 1.0, 0.5))
	await _walk_to(Vector3(-3.5, 2.0, -1.5))
	await _walk_to(Vector3(-0.5, 2.0, -6.5))
	_lend(w.terrain_target(Vector3i(-1, 1, -7)), _slot_of(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(JUMP)
	await _ride_onto_ledge(Vector3(-0.5, 4.0, -8.6))
	await _pick_the_summit_jump()
	await _drop_the_high_stone()
	await _walk_to(Vector3(-1.5, 2.0, -2.5))
	await _walk_to(Vector3(-1.5, 0.0, 2.5))
	await _send_the_critter_home()
	await _walk_to(Vector3(-3.5, 1.0, 0.5))
	await _walk_to(Vector3(-3.5, 2.0, -5.5))
	await _walk_to(Vector3(-3.5, 3.0, -6.5))
	await _walk_to(Vector3(-3.5, 4.0, -8.5))
	await _walk_into_goal([Vector3(0.5, 4.0, -11.5)])
	assert_true(await _cleared(), "up the critter's stairs without the pit lifts")
	for key: String in ["shore_lift", "terrace_lift"]:
		assert_true(w.ledger.tokens_on(_block(key).entity_id).is_empty(), "%s never used" % key)


## 上昇中の台（足もとのセル）の上で、十分高くなったら上の段（onto）へ歩いて移る。
func _ride_onto_ledge(onto: Vector3) -> void:
	for i in 300:
		var flat := _face(onto)
		if flat.length() < 0.4 and _me().global_position.y > onto.y - 0.2:
			break
		_me().move_intent = Vector2(0.0, 1.0) if _me().global_position.y > onto.y else Vector2.ZERO
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	assert_gt(_me().global_position.y, onto.y - 0.3, "rode up onto %s" % onto)


# --- 押し石の小道 -----------------------------------------------------------------


## 段の縁のセル（上面）を南へ押して、原っぱとの間に 1 段ずつの階段を作る。
func _carve_stairs(x: int) -> void:
	await _walk_to(Vector3(float(x) + 2.5, 0.0, 0.5), 0.3)
	var landed := await _push_cell(Vector3i(x, 1, -1), BACK)
	assert_eq(landed, Vector3i(x, 0, 0), "the edge cell fell onto the meadow as a step")


## 生き物に移動（D）を渡して、段の上で待つまで見守る。
func _send_the_kit_to_the_ledge() -> void:
	var kit := _creature("kit")
	var slots: Array[int] = [_slot_of(RIGHT)]
	await _give_creature("kit", kit.global_position + Vector3(1.4, 0.0, 0.0), slots)
	var ledge := AABB(Vector3(-7.0, 1.9, -6.0), Vector3(15.0, 1.0, 6.0))
	assert_true(await _wait_creature_in("kit", ledge, 900), "the kit hopped up the carved stairs")


## ひとりの道 1: 階段を削り、生き物を段へ送り、段の北の縁のセルを溝へ押し込む。自分は階段で上がる。
func test_push_path_carve_stairs_and_fill_the_ditch_from_the_ledge() -> void:
	await _enter(PATH_ID)
	await _carve_stairs(-1)
	await _send_the_kit_to_the_ledge()
	await _walk_to(Vector3(-0.5, 1.0, 0.5))
	await _walk_to(Vector3(-0.5, 2.0, -2.5))
	await _walk_to(Vector3(0.5, 2.0, -4.6), 0.3)
	var filled := await _push_cell(Vector3i(0, 1, -6), FORWARD)
	assert_eq(filled, Vector3i(0, 1, -7), "the ledge cell filled the ditch")
	assert_true(
		await _wait_creature_in("kit", OpenIslandsW1.PATH_NEST, 1800), "the kit reached its nest"
	)
	await _walk_into_goal([Vector3(1.5, 2.0, -2.5)])
	assert_true(await _cleared(), "the kit is home and everyone is at the goal")


## ひとりの道 2: 窪みのブロックで段へ上がり、溝を跳び越えて、花畑の南の縁のセルを溝へ押し落とす。
## 階段は段の上から縁のセルを押して作る（生き物は最後に送る）。
func test_push_path_fill_from_the_flowers_and_carve_from_above() -> void:
	await _enter(PATH_ID)
	await _lift_up("meadow_lift", Vector3(-3.5, 0.0, 1.5), Vector3(-4.5, 2.0, -1.5))
	assert_true(
		await _run_and_jump(
			Vector3(-2.5, 2.0, -4.5), Vector3(-2.5, 2.0, -5.7), Vector3(-2.5, 3.0, -9.5)
		),
		"hopped over the ditch onto the flowers"
	)
	await _walk_to(Vector3(5.5, 3.0, -10.5), 0.3)
	var filled := await _push_cell(Vector3i(5, 2, -8), BACK)
	assert_eq(filled, Vector3i(5, 1, -7), "the flower-field cell dropped into the ditch")
	await _walk_to(Vector3(5.5, 2.0, -7.5))
	await _walk_to(Vector3(7.5, 2.0, -5.5))
	await _walk_to(Vector3(7.5, 2.0, -2.5))
	await _walk_to(Vector3(6.5, 2.0, -2.5), 0.3)
	var landed := await _push_cell(Vector3i(4, 1, -1), BACK)
	assert_eq(landed, Vector3i(4, 0, 0), "carved the stairs from the ledge")
	await _walk_to(Vector3(4.5, 1.0, -0.5))
	await _walk_to(Vector3(2.5, 0.0, 1.5))
	var kit := _creature("kit")
	var slots: Array[int] = [_slot_of(RIGHT)]
	await _give_creature("kit", kit.global_position + Vector3(1.4, 0.0, 0.0), slots)
	assert_true(
		await _wait_creature_in("kit", OpenIslandsW1.PATH_NEST, 2400), "the kit reached its nest"
	)
	await _walk_to(Vector3(4.5, 1.0, -0.5))
	await _walk_into_goal([Vector3(4.5, 2.0, -2.0)])
	assert_true(await _cleared(), "filled the ditch from the far side")
