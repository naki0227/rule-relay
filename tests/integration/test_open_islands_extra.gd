extends "res://tests/integration/island_playthrough.gd"
## 「けものの巣」と「札の庭」を、ひとりで最初から最後まで自動で遊ぶ（通しプレイ。docs/adr/0011）。
## 操作はプレイヤーと同じ（歩く・段差で跳ぶ・渡す・乗る・拾う・装備する・回収する・鐘を鳴らす）で、
## 瞬間移動はしない。どちらの島も、ひとりの道 2 通りと協力の近道 1 通りを通す。
## 部品は island_playthrough.gd。関所と詰みの試遊は test_island_probes_extra.gd。

const BACK := RuleAction.Kind.BACK
const RIGHT := RuleAction.Kind.RIGHT
const CLIMB := RuleAction.Kind.CLIMB
const DASH := RuleAction.Kind.DASH

# --- けものの巣 ----------------------------------------------------------------


## 生き物の近く（浜の西）へ歩いて、能力を触って渡す（生き物は発動方式を持たない）。
func _give_kit(slots: Array[int]) -> void:
	var critter := _creature("kit")
	await _walk_to(critter.global_position + Vector3(1.6, 0.0, 0.0), 0.4)
	for slot in slots:
		_lend(critter, slot, TriggerMode.Kind.NONE)


## 浜の窪みのブロックで段へ、段の窪みのブロックで台地へ上がる。
func _lifts_to_the_plateau() -> void:
	await _lift_up("shore_lift", Vector3(4.5, 0.0, -3.5), Vector3(3.5, 2.0, -7.5))
	await _lift_up("terrace_lift", Vector3(4.5, 2.0, -8.5), Vector3(3.5, 4.0, -12.5))


## 生き物の道 1（グローブ）＋自分の道（窪みのブロック 2 つ）。
func test_creature_nest_gloves_for_the_kit_and_lifts_for_me() -> void:
	await _enter(StageCatalog.NEST_ID)
	var climb_slot := await _pick_to_hotbar(Vector3(9.5, 0.0, 4.5), CLIMB)
	await _give_kit([climb_slot, _slot_of(RIGHT)])
	assert_true(
		await _wait_creature_in("kit", OpenIslandsExtra.NEST), "the kit climbed to its nest"
	)
	assert_eq(director.last_clear_text, "", "the kit alone does not clear")
	await _lifts_to_the_plateau()
	await _walk_into_goal()
	assert_true(await _cleared(), "the kit is in its nest and everyone is at the goal")


## 生き物の道 2（石と瓦礫の段＋ジャンプ）＋自分の道（ジャンプが無いのでグローブで登る）。
func test_creature_nest_stone_steps_for_the_kit_and_gloves_for_me() -> void:
	await _enter(StageCatalog.NEST_ID)
	await _slide_stone("step_stone", Vector3(-4.4, 0.0, -2.5), LEFT, Vector3i(-10, 0, -3))
	await _give_kit([_slot_of(JUMP), _slot_of(RIGHT)])
	assert_false(w.ledger.player_can(JUMP, _me().player_id), "the kit took my jump")
	assert_true(
		await _wait_creature_in("kit", OpenIslandsExtra.NEST), "the kit hopped up to its nest"
	)
	await _pick_and_wear(Vector3(9.5, 0.0, 4.5), RuleVessel.Part.HANDS)
	await _walk_to(Vector3(7.5, 0.0, -4.5))
	await _walk_to(Vector3(7.5, 2.0, -7.0))
	await _walk_to(Vector3(7.5, 2.0, -9.5))
	await _walk_to(Vector3(7.5, 4.0, -12.0))
	await _walk_into_goal()
	assert_true(await _cleared(), "climbed up after the kit without a jump")


## 協力の近道: 仲間のジャンプがもう 1 つあれば、1 個を生き物に渡しても、もう 1 個で自分も
## 石と瓦礫の段を上がれる（グローブを取りに行かない）。
func test_creature_nest_coop_two_jumps_share_the_stone_steps() -> void:
	await _enter(StageCatalog.NEST_ID)
	_gift_from_teammate(JUMP)
	await _slide_stone("step_stone", Vector3(-4.4, 0.0, -2.5), LEFT, Vector3i(-10, 0, -3))
	await _give_kit([_slot_of(JUMP), _slot_of(RIGHT)])
	assert_true(w.ledger.player_can(JUMP, _me().player_id), "still one jump left")
	await _walk_to(Vector3(-9.5, 1.0, -2.5))
	await _walk_to(Vector3(-11.5, 2.0, -3.5))
	await _walk_to(Vector3(-10.5, 2.0, -8.5))
	await _walk_to(Vector3(-9.5, 3.0, -9.5))
	await _walk_to(Vector3(-9.5, 4.0, -11.5))
	assert_true(await _wait_creature_in("kit", OpenIslandsExtra.NEST), "the kit reached its nest")
	await _walk_into_goal([Vector3(0.5, 4.0, -13.5)])
	assert_true(await _cleared(), "shared the jumps with the kit")


# --- 札の庭 --------------------------------------------------------------------


## 東の岸の発射台の札（投げる禁止）を F で取り、触って「投げる」を渡して東の鐘を撃つ。
func _launcher_rings_the_east_bell() -> void:
	var launcher := _block("launcher")
	await _walk_to(Vector3(12.5, 0.0, 1.5))
	w.interact(launcher)
	await wait_physics_frames(2)
	assert_true(w.ledger.player_prohibited(THROW, _me().player_id), "the launcher's sign is on me")
	_lend(launcher, _slot_of(THROW), TriggerMode.Kind.NONE)
	assert_true(await _wait_until_rung("east_bell"), "the launcher rang the east bell")


## ひとりの道 1（庭の決まりを持ったまま）: グローブで登り、発射台の札を取って撃つ。
func test_ban_garden_keep_the_rule_with_gloves_and_the_launcher() -> void:
	await _enter(StageCatalog.GARDEN_ID)
	assert_true(w.ledger.player_prohibited(JUMP, _me().player_id), "the garden rule: no jumping")
	await _launcher_rings_the_east_bell()
	await _pick_and_wear(Vector3(-11.5, 0.0, 5.5), RuleVessel.Part.HANDS)
	await _walk_to(Vector3(-9.5, 0.0, -6.5))
	await _walk_to(Vector3(-9.5, 2.0, -8.8))
	await _walk_to(Vector3(-4.5, 2.0, -14.5))
	await _walk_to(Vector3(-4.5, 4.0, -17.0))
	await _ring("shrine_bell")
	assert_true(w.ledger.player_prohibited(JUMP, _me().player_id), "never dropped the rule")
	await _walk_into_goal()
	assert_true(await _cleared(), "both bells and the goal without ever jumping")


## ひとりの道 2（庭の決まりを手放す）: ダッシュで小島へ渡って鐘を鳴らし、窪みのブロックと
## 札付きの台（札を取ってもう一度手放す）で社へ。
func test_ban_garden_drop_the_rule_dash_and_the_signed_lift() -> void:
	await _enter(StageCatalog.GARDEN_ID)
	await _walk_to(Vector3(2.5, 0.0, 4.5))
	_hand_off_ban(JUMP, w.terrain_target(Vector3i(2, -1, 3)))
	var dash_slot := await _pick_to_hotbar(Vector3(10.5, 0.0, 6.5), DASH)
	await _dash_jump_across(Vector3(14.4, 0.0, -1.5), Vector3(20.0, 0.0, -1.5), dash_slot)
	await _ring("east_bell")
	await _dash_jump_across(Vector3(19.6, 0.0, 1.5), Vector3(12.5, 0.0, 1.5), dash_slot)
	await _lift_up("garden_lift", Vector3(-2.5, 0.0, -5.5), Vector3(-3.5, 2.0, -9.5))
	var signed := _block("shrine_lift")
	await _walk_to(Vector3(4.5, 2.0, -13.5))
	w.interact(signed)
	await wait_physics_frames(2)
	assert_true(w.ledger.player_prohibited(JUMP, _me().player_id), "the lift's sign is on me now")
	_hand_off_ban(JUMP, w.terrain_target(Vector3i(5, 1, -13)))
	await _lift_up("shrine_lift", Vector3(4.5, 2.0, -13.5), Vector3(3.5, 4.0, -17.5))
	await _ring("shrine_bell")
	await _walk_into_goal()
	assert_true(await _cleared(), "dropped the rule twice and rode the signed lift")


## 協力の近道: 決まりを手放してから、仲間のジャンプでジャンプ×2 にすれば、段差 2 を直接跳べる
## （窪みのブロックも札付きの台も要らない）。
func test_ban_garden_coop_double_jump_skips_the_signed_lift() -> void:
	await _enter(StageCatalog.GARDEN_ID)
	await _walk_to(Vector3(0.5, 0.0, -4.5))
	_hand_off_ban(JUMP, w.terrain_target(Vector3i(0, -1, -3)))
	_gift_from_teammate(JUMP)
	await _walk_to(Vector3(0.5, 2.0, -9.5))
	await _walk_to(Vector3(-1.5, 2.0, -14.5))
	await _walk_to(Vector3(-1.5, 4.0, -17.5))
	await _ring("shrine_bell")
	assert_true(w.ledger.tokens_on(_block("shrine_lift").entity_id).size() == 1, "sign untouched")


## 谷の縁の手前（edge）から向こう（land）へ走って跳び、落ち始めたら空中でダッシュする。
func _dash_jump_across(edge: Vector3, land: Vector3, dash_slot: int) -> void:
	assert_ne(dash_slot, -1, "has a dash")
	await _walk_to(edge, 0.25)
	_face(land)
	_me().move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(4)
	w.press_action(JUMP)
	for i in 60:
		await tree.physics_frame
		if _me().velocity.y < 0.0:
			break
	w.press_action(DASH)
	await _walk_to(land, 0.6, 240)
