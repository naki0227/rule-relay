extends TestCase
## はじめての 10 分の通し（docs/reports/2026-11-22-first-ten-minutes.md）で見つけて直した、画面の文の不具合。
## ひとりで遊ぶ人に「全員」「チーム」と見せない・何もしていないのに断らない・内部の ID や仮の言い方を出さない。

const PROFILE := "zz_test_first_ten"
const JUMP := RuleAction.Kind.JUMP

var director: PartyDirector
var told: PackedStringArray = PackedStringArray()


func before_each() -> void:
	ProgressStore.new().delete(PROFILE)
	director = PartyDirector.new()
	director.profile = PROFILE
	tree.root.add_child(director)
	director.world_changed.connect(_listen)
	director.enter_stage(StageCatalog.INTRO_ID)
	_listen(director.world)
	await wait_physics_frames(5)


func after_each() -> void:
	director.queue_free()
	await tree.process_frame
	ProgressStore.new().delete(PROFILE)


func _listen(world: StageWorld) -> void:
	if not world.message_posted.is_connected(_note):
		world.message_posted.connect(_note)


func _note(text: String) -> void:
	told.append(InputMode.resolve(text))


func _w() -> StageWorld:
	return director.world


func _lift() -> RuleBlock:
	return _w().blocks[int(_w().entity_ids["lift"])]


func _stand_on_the_pad() -> void:
	_w().player.global_position = _w().def.checkpoints[0] + Vector3(0.0, 0.1, 0.0)
	_w().player.velocity = Vector3.ZERO
	await wait_physics_frames(8)


func test_solo_banner_has_no_vote_line() -> void:
	var banner := PartyBanner.describe(director)
	assert_eq(banner, _w().def.display_name, "solo: just the stage name")
	assert_false(banner.contains("全員"), banner)


func test_solo_checkpoint_toast_and_no_refusal_after_lending_on_the_pad() -> void:
	await _stand_on_the_pad()
	assert_ne(director.lifecycle.latest_checkpoint(), PartyLifecycle.STAGE_START, "activated")
	var joined := " ".join(told)
	assert_true(joined.contains("落ちたらここから"), joined)
	assert_false(joined.contains("全員"), "solo: no team words")
	# 台座の上から、窪みのブロックにジャンプを貸す（チェックポイントはもう有効）
	_w().select_slot(4)
	assert_eq(_w().lend_to(_lift(), false), RuleLedger.LendResult.OK)
	await wait_physics_frames(8)
	joined = " ".join(told)
	assert_false(joined.contains("できません"), "not refused for something I did not try: " + joined)
	assert_true(joined.contains("ジャンプを渡しました"), "the same verb as the hint: " + joined)
	assert_false(joined.contains("付与"), joined)
	assert_false(joined.contains("能力["), joined)


func test_coop_checkpoint_toast_still_names_the_team() -> void:
	var text := InputMode.resolve(CheckpointWatch.activated_text(2))
	assert_true(text.contains("チーム共通"), text)


func test_clear_text_and_first_clear_toast_have_no_internal_ids() -> void:
	_w().player.global_position = _lift().global_position + Vector3(0.0, 0.6, 1.4)
	await wait_physics_frames(4)
	_w().select_slot(4)
	assert_eq(_w().lend_to(_lift(), false), RuleLedger.LendResult.OK)
	_w().player.global_position = _lift().global_position + Vector3(0.0, 0.6, 0.0)
	await wait_physics_frames(4)
	_w().press_action(JUMP)
	for i in 300:
		if director.last_clear_text != "":
			break
		var at := _w().player.global_position
		var go := at.y > 2.05 or (at.y > 0.5 and at.z > -8.4)
		_w().player.move_intent = Vector2(0.0, 1.0) if go else Vector2.ZERO
		_w().player.view_yaw = 0.0
		await tree.physics_frame
	_w().player.move_intent = Vector2.ZERO
	assert_ne(director.last_clear_text, "", "cleared")
	assert_false(director.last_clear_text.contains("付与"), director.last_clear_text)
	await wait_physics_frames(5)
	var joined := " ".join(told)
	assert_true(joined.contains(PartyDirector.FIRST_CLEAR_TEXT), joined)
	assert_false(joined.contains("tmp_"), "no reward IDs on screen: " + joined)
	assert_false(PartyBanner.describe(director).contains("クリア"), "the banner stays short")


func test_token_names_match_the_hotbar() -> void:
	var t := RuleToken.new()
	t.action = JUMP
	assert_eq(t.describe(), "ジャンプ")
	t.is_prohibition = true
	assert_eq(t.describe(), "ジャンプ禁止")


## 落ちている器を拾うとかばんに入る（企画書 7）。ホットバーへ移すまで、何も狙っていなければ照準の下に
## 「E かばんの能力をホットバーへ」を出す（1-3 の頂のジャンプ）。
func test_a_picked_up_jump_points_to_the_bag_until_it_is_on_the_hotbar() -> void:
	var game := GameRoot.new()
	tree.root.add_child(game)
	game.start_solo(PROFILE)
	await wait_physics_frames(5)
	game.director.enter_stage("w1_lift_steps")
	await wait_physics_frames(5)
	var w := game.director.world
	var hud := game.current_hud()
	hud.hints.used("move")
	hud.hints.used("move")
	hud.hints.used("move")
	assert_false(hud.needs_bag_prompt(), "nothing in the bag yet")
	w.player.global_position = Vector3(4.5, 4.1, -11.5)
	w.player.velocity = Vector3.ZERO
	await wait_physics_frames(4)
	w.interact(null)
	await wait_physics_frames(3)
	assert_true(hud.needs_bag_prompt(), "the jump went into the bag")
	var joined := " ".join(hud.toasts.messages())
	assert_true(joined.contains("かばん"), joined)
	assert_false(joined.contains("通常インベントリ"), "the inventory screen says かばん: " + joined)
	# 入った直後の目的の札が大きい間は案内を出さない（TeachHints）。縮むまで待つ
	await wait_physics_frames(int((ObjectivePanel.BIG_SECONDS + 0.5) * 60.0))
	game.current_input().set_process(false)  # 照準の先によらず、何も狙っていないときの案内を見る
	hud.update_context(null, false, false)
	assert_true(hud.context_actions().has("かばんの能力をホットバーへ"), str(hud.context_actions()))
	game.current_input().set_process(true)
	for v in w.ledger.inventory_vessels(w.acting_id()):
		w.ledger_actions.move_to_hotbar(v.id, 4)
	await wait_physics_frames(3)
	assert_false(hud.needs_bag_prompt(), "gone once it is on the hotbar")
	game.shutdown()
	game.queue_free()
	await tree.process_frame
	for path: String in ["user://hints/%s.json" % PROFILE, "user://hints/%s.json.tmp" % PROFILE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## 同じ能力が 2 枠にあるとき、「×2」はその能力の最初の枠にだけ出す（両方に出すと 4 つあるように見えた）。
func test_two_jumps_show_one_times_two() -> void:
	_w().ledger.give_player_item(JUMP, false, 5, _w().acting_id())
	var hud := Hud.new()
	hud.world = _w()
	tree.root.add_child(hud)
	await tree.process_frame
	hud.refresh()
	var stacks := hud.hotbar_stacks()
	assert_eq(stacks[4], 2, "the first jump slot says x2")
	assert_eq(stacks[5], 0, "the second one does not repeat it")
	hud.queue_free()
