extends "res://tests/integration/island_probing.gd"
## 「けものの巣」と「札の庭」の関所と詰みを、プレイヤーと同じ操作で壊しにいく試遊（2026-11-20）。
## 書き方は test_island_probes.gd と同じ:
## - test_gate_*: 意図した関所が守られていること（壊れたら失敗する）
## - test_accepted_*: 本人が「残してよい」と決めた技（縁ちょうどの幅 4 越え など）がこの島でも起きること
## - test_finding_*: 試遊で見つけた挙動の記録（直すかどうかは本人が決める）
## 結果は docs/adr/0011 の「10・18・40 分の島」にまとめた。

const RIGHT := RuleAction.Kind.RIGHT
const CLIMB := RuleAction.Kind.CLIMB

# --- けものの巣: 関所 -----------------------------------------------------------


func test_gate_nest_terrace_is_not_a_plain_jump_from_the_shore() -> void:
	await _enter(StageCatalog.NEST_ID)
	var best := await _jump_against(Vector3(0.5, 0.0, -4.2), Vector3(0.5, 2.0, -6.5))
	assert_lt(best, 1.5, "shore (0) to terrace (2)")
	# 張り出し（2）も、石を寄せなければ跳べない
	best = await _jump_against(Vector3(-9.6, 0.0, -4.5), Vector3(-10.5, 2.0, -4.5))
	assert_lt(best, 1.5, "shore (0) to the terrace spur (2) without the stone")


func test_gate_nest_plateau_is_not_a_plain_jump_from_the_terrace() -> void:
	await _enter(StageCatalog.NEST_ID)
	await _lift_up("shore_lift", Vector3(4.5, 0.0, -3.5), Vector3(3.5, 2.0, -7.5))
	var best := await _jump_against(Vector3(6.5, 2.0, -9.2), Vector3(6.5, 4.0, -11.5))
	assert_lt(best, 3.5, "terrace (2) to plateau (4) away from the rubble")


## 生き物は、移動だけでは段差 2 を上がれず待つ。ジャンプを足しても、石が無ければ待つ。
## 待っている生き物からは F で能力を取り戻せる（ジャンプを渡しても詰まない）。
func test_gate_nest_kit_waits_without_a_way_up_and_gives_the_jump_back() -> void:
	await _enter(StageCatalog.NEST_ID)
	var critter := _creature("kit")
	await _walk_to(critter.global_position + Vector3(1.6, 0.0, 0.0), 0.4)
	_lend(critter, _slot_of(RIGHT), TriggerMode.Kind.NONE)
	assert_lt(await _creature_top("kit", 300), 0.3, "a move alone does not climb")
	assert_eq(critter.stage, CreatureMind.Stage.WAIT, "it waits")
	_lend(critter, _slot_of(JUMP), TriggerMode.Kind.NONE)
	# 1 段は跳べるので、浜の石（高さ 1）には跳び乗るが、段（2）へは上がれない
	assert_lt(
		await _creature_top("kit", 360), 1.6, "jump + move without the stone moved: no terrace"
	)
	assert_eq(critter.stage, CreatureMind.Stage.WAIT, "it waits on the stone")
	var below := critter.global_position + Vector3(1.6, 0.0, 0.0)
	await _walk_to(Vector3(below.x, 0.0, below.z), 0.4)
	w.interact(critter)
	await wait_physics_frames(2)
	assert_true(w.ledger.player_can(JUMP, _me().player_id), "took my jump back")


## 巣に生き物がいなければ、全員がゴールに集まってもクリアしない。
func test_gate_nest_goal_without_the_kit_is_not_a_clear() -> void:
	await _enter(StageCatalog.NEST_ID)
	await _lift_up("shore_lift", Vector3(4.5, 0.0, -3.5), Vector3(3.5, 2.0, -7.5))
	await _lift_up("terrace_lift", Vector3(4.5, 2.0, -8.5), Vector3(3.5, 4.0, -12.5))
	await _walk_into_goal()
	assert_false(await _cleared(120), "everyone at the goal, but the kit is not in its nest")


func test_accepted_nest_west_gap_of_four_only_at_the_exact_edge() -> void:
	await _enter(StageCatalog.NEST_ID)
	var route: Array[Vector3] = [Vector3(-9.5, 0.0, 1.5), Vector3(-10.5, 0.0, 1.5)]
	var offset := await _first_crossing(route, Vector3.LEFT, 12.0, 4.0)
	print("    creature_nest west gap 4: plain jump crossed at offset %.1f" % offset)
	assert_false(is_nan(offset), "ACCEPTED: a plain running jump crosses the 4-wide gap")
	assert_gt(offset, -0.15, "ACCEPTED: only at the exact edge")


func test_gate_nest_ground_dash_does_not_cross_the_west_gap() -> void:
	await _enter(StageCatalog.NEST_ID)
	await _pick_to_hotbar(Vector3(-9.5, 0.0, 6.5), DASH)
	assert_false(await _ground_dash(Vector3(-11.8, 0.0, 1.5), Vector3.LEFT), "3 m < gap 4")
	assert_gt(_me().global_position.x, -12.5, "back on the shore")


func test_gate_nest_dash_into_the_terrace_cliff_does_not_climb() -> void:
	await _enter(StageCatalog.NEST_ID)
	await _pick_to_hotbar(Vector3(-9.5, 0.0, 6.5), DASH)
	await _ground_dash(Vector3(6.5, 0.0, -3.0), Vector3.FORWARD)
	assert_lt(_me().global_position.y, 0.2, "the dash stops at the 2-high face")


# --- けものの巣: 記録 ------------------------------------------------------------


## 生き物は 1 段（1.1 まで）しか跳べず、自分から跳ぶ道しか探さない（窪みのブロックに乗せて持ち上げる、
## という道は生き物の判断に無い）。石を寄せる・グローブを渡す、のどちらかが無いと巣へは行けない。
## 自分（プレイヤー）は、地面のセルを持ち上げ台にする技（試遊 F3。残す）でも段へ上がれる。
func test_finding_nest_kit_needs_the_stone_or_the_gloves() -> void:
	await _enter(StageCatalog.NEST_ID)
	var critter := _creature("kit")
	await _walk_to(critter.global_position + Vector3(1.6, 0.0, 0.0), 0.4)
	_lend(critter, _slot_of(RIGHT), TriggerMode.Kind.NONE)
	_lend(critter, _slot_of(JUMP), TriggerMode.Kind.NONE)
	assert_lt(await _creature_top("kit", 600), 1.6, "no stone, no gloves: the kit stays below")
	assert_false(OpenIslandsExtra.NEST.has_point(critter.global_position), "not in the nest")


# --- 札の庭: 関所 ---------------------------------------------------------------


## 庭の決まり（ジャンプ禁止）を持っている間は、跳べず、窪みのブロックの単発も起動しない。
func test_gate_garden_rule_blocks_jumping_and_single_shots() -> void:
	await _enter(StageCatalog.GARDEN_ID)
	var best := await _jump_against(Vector3(0.5, 0.0, 3.5), Vector3(0.5, 0.0, 0.5), 60)
	assert_lt(best, 0.2, "cannot jump with the garden rule")
	var lift := _block("garden_lift")
	var rest_y := lift.global_position.y
	await _walk_to(Vector3(-2.5, 0.0, -5.5))
	_lend(lift, _slot_of(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	await _walk_to(lift.global_position + Vector3(0.0, 0.5, 0.0), 0.25)
	w.press_action(JUMP)
	await wait_physics_frames(40)
	assert_almost(
		lift.global_position.y, rest_y, 0.05, "the rule keeps the single shot from firing"
	)
	assert_true(w.ledger.tokens_on(lift.entity_id).size() == 1, "the single shot is still on it")


## 発射台の札（投げる禁止）が付いたままでは、「投げる」を渡しても撃たない。
## 札を F で取ると自分に来て、「投げる」の届き方が使えなくなる（触って渡すことはできる）。
func test_gate_garden_launcher_sign_stops_it_and_blocks_throw_reach() -> void:
	await _enter(StageCatalog.GARDEN_ID)
	var launcher := _block("launcher")
	await _walk_to(Vector3(12.5, 0.0, 1.5))
	_lend(launcher, _slot_of(THROW), TriggerMode.Kind.NONE)
	assert_false(await _wait_until_rung("east_bell", 240), "the sign keeps the launcher quiet")
	w.interact(launcher)
	await wait_physics_frames(2)
	assert_true(w.ledger.player_prohibited(THROW, _me().player_id), "everything came off")
	w.toggle_reach()
	assert_false(w.throw_mode, "no throw reach while holding the launcher's sign")


func test_gate_garden_upper_is_not_a_plain_jump_after_dropping_the_rule() -> void:
	await _enter(StageCatalog.GARDEN_ID)
	await _walk_to(Vector3(6.5, 0.0, -4.5))
	_hand_off_ban(JUMP, w.terrain_target(Vector3i(6, -1, -3)))
	var best := await _jump_against(Vector3(6.5, 0.0, -6.2), Vector3(6.5, 2.0, -8.5))
	assert_lt(best, 1.5, "garden (0) to the upper garden (2)")


func test_gate_garden_shrine_is_not_a_plain_jump_and_its_bell_is_out_of_reach() -> void:
	await _enter(StageCatalog.GARDEN_ID)
	await _walk_to(Vector3(-2.5, 0.0, -4.5))
	_hand_off_ban(JUMP, w.terrain_target(Vector3i(-2, -1, -3)))
	await _lift_up("garden_lift", Vector3(-2.5, 0.0, -5.5), Vector3(-3.5, 2.0, -9.5))
	var best := await _jump_against(Vector3(-0.5, 2.0, -14.2), Vector3(-0.5, 4.0, -16.5))
	assert_lt(best, 3.5, "upper garden (2) to the shrine (4)")
	assert_false(await _try_ring_from("shrine_bell", Vector3(0.5, 2.0, -14.7)), "from below")
	assert_eq(director.last_clear_text, "", "not cleared")


## 社への持ち上げ台の札が付いたままでは、決まりを手放していても単発が起動しない。
func test_gate_garden_signed_lift_needs_its_sign_moved() -> void:
	await _enter(StageCatalog.GARDEN_ID)
	await _walk_to(Vector3(-2.5, 0.0, -4.5))
	_hand_off_ban(JUMP, w.terrain_target(Vector3i(-2, -1, -3)))
	await _lift_up("garden_lift", Vector3(-2.5, 0.0, -5.5), Vector3(-3.5, 2.0, -9.5))
	var signed := _block("shrine_lift")
	var rest_y := signed.global_position.y
	await _walk_to(Vector3(4.5, 2.0, -13.5))
	_lend(signed, _slot_of(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	await _walk_to(signed.global_position + Vector3(0.0, 0.5, 0.0), 0.25)
	w.press_action(JUMP)
	await wait_physics_frames(40)
	assert_almost(signed.global_position.y, rest_y, 0.05, "the sign keeps the lift down")
	assert_lt(_me().global_position.y, 2.6, "still on the upper garden")


func test_accepted_garden_east_gap_of_four_only_at_the_exact_edge() -> void:
	await _enter(StageCatalog.GARDEN_ID)
	await _walk_to(Vector3(8.5, 0.0, -2.5))
	_hand_off_ban(JUMP, w.terrain_target(Vector3i(8, -1, -1)))
	await _walk_to(Vector3(-8.5, 0.0, 0.5))  # チェックポイントで保存（落ちても決まりが戻らない）
	var route: Array[Vector3] = [Vector3(12.5, 0.0, -2.5)]
	var offset := await _first_crossing(route, Vector3.RIGHT, 15.0, 4.0)
	print("    ban_garden east gap 4: plain jump crossed at offset %.1f" % offset)
	assert_false(is_nan(offset), "ACCEPTED: a plain running jump crosses the 4-wide gap")
	assert_gt(offset, -0.15, "ACCEPTED: only at the exact edge")


## 決まりを持ったまま、跳ばずに地上のダッシュだけでは谷 4 を越えられない（3 マス）。
func test_gate_garden_ground_dash_with_the_rule_does_not_cross_the_east_gap() -> void:
	await _enter(StageCatalog.GARDEN_ID)
	await _pick_to_hotbar(Vector3(10.5, 0.0, 6.5), DASH)
	assert_false(await _ground_dash(Vector3(14.8, 0.0, -2.5), Vector3.RIGHT), "3 m < gap 4")
	assert_lt(_me().global_position.x, 15.0, "back in the garden")
	assert_false(w.activated.has("east_bell"), "the east bell is still silent")


## 決まりを持ったまま（グローブを外して）ゴールの窪みに降りると、自力では出られない。
## ただし禁止を足もとへ渡せば跳んで出られるので、詰まない。
func test_gate_garden_hollow_with_the_rule_is_escapable() -> void:
	await _enter(StageCatalog.GARDEN_ID)
	await _pick_and_wear(Vector3(-11.5, 0.0, 5.5), RuleVessel.Part.HANDS)
	await _walk_route(
		[
			Vector3(-9.5, 0.0, -6.5),
			Vector3(-9.5, 2.0, -8.8),
			Vector3(-4.5, 2.0, -14.5),
			Vector3(-4.5, 4.0, -17.0),
		]
	)
	await _walk_into_goal()
	var gloves := w.ledger.equipped_vessel(RuleVessel.Part.HANDS, _me().player_id)
	assert_true(w.ledger_actions.unequip(gloves.id), "took the gloves off")
	var out := Vector3(-3.5, 4.0, -22.5)
	assert_false(await _try_walk_to(out, 0.35, 180), "stuck in the hollow with the rule")
	_hand_off_ban(JUMP, w.terrain_target(Vector3i(0, 2, -23)))
	assert_true(await _try_walk_to(out, 0.35, 300), "dropped the rule and hopped out")
