extends "res://tests/integration/world_playing.gd"
## ワールド 3「ふわふわ浮島」の新しいステージを、ひとりで最初から最後まで自動で遊ぶ（通しプレイ）。
## どのステージも、ひとりの道を 2 通り通す（協力の道は test_world34_coop.gd、関所と詰みは
## test_world3_probes.gd）。操作はプレイヤーと同じで、瞬間移動しない。部品は world_playing.gd。

const GUST_AT := Vector3(-1.5, 0.5, -2.5)
const CROSSWIND_AT := Vector3(-9.0, 0.5, -3.0)

# --- 3-1 ダッシュの浜 -------------------------------------------------------------


## うさぎに D とジャンプを渡して砂丘へ上げ、ふもとから F で取り戻す。
func _beach_bunny() -> void:
	await _walk_to(Vector3(-1.0, 0.0, 2.5), 0.4)
	await _give_creature("bunny", [_slot_of(RIGHT), _slot_of(JUMP)])
	assert_false(w.ledger.player_can(JUMP, _me().player_id), "the bunny has my jump")
	assert_true(await _wait_wish("bunny"), "the bunny hopped to the top of its dune")
	await _walk_to(Vector3(-2.5, 0.0, 0.5), 0.3)
	await _recall_creature("bunny")
	assert_true(w.ledger.player_can(JUMP, _me().player_id), "my jump is back")


func _beach_goal() -> void:
	await _walk_into_goal(
		[Vector3(5.5, 0.0, -7.5), Vector3(7.5, 1.0, -8.5), Vector3(7.5, 2.0, -10.5)]
	)
	assert_true(await _cleared(), "the bunny is on its dune and everyone is at the goal")


## 西の道: 浜 → 幅 5 → 西の小島 → 幅 5 → ゴールの島（どちらも空中ダッシュ）。
func test_dash_beach_west_over_the_islet() -> void:
	await _enter(World3Stages.DASH_BEACH_ID)
	await _beach_bunny()
	await _pick(Vector3(1.5, 0.0, 2.5), DASH)
	assert_true(
		await _dash_jump_across(Vector3(-3.5, 0.0, -0.7), Vector3(-3.5, 0.0, -7.5)), "to the islet"
	)
	assert_true(
		await _dash_jump_across(Vector3(-1.3, 0.0, -9.5), Vector3(4.6, 0.0, -9.0)),
		"to the goal isle"
	)
	await _beach_goal()


## 東の道: 浜の東の崖（高さ 1）から、北へ幅 6 を空中ダッシュで越える（1 段降りる）。
func test_dash_beach_east_from_the_bluff() -> void:
	await _enter(World3Stages.DASH_BEACH_ID)
	await _pick(Vector3(1.5, 0.0, 2.5), DASH)
	await _beach_bunny()
	await _walk_to(Vector3(5.5, 1.0, 2.5))
	assert_true(
		await _dash_jump_across(Vector3(5.5, 1.0, 0.3), Vector3(5.5, 0.0, -7.5)),
		"over the gap of 6"
	)
	await _beach_goal()


# --- 3-2 往復足場の入り江 ---------------------------------------------------------


## 北の島で、ひつじに D を渡して岩へ上げ、窪みへ歩いて入る。
func _cove_lamb_and_goal() -> void:
	await _walk_to(Vector3(5.5, 1.0, -12.5), 0.4)
	await _walk_to(Vector3(3.5, 1.0, -13.5), 0.4)
	await _give_creature("lamb", [_slot_of(RIGHT)])
	assert_true(await _wait_wish("lamb"), "the lamb hopped up its rock")
	await _walk_into_goal([Vector3(3.5, 1.0, -14.5)])
	assert_true(await _cleared(), "the lamb is on its rock and everyone is in the hollow")


## 西の道: 北の足場 → 中の島 → 向かい合う 2 つの足場を乗り継ぐ → 北の島。
func test_shuttle_cove_west_by_the_twin_shuttles() -> void:
	await _enter(World3Stages.SHUTTLE_COVE_ID)
	assert_eq(_slot_of(JUMP), -1, "no jump in the cove")
	await _ride(
		"north_shuttle",
		Vector3(-3.5, 1.0, 2.6),
		Vector3i(-4, 0, 1),
		Vector3i(-4, 0, 0),
		Vector3(-3.5, 1.0, -1.5)
	)
	await _ride(
		"twin_south",
		Vector3(0.5, 1.0, -4.4),
		Vector3i(0, 0, -6),
		Vector3i(0, 0, -7),
		Vector3(0.5, 1.0, -7.5)
	)
	assert_true(await _wait_shuttle_at("twin_north", Vector3i(0, 0, -9)), "carried north")
	await _walk_to(Vector3(0.5, 1.0, -10.5), 0.35, 120)
	await _walk_to(Vector3(5.5, 1.0, -10.5))
	await _cove_lamb_and_goal()


## 東の道: 東の足場 → 東の島 → 西へ戻る足場 → 北の島。
func test_shuttle_cove_east_around_the_bay() -> void:
	await _enter(World3Stages.SHUTTLE_COVE_ID)
	await _ride(
		"east_shuttle",
		Vector3(6.4, 1.0, 4.5),
		Vector3i(7, 0, 4),
		Vector3i(8, 0, 4),
		Vector3(9.5, 1.0, 4.5)
	)
	await _walk_to(Vector3(9.6, 1.0, -10.5))
	await _ride(
		"return_shuttle",
		Vector3(9.6, 1.0, -10.5),
		Vector3i(8, 0, -11),
		Vector3i(7, 0, -11),
		Vector3(5.5, 1.0, -10.5)
	)
	await _cove_lamb_and_goal()


# --- 3-4 風の通り道 ---------------------------------------------------------------


## 北の島で、うさぎに D とジャンプを渡して見晴らしへ上げ、取り戻して丘の窪みへ。
func _wind_bunny_and_goal() -> void:
	await _walk_to(Vector3(3.5, 0.0, -10.5), 0.4)
	await _give_creature("bunny", [_slot_of(RIGHT), _slot_of(JUMP)])
	assert_true(await _wait_wish("bunny"), "the bunny hopped up to its lookout")
	await _walk_to(Vector3(5.5, 0.0, -10.5), 0.3)
	await _recall_creature("bunny")
	await _walk_into_goal(
		[Vector3(-3.5, 0.0, -9.5), Vector3(-3.5, 1.0, -10.5), Vector3(-3.5, 2.0, -12.5)]
	)
	assert_true(await _cleared(), "the bunny is on its lookout and everyone is at the goal")


## 追い風の道: 吹き始めるのを待って、風の中を走って幅 5 を跳ぶ。
func test_wind_path_ride_the_gust_over_the_gap() -> void:
	await _enter(World3Stages.WIND_PATH_ID)
	await _walk_to(Vector3(-1.5, 0.0, 2.5), 0.25)
	assert_true(await _wait_wind(GUST_AT, false), "calm")
	assert_true(await _wait_wind(GUST_AT, true), "the gust starts")
	assert_true(
		await _run_and_jump(
			Vector3(-1.5, 0.0, 2.5), Vector3(-1.5, 0.0, 0.2), Vector3(-1.5, 0.0, -6.5)
		),
		"the tailwind carried me over the gap of 5"
	)
	await _wind_bunny_and_goal()


## 横風の橋: 西の橋の手前で、横風が止むのを待ってから渡る。
func test_wind_path_cross_the_bridge_between_gusts() -> void:
	await _enter(World3Stages.WIND_PATH_ID)
	await _walk_to(Vector3(-9.0, 0.0, 0.6), 0.2)
	assert_true(await _wait_wind(CROSSWIND_AT, true), "a crosswind")
	assert_true(await _wait_wind(CROSSWIND_AT, false), "it stops")
	await _walk_to(Vector3(-9.0, 0.0, -6.5), 0.35, 300)
	await _walk_to(Vector3(-5.5, 0.0, -8.5))
	await _wind_bunny_and_goal()


# --- 3-5 谷越えリレー -------------------------------------------------------------


func _relay_goal() -> void:
	await _walk_into_goal(
		[Vector3(-4.5, 0.0, -12.5), Vector3(-4.5, 1.0, -13.5), Vector3(-4.5, 2.0, -15.5)]
	)
	assert_true(await _cleared(), "the lamb is on its rock and everyone is at the goal")


## 道 1: 東の小島の発射台へ「投げる」を投げ渡す → 鐘が鳴り続け、橋が架かったまま → 渡ってひつじに D。
func test_gap_relay_launcher_keeps_the_bridge_up() -> void:
	await _enter(World3Stages.GAP_RELAY_ID)
	assert_false(_door_closed("relay_bridge"), "no bridge yet")
	await _walk_to(Vector3(5.5, 0.0, 0.5), 0.3)
	_lend_by_throwing(_block("launcher"), _slot_of(THROW))
	assert_true(await _wait_until_rung("bridge_bell"), "the launcher rang the bell")
	assert_true(await _wait_door("relay_bridge", true), "the bridge rose")
	await _walk_to(Vector3(0.0, 0.0, 0.5), 0.3)
	await _walk_to(Vector3(0.0, 0.0, -10.5), 0.35, 400)
	await _walk_to(Vector3(-0.5, 0.0, -13.5), 0.4)
	await _give_creature("lamb", [_slot_of(RIGHT)])
	assert_true(await _wait_wish("lamb"), "the lamb climbed its rock")
	await _relay_goal()


## 道 2: ひつじに D を投げ渡して見張り岩へ上げ、東を向いたら「投げる」を投げ渡す → 木の実で鐘 → 6 秒の橋。
func test_gap_relay_the_lambs_nut_rings_the_bell() -> void:
	await _enter(World3Stages.GAP_RELAY_ID)
	await _walk_to(Vector3(0.0, 0.0, 0.5), 0.3)
	await _give_creature("lamb", [_slot_of(RIGHT)], true)
	assert_true(await _wait_wish("lamb"), "the lamb climbed its rock")
	await _give_creature("lamb", [_slot_of(THROW)], true)
	assert_true(await _wait_until_rung("bridge_bell"), "the lamb's nut rang the bell")
	assert_true(await _wait_door("relay_bridge", true), "the bridge rose")
	await _walk_to(Vector3(0.0, 0.0, -10.5), 0.35, 400)
	await _relay_goal()
