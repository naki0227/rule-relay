extends SceneTree
## はじめての 10 分を、人の速さで通して撮る（docs/reports/2026-11-22-first-ten-minutes.md）。
## タイトル → ひとりで遊ぶ → 広場 → 最初のポータル → 1-1〜1-4（入る・目的を読む・渡す・F で回収・解く・クリア）
## → 広場のポータルの前 → 一時停止のメニュー・持ち物・せってい を 1 回ずつ。
## 入力はゲームと同じ Input（キーの押し下げ・押し離し）を通す。瞬間移動はしない。視点はマウスと同じく
## camera_rig の向きを少しずつ（1 秒に最大 4.5 rad）回す。持ち物の中の並べ替えだけは、マウスで指す代わりに
## 選んだ状態にしてから番号キーを押す。
## 撮り方（lavapipe ＋ xvfb で Forward+。HUD も入ったゲーム本体の画面）:
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver vulkan --resolution 1280x720 --fixed-fps 60 \
##     --script res://tools/capture_first_ten_minutes.gd -- <出力のフォルダ>
## 出力: <フォルダ>/NN-名前.png と、各場面の画面の文字（札・案内・知らせ・目的）を書いた moments.txt。

const PROFILE := "zz_first_ten"
const HINT_FILE := "user://hints/zz_first_ten.json"
const TURN_SPEED := 4.5
const JUMP := RuleAction.Kind.JUMP

var game: GameRoot
var out_dir := "docs/reports/first-ten-minutes"
var shot := 0
var log_lines := PackedStringArray()
var started_ms := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_clean()
	started_ms = Time.get_ticks_msec()
	game = (load("res://scenes/prototype_island.tscn") as PackedScene).instantiate() as GameRoot
	root.add_child(game)
	await _wait(40)
	RenderingServer.render_loop_enabled = false
	await _title()
	if args.size() > 1 and args[1].begins_with("only="):
		# 1 つのステージだけ撮り直す（only=w1_lift_steps など。広場を歩かずに進行役で入る）
		var only := args[1].trim_prefix("only=")
		shot = int(args[2]) - 1 if args.size() > 2 else 0
		await _seconds(1.0)
		game.director.enter_stage(only)
		await _wait(20)
		var stages := {
			StageCatalog.RELAY_ID: _stage_relay,
			"w1_lift_steps": _stage_lift_steps,
			"w1_push_path": _stage_push_path,
		}
		await (stages[only] as Callable).call()
		_finish()
		return
	if args.size() > 1 and args[1] == "from-1-4":
		# 1-4 だけ撮り直す（広場からポータルで入る代わりに、進行役でそのステージへ入る）
		shot = 37
		await _seconds(1.0)
		game.director.enter_stage("w1_push_path")
		await _wait(20)
	else:
		await _hub_to_first_portal()
		await _stage_intro()
		await _back_in_hub_then_walk_to(StageCatalog.RELAY_ID)
		await _stage_relay()
		await _back_in_hub_then_walk_to("w1_lift_steps")
		await _stage_lift_steps()
		await _back_in_hub_then_walk_to("w1_push_path")
	await _stage_push_path()
	await _back_in_hub_and_menus()
	_finish()


func _finish() -> void:
	_note("done", "total game frames ~%d" % Engine.get_physics_frames())
	var file := FileAccess.open(out_dir.path_join("moments.txt"), FileAccess.WRITE)
	file.store_string("\n".join(log_lines) + "\n")
	file.close()
	_clean()
	quit()


func _clean() -> void:
	ProgressStore.new().delete(PROFILE)
	for path: String in [HINT_FILE, HINT_FILE + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# --- 道具 -----------------------------------------------------------------------


func _w() -> StageWorld:
	return game.director.world


func _hud() -> Hud:
	return game.current_hud()


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _seconds(s: float) -> void:
	await _wait(int(s * 60.0))


## 押して離す（人の短い押し方: 6 フレーム ≒ 0.1 秒）。
func _tap(action: StringName, frames: int = 6) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await _wait(frames)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await _wait(2)


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await _wait(4)


## 撮って、その場面で画面に出ている文字を書き残す。
func _cap(name: String, note: String = "") -> void:
	shot += 1
	# 撮るときだけ描く（ソフトウェア描画は 1 フレームが重いので、間は描かずに進める。ゲームの時間は
	# --fixed-fps で 1 フレーム 1/60 秒のまま進むので、動きの速さは変わらない）
	RenderingServer.render_loop_enabled = true
	for i in 3:
		await process_frame
	var file := "%02d-%s.png" % [shot, name]
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join(file))
	var lines := PackedStringArray(["## %s  (%s)" % [file, _clock()]])
	if note != "":
		lines.append("note: " + note)
	var hud := _hud()
	if hud != null:
		lines.append("context: %s / %s" % [hud.context_keys(), hud.context_actions()])
		lines.append("target: " + hud.context_target_name())
		lines.append("toasts: %s" % [hud.toasts.messages()])
		var objectives := hud.get_node_or_null("Objectives") as ObjectivePanel
		if objectives != null:
			lines.append("objectives: %s big=%s" % [objectives.lines(), objectives.is_big()])
	if game.director != null and game.director.world != null:
		lines.append("banner: " + PartyBanner.describe(game.director).replace("\n", " / "))
		lines.append("stage: %s at %s" % [game.director.stage_id, _w().player.global_position])
	log_lines.append("\n".join(lines))
	print("[shot] ", file, " ", note)
	RenderingServer.render_loop_enabled = false


func _note(name: String, text: String) -> void:
	log_lines.append("## (%s) %s: %s" % [_clock(), name, text])
	print("[note] ", name, ": ", text)


func _clock() -> String:
	var s := Engine.get_physics_frames() / 60
	return "%d:%02d" % [s / 60, s % 60]


## 視点を少しずつ回す（マウスで回すのと同じ速さの上限）。
func _turn_to(yaw: float, pitch: float = NAN) -> void:
	var rig := _w().camera_rig
	for i in 120:
		var dy := angle_difference(rig.yaw, yaw)
		var step := TURN_SPEED / 60.0
		rig.yaw += clampf(dy, -step, step)
		if not is_nan(pitch):
			rig.pitch += clampf(pitch - rig.pitch, -step, step)
		await physics_frame
		if absf(dy) < step and (is_nan(pitch) or absf(pitch - rig.pitch) < step):
			return


func _yaw_to(target: Vector3) -> float:
	var me := _w().player.global_position
	return atan2(-(target.x - me.x), -(target.z - me.z))


## target へ歩く: 視点をそちらへ向けながら W を押し続ける。段差で止まったら Space（人と同じ）。
func _walk_to(target: Vector3, tolerance: float = 0.4, limit: int = 1500) -> bool:
	var rig := _w().camera_rig
	var stuck := 0
	var holding := false
	for i in limit:
		var me := _w().player
		var flat := Vector3(target.x - me.global_position.x, 0.0, target.z - me.global_position.z)
		if flat.length() <= tolerance and absf(me.global_position.y - target.y) < 0.8:
			break
		var want := atan2(-flat.x, -flat.z)
		var dy := angle_difference(rig.yaw, want)
		rig.yaw += clampf(dy, -TURN_SPEED / 60.0, TURN_SPEED / 60.0)
		var go := absf(dy) < 0.7
		if go != holding:
			if go:
				Input.action_press(&"move_forward")
			else:
				Input.action_release(&"move_forward")
			holding = go
		var moving := Vector2(me.velocity.x, me.velocity.z).length() > 0.5
		stuck = 0 if moving or not go else stuck + 1
		if stuck > 10 and me.is_on_floor():
			await _tap(&"jump", 4)
			stuck = 0
		await physics_frame
	Input.action_release(&"move_forward")
	await _wait(6)
	var p := _w().player.global_position
	var ok := Vector2(target.x - p.x, target.z - p.z).length() <= tolerance + 0.3
	if not ok:
		_note("walk", "could not reach %s (at %s)" % [target, p])
	return ok


## 照準を target に合わせる（向きと高さを少しずつ変える。マウスで狙うのと同じ）。
func _aim(target: Node3D, cell: Variant = null) -> bool:
	var w := _w()
	var base := target.global_position if cell == null else Vector3(cell) + Vector3(0.5, 1.0, 0.5)
	await _turn_to(_yaw_to(base), -0.4)
	for h: float in [0.0, 0.3, -0.3, 0.6, -0.6, 0.9, 1.2]:
		for dyaw: float in [0.0, 0.08, -0.08, 0.16, -0.16]:
			var eye := w.player.global_position + Vector3(0.0, CameraRig.PIVOT_HEIGHT, 0.0)
			var dir := (base + Vector3(0.0, h, 0.0) - eye).normalized()
			w.camera_rig.yaw = atan2(-dir.x, -dir.z) + dyaw
			w.camera_rig.pitch = clampf(asin(dir.y), CameraRig.MIN_PITCH, CameraRig.MAX_PITCH)
			await _wait(2)
			var aimed := w.aimed_block()
			if cell == null and aimed == target:
				return true
			if cell != null and aimed is TerrainCell and (aimed as TerrainCell).cell == cell:
				return true
	_note("aim", "could not aim at %s %s" % [target, cell])
	return false


func _slot_of(action: RuleAction.Kind) -> int:
	var w := _w()
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(slot, w.acting_id())
		if v != null and not w.ledger.token(v.token_id).is_prohibition:
			if w.ledger.token(v.token_id).action == action:
				return slot
	return -1


func _select(action: RuleAction.Kind) -> void:
	var slot := _slot_of(action)
	if slot >= 0 and _w().selected_slot != slot:
		await _tap(StringName("slot_%d" % (slot + 1)))


## 発動方式を Q で回して合わせる。
func _mode(kind: TriggerMode.Kind) -> void:
	for i in 3:
		if _w().lend_mode == kind:
			return
		await _tap(&"cycle_mode")


func _block(key: String) -> RuleBlock:
	return _w().blocks[int(_w().entity_ids[key])]


func _creature(key: String) -> Creature:
	return _w().creatures[int(_w().entity_ids[key])]


## かばんに入った能力を E で開いてホットバーの空きへ（指して番号キー）。開いた画面を撮る。
func _bag_to_hotbar(action: RuleAction.Kind, shot_name: String = "") -> void:
	var in_bag := false
	for v in _w().ledger.inventory_vessels(_w().acting_id()):
		var t := _w().ledger.token(v.token_id)
		in_bag = in_bag or (t.action == action and not t.is_prohibition)
	if not in_bag:
		return  # ブロック・生き物から F で取った能力は、すぐホットバーに入る（PR #88）
	await _tap(&"inventory")
	await _seconds(0.6)
	var w := _w()
	var free := -1
	for slot in RuleLedger.HOTBAR_SIZE:
		if w.ledger.hotbar_vessel(slot, w.acting_id()) == null:
			free = slot
			break
	for v in w.ledger.inventory_vessels(w.acting_id()):
		var t := w.ledger.token(v.token_id)
		if t.action == action and not t.is_prohibition:
			_hud().inventory.select_vessel(v.id)
	await _seconds(0.4)
	if shot_name != "":
		await _cap(shot_name, "inventory open with the picked-up ability in the bag")
	await _key(KEY_1 + free as Key)
	await _seconds(0.5)
	await _tap(&"inventory")
	await _seconds(0.3)


## 窪みのブロック（持ち上げ台）にジャンプを単発で渡し、乗って Space、高くなったら上の段へ。
func _lift_up(key: String, beside: Vector3, onto: Vector3, shots: bool = false) -> void:
	var lift := _block(key)
	await _walk_to(beside)
	await _aim(lift)
	await _select(JUMP)
	await _mode(TriggerMode.Kind.SINGLE_SHOT)
	await _tap(&"lend_single")
	await _seconds(0.4)
	await _walk_to(lift.global_position + Vector3(0.0, 0.5, 0.0), 0.25)
	await _turn_to(_yaw_to(onto))
	await _tap(&"jump", 4)
	var holding := false
	for i in 400:
		var me := _w().player
		var flat := Vector3(onto.x - me.global_position.x, 0.0, onto.z - me.global_position.z)
		if flat.length() < 0.5 and me.global_position.y > onto.y - 0.2:
			break
		var go := me.global_position.y > onto.y - 0.05 or holding and not me.is_on_floor()
		if go != holding:
			if go:
				Input.action_press(&"move_forward")
			else:
				Input.action_release(&"move_forward")
			holding = go
		if shots and i == 14:
			await _cap("%s-riding" % key, "riding the lift")
		await physics_frame
	Input.action_release(&"move_forward")
	await _wait(10)


func _wait_clear(frames: int = 900) -> bool:
	for i in frames:
		if game.director.last_clear_text != "":
			return true
		await physics_frame
	_note("clear", "not cleared yet in %s" % game.director.stage_id)
	return false


func _goal_center() -> Vector3:
	var goal := _w().def.clear_condition.goal_area()
	var c := goal.get_center()
	return Vector3(c.x, goal.position.y + 0.1, c.z)


## 入った直後: 目的を読む（大きく出た一覧を撮り、隅へ縮んだ後も撮る）。
func _read_objectives(tag: String) -> void:
	await _seconds(0.8)
	await _cap("%s-enter" % tag, "just entered; big objective card")
	await _seconds(ObjectivePanel.BIG_SECONDS + 0.5)
	await _cap("%s-look" % tag, "objective shrank to the corner; first look at the island")


## 広場で、ポータルの台まで歩いて F。
func _enter_portal(stage_id: String) -> void:
	var portal: Vector3 = _w().def.overworld.portal(stage_id).position
	await _walk_to(portal + Vector3(0.0, 0.1, 0.0), 0.5)
	await _seconds(0.5)
	await _cap("portal-%s" % stage_id, "standing on the portal")
	await _tap(&"interact")
	await _wait(20)


# --- 場面 -----------------------------------------------------------------------


func _title() -> void:
	await _cap("title", "launch: title screen")
	var title := game.get_node("Title") as TitleMenu
	for child in title.menu_box().get_children():
		if child is LineEdit:
			(child as LineEdit).text = PROFILE
			break
	await _seconds(1.0)
	# 焦点は「ひとりで遊ぶ」。Enter で決める
	await _key(KEY_ENTER)
	await _wait(30)
	if game.director == null:
		_note("title", "Enter did not start; pressing the button")
		for child in title.menu_box().get_children():
			if child is Button and (child as Button).text == "ひとりで遊ぶ":
				(child as Button).pressed.emit()
		await _wait(30)


func _hub_to_first_portal() -> void:
	await _seconds(1.0)
	await _cap("hub-arrive", "first frame in the hub")
	# 見回す（マウスで右へ半周、戻る）
	var rig := _w().camera_rig
	var start := rig.yaw
	await _turn_to(start + 2.2)
	await _cap("hub-look-around", "looked right")
	await _turn_to(start)
	await _seconds(0.5)
	var portal: Vector3 = _w().def.overworld.portal(StageCatalog.INTRO_ID).position
	var me := _w().player.global_position
	await _walk_to(me.lerp(portal, 0.5))
	await _cap("hub-walk", "halfway to the first portal")
	await _enter_portal(StageCatalog.INTRO_ID)


func _stage_intro() -> void:
	await _read_objectives("1-1")
	var w := _w()
	# 小段差を越え、台座を踏んで、ブロックの手前へ
	await _walk_to(Vector3(0.5, 1.0, 0.0))
	await _walk_to(Vector3(0.5, 0.0, -2.0), 0.5)
	await _seconds(0.4)
	await _cap("1-1-checkpoint", "walked over the checkpoint pad")
	var lift := _block("lift")
	await _walk_to(lift.global_position + Vector3(0.0, 0.6, 1.6), 0.3)
	await _aim(lift)
	await _seconds(0.5)
	await _cap("1-1-aim-block", "aiming at the lift block with W selected")
	await _select(JUMP)
	await _seconds(0.3)
	await _cap("1-1-select-jump", "pressed 5")
	await _tap(&"lend_single")
	await _seconds(0.4)
	await _cap("1-1-lent", "lent the jump (single shot)")
	# F で回収してみる → もう一度渡す
	await _tap(&"interact")
	await _seconds(0.5)
	await _cap("1-1-recalled", "pressed F: recalled")
	await _tap(&"lend_single")
	await _seconds(0.4)
	await _walk_to(lift.global_position + Vector3(0.0, 0.5, 0.0), 0.25)
	await _turn_to(0.0, deg_to_rad(-15.0))
	await _tap(&"jump", 4)
	await _wait(12)
	await _cap("1-1-riding", "the lift is jumping")
	# 動いている最中に W を押す（人は早めに押す）
	var holding := false
	for i in 300:
		if game.director.last_clear_text != "":
			break
		var at := _w().player.global_position
		var go := at.y > 2.0 or (at.y > 0.5 and at.z > -8.4)
		if go != holding:
			if go:
				Input.action_press(&"move_forward")
			else:
				Input.action_release(&"move_forward")
			holding = go
		await physics_frame
	Input.action_release(&"move_forward")
	await _walk_to(_goal_center(), 0.6, 300)
	await _wait_clear()
	await _seconds(0.6)
	await _cap("1-1-clear", "cleared")
	await _seconds(PartyDirector.RETURN_DELAY + 0.6)
	if w == _w():
		_note("1-1", "still in the stage after the return delay")


func _back_in_hub_then_walk_to(stage_id: String) -> void:
	await _wait(30)
	await _cap("hub-return-before-%s" % stage_id, "back in the hub in front of the cleared portal")
	await _enter_portal(stage_id)


func _stage_relay() -> void:
	await _read_objectives("1-2")
	# 出現地点のすぐ前の「ジャンプの台」から F でジャンプを取る（ホットバーに入る。PR #88）
	var post := _block("jump_post")
	await _walk_to(post.global_position + Vector3(0.0, -0.5, 1.6), 0.4)
	await _seconds(0.3)
	await _cap("1-2-post", "standing by the jump post")
	await _aim(post)
	await _tap(&"interact")
	await _seconds(0.5)
	await _cap("1-2-took", "took the jump with F")
	# 段へ（自分のジャンプで 1 段）
	await _walk_to(Vector3(-0.5, 1.0, -3.5), 0.4)
	# はねる台（繰り返しのジャンプ）に跳び乗り、上がったところで岩棚へ。人と同じく、台が下りたのを見て跳ぶ
	var bouncer := _block("bouncer")
	var top := bouncer.global_position + Vector3(0.0, 0.5, 0.0)
	var tries := 0
	for attempt in 8:
		tries += 1
		await _walk_to(Vector3(top.x, 1.0, top.z + 1.4), 0.3)
		await _turn_to(_yaw_to(top))
		for i in 240:
			if bouncer.is_grounded():
				break
			await physics_frame
		Input.action_press(&"move_forward")
		await _tap(&"jump", 4)
		await _wait(14)
		Input.action_release(&"move_forward")
		if attempt == 0:
			await _cap("1-2-bouncer", "jumping onto the bouncing block")
		await _wait(20)
		var me := _w().player.global_position
		var flat := Vector2(me.x - bouncer.global_position.x, me.z - bouncer.global_position.z)
		if flat.length() < 0.6 and me.y > bouncer.global_position.y + 0.3:
			break
	_note("1-2", "bouncer: on it after %d tries" % tries)
	var onto := Vector3(top.x, 3.0, -6.6)
	await _turn_to(_yaw_to(onto))
	var holding := false
	for i in 600:
		var me := _w().player
		var flat := Vector3(onto.x - me.global_position.x, 0.0, onto.z - me.global_position.z)
		if flat.length() < 0.5 and me.global_position.y > onto.y - 0.2:
			break
		var go := me.global_position.y > onto.y - 0.05 or holding and not me.is_on_floor()
		if go != holding:
			if go:
				Input.action_press(&"move_forward")
			else:
				Input.action_release(&"move_forward")
			holding = go
		await physics_frame
	Input.action_release(&"move_forward")
	await _walk_to(_goal_center(), 0.8, 400)
	await _wait_clear()
	await _seconds(0.6)
	await _cap("1-2-clear", "cleared")
	await _seconds(PartyDirector.RETURN_DELAY + 0.6)


func _stage_lift_steps() -> void:
	await _read_objectives("1-3")
	var critter := _creature("critter")
	await _walk_to(critter.global_position + Vector3(1.6, 0.0, 0.0), 0.4)
	await _aim(critter)
	await _seconds(0.5)
	await _cap("1-3-critter", "aiming at the critter that holds a jump")
	await _tap(&"interact")
	await _seconds(0.5)
	await _cap("1-3-borrowed", "F on the critter")
	await _bag_to_hotbar(JUMP)
	await _lift_up("shore_lift", Vector3(5.5, 0.0, 1.5), Vector3(4.5, 2.0, -1.5), true)
	await _lift_up("terrace_lift", Vector3(5.5, 2.0, -5.5), Vector3(4.5, 4.0, -8.6))
	await _cap("1-3-summit", "on the summit")
	await _walk_to(Vector3(4.5, 4.0, -11.5), 0.5)
	await _tap(&"interact")
	await _seconds(0.6)
	await _cap("1-3-picked", "picked up the summit jump (goes to the bag)")
	await _bag_to_hotbar(JUMP, "1-3-bag")
	# 頂の石を南へ 3 回押す（単発の S。押した直後の、石がまだ動いている間にも S を押す）
	await _walk_to(Vector3(-2.5, 4.0, -10.5), 0.3)
	var stone := _block("stone_high")
	for i in 3:
		await _aim(stone)
		await _select(RuleAction.Kind.BACK)
		await _tap(&"lend_single")
		await _wait(4)
		await _tap(&"move_back", 4)
		if i == 0:
			await _wait(6)
			await _tap(&"move_back", 4)  # 動いている間の 2 回目（予約は無いので何も起きないはず）
			await _cap("1-3-push-stone", "pushed the high stone; pressed S again while it moves")
		await _wait(50)
		await _walk_to(Vector3(-2.5, 4.0, stone.global_position.z - 1.4), 0.3, 300)
	_note("1-3", "high stone at %s" % stone.cell())
	await _walk_to(Vector3(-2.5, 2.0, -5.5), 0.5)
	await _walk_to(Vector3(-2.5, 2.0, -3.3), 0.25)
	var low := _block("stone_low")
	for i in 3:
		await _aim(low)
		await _select(RuleAction.Kind.BACK)
		await _tap(&"lend_single")
		await _wait(4)
		await _tap(&"move_back", 4)
		await _wait(50)
		await _walk_to(Vector3(-2.5, 2.0, low.global_position.z - 1.4), 0.3, 300)
	_note("1-3", "low stone at %s" % low.cell())
	await _cap("1-3-stones", "both stones pushed down")
	await _walk_to(Vector3(-1.5, 0.0, 2.5), 0.5)
	await _walk_to(critter.global_position + Vector3(1.6, 0.0, 0.0), 0.4)
	for action: RuleAction.Kind in [JUMP, RuleAction.Kind.RIGHT]:
		await _aim(critter)
		var slots := []
		for slot in RuleLedger.HOTBAR_SIZE:
			var v := _w().ledger.hotbar_vessel(slot, _w().acting_id())
			if v != null and _w().ledger.token(v.token_id).action == action:
				slots.append(slot)
		await _tap(StringName("slot_%d" % (int(slots[-1]) + 1)))
		await _tap(&"lend_single")
		await _seconds(0.3)
	await _cap("1-3-critter-go", "gave the critter a jump and D")
	for i in 2400:
		if OpenIslandsW1.STEPS_NEST.has_point(critter.global_position):
			break
		if i == 300:
			await _cap("1-3-critter-climbing", "the critter on its way")
		await physics_frame
	_note("1-3", "critter at %s home=%s" % [critter.global_position, critter.is_wish_met()])
	await _lift_up("shore_lift", Vector3(5.5, 0.0, 1.5), Vector3(4.5, 2.0, -1.5))
	await _lift_up("terrace_lift", Vector3(5.5, 2.0, -5.5), Vector3(4.5, 4.0, -8.6))
	await _walk_to(_goal_center(), 0.6, 600)
	await _wait_clear()
	await _seconds(0.6)
	await _cap("1-3-clear", "cleared")
	await _seconds(PartyDirector.RETURN_DELAY + 0.6)


func _push_cell(cell: Vector3i, action: RuleAction.Kind, key: StringName, name: String) -> void:
	var w := _w()
	await _aim(w.terrain_target(cell), cell)
	await _select(action)
	await _mode(TriggerMode.Kind.SINGLE_SHOT)
	await _seconds(0.3)
	await _cap("%s-aim" % name, "aiming at the terrain cell")
	await _tap(&"lend_single")
	await _wait(4)
	await _tap(key, 4)
	await _wait(10)
	await _cap("%s-moving" % name, "the cell is moving")
	await _seconds(1.5)


func _stage_push_path() -> void:
	await _read_objectives("1-4")
	var kit := _creature("kit")
	await _walk_to(kit.global_position + Vector3(1.6, 0.0, 0.0), 0.4)
	await _aim(kit)
	await _seconds(0.5)
	await _cap("1-4-kit", "aiming at the kit")
	# 段の真下からは縁のセルの上面が見えず、見上げるとカメラが地面に寄って狙えなかった（通しの 1 回目）。
	# 人がするように、少し下がって上面が見える所から狙う
	await _walk_to(Vector3(0.5, 0.0, 2.5), 0.3)
	await _push_cell(Vector3i(-1, 1, -1), RuleAction.Kind.BACK, &"move_back", "1-4-carve")
	await _walk_to(kit.global_position + Vector3(1.6, 0.0, 0.0), 0.4)
	await _aim(kit)
	await _select(RuleAction.Kind.RIGHT)
	await _tap(&"lend_single")
	await _seconds(1.0)
	await _cap("1-4-kit-go", "gave the kit D")
	var ledge := AABB(Vector3(-7.0, 1.9, -6.0), Vector3(15.0, 1.0, 6.0))
	for i in 900:
		if ledge.has_point(kit.global_position):
			break
		await physics_frame
	await _walk_to(Vector3(-0.5, 1.0, 0.5), 0.4)
	await _walk_to(Vector3(-0.5, 2.0, -2.5), 0.4)
	await _walk_to(Vector3(0.5, 2.0, -4.6), 0.3)
	await _push_cell(Vector3i(0, 1, -6), RuleAction.Kind.FORWARD, &"move_forward", "1-4-fill")
	for i in 1800:
		if OpenIslandsW1.PATH_NEST.has_point(kit.global_position):
			break
		if i == 240:
			await _cap("1-4-kit-walking", "the kit heads for its nest")
		await physics_frame
	_note("1-4", "kit at %s home=%s" % [kit.global_position, kit.is_wish_met()])
	await _walk_to(Vector3(1.5, 2.0, -2.5), 0.5)
	await _walk_to(_goal_center(), 0.6, 600)
	await _wait_clear()
	await _seconds(0.6)
	await _cap("1-4-clear", "cleared")
	await _seconds(PartyDirector.RETURN_DELAY + 0.6)


func _back_in_hub_and_menus() -> void:
	await _wait(30)
	await _cap("hub-return-final", "back in front of the 1-4 portal")
	await _tap(&"restore_checkpoint")
	await _seconds(0.6)
	await _cap("menu-pause", "Esc in the hub")
	_hud().pause_menu.close()
	await _seconds(0.4)
	await _tap(&"inventory")
	await _seconds(0.8)
	await _cap("menu-inventory", "E in the hub")
	await _tap(&"inventory")
	await _seconds(0.4)
	await _tap(&"restore_checkpoint")
	await _seconds(0.4)
	_hud().pause_menu.choose("settings")
	await _seconds(0.8)
	await _cap("menu-settings", "settings from the pause menu")
