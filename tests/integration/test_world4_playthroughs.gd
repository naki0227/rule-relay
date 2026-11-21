extends "res://tests/integration/world_playing.gd"
## ワールド 4「けものの森」の新しいステージ（4-1・4-2・4-4・4-5）を、ひとりで最初から最後まで自動で遊ぶ。
## どのステージも、ひとりの道を 2 通り通す（4-6 は test_world4_forest.gd、協力の道は test_world34_coop.gd、
## 関所と詰みは test_world4_probes.gd）。操作はプレイヤーと同じで、瞬間移動しない。

# --- 4-1 木の実投げ ---------------------------------------------------------------


func _nut_goal() -> void:
	await _walk_into_goal(
		[Vector3(-1.5, 0.0, 2.5), Vector3(-1.5, 1.0, 4.5), Vector3(-2.5, 2.0, 4.5)]
	)
	assert_true(await _cleared(), "the bell rang, the kit is on its stump, all at the goal")


## 道 1: 子どもに D を投げ渡して切り株へ上げ、「投げる」を投げ渡す → 北の鐘を木の実で鳴らす。
func test_nut_toss_the_kit_throws_its_nut() -> void:
	await _enter(World4Stages.NUT_TOSS_ID)
	await _walk_to(Vector3(-1.5, 0.0, -1.6), 0.3)
	await _give_creature("kit", [_slot_of(RIGHT)], true)
	assert_true(await _wait_wish("kit"), "the kit hopped onto its stump")
	assert_eq(_creature("kit").facing, Vector2i(0, -1), "still facing north")
	await _give_creature("kit", [_slot_of(THROW)], true)
	assert_true(await _wait_until_rung("nut_bell"), "the nut rang the bell")
	await _nut_goal()


## 道 2: 子どもに D だけ投げ渡して切り株へ。発射台に S を単発で投げ渡して 1 マス押し、「投げる」を投げ渡す。
func test_nut_toss_push_the_launcher_into_line() -> void:
	await _enter(World4Stages.NUT_TOSS_ID)
	await _walk_to(Vector3(5.5, 0.0, -1.6), 0.3)
	await _give_creature("kit", [_slot_of(RIGHT)], true)
	var launcher := _block("launcher")
	await _throw_lend(launcher, _slot_of(BACK), TriggerMode.Kind.SINGLE_SHOT)
	await _fire(BACK)
	assert_eq(launcher.cell(), Vector3i(5, 2, -16), "the launcher moved into line")
	await _walk_to(Vector3(5.5, 0.0, -1.6), 0.3)
	await _throw_lend(launcher, _slot_of(THROW), TriggerMode.Kind.NONE)
	assert_true(await _wait_until_rung("nut_bell"), "the launcher rang the bell")
	assert_true(await _wait_wish("kit"), "the kit hopped onto its stump")
	await _nut_goal()


# --- 4-2 生き物のはしご -----------------------------------------------------------


func _ladder_goal() -> void:
	await _lift_up("ledge_lift", Vector3(4.5, 0.0, -1.5), Vector3(5.5, 2.0, -3.5))
	await _walk_into_goal()
	assert_true(await _cleared(), "the bunny is on its meadow and everyone is at the goal")


## 道 1（はしご）: 石を西へすべらせて足場にし、うさぎにジャンプと D → 石 → 段 → 崖。ふもとから取り戻す。
func test_creature_ladder_slide_the_stone_into_a_step() -> void:
	await _enter(World4Stages.LADDER_ID)
	await _slide_stone("ladder_stone", Vector3(-0.4, 0.0, -2.5), LEFT, Vector3i(-6, 0, -3))
	await _walk_to(Vector3(-4.0, 0.0, -1.0), 0.4)
	await _give_creature("bunny", [_slot_of(JUMP), _slot_of(RIGHT)])
	assert_true(await _wait_wish("bunny"), "the bunny climbed the ladder to its meadow")
	await _walk_to(Vector3(-4.5, 0.0, -2.5), 0.3)
	await _recall_creature("bunny")
	await _ladder_goal()


## 道 2（グローブ）: 窪みのブロックで東の段へ上がってグローブを取り、うさぎにグローブと D。
func test_creature_ladder_gloves_from_the_ledge() -> void:
	await _enter(World4Stages.LADDER_ID)
	await _lift_up("ledge_lift", Vector3(4.5, 0.0, -1.5), Vector3(5.5, 2.0, -3.5))
	await _pick(Vector3(7.5, 2.0, -3.5), CLIMB)
	await _walk_to(Vector3(3.5, 0.0, -1.5))
	await _walk_to(Vector3(-4.0, 0.0, -1.0), 0.4)
	await _give_creature("bunny", [_slot_of(CLIMB), _slot_of(RIGHT)])
	assert_true(await _wait_wish("bunny"), "the bunny climbed the cliff with the gloves")
	assert_eq(_block("ladder_stone").cell(), Vector3i(-2, 0, -3), "the stone never moved")
	await _ladder_goal()


# --- 4-4 重さの板 -----------------------------------------------------------------


func _plates_cross_and_goal() -> void:
	assert_true(await _wait_door("plate_bridge", true), "the bridge rose")
	await _walk_to(Vector3(0.0, 1.0, 0.6), 0.3)
	await _walk_to(Vector3(0.0, 1.0, -10.5), 0.35, 400)
	await _walk_into_goal([Vector3(4.5, 1.0, -11.5), Vector3(4.5, 1.0, -15.5)])
	assert_true(await _cleared(), "the lamb is on its dais and everyone is at the goal")


## 道 1: ひつじに重い・ジャンプ・A を渡す → 台の上の板を 1 匹で押す（4 人分）。ジャンプなしで渡る。
func test_weight_plates_the_heavy_lamb_holds_the_bridge() -> void:
	await _enter(World4Stages.PLATES_ID)
	var heavy := await _pick(Vector3(-5.5, 1.0, 5.5), HEAVY)
	await _walk_to(Vector3(7.5, 1.0, 3.0), 0.4)
	await _give_creature("lamb", [heavy, _slot_of(JUMP), _slot_of(LEFT)])
	assert_true(await _wait_wish("lamb"), "the lamb hopped onto its dais")
	assert_true(await _wait_door("plate_bridge", true), "one heavy lamb is 4 people's weight")
	assert_true(_plate_pressed("dais_plate"), "the dais plate is down")
	await _plates_cross_and_goal()


## 道 2: 石に重いを渡して D の単発で板へ押す。ひつじにはジャンプと A だけ渡して台へ上げ、取り戻して渡る。
func test_weight_plates_a_heavy_stone_on_the_ground_plate() -> void:
	await _enter(World4Stages.PLATES_ID)
	var heavy := await _pick(Vector3(-5.5, 1.0, 5.5), HEAVY)
	var stone := _block("weight_stone")
	await _walk_to(Vector3(-5.5, 1.0, 2.5), 0.3)
	_lend(stone, heavy, TriggerMode.Kind.NONE)
	_lend(stone, _slot_of(RIGHT), TriggerMode.Kind.SINGLE_SHOT)
	await _fire(RIGHT)
	assert_eq(stone.cell(), Vector3i(-3, 1, 2), "the heavy stone sits on the plate")
	assert_true(_plate_pressed("ground_plate"), "the stone is 4 people's weight")
	await _walk_to(Vector3(7.5, 1.0, 3.0), 0.4)
	await _give_creature("lamb", [_slot_of(JUMP), _slot_of(LEFT)])
	assert_true(await _wait_wish("lamb"), "the lamb hopped onto its dais")
	await _recall_creature("lamb")
	assert_true(w.ledger.player_can(JUMP, _me().player_id), "my jump is back")
	await _plates_cross_and_goal()


# --- 4-5 群れの道 -----------------------------------------------------------------


## 3 匹に A・S・D を 1 つずつ渡す（W は残す）。
func _herd_moves() -> void:
	var gifts: Array[RuleAction.Kind] = [LEFT, BACK, RIGHT]
	for i in World4Stages.HERD.size():
		var critter := _creature(World4Stages.HERD[i])
		await _walk_to(critter.global_position + Vector3(0.0, 0.0, 1.6), 0.4)
		await _give_creature(World4Stages.HERD[i], [_slot_of(gifts[i])])
	assert_true(w.ledger.player_can(FORWARD, _me().player_id), "W is left")


func _herd_in_the_pasture() -> void:
	for key in World4Stages.HERD:
		assert_true(
			await _wait_creature_in(key, World4Stages.PASTURE), "%s is in the pasture" % key
		)
	assert_true(await _wait_door("herd_bridge", true), "the herd on the scale raised the bridge")


func _herd_cross_and_goal() -> void:
	await _walk_to(Vector3(8.6, 1.0, 5.6), 0.3)
	await _walk_to(Vector3(18.5, 1.0, 5.6), 0.35, 400)
	await _walk_into_goal([Vector3(19.5, 1.0, 0.5), Vector3(21.5, 1.0, 0.5)])
	assert_true(await _cleared(), "the herd is in the pasture and everyone is at the goal")


## 道 1: 自分が門の板に乗って、3 匹が牧場へ入って秤に乗るまで待つ。
func test_herd_path_hold_the_gate_yourself() -> void:
	await _enter(World4Stages.HERD_ID)
	await _herd_moves()
	await _walk_to(Vector3(7.5, 1.0, 4.5), 0.2)
	assert_true(_plate_pressed("gate_plate"), "standing on the gate plate")
	await _herd_in_the_pasture()
	await _herd_cross_and_goal()


## 道 2: 先に板の隣の石に A を単発で渡して板へ載せ（門が開いたままになる）、それから 3 匹に渡す。
func test_herd_path_a_stone_holds_the_gate() -> void:
	await _enter(World4Stages.HERD_ID)
	var stone := _block("gate_stone")
	await _walk_to(Vector3(8.5, 1.0, 6.0), 0.3)
	_lend(stone, _slot_of(LEFT), TriggerMode.Kind.SINGLE_SHOT)
	await _fire(LEFT)
	assert_eq(stone.cell(), Vector3i(7, 1, 4), "the stone sits on the gate plate")
	assert_true(await _wait_door("pasture_gate", false), "the gate is open")
	await _herd_moves()
	await _herd_in_the_pasture()
	await _herd_cross_and_goal()
