extends "res://tests/integration/world_playing.gd"
## 鐘の谷（W2）とふわふわ浮島（W3）の教える順番（docs/w2-w3-teaching.md）を確かめる。
## - 新しい能力・仕掛けは、それが出てくるステージで「要る」（無いと先へ進めない）か、そこで初めて出る
## - 1 つずつ出る短い案内が、その場で出て、その操作をした後に消える
## 操作はプレイヤーと同じ（歩く・跳ぶ・渡す・F・ダッシュ）。通しプレイは各ワールドのテスト。

const DASH_BEACH := World3Stages.DASH_BEACH_ID
const W1_LEARNED: PackedStringArray = [
	"move",
	"look",
	"jump",
	"select",
	"lend",
	"fire",
	"recall",
	"push",
	"jump_then_move",
	"ground",
	"range",
	"creature_move",
	"ban",
	"equip",
	"save",
]

var hud: Hud


func after_each() -> void:
	if hud != null:
		hud.queue_free()
		hud = null
	await super.after_each()


## このステージの画面（案内を選ぶ HUD）を、いまの島につなぐ。W1 で教えた操作は慣れたことにする。
func _attach_hud() -> void:
	hud = Hud.new()
	hud.world = w
	tree.root.add_child(hud)
	await wait_physics_frames(2)
	for key in W1_LEARNED:
		_learn(key)


func _learn(key: String) -> void:
	for i in HintMemory.LEARN_AFTER:
		hud.hints.used(key)


func _shown(target: Node3D = null) -> PackedStringArray:
	var in_reach := target != null and w.is_within_reach(target)
	hud.update_context(target, in_reach, false)
	return hud.context_actions()


# --- 順番 -------------------------------------------------------------------------


## W2・W3 の新しいことは、計画の順で 1 つずつ初めて出る（発射台 2-1・信号 2-2・時の鐘 2-5・ダッシュ 3-1・
## 往復足場 3-2・風 3-4・レバー 3-5）。W2 にはダッシュも風も無い（前は 2-3・2-6 にダッシュが落ちていた）。
func test_w2_w3_bring_each_new_thing_in_teaching_order() -> void:
	var order: Array[String] = []
	for world_index: int in [1, 2]:
		for s in CampaignPlan.built_slots(CampaignPlan.worlds()[world_index]):
			order.append(s.stage_id)
	assert_eq(
		order,
		[
			"bell_valley",
			"w2_echo_bells",
			"three_bells",
			"w2_rolling_shots",
			"w2_timed_bells",
			"windy_ridge",
			"w3_dash_beach",
			"w3_shuttle_cove",
			"floating_isles",
			"w3_wind_path",
			"w3_gap_relay",
			"w3_cloud_corridor",
		]
	)
	var first := {}
	for i in order.size():
		var def := StageCatalog.by_id(order[i])
		var found := PackedStringArray()
		for b in def.blocks:
			if b.is_launcher():
				found.append("launcher")
			for t in b.tokens:
				if t.mode == TriggerMode.Kind.SIGNAL:
					found.append("signal")
				if t.mode == TriggerMode.Kind.REPEAT and RuleAction.is_horizontal(t.action):
					found.append("shuttle")
		for spec in def.world_items:
			if spec.action == RuleAction.Kind.DASH:
				found.append("dash")
		if not def.mechanisms.timed_bells.is_empty():
			found.append("timed_bell")
		if not def.mechanisms.levers.is_empty():
			found.append("lever")
		if not def.nature.winds.is_empty():
			found.append("wind")
		for key in found:
			if not first.has(key):
				first[key] = order[i]
	assert_eq(first.get("launcher"), "bell_valley", "launchers from 2-1")
	assert_eq(first.get("signal"), "w2_echo_bells", "signals from 2-2")
	assert_eq(first.get("timed_bell"), "w2_timed_bells", "timed bells from 2-5")
	assert_eq(first.get("dash"), DASH_BEACH, "the dash from 3-1 (none lies around in W2)")
	assert_eq(first.get("shuttle"), World3Stages.SHUTTLE_COVE_ID, "shuttles from 3-2")
	assert_eq(first.get("wind"), World3Stages.WIND_PATH_ID, "wind from 3-4")
	assert_eq(first.get("lever"), World3Stages.GAP_RELAY_ID, "levers from 3-5")


# --- 2-1 鐘の谷: 発射台 ---------------------------------------------------------------


## 鐘は谷の向こうで、岸からは触れず、ステージの禁止で跳べない。発射台に「投げる」を渡すほかに鳴らす方法は無い。
func test_bell_valley_rings_only_through_the_launcher() -> void:
	await _enter(StageCatalog.BELL_ID)
	assert_true(w.ledger.player_prohibited(JUMP, _me().player_id), "jumps are banned here")
	assert_false(await _try_ring_from("valley_bell", Vector3(1.4, 0.0, 0.5)), "out of touch")
	var launcher := _block("launcher")
	await _walk_to(launcher.global_position + Vector3(-1.4, -0.5, 0.0), 0.3)
	_lend(launcher, _slot_of(THROW), TriggerMode.Kind.NONE)
	assert_true(await _wait_until_rung("valley_bell"), "the launcher rang the bell")


## 案内: W を選んだまま発射台を狙うと「[6] 投げるをえらぶ」、選ぶと「発射台に投げるを渡す」。渡したら消える。
## 遠くの鐘を狙っても「投げるで届く」とは出さない（鐘は投げても鳴らない）。
func test_bell_valley_hints_pick_the_throw_for_the_launcher() -> void:
	await _enter(StageCatalog.BELL_ID)
	await _attach_hud()
	var launcher := _block("launcher")
	await _walk_to(launcher.global_position + Vector3(-1.4, -0.5, 0.0), 0.3)
	assert_eq(_shown(w.bells_by_key["valley_bell"]), PackedStringArray(), "no throw hint at a bell")
	w.select_slot(0)
	assert_eq(_shown(launcher), PackedStringArray(["投げるをえらぶ"]))
	assert_eq(hud.context_keys(), PackedStringArray(["%d" % (_slot_of(THROW) + 1)]))
	w.select_slot(_slot_of(THROW))
	assert_eq(_shown(launcher), PackedStringArray(["発射台に投げるを渡す"]))
	assert_eq(hud.context_keys(), PackedStringArray(["左クリック"]))
	assert_eq(w.lend_to(launcher, false), RuleLedger.LendResult.OK)
	_learn("recall")
	assert_eq(_shown(launcher), PackedStringArray(), "learned once the launcher holds my throw")
	assert_false(hud.hints.should_show("launcher"))


# --- 2-2 こだまの鐘: 信号 -------------------------------------------------------------


## 青い台のそばで「乗ったまま鐘を鳴らす」。台の上で鐘を鳴らすと、鳴っている間だけ台が跳ねて中の段へ上がり、
## 信号を覚えたことになって案内は消える。
func test_echo_bells_spot_teaches_the_signal_lift() -> void:
	await _enter("w2_echo_bells")
	await _attach_hud()
	var lift := _block("echo_lift_1")
	await _walk_to(lift.global_position + Vector3(0.0, 0.5, 1.2), 0.3)
	assert_eq(_shown(), PackedStringArray(["乗ったまま鐘を鳴らす"]))
	assert_eq(hud.context_keys(), PackedStringArray(["F"]))
	await _walk_to(lift.global_position + Vector3(0.0, 0.5, 0.0), 0.25)
	var bell := w.bells_by_key["echo_bell_1"]
	assert_true(w.is_within_reach(bell), "the bell is in reach from the lift")
	assert_false(w.is_receiving_signal(lift.entity_id), "quiet before the bell")
	w.interact(bell)
	await wait_physics_frames(2)
	assert_true(w.is_receiving_signal(lift.entity_id), "the bell's sound reaches the lift")
	var top := lift.global_position.y
	for i in 120:
		top = maxf(top, lift.global_position.y)
		await tree.physics_frame
	assert_gt(top, 0.5, "the signal lift jumped while the bell rang")
	_shown()
	assert_false(hud.hints.should_show("signal"), "learned by watching the lift move")


# --- 2-6 風の尾根: ダッシュを外した後の道 -------------------------------------------


## 浜のダッシュを外した（教えるのは 3-1）。西の小島のブーツの道は、谷を 3 にしたので走って跳べば届く。
func test_windy_ridge_boots_islet_without_a_dash() -> void:
	await _enter(StageCatalog.WINDY_ID)
	for spec in w.def.world_items:
		assert_ne(spec.action, DASH, "no dash lies on the ridge")
	await _jump_across(Vector3(-11.8, 0.0, -0.5), Vector3(-16.5, 0.0, -0.5))
	assert_lt(_me().global_position.x, -15.0, "a running jump reached the west islet")
	await _pick_and_wear(Vector3(-17.5, 0.0, -0.5), RuleVessel.Part.FEET)
	assert_true(w.ledger.player_can(RuleAction.Kind.HIGH_JUMP, _me().player_id), "boots on")


# --- 3-1 ダッシュの浜: ダッシュ -------------------------------------------------------


## 浜の北の幅 5 は、ふつうの走り跳びでは越えない。ダッシュを拾って、跳んでから空中でダッシュすると越える。
func test_dash_beach_needs_the_air_dash() -> void:
	await _enter(DASH_BEACH)
	assert_eq(_slot_of(DASH), -1, "no dash at the start")
	var route: Array[Vector3] = [Vector3(-2.5, 0.0, 3.5)]
	assert_true(is_nan(await _first_crossing(route, Vector3.FORWARD, 1.0, 5.0)), "5 > a plain jump")
	await _pick(Vector3(1.5, 0.0, 2.5), DASH)
	assert_true(
		await _dash_jump_across(Vector3(-3.5, 0.0, -0.7), Vector3(-3.5, 0.0, -7.5)),
		"the air dash crossed the gap of 5"
	)


## 案内: ダッシュを持って空の縁に来ると「[Space→Shift] 跳んでからダッシュ」（持っていなければ出ない）。
## ダッシュを 3 回したら出ない。
func test_dash_beach_spot_teaches_jump_then_dash() -> void:
	await _enter(DASH_BEACH)
	await _attach_hud()
	await _walk_to(Vector3(-3.5, 0.0, -0.3), 0.3)
	assert_eq(_shown(), PackedStringArray(), "no dash yet: nothing to teach")
	await _pick(Vector3(1.5, 0.0, 2.5), DASH)
	await _walk_to(Vector3(-3.5, 0.0, -0.3), 0.3)
	assert_eq(_shown(), PackedStringArray(["跳んでからダッシュ"]))
	assert_eq(hud.context_keys(), PackedStringArray(["Space→Shift"]))
	for i in HintMemory.LEARN_AFTER:
		await _walk_to(Vector3(-0.5, 0.0, 1.5 + i), 0.3)
		_face(Vector3(4.0, 0.0, 1.5 + i))
		_me().move_intent = Vector2(0.0, 1.0)
		await wait_physics_frames(1)
		w.press_action(DASH)
		for f in 30:
			_shown()  # 画面は毎フレーム案内を選ぶ（ダッシュの始まりを数える）
			await tree.physics_frame
		_me().move_intent = Vector2.ZERO
		await wait_physics_frames(10)
	await _walk_to(Vector3(-3.5, 0.0, -0.3), 0.3)
	assert_eq(_shown(), PackedStringArray(), "gone after three dashes")


# --- 3-2 往復足場の入り江: 往復足場 ---------------------------------------------------


## 入り江にジャンプは無く、浜から中の島への幅 2 は歩いて越えられない（落ちる）。往復足場に乗るしかない。
func test_shuttle_cove_needs_the_shuttle() -> void:
	await _enter(World3Stages.SHUTTLE_COVE_ID)
	assert_false(w.ledger.player_can(JUMP, _me().player_id), "no jump in the cove")
	await _walk_to(Vector3(2.5, 1.0, 2.6), 0.3)
	assert_true(await _walk_off(Vector3(2.5, 1.0, -2.0)), "walking off the beach falls")
	await _ride(
		"north_shuttle",
		Vector3(-3.5, 1.0, 2.6),
		Vector3i(-4, 0, 1),
		Vector3i(-4, 0, 0),
		Vector3(-3.5, 1.0, -1.5)
	)
	assert_lt(_me().global_position.z, -1.0, "the shuttle carried me over")


# --- 3-4 風の通り道: 風 ---------------------------------------------------------------


## 追い風の空（幅 5）は、風が止んでいる間に走って跳んでも越えない。吹いている間なら越える（通しプレイ）。
## 案内「[Space] 風が吹いたら跳ぶ」は空の手前で出て、風の中を跳んだら消える。
func test_wind_path_needs_the_gust_and_teaches_it() -> void:
	await _enter(World3Stages.WIND_PATH_ID)
	await _attach_hud()
	var gust := Vector3(-1.5, 0.5, -2.5)
	await _walk_to(Vector3(-1.5, 0.0, 1.0), 0.3)
	assert_eq(_shown(), PackedStringArray(["風が吹いたら跳ぶ"]))
	assert_eq(hud.context_keys(), PackedStringArray(["Space"]))
	await _walk_to(Vector3(-1.5, 0.0, 2.5), 0.25)
	assert_true(await _wait_wind(gust, true), "a gust")
	assert_true(await _wait_wind(gust, false), "calm again")
	var route: Array[Vector3] = [Vector3(-1.5, 0.0, 2.5)]
	assert_false(await _running_jump(route, Vector3.FORWARD, 0.0, 5.0, 0.0), "5 is too far in calm")
	await _walk_to(Vector3(-1.5, 0.0, 2.5), 0.25)
	assert_true(await _wait_wind(gust, false), "calm")
	assert_true(await _wait_wind(gust, true), "the gust starts")
	_face(Vector3(-1.5, 0.0, -6.5))
	_me().move_intent = Vector2(0.0, 1.0)
	var crossed := false
	for i in 240:
		_shown()
		if _me().global_position.z < 0.2 and _me().is_on_floor() and _me().global_position.z > -1.0:
			w.press_action(JUMP)
		if _me().global_position.z < -5.5 and _me().is_on_floor():
			crossed = true
			break
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	assert_true(crossed, "the tailwind carried me over the gap of 5")
	assert_false(hud.hints.should_show("wind"), "learned by jumping in the wind")


# --- 3-5 谷越えリレー: レバー ---------------------------------------------------------


## 北の島のレバーのそばで「[F] レバー」。倒したら消え、橋は架かったまま（後から来る人のため）。
func test_gap_relay_lever_hint_until_pulled() -> void:
	await _enter(World3Stages.GAP_RELAY_ID)
	await _attach_hud()
	_learn("throw")
	await _walk_to(Vector3(5.5, 0.0, 0.5), 0.3)
	await _lend_by_throwing(_block("launcher"), _slot_of(THROW))
	assert_true(await _wait_door("relay_bridge", true), "the launcher's bell raised the bridge")
	await _walk_to(Vector3(0.0, 0.0, 0.5), 0.3)
	await _walk_to(Vector3(0.0, 0.0, -10.5), 0.35, 400)
	await _walk_to(Vector3(-2.5, 0.0, -10.6), 0.3)
	assert_eq(_shown(), PackedStringArray(["レバー"]))
	assert_eq(hud.context_keys(), PackedStringArray(["F"]))
	w.interact(null)
	await wait_physics_frames(2)
	assert_true(MechanismSet.of(w).levers[0].on, "pulled the lever")
	assert_eq(_shown(), PackedStringArray(), "gone once pulled")
