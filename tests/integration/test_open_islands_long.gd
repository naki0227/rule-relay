extends "res://tests/integration/island_playthrough.gd"
## 「遠征」を、ひとりで最初から最後まで自動で遊ぶ（通しプレイ。docs/adr/0011）。
## 操作はプレイヤーと同じ（歩く・段差で跳ぶ・渡す・乗る・拾う・装備する・回収する・鐘を鳴らす）で、
## 瞬間移動はしない。ひとりの道 2 通り（窪みのブロックと発射台／ダッシュ・ブーツ・生き物）と、協力の近道を通す。
## 部品は island_playthrough.gd。関所と詰みの試遊は test_island_probes_long.gd。

const DASH := RuleAction.Kind.DASH


## ひとりの道 1: 発射台で東の鐘、窪みのブロックで西の台地・森の台地・上の段・峰、札付きの台で物見。
func test_long_expedition_by_the_lifts_and_the_launcher() -> void:
	await _enter(StageCatalog.EXPEDITION_ID)
	# 東の岬: 野原の東の岸の発射台に「投げる」を渡す
	await _walk_to(Vector3(10.5, 0.0, -8.5))
	_lend(_block("launcher"), _slot_of(THROW), TriggerMode.Kind.NONE)
	assert_true(await _wait_until_rung("east_bell"), "the launcher rang the east bell")
	# 西の段丘: 窪みのブロックで台地へ
	await _walk_to(Vector3(-11.5, 0.0, -10.5))
	await _walk_to(Vector3(-14.5, 1.0, -10.5))
	await _lift_up("west_lift", Vector3(-22.5, 1.0, -8.5), Vector3(-25.5, 3.0, -9.5))
	await _ring("west_bell")
	# 森の台地: 岩棚の窪みのブロックで上がって触る
	await _walk_to(Vector3(-13.5, 1.0, -12.5))
	await _walk_to(Vector3(-10.5, 0.0, -17.5))
	await _walk_to(Vector3(7.5, 1.0, -18.5))
	await _lift_up("forest_lift", Vector3(7.5, 1.0, -18.5), Vector3(6.5, 3.0, -21.5))
	await _ring("forest_bell")
	assert_eq(director.last_clear_text, "", "three bells do not clear")
	# 北の峰: 上の段へ、札付きの台で物見へ（札を取ってどこかへ渡す）
	await _lift_up("ridge_lift", Vector3(-1.5, 3.0, -28.5), Vector3(-2.5, 5.0, -31.5))
	await _walk_to(Vector3(9.5, 5.0, -35.5))
	w.interact(_block("lookout_lift"))
	await wait_physics_frames(2)
	assert_true(
		w.ledger.player_prohibited(JUMP, _me().player_id), "the lookout lift's sign is on me"
	)
	_hand_off_ban(JUMP, w.terrain_target(Vector3i(8, 4, -35)))
	await _lift_up("lookout_lift", Vector3(9.5, 5.0, -35.5), Vector3(11.5, 7.0, -36.5))
	await _ring("lookout_bell")
	await _walk_to(Vector3(11.5, 7.0, -38.5))
	await _walk_to(Vector3(8.5, 5.0, -38.5))
	await _lift_up("summit_lift", Vector3(1.5, 5.0, -40.5), Vector3(0.5, 7.0, -43.5))
	await _walk_into_goal()
	assert_true(await _cleared(), "four bells and everyone at the goal")


## ひとりの道 2: ダッシュで東の岬へ渡り、段丘のブーツで西の台地、森の生き物に「投げる」を投げ渡し、
## ブーツで岩棚から峰まで跳び上がる（窪みのブロックも発射台も使わない）。
func test_long_expedition_by_dash_boots_and_the_creature() -> void:
	await _enter(StageCatalog.EXPEDITION_ID)
	var dash_slot := await _pick_to_hotbar(Vector3(5.5, 0.0, 10.5), DASH)
	await _dash_jump_across(Vector3(12.4, 0.0, -6.5), Vector3(19.5, 0.0, -6.5), dash_slot)
	await _ring("east_bell")
	await _walk_to(Vector3(20.5, 0.0, -11.5))
	await _dash_jump_across(Vector3(18.6, 0.0, -11.5), Vector3(11.5, 0.0, -11.5), dash_slot)
	# 西の段丘: ブーツで台地へ
	await _walk_to(Vector3(-11.5, 0.0, -13.5))
	await _pick_and_wear(Vector3(-20.5, 1.0, -14.5), RuleVessel.Part.FEET)
	await _walk_to(Vector3(-23.0, 1.0, -10.5))
	await _walk_to(Vector3(-26.0, 3.0, -10.5))
	await _ring("west_bell")
	# 森の台地: 下の野原から生き物へ「投げる」を投げ渡す
	await _walk_to(Vector3(-13.5, 1.0, -12.5))
	await _walk_to(Vector3(0.5, 0.0, -18.5))
	await _lend_by_throwing(_creature("forest_creature"), _slot_of(THROW))
	assert_true(await _wait_until_rung("forest_bell"), "the creature's nut rang the forest bell")
	assert_true(w.ledger.tokens_on(_block("launcher").entity_id).is_empty(), "launcher unused")
	# 北の峰: ブーツで段差 2 を 1 つずつ跳ぶ
	await _walk_to(Vector3(5.5, 1.0, -19.5))
	await _walk_to(Vector3(5.5, 3.0, -21.5))
	await _walk_to(Vector3(5.5, 3.0, -29.5))
	await _walk_to(Vector3(5.5, 5.0, -31.5))
	# 物見の窪みのブロックには札（ジャンプ禁止）。その上に立つと自分も跳べない（2026-11-21 本人「禁止はその上も
	# 禁止」。ADR 0003 決定 7）ので、ブロックの手前の地形の縁から跳んで、ブロックの上を越える
	assert_true(
		await _run_and_jump(
			Vector3(7.5, 5.0, -36.5), Vector3(9.7, 5.0, -36.5), Vector3(12.0, 7.0, -36.5)
		),
		"jump from the ground just before the signed lift"
	)
	await _ring("lookout_bell")
	await _walk_to(Vector3(11.5, 7.0, -38.5))
	await _walk_to(Vector3(8.5, 5.0, -38.5))
	await _walk_to(Vector3(0.5, 5.0, -40.5))
	await _walk_to(Vector3(0.5, 7.0, -43.0))
	await _walk_into_goal()
	assert_true(await _cleared(), "four bells and everyone at the goal")


## 協力の近道: 仲間の W で W×2 にして東の谷 5 を跳び（ダッシュを拾いに浜へ戻らない）、仲間のジャンプで
## ジャンプ×2 にして岩棚から峰まで段差 2 を直接跳ぶ（窪みのブロックも札も使わない）。
func test_long_expedition_coop_double_speed_and_double_jump() -> void:
	await _enter(StageCatalog.EXPEDITION_ID)
	_gift_from_teammate(FORWARD)
	var cape := Vector3(19.5, 0.0, -6.5)
	assert_true(
		await _run_and_jump(Vector3(9.5, 0.0, -6.5), Vector3(12.8, 0.0, -6.5), cape),
		"gap 5 with W x2"
	)
	await _ring("east_bell")
	assert_true(
		await _run_and_jump(
			Vector3(21.5, 0.0, -12.5), Vector3(18.2, 0.0, -12.5), Vector3(11.0, 0.0, -12.5)
		),
		"back over gap 5"
	)
	_gift_from_teammate(JUMP)
	await _walk_to(Vector3(5.5, 1.0, -19.5))
	await _walk_to(Vector3(5.5, 3.0, -21.5))
	await _ring("forest_bell")
	await _walk_to(Vector3(5.5, 5.0, -31.5))
	# 物見の窪みのブロックには札（ジャンプ禁止）。その上に立つと自分も跳べない（2026-11-21 本人「禁止はその上も
	# 禁止」。ADR 0003 決定 7）ので、ブロックの手前の地形の縁から跳んで、ブロックの上を越える
	assert_true(
		await _run_and_jump(
			Vector3(7.5, 5.0, -36.5), Vector3(9.7, 5.0, -36.5), Vector3(12.0, 7.0, -36.5)
		),
		"jump from the ground just before the signed lift"
	)
	await _ring("lookout_bell")
	assert_eq(w.ledger.tokens_on(_block("lookout_lift").entity_id).size(), 1, "sign untouched")
	await _walk_to(Vector3(8.5, 5.0, -38.5))
	await _walk_to(Vector3(0.5, 7.0, -43.0))
	await _walk_into_goal()
	assert_eq(director.last_clear_text, "", "the west bell is still silent")


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
