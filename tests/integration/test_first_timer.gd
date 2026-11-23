extends TestCase
## 初めて遊ぶ人の最初の数分（ひとりで遊ぶ → ハブ → 導入「跳ぶ力を貸す」→ クリア → ハブ）を、
## 画面の案内に従って進める（docs/onboarding.md）。案内がちょうどよい時に出て、その操作をしたら
## 「1回使った」と記録され、慣れたら消えることを確かめる。
## 入力はゲームと同じ PlayerInput を通す（Input.parse_input_event / Input.action_press）。
## 道のり（入口・台座・ブロックの前まで歩く）だけは、テストを安定させるため置き直す。
## 照準は test_goal_probes と同じく、カメラを向けて GameWorld.aimed_block() の光線で決める。

const PROFILE := "zz_test_first_timer"
const HINT_FILE := "user://hints/zz_test_first_timer.json"
const JUMP := RuleAction.Kind.JUMP

var game: GameRoot


func before_each() -> void:
	_clean()
	InputMap.load_from_project_settings()
	InputMode.using_pad = false
	game = GameRoot.new()
	tree.root.add_child(game)
	# 設定ファイルの割り当てに左右されないよう、初期の割り当てで始める
	InputMap.load_from_project_settings()
	game.start_solo(PROFILE)
	await wait_physics_frames(5)


func after_each() -> void:
	for action: StringName in [&"move_forward", &"move_right", &"camera_right", &"vote_reset"]:
		Input.action_release(action)
	tree.paused = false
	InputMode.using_pad = false
	InputMap.load_from_project_settings()
	game.shutdown()
	game.queue_free()
	await tree.process_frame
	_clean()


func _clean() -> void:
	ProgressStore.new().delete(PROFILE)
	for path: String in [HINT_FILE, HINT_FILE + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# --- 道具 ---------------------------------------------------------------------


func _world() -> StageWorld:
	return game.director.world


func _hud() -> Hud:
	return game.current_hud()


func _hints() -> HintMemory:
	return game.current_hud().hints


func _shown() -> PackedStringArray:
	await wait_physics_frames(2)
	return _hud().context_actions()


## 押して離す（ゲームの PlayerInput が受け取る）。
func _press(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await tree.process_frame


func _hold(action: StringName, frames: int) -> void:
	Input.action_press(action)
	await wait_physics_frames(frames)
	Input.action_release(action)
	await wait_physics_frames(2)


func _put(at: Vector3) -> void:
	var me := _world().player
	me.global_position = at
	me.velocity = Vector3.ZERO
	await wait_physics_frames(4)


## カメラを point へ向け、照準が target に合うまで高さを少しずつ変える（マウスで狙うのと同じ）。
func _aim_at(target: Node3D) -> bool:
	var w := _world()
	for h: float in [0.0, 0.2, 0.4, -0.2, 0.6]:
		var eye := w.player.global_position + Vector3(0.0, 1.5, 0.0)
		var dir := (target.global_position + Vector3(0.0, h, 0.0) - eye).normalized()
		w.camera_rig.yaw = atan2(-dir.x, -dir.z)
		w.camera_rig.pitch = clampf(asin(dir.y), CameraRig.MIN_PITCH, CameraRig.MAX_PITCH)
		await wait_physics_frames(2)
		if w.aimed_block() == target:
			return true
	return false


func _enter_intro() -> void:
	var entrance: StageDef.EntranceSpec = _world().def.entrances[0]
	await _put(entrance.position + Vector3(0.0, 0.1, 0.0))
	await _press(&"interact")
	await wait_physics_frames(5)
	await _wait_objectives_small()


## ステージに入った直後の目的の札が大きく出ている間は、案内を重ねない（TeachHints）。縮むまで待つ。
func _wait_objectives_small() -> void:
	var panel := _hud().get_node_or_null(^"Objectives") as ObjectivePanel
	for i in 400:
		if panel == null or not panel.is_big():
			return
		await tree.process_frame


func _learn(keys: Array[String]) -> void:
	for key: String in keys:
		for i: int in HintMemory.LEARN_AFTER:
			_hints().used(key)


func _lift() -> RuleBlock:
	var w := _world()
	return w.blocks[int(w.entity_ids["lift"])]


# --- 通しの試遊 ---------------------------------------------------------------


func test_a_first_timer_follows_the_hints_from_the_hub_to_the_clear() -> void:
	# 1. ハブ: 最初は「歩く」だけ（案内は 1 つずつ）。最初に正面に見える入口は導入
	assert_eq(_world().def.stage_id, StageCatalog.HUB_ID)
	assert_eq(await _shown(), PackedStringArray(["歩く"]), "only the first step")
	assert_eq(_hud().context_keys(), PackedStringArray(["W/A/S/D"]))
	var first: StageDef.EntranceSpec = _world().def.entrances[0]
	assert_eq(first.stage_id, StageCatalog.INTRO_ID)
	var ahead := first.position - _world().player.global_position
	assert_lt(absf(ahead.x), 0.6, "the intro entrance is straight ahead of the spawn")
	assert_lt(ahead.z, 0.0, "and the camera starts facing it (north)")

	# 2. 歩くと「見回す」に変わり、見回すと消える（記録される）
	await _hold(&"move_right", 200)
	assert_false(_hints().should_show("move"), "walked for a few seconds")
	assert_eq(await _shown(), PackedStringArray(["見回す"]), "then looking around")
	assert_eq(_hud().context_keys(), PackedStringArray(["マウス"]))
	await _hold(&"camera_right", 75)
	assert_false(_hints().should_show("look"), "looked around")
	assert_eq(await _shown(), PackedStringArray(), "nothing left on screen in the open hub")
	_world().camera_rig.yaw = 0.0

	# 3. 入口に立つと「F 入る」が出る。F で導入へ
	await _put(first.position + Vector3(0.0, 0.1, 0.0))
	assert_true((await _shown()).has("「跳ぶ力を貸す」へ"))
	await _press(&"interact")
	await wait_physics_frames(5)
	assert_eq(game.director.stage_id, StageCatalog.INTRO_ID)
	assert_eq(_hints().uses("recall"), 0, "entering a stage is not a recall")
	assert_eq(await _shown(), PackedStringArray(), "no hint over the big objective card")
	await _wait_objectives_small()
	assert_false(_hints().should_show("move"), "the new island's HUD keeps the same record")

	# 4. 小段差の手前でその方を向くと「ジャンプ」。跳ぶと数える
	await _put(Vector3(0.5, 0.1, 1.6))
	_world().camera_rig.yaw = 0.0
	assert_eq(await _shown(), PackedStringArray(["ジャンプ"]), "a step you can hop")
	assert_eq(_hud().context_keys(), PackedStringArray(["Space"]))
	await _press(&"jump")
	assert_eq(_hints().uses("jump"), 1)
	await wait_physics_frames(40)

	# 5. 道なりの台座でチェックポイントを知る（知らせが出る）
	await _put(Vector3(0.5, 1.1, 0.0))  # 小段差の上（台座の手前）から北へ歩く
	await _hold(&"move_forward", 30)
	await wait_physics_frames(5)
	assert_eq(game.director.lifecycle.latest_checkpoint(), "cp0", "walked over the pad")
	var told := " ".join(_hud().toasts.messages())
	assert_true(told.contains("チェックポイント"), told)
	assert_true(told.contains("落ちたらここから"), "solo: what the pad means for me")
	assert_false(told.contains("全員"), "solo: no team words")

	# 6. 窪みのブロックを狙う: 最初は W が選ばれているので「[5] ジャンプをえらぶ」。選ぶと「ジャンプを渡す」
	var lift := _lift()
	await _put(lift.global_position + Vector3(0.0, 0.6, 1.4))
	assert_true(await _aim_at(lift), "can aim at the block in the hollow")
	assert_eq(await _shown(), PackedStringArray(["ジャンプをえらぶ"]))
	assert_eq(_hud().context_keys(), PackedStringArray(["5"]))
	await _press(&"slot_5")
	assert_eq(_hints().uses("select"), 1)
	assert_eq(await _shown(), PackedStringArray(["ジャンプを渡す"]))

	# 7. 渡す（単発）。手元のジャンプが減り、「[Space] 貸したジャンプを使う」だけが出る
	await _press(&"lend_single")
	assert_eq(_hints().uses("lend"), 1)
	assert_false(_world().ledger.player_can(JUMP), "the jump went to the block")
	assert_eq(await _shown(), PackedStringArray(["貸したジャンプを使う"]), "one hint at a time")
	assert_eq(_hud().context_keys(), PackedStringArray(["Space"]))

	# 8. ブロックに乗って Space: ブロックが跳ぶ。頂点で岩棚へ歩き、ゴールの窪みに降りる
	await _put(lift.global_position + Vector3(0.0, 0.6, 0.0))
	_world().camera_rig.yaw = 0.0
	await _press(&"jump")
	assert_eq(_hints().uses("fire"), 1)
	for i: int in 300:
		if game.director.last_clear_text != "":
			break
		var at := _world().player.global_position
		# 岩棚に上がったら前へ。窪みに降りたあとも、ゴールの真ん中（z -8.5 付近）まで歩く
		if at.y > 2.05 or (at.y > 0.5 and at.z > -8.4):
			Input.action_press(&"move_forward")
		else:
			Input.action_release(&"move_forward")
		await tree.physics_frame
	Input.action_release(&"move_forward")
	assert_ne(game.director.last_clear_text, "", "cleared in the goal hollow")
	assert_true(_world().ledger.player_can(JUMP), "the single shot came back")
	assert_false((await _shown()).has("貸したジャンプを使う"), "nothing left to fire")

	# 9. しばらくしてハブへ戻る。慣れた案内は戻っても出ない
	await wait_physics_frames(int(PartyDirector.RETURN_DELAY * 60.0) + 10)
	assert_eq(game.director.stage_id, StageCatalog.HUB_ID)
	assert_false((await _shown()).has("歩く"), "learned hints stay learned")


## 自分が渡したブロックは「[F] 取り戻す」。取り戻したときだけ数え、慣れたら消える。
func test_recall_hint_counts_only_real_recalls() -> void:
	await _enter_intro()
	_learn(["move", "look", "fire", "jump"])
	var lift := _lift()
	await _put(lift.global_position + Vector3(0.0, 0.6, 1.4))
	assert_true(await _aim_at(lift))
	await _press(&"slot_5")
	for turn: int in HintMemory.LEARN_AFTER:
		await _press(&"lend_single")
		assert_eq(await _shown(), PackedStringArray(["取り戻す"]), "round %d" % turn)
		await _press(&"interact")
		assert_eq(_hints().uses("recall"), turn + 1)
		assert_true(_world().ledger.player_can(JUMP), "recalled into the hand")
	assert_false((await _shown()).has("取り戻す"), "learned after %d recalls" % HintMemory.LEARN_AFTER)


## 目安の時間を過ぎたら「V 長押しでやり直し」「Esc メニュー」をそっと出す。使ったら一度消える。
func test_retry_hints_appear_only_after_the_target_time() -> void:
	await _enter_intro()
	_learn(["move", "look", "jump"])
	await _put(Vector3(-1.5, 0.1, 4.5))
	assert_false((await _shown()).has("長押しでやり直し"), "not before the target time")
	_hud().stage_seconds = _world().def.target_minutes * 60.0 + 1.0
	assert_eq(await _shown(), PackedStringArray(["長押しでやり直し"]), "one at a time")
	assert_eq(_hud().context_keys(), PackedStringArray(["V"]))
	await _hold(&"vote_reset", int(HoldAction.new().hold_seconds * 60.0) + 10)
	assert_eq(game.director.lifecycle.reset_count(), 1, "the solo vote resets at once")
	assert_eq(_hints().uses("vote"), 1)
	assert_eq(await _shown(), PackedStringArray(), "quiet again after use")
	_learn(["vote"])
	_hud().stage_seconds = _world().def.target_minutes * 60.0 + 1.0
	assert_eq(await _shown(), PackedStringArray(["メニュー"]), "then the menu")
	assert_eq(_hud().context_keys(), PackedStringArray(["Esc"]))
	await _press(&"restore_checkpoint")
	assert_true(_hud().pause_menu.is_open())
	assert_eq(_hints().uses("menu"), 1)
	_hud().pause_menu.close()


## ゲームパッドでも、割り当て直したキーでも、同じ案内が今の入力の表記で出る。
func test_hints_follow_the_pad_and_rebinding() -> void:
	await _enter_intro()
	InputMode.using_pad = true
	assert_eq(await _shown(), PackedStringArray(["歩く"]))
	assert_eq(_hud().context_keys(), PackedStringArray(["左スティック"]))
	_learn(["move"])
	assert_eq(await _shown(), PackedStringArray(["見回す"]))
	assert_eq(_hud().context_keys(), PackedStringArray(["右スティック"]))
	_learn(["look", "jump"])
	var lift := _lift()
	await _put(lift.global_position + Vector3(0.0, 0.6, 1.4))
	assert_true(await _aim_at(lift))
	assert_eq(await _shown(), PackedStringArray(["ジャンプをえらぶ"]))
	assert_eq(_hud().context_keys(), PackedStringArray(["LB / RB"]))
	_world().select_slot(4)
	assert_eq(await _shown(), PackedStringArray(["ジャンプを渡す"]))
	assert_eq(_hud().context_keys(), PackedStringArray(["RT"]))
	_world().lend_to(lift, false)
	var shown := await _shown()
	assert_eq(_hud().context_keys()[shown.find("貸したジャンプを使う")], "A")
	# キーボードで、ジャンプを J に割り当て直す
	InputMode.using_pad = false
	var key := InputEventKey.new()
	key.physical_keycode = KEY_J
	for event: InputEvent in InputMap.action_get_events(&"jump"):
		if event is InputEventKey:
			InputMap.action_erase_event(&"jump", event)
	InputMap.action_add_event(&"jump", key)
	shown = await _shown()
	assert_eq(_hud().context_keys()[shown.find("貸したジャンプを使う")], "J")
