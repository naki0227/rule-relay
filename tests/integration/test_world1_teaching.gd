extends "res://tests/integration/island_playthrough.gd"
## はじまりの草原（W1）の教える順番（docs/w1-teaching.md）を確かめる。
## - 新しいことは、それが出てくるステージで「要る」（無いと先へ進めない）か、そこで初めて使えるようになる
## - 1 つずつ出る短い案内が、その場で出て、その操作をした後に消える
## 操作はプレイヤーと同じ（歩く・段差で跳ぶ・渡す・F・乗る）。協力の道は test_world1_coop.gd。

const RELAY := StageCatalog.RELAY_ID
const BACK := RuleAction.Kind.BACK

var hud: Hud


func after_each() -> void:
	if hud != null:
		hud.queue_free()
		hud = null
	await super.after_each()


## このステージの画面（案内を選ぶ HUD）を、いまの島につなぐ。
func _attach_hud() -> void:
	hud = Hud.new()
	hud.world = w
	tree.root.add_child(hud)
	await wait_physics_frames(2)
	for key: String in ["move", "look", "jump"]:
		_learn(key)


func _learn(key: String) -> void:
	for i in HintMemory.LEARN_AFTER:
		hud.hints.used(key)


func _shown(target: Node3D = null) -> PackedStringArray:
	var in_reach := target != null and w.is_within_reach(target)
	hud.update_context(target, in_reach, false)
	return hud.context_actions()


# --- 1-2 みんなで回す: F で取り戻す ------------------------------------------------


## F のほかに段へ上がる方法は無い（誰もジャンプを持たず、段は高さ 1 でも歩いては上がれない）。
func test_relay_the_shelf_needs_a_jump_taken_with_f() -> void:
	await _enter(RELAY)
	assert_false(w.ledger.player_can(JUMP, _me().player_id), "nobody starts with a jump")
	assert_eq(w.ledger.world_vessels().size(), 0, "no jump lies on the ground")
	assert_false(await _try_walk_to(Vector3(0.5, 1.0, -3.5), 0.4, 240), "the shelf is a wall")
	assert_lt(_me().global_position.y, 0.5, "still on the ground")


## 台のジャンプを F で取ると、その枠が選ばれる。空になった台を狙っても「W を渡す」とは出ない
## （2026-11-23。はじめての 10 分の通しで、取った直後も W のままで、W を台へ返しそうになった）。
func test_relay_the_jump_taken_from_the_post_is_selected() -> void:
	await _enter(RELAY)
	await _attach_hud()
	w.select_slot(0)
	await _take_the_post_jump()
	_learn("recall")
	var post := _block("jump_post")
	var shown := _shown(post)
	assert_false(shown.has("Wを渡す"), str(shown))


## ひとりの道 1: 台のジャンプを F で取り（すぐホットバーに入る）、段へ跳び、はねる台に乗って岩棚へ。
func test_relay_take_the_post_jump_and_ride_the_bouncer() -> void:
	await _enter(RELAY)
	await _take_the_post_jump()
	await _walk_to(Vector3(-0.5, 1.0, -3.5))
	await _ride_the_bouncer()
	await _walk_into_goal()
	assert_true(await _cleared(), "rode the bouncer up to the ledge")


## ひとりの道 2（少し難しい使い方）: はねる台のジャンプも F で取り、ジャンプ ×2 で岩棚へ自分で跳ぶ。
func test_relay_take_both_jumps_and_jump_twice() -> void:
	await _enter(RELAY)
	await _take_the_post_jump()
	await _walk_to(Vector3(-0.5, 1.0, -3.5))
	assert_false(
		await _try_walk_to(Vector3(-0.5, 3.0, -6.6), 0.4, 180), "one jump does not reach the ledge"
	)
	await _walk_to(Vector3(1.5, 1.0, -3.5), 0.4)
	await _recall_all_from("bouncer")
	assert_eq(w.ledger.ability_count(JUMP, _me().player_id), 2, "jump x2")
	await _walk_to(Vector3(-0.5, 3.0, -6.6))
	await _walk_into_goal()
	assert_true(await _cleared(), "jumped up with jump x2")


## 案内: 台のそばで「台を見て取る」、狙うと「取る」。取ると数え、ジャンプを渡したブロックでは「取り戻す」。
func test_relay_hints_teach_taking_back() -> void:
	await _enter(RELAY)
	await _attach_hud()
	var post := _block("jump_post")
	await _walk_to(post.global_position + Vector3(0.0, -0.5, 1.4), 0.4)
	assert_eq(_shown(), PackedStringArray(["台を見て取る"]), "the stage's spot near the post")
	assert_eq(_shown(post), PackedStringArray(["取る"]), "aiming at it")
	assert_eq(hud.context_keys(), PackedStringArray(["F"]))
	w.interact(post)
	hud.hints.used("recall")  # ゲームでは PlayerInput が数える（test_first_timer）
	await wait_physics_frames(2)
	assert_false(_shown(post).has("取る"), "nothing left on the post")
	w.select_slot(_slot_of(JUMP))
	assert_eq(w.lend_to(post, false), RuleLedger.LendResult.OK)
	_learn("fire")
	assert_eq(_shown(post), PackedStringArray(["取り戻す"]), "my own lent jump")
	_learn("recall")
	assert_eq(_shown(post), PackedStringArray(), "gone once learned")


func _take_the_post_jump() -> void:
	var post := _block("jump_post")
	await _walk_to(post.global_position + Vector3(0.0, -0.5, 1.4), 0.4)
	w.interact(post)
	await wait_physics_frames(2)
	assert_true(w.ledger.player_can(JUMP, _me().player_id), "took the jump with F")
	assert_ne(_slot_of(JUMP), -1, "it went straight to the hotbar (no bag to open)")
	assert_eq(w.selected_slot, _slot_of(JUMP), "the jump just taken is selected")


## はねる台が下りているときに跳び乗り、上がりきったところで岩棚へ歩いて移る。
func _ride_the_bouncer() -> void:
	var bouncer := _block("bouncer")
	var top := bouncer.global_position + Vector3(0.0, 0.5, 0.0)
	await _walk_to(Vector3(top.x, 1.0, top.z + 1.3), 0.3)
	for attempt in 6:
		for i in 240:
			if bouncer.is_grounded():
				break
			await tree.physics_frame
		_face(top)
		_me().move_intent = Vector2(0.0, 1.0)
		w.press_action(JUMP)
		for i in 50:
			var flat := Vector2(
				_me().global_position.x - bouncer.global_position.x,
				_me().global_position.z - bouncer.global_position.z
			)
			if flat.length() < 0.35:
				break
			_face(bouncer.global_position)
			await tree.physics_frame
		_me().move_intent = Vector2.ZERO
		await wait_physics_frames(20)
		if _me().global_position.y > bouncer.global_position.y + 0.3:
			break
		await _walk_to(Vector3(top.x, 1.0, top.z + 1.3), 0.3)
	var onto := Vector3(top.x, 3.0, -6.6)
	for i in 600:
		var flat := _face(onto)
		if flat.length() < 0.4 and _me().global_position.y > onto.y - 0.2:
			break
		var high := _me().global_position.y > onto.y + 0.1
		_me().move_intent = Vector2(0.0, 1.0) if high else Vector2.ZERO
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	assert_gt(_me().global_position.y, onto.y - 0.3, "rode the bouncer onto the ledge")


# --- 1-3 持ち上げ台の段々: ブロックの W/A/S/D --------------------------------------


## 浜で石 1 の真下に来ると「石にSを渡す」。単発の S を押すと数え、3 回で消える。
func test_lift_steps_spot_teaches_pushing_the_stone() -> void:
	await _enter("w1_lift_steps")
	await _attach_hud()
	await _walk_to(Vector3(-3.5, 0.0, 0.6), 0.3)
	assert_eq(_shown(), PackedStringArray(["石にSを渡す"]))
	_lend(_block("stone_low"), _slot_of(BACK), TriggerMode.Kind.SINGLE_SHOT)
	assert_eq(_shown(), PackedStringArray(["貸したSを使う"]), "then the key that fires it")
	assert_eq(hud.context_keys(), PackedStringArray(["S"]))
	for i in HintMemory.LEARN_AFTER:
		hud.hints.used("push")
	_learn("fire")
	w.press_action(BACK)
	await wait_physics_frames(40)
	assert_eq(_shown(), PackedStringArray(), "quiet once learned")


## ブロックにジャンプと W/A/S/D の単発を両方渡すと「跳んでから進む」（Space → W の予約）。
func test_jump_then_move_hint_when_a_block_holds_both() -> void:
	await _enter("w1_push_path")
	await _attach_hud()
	var lift := _block("meadow_lift")
	await _walk_to(lift.global_position + Vector3(1.4, 0.5, 0.0), 0.4)
	_lend(lift, _slot_of(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	_lend(lift, _slot_of(RuleAction.Kind.FORWARD), TriggerMode.Kind.SINGLE_SHOT)
	assert_eq(_shown(), PackedStringArray(["跳んでから進む"]))
	assert_eq(hud.context_keys(), PackedStringArray(["Space→W"]))
	_learn("jump_then_move")
	assert_eq(_shown(), PackedStringArray(["貸したWを使う"]), "then the plain fire hint")


# --- 1-4 押し石の小道: 地面にも渡せる -----------------------------------------------


## 段のふちの下で「地面にも渡せる」。地面に渡すと数える。投げるは、まだ持っていない。
func test_push_path_spot_teaches_lending_to_the_ground() -> void:
	await _enter("w1_push_path")
	assert_eq(_slot_of(RuleAction.Kind.THROW), -1, "throw is taught later (1-5)")
	await _attach_hud()
	await _walk_to(Vector3(-2.5, 0.0, 1.0), 0.4)
	assert_eq(_shown(), PackedStringArray(["地面にも渡せる"]))
	assert_eq(hud.context_keys(), PackedStringArray(["左クリック"]))
	_learn("ground")
	assert_eq(_shown(), PackedStringArray(), "gone once learned")


# --- 1-5 丘の上の旗: 投げる ---------------------------------------------------------


## 小島の生き物は、触る届き方では届かず、幅 14 の空は走って跳んでも、重ね跳び（約 8.4 m）に
## ダッシュ（3 マス）を足しても越えない。だから「投げる」が要る。
func test_hill_islet_critter_needs_a_throw() -> void:
	await _enter(StageCatalog.HILL_ID)
	var critter := _creature("islet_critter")
	var slot := await _take_the_spare_s()
	await _walk_to(Vector3(9.3, 0.0, 5.5), 0.3)
	assert_false(w.is_within_reach(critter), "out of touch reach from the beach's edge")
	w.select_slot(slot)
	assert_ne(w.lend_to(critter, false), RuleLedger.LendResult.OK, "touch cannot give it")
	var gap := float(OpenIslands.HILL_ISLET_X0 - 10)
	assert_gt(gap, 8.4 + Tuning.DASH_CELLS + 1.0, "no jump-and-dash crosses the gap")
	assert_false(await _try_walk_to(critter.global_position, 0.6, 200), "cannot walk over")
	assert_false(critter.can_walk(), "the critter still waits")


## 浜の東の端の近くで「投げると遠くへ届く」、生き物を狙うと「[C] 投げるで届く」。投げると数える。
func test_hill_spot_and_aim_teach_throwing() -> void:
	await _enter(StageCatalog.HILL_ID)
	await _attach_hud()
	await _walk_to(Vector3(8.5, 0.0, 6.2), 0.3)
	assert_eq(_shown(), PackedStringArray(["投げると遠くへ届く"]))
	assert_eq(hud.context_keys(), PackedStringArray(["C"]))
	var critter := _creature("islet_critter")
	assert_eq(_shown(critter), PackedStringArray(["投げるで届く"]), "aiming beats the spot")
	_learn("throw")
	assert_eq(_shown(), PackedStringArray(), "gone once learned")


## 装備を拾うと「[E] そうびする」。身につけたら消える（ホットバー・かばんの装備は効かない）。
func test_hill_equipment_hint_until_worn() -> void:
	await _enter(StageCatalog.HILL_ID)
	await _attach_hud()
	_learn("throw")
	await _walk_to(Vector3(8.5, 0.0, 3.5), 0.6)
	await _walk_to(Vector3(8.5, 1.0, 1.5))
	await _walk_to(Vector3(8.5, 2.0, -0.5))
	await _walk_to(Vector3(8.5, 3.0, -3.5))
	await _walk_to(Vector3(7.5, 3.0, -5.0), 0.6)
	w.interact(null)
	await wait_physics_frames(2)
	await _walk_to(Vector3(8.5, 3.0, -3.5), 0.4)
	assert_eq(_shown(), PackedStringArray(["そうびする"]))
	assert_eq(hud.context_keys(), PackedStringArray(["E"]))
	# 拾ったブーツは身につけずにホットバーへ入っている（2026-11-23。ADR 0021）
	for v in carried(w.ledger, _me().player_id):
		if v.part == RuleVessel.Part.FEET:
			assert_eq(v.location, RuleVessel.Location.HOTBAR, "the boots sit on the hotbar")
			assert_true(w.ledger_actions.equip(v.id), "wear the boots")
	assert_eq(_shown(), PackedStringArray(), "worn: the hint is learned")
	assert_false(hud.hints.should_show("equip"))


# --- 1-6 採石場: 禁止（上に立つ人にも効く） -----------------------------------------


## 底の石のジャンプ禁止は、その上に立つ人にも効く。F で取ると自分に効き、手放すと跳べる。
func test_quarry_banned_stone_stops_the_rider_until_the_ban_is_handed_off() -> void:
	await _enter(StageCatalog.QUARRY_ID)
	await _attach_hud()
	_learn("throw")  # 1-5 で覚えた（遠くの石を狙っても「投げるで届く」を出さない）
	var stone := _block("stone_a")
	await _walk_to(stone.global_position + Vector3(0.0, -0.5, 1.4), 0.4)
	await _walk_to(stone.global_position + Vector3(0.0, 0.5, 0.0), 0.3)
	await wait_physics_frames(30)
	assert_gt(_me().global_position.y, 0.9, "standing on the stone")
	assert_eq(_shown(), PackedStringArray(["下を見て禁止を取る"]), "the ban under my feet")
	assert_false(_me().can(JUMP), "the ban on the stone applies to its rider")
	var before := _me().global_position.y
	w.press_action(JUMP)
	await wait_physics_frames(20)
	assert_almost(_me().global_position.y, before, 0.05, "no jump on the banned stone")
	assert_eq(_shown(stone), PackedStringArray(["禁止を取る"]), "aiming at it")
	w.interact(stone)
	await wait_physics_frames(2)
	assert_false(w.ledger.player_can(JUMP, _me().player_id), "now the ban is in my hand")
	assert_eq(_shown(stone), PackedStringArray(["禁止をえらぶ"]), "how to let go: pick the ban")
	var other := _block("stone_b")
	await _walk_to(other.global_position + Vector3(-1.4, -0.5, 0.0), 0.4)
	assert_eq(_shown(other), PackedStringArray(["禁止を取る"]), "the other stone has its own ban")
	w.select_slot(_ban_slot(JUMP))
	_learn("lend")
	_hand_off_ban(JUMP, other)
	await _walk_to(stone.global_position + Vector3(0.0, 0.5, 0.0), 0.3)
	await wait_physics_frames(30)
	assert_true(_me().can(JUMP), "the freed stone lets its rider jump")


# --- 教える順番の全体 ---------------------------------------------------------------


## 能力・仕掛けが、教える順番どおりに W1 のステージに現れる（前のステージで先に使わせない）。
func test_w1_brings_each_new_thing_in_teaching_order() -> void:
	var order: Array[String] = []
	for s in CampaignPlan.built_slots(CampaignPlan.worlds()[0]):
		order.append(s.stage_id)
	assert_eq(
		order,
		(
			[
				StageCatalog.INTRO_ID,
				RELAY,
				"w1_lift_steps",
				"w1_push_path",
				StageCatalog.HILL_ID,
				StageCatalog.QUARRY_ID
			]
			as Array[String]
		)
	)
	# 投げるは 1-5 から（1-1〜1-4 のホットバーにも、落ちている物にも無い）
	for i in order.size():
		var def := StageCatalog.by_id(order[i])
		var throws := def.loadout_for(0).has(RuleAction.Kind.THROW)
		for item in def.world_items:
			throws = throws or item.action == RuleAction.Kind.THROW
		assert_eq(throws, i >= 4, "%s: throw only from 1-5" % order[i])
		# 装備は 1-5 から、禁止は 1-6 から
		var equipment := def.world_items.any(
			func(p: StageDef.PlacementSpec) -> bool: return p.part != RuleVessel.Part.NONE
		)
		assert_eq(equipment, i >= 4, "%s: equipment only from 1-5" % order[i])
		var bans := def.blocks.any(
			func(b: StageDef.BlockSpec) -> bool:
				return b.tokens.any(func(t: StageDef.TokenSpec) -> bool: return t.is_prohibition)
		)
		assert_eq(bans or not def.prohibitions.is_empty(), i == 5, "%s: bans in 1-6" % order[i])
		# 生き物は 1-3 から
		assert_eq(not def.creatures.is_empty(), i >= 2 and i != 5, "%s: animals" % order[i])
	# 1-2 と 1-3 は、だれもジャンプを持たずに始まる（1-2 で F を、1-3 で生き物から借りることを使う）
	for stage_id: String in [RELAY, "w1_lift_steps"]:
		assert_false(StageCatalog.by_id(stage_id).loadout_for(0).has(JUMP), stage_id)


## 広場: W1 で次に遊ぶポータルにだけ光の柱（はじめは導入、導入をクリアしたら 1-2）。
func test_hub_beam_points_at_the_next_w1_portal() -> void:
	var first := Overworld.build(OverworldState.first_visit())
	var nexts := first.overworld.portals.filter(
		func(p: OverworldLayout.PortalSpec) -> bool: return p.next
	)
	assert_eq(nexts.size(), 1, "one beam")
	assert_eq((nexts[0] as OverworldLayout.PortalSpec).stage_id, StageCatalog.INTRO_ID)
	var state := OverworldState.first_visit()
	state.cleared.append(StageCatalog.INTRO_ID)
	var later := Overworld.build(state)
	assert_true(later.overworld.portal(RELAY).next, "after the intro, 1-2 glows")
	assert_false(later.overworld.portal(StageCatalog.INTRO_ID).next)
