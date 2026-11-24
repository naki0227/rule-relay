extends "res://tools/capture_first_ten_minutes.gd"
## 鐘の谷（W2）とふわふわ浮島（W3）の 12 ステージを、人の速さで通して撮る
## （docs/reports/2026-11-24-w2-w3-audit.md）。はじめての 10 分の通し（capture_first_ten_minutes.gd）の道具を
## そのまま使う: 入力はゲームと同じ Input（キーの押し下げ・押し離し）、瞬間移動はしない、視点はマウスと同じ
## 速さの上限で回す。ステージへは広場の進行役で入る（広場を歩く所は W1 の通しで見た）。
## W1 を遊び終えた人として通すので、W1 で教えた操作の案内は最初から「慣れた」ことにする（新しい案内だけが出る）。
## 撮り方は capture_first_ten_minutes.gd と同じ（lavapipe ＋ xvfb、Forward+、1280×720、--fixed-fps 60）:
##   ... --script res://tools/capture_w2_w3_audit.gd -- <出力のフォルダ> [only=<stage_id>]
## 出力: <フォルダ>/NN-名前.png と、各場面の画面の文字（案内・知らせ・目的）を書いた moments.txt。

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
	"throw",
	"creature_move",
	"ban",
	"equip",
	"save",
	"mode",
]
const BACK := RuleAction.Kind.BACK
const RIGHT := RuleAction.Kind.RIGHT
const LEFT := RuleAction.Kind.LEFT
const FORWARD := RuleAction.Kind.FORWARD
const THROW := RuleAction.Kind.THROW
const DASH := RuleAction.Kind.DASH
const CLIMB := RuleAction.Kind.CLIMB

var _stage_frames: Dictionary[String, int] = {}


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if not args.is_empty() else "docs/images/w2-w3-teaching/audit"
	DirAccess.make_dir_recursive_absolute(out_dir)
	_clean()
	game = (load("res://scenes/prototype_island.tscn") as PackedScene).instantiate() as GameRoot
	root.add_child(game)
	await _wait(40)
	RenderingServer.render_loop_enabled = false
	await _title()
	await _seconds(1.0)
	_prelearn()
	var stages: Array = [
		["bell_valley", _s21],
		["w2_echo_bells", _s22],
		["three_bells", _s23],
		["w2_rolling_shots", _s24],
		["w2_timed_bells", _s25],
		["windy_ridge", _s26],
		["w3_dash_beach", _s31],
		["w3_shuttle_cove", _s32],
		["floating_isles", _s33],
		["w3_wind_path", _s34],
		["w3_gap_relay", _s35],
		["w3_cloud_corridor", _s36],
	]
	# only=<stage_id> で 1 つだけ、from=<stage_id> でそこから後ろ、pick=<id>,<id> で選んだものだけを撮り直す
	# （3 つ目の引数は最初の番号）
	var only := ""
	var from := ""
	if args.size() > 1 and args[1].begins_with("only="):
		only = args[1].trim_prefix("only=")
	if args.size() > 1 and args[1].begins_with("from="):
		from = args[1].trim_prefix("from=")
	var pick := PackedStringArray()
	if args.size() > 1 and args[1].begins_with("pick="):
		pick = args[1].trim_prefix("pick=").split(",")
	if args.size() > 2:
		shot = int(args[2]) - 1
	for entry: Array in stages:
		var id := String(entry[0])
		if from != "" and id != from:
			continue
		from = ""
		if only != "" and id != only or not pick.is_empty() and not pick.has(id):
			continue
		game.director.enter_stage(id)
		await _wait(20)
		_prelearn()
		var start := Engine.get_physics_frames()
		await (entry[1] as Callable).call()
		_stage_frames[id] = Engine.get_physics_frames() - start
		_note(id, "game time %.1f s, cleared=%s" % [_stage_frames[id] / 60.0, _was_cleared()])
		await _seconds(PartyDirector.RETURN_DELAY + 0.8)
		if game.director.stage_id != StageCatalog.HUB_ID:
			game.director.enter_stage(StageCatalog.HUB_ID)
			await _wait(20)
	_finish()


## W1 で教えた操作の案内を「慣れた」ことにする（W1 を遊び終えた人として通す）。
func _prelearn() -> void:
	var hud := _hud()
	if hud == null:
		return
	for key in W1_LEARNED:
		for i in HintMemory.LEARN_AFTER:
			hud.hints.used(key)


func _was_cleared() -> bool:
	return game.director.last_clear_text != ""


# --- 道具 -----------------------------------------------------------------------


## 能力の器があって、まだ貸していない枠（無ければ -1）。
func _ready_slot(action: RuleAction.Kind) -> int:
	var w := _w()
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(slot, w.acting_id())
		if v == null:
			continue
		var t := w.ledger.token(v.token_id)
		if t != null and t.action == action and not t.is_prohibition and t.is_in_vessel():
			return slot
	return -1


func _select_ready(action: RuleAction.Kind) -> void:
	var slot := _ready_slot(action)
	if slot < 0:
		_note("select", "no free %s" % RuleAction.label(action))
		return
	if _w().selected_slot != slot:
		await _tap(StringName("slot_%d" % (slot + 1)))


## target を狙って action を渡す（mode が NONE なら今の方式のまま）。by_throw なら C で届き方を変えてから。
func _give(
	target: Node3D,
	action: RuleAction.Kind,
	mode: TriggerMode.Kind = TriggerMode.Kind.NONE,
	by_throw: bool = false,
	cell: Variant = null
) -> void:
	if by_throw and not _w().throw_mode:
		await _tap(&"toggle_reach")
	if cell == null or not await _aim_cell(cell as Vector3i):
		await _aim(target, cell)
	if cell == null and _w().aimed_block() != target:
		await _aim_sweep(target)
	await _select_ready(action)
	if mode != TriggerMode.Kind.NONE:
		await _mode(mode)
	await _tap(&"lend_single")
	await _seconds(0.3)
	if _w().throw_mode:
		await _tap(&"toggle_reach")


## 地形のセルを狙う: 人がするように、こちらを向いた面の真ん中から上面の手前まで、見上げ・見下ろしを少しずつ
## 変えて照準を合わせる（崖の縁のセルを下から狙うとき。上面の真ん中だけを狙う _aim では合わなかった）。
func _aim_cell(cell: Vector3i) -> bool:
	var w := _w()
	var me := w.player.global_position
	var center := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	var toward := Vector3(me.x - center.x, 0.0, me.z - center.z).normalized() * 0.45
	await _turn_to(_yaw_to(center))
	for dy: float in [0.0, 0.25, -0.25, 0.45, 0.6]:
		for dyaw: float in [0.0, 0.06, -0.06, 0.12, -0.12]:
			var eye := w.camera_rig.global_position if w.camera_rig != null else me
			var point := center + toward + Vector3(0.0, dy, 0.0)
			var dir := (point - eye).normalized()
			w.camera_rig.yaw = atan2(-dir.x, -dir.z) + dyaw
			w.camera_rig.pitch = clampf(asin(dir.y), CameraRig.MIN_PITCH, CameraRig.MAX_PITCH)
			await _wait(2)
			var aimed := w.aimed_block()
			if aimed is TerrainCell and (aimed as TerrainCell).cell == cell:
				return true
	return false


## 鐘（時の鐘も）の手が届く所まで歩いて、狙って F。
func _ring(key: String, walk: bool = true) -> void:
	var bell: Bell = _w().bells_by_key[key]
	if walk and not _w().is_within_reach(bell):
		var me := _w().player.global_position
		var at := bell.global_position + (me - bell.global_position).normalized() * 1.4
		await _walk_to(Vector3(at.x, me.y, at.z), 0.5)
	await _aim(bell)
	await _tap(&"interact")
	await _wait(4)
	if not bell.is_ringing():
		_note("ring", "%s did not ring" % key)


func _until(check: Callable, frames: int) -> bool:
	for i in frames:
		if check.call():
			return true
		await physics_frame
	return false


func _bell_rang(key: String, frames: int = 600) -> bool:
	var w := _w()
	var ok := await _until(func() -> bool: return w.activated.has(key), frames)
	if not ok:
		_note("bell", "%s never rang" % key)
	return ok


func _wish_met(key: String, frames: int = 2400) -> bool:
	var critter := _creature(key)
	var ok := await _until(func() -> bool: return critter.is_wish_met(), frames)
	_note("wish", "%s at %s met=%s" % [key, critter.global_position, critter.is_wish_met()])
	return ok


## 単発で渡した移動のキー（W/A/S/D）を押して、ブロックを 1 マス動かす。
func _push(key: String, action: RuleAction.Kind, stand: Vector3, times: int = 1) -> void:
	var block := _block(key)
	var keys: Dictionary = {FORWARD: &"move_forward", BACK: &"move_back", LEFT: &"move_left"}
	keys[RIGHT] = &"move_right"
	for i in times:
		var at := block.global_position + stand
		await _walk_to(Vector3(at.x, _w().player.global_position.y, at.z), 0.3)
		await _give(block, action, TriggerMode.Kind.SINGLE_SHOT)
		await _tap(keys[action] as StringName, 4)
		await _wait(40)
		await _until(
			func() -> bool: return block.is_grounded() and not block.is_moving_horizontally(), 120
		)


## 乗った台・ブロックが上がりきったところで、上の段（onto）へ歩いて移る。
func _ride_up(onto: Vector3, frames: int = 600) -> void:
	await _turn_to(_yaw_to(onto))
	var holding := false
	for i in frames:
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
	await _wait(8)


## 縁（edge）の 1.6 m 手前から走って、縁で Space。dash_after > 0 なら、跳んでからその後に Shift。
func _leap(edge: Vector3, land: Vector3, dash_after: int = 0, shot_name: String = "") -> bool:
	var dir := Vector3(land.x - edge.x, 0.0, land.z - edge.z).normalized()
	await _walk_to(edge - dir * 1.6, 0.25)
	await _turn_to(_yaw_to(land))
	if shot_name != "":
		await _cap(shot_name, "at the take-off point")
	Input.action_press(&"move_forward")
	var me := _w().player
	for i in 120:
		if (me.global_position - edge).dot(dir) > -0.15:
			break
		await physics_frame
	await _tap(&"jump", 4)
	if dash_after > 0:
		await _wait(dash_after)
		await _tap(&"dash", 4)
	var landed := await _until(
		func() -> bool: return me.is_on_floor() and (me.global_position - edge).dot(dir) > 1.0, 180
	)
	Input.action_release(&"move_forward")
	await _wait(6)
	if not landed or me.global_position.y < land.y - 1.0:
		_note("leap", "fell from %s toward %s (at %s)" % [edge, land, me.global_position])
		await _seconds(2.5)
		return false
	await _walk_to(land, 0.5, 300)
	return true


## 跳ばずに縁で Shift（地上のダッシュ）。
func _ground_dash(edge: Vector3, land: Vector3) -> void:
	await _walk_to(edge, 0.2)
	await _turn_to(_yaw_to(land))
	Input.action_press(&"move_forward")
	await _wait(2)
	await _tap(&"dash", 4)
	await _wait(30)
	Input.action_release(&"move_forward")
	await _walk_to(land, 0.5, 200)


## 往復足場（key）が board に来て止まったら乗り、off_cell まで運ばれたら off_to へ降りる。
func _ride(
	key: String, from: Vector3, board: Vector3i, off_cell: Vector3i, off_to: Vector3
) -> void:
	var block := _block(key)
	await _walk_to(from, 0.3)
	var at := func(c: Vector3i) -> bool:
		return block.cell() == c and block.is_grounded() and not block.is_moving_horizontally()
	await _until(at.bind(board), 900)
	await _walk_to(RuleBlock.cell_center(board) + Vector3(0.0, 0.5, 0.0), 0.25, 60)
	await _until(at.bind(off_cell), 900)
	await _walk_to(off_to, 0.35, 120)


func _pick_at(at: Vector3) -> void:
	await _walk_to(at, 0.4)
	await _tap(&"interact")
	await _seconds(0.4)


func _recall(key: String) -> void:
	var critter := _creature(key)
	for i in 6:
		if _w().ledger.tokens_on(critter.entity_id).is_empty():
			return
		if not await _aim_sweep(critter):
			await _aim(critter)
		await _tap(&"interact")
		await _seconds(0.3)


## 高い所の相手を、見上げを 5 度ずつ変えて探す（マウスで上を探すのと同じ。_aim は真ん中の高さしか見ない）。
func _aim_sweep(target: Node3D) -> bool:
	var w := _w()
	var base := _yaw_to(target.global_position)
	await _turn_to(base)
	for p in 11:
		for dyaw: float in [0.0, 0.1, -0.1, 0.2, -0.2, 0.3, -0.3]:
			w.camera_rig.yaw = base + dyaw
			w.camera_rig.pitch = deg_to_rad(-20.0 + p * 5.0)
			await _wait(2)
			if w.aimed_block() == target:
				return true
	_note("aim", "sweep could not find %s" % target)
	return false


func _goal_and_clear(via: Array[Vector3] = []) -> void:
	for p in via:
		await _walk_to(p, 0.5)
	await _walk_to(_goal_center(), 0.6, 900)
	await _wait_clear()
	await _seconds(0.6)
	await _cap("%s-clear" % _tag(), "cleared" if _was_cleared() else "NOT cleared")


func _tag() -> String:
	var plan := CampaignPlan.slot(game.director.stage_id)
	return plan.label() if plan != null else game.director.stage_id


# --- W2 鐘の谷 ---------------------------------------------------------------------


func _s21() -> void:
	await _read_objectives("2-1")
	var launcher := _block("launcher")
	await _walk_to(launcher.global_position + Vector3(-1.5, -0.5, 0.0), 0.3)
	await _aim(launcher)
	await _seconds(0.3)
	await _cap("2-1-aim-launcher", "aiming at the launcher; W is selected")
	var bell: Bell = _w().bells_by_key["valley_bell"]
	await _aim(bell)
	await _seconds(0.3)
	await _cap("2-1-aim-bell", "aiming at the far bell")
	await _give(launcher, THROW)
	await _cap("2-1-launcher-throws", "gave the launcher the throw")
	await _bell_rang("valley_bell")
	await _goal_and_clear()


func _s22() -> void:
	await _read_objectives("2-2")
	var kit := _creature("kit")
	await _walk_to(kit.global_position + Vector3(1.6, 0.0, 0.0), 0.4)
	await _give(kit, RIGHT)
	await _cap("2-2-kit", "gave the kit D (it waits below the middle tier)")
	var lift := _block("echo_lift_1")
	await _walk_to(lift.global_position + Vector3(0.0, 0.5, 1.4), 0.3)
	await _cap("2-2-lift", "beside the blue lift; the bell is above")
	await _walk_to(lift.global_position + Vector3(0.0, 0.5, 0.0), 0.25)
	await _cap("2-2-on-lift", "standing on the blue lift")
	await _ring("echo_bell_1", false)
	await _wait(10)
	await _cap("2-2-signal", "rang the bell: the lift and the stone move while it rings")
	await _ride_up(Vector3(2.5, 2.0, -1.6))
	await _walk_to(Vector3(0.5, 2.0, -1.5))
	var bell_1: Bell = _w().bells_by_key["echo_bell_1"]
	await _until(func() -> bool: return not bell_1.is_ringing(), 400)
	await _ring("echo_bell_1")
	await _until(func() -> bool: return _block("echo_stone_1").cell() == Vector3i(-4, 0, 0), 600)
	await _cap("2-2-stone-1", "the first stone came down")
	var lift_2 := _block("echo_lift_2")
	await _walk_to(lift_2.global_position + Vector3(0.0, 0.5, 0.0), 0.25)
	await _until(func() -> bool: return not bell_1.is_ringing(), 400)
	await _ring("echo_bell_2", false)
	await _ride_up(Vector3(2.5, 4.0, -8.6))
	await _walk_to(Vector3(1.5, 4.0, -8.6))
	var bell_2: Bell = _w().bells_by_key["echo_bell_2"]
	await _until(func() -> bool: return not bell_2.is_ringing(), 400)
	await _ring("echo_bell_2")
	await _wish_met("kit")
	await _cap("2-2-kit-home", "the kit hopped up the stones")
	await _goal_and_clear()


func _s23() -> void:
	await _read_objectives("2-3")
	await _walk_to(Vector3(9.5, 0.0, 1.5))
	var launcher := _block("launcher")
	await _give(launcher, THROW)
	await _bell_rang("east_bell")
	await _cap("2-3-east", "the launcher rang the east bell")
	await _walk_to(Vector3(-13.5, 1.0, 1.5))
	await _lift_up("west_lift", Vector3(-14.5, 1.0, 1.5), Vector3(-16.5, 3.0, -0.5))
	await _ring("west_bell")
	await _cap("2-3-west", "rang the west bell")
	for p: Vector3 in [
		Vector3(-12.5, 0.0, -2.5),
		Vector3(5.5, 0.0, -12.5),
		Vector3(5.5, 1.0, -15.5),
		Vector3(5.5, 2.0, -17.5),
		Vector3(3.5, 3.0, -16.5)
	]:
		await _walk_to(p)
	await _lift_up("north_lift", Vector3(0.5, 3.0, -16.5), Vector3(-0.5, 5.0, -18.5))
	await _ring("north_bell")
	await _cap("2-3-north", "rang the north bell")
	await _goal_and_clear([Vector3(2.0, 5.0, -21.5)])


func _s24() -> void:
	await _read_objectives("2-4")
	var launcher := _block("launcher")
	await _walk_to(launcher.global_position + Vector3(-1.5, -0.5, 0.0), 0.3)
	await _give(launcher, THROW)
	await _seconds(2.0)
	await _cap("2-4-short", "one throw: the ball falls short of the far bell")
	await _aim(launcher)
	await _tap(&"interact")
	await _seconds(0.3)
	await _lift_up("plateau_lift", Vector3(0.5, 0.0, -7.5), Vector3(-2.5, 2.0, -8.5))
	await _pick_at(Vector3(-3.5, 2.0, -6.5))
	await _cap("2-4-second-throw", "picked up the second throw on the plateau")
	await _walk_to(Vector3(0.5, 0.0, -3.5))
	await _push("launcher", RIGHT, Vector3(0.0, -0.5, 1.5), 4)
	await _cap("2-4-push-launcher", "pushed the launcher east")
	await _push("launcher", FORWARD, Vector3(-1.5, -0.5, 0.0), 5)
	await _walk_to(launcher.global_position + Vector3(-1.5, -0.5, 0.0), 0.3)
	await _give(launcher, THROW)
	await _give(launcher, THROW)
	await _bell_rang("isle_bell")
	await _cap("2-4-double", "throw x2 reached the far bell")
	await _walk_to(Vector3(-3.5, 0.0, -1.6), 0.3)
	await _give(
		_w().terrain_target(Vector3i(-4, 1, -5)),
		BACK,
		TriggerMode.Kind.SINGLE_SHOT,
		false,
		Vector3i(-4, 1, -5)
	)
	await _tap(&"move_back", 4)
	await _seconds(1.0)
	var kit := _creature("kit")
	await _walk_to(kit.global_position + Vector3(-1.6, 0.0, 0.0), 0.4)
	await _give(kit, RIGHT)
	await _wish_met("kit")
	await _goal_and_clear([Vector3(-3.5, 1.0, -3.5), Vector3(-3.5, 2.0, -6.5)])


func _s25() -> void:
	await _read_objectives("2-5")
	var kit := _creature("kit")
	await _walk_to(kit.global_position + Vector3(1.6, 0.0, 0.0), 0.4)
	await _give(kit, RIGHT)
	await _walk_to(Vector3(-0.5, 0.0, 3.5), 0.5)
	var stone := _block("walking_stone")
	await _walk_to(stone.global_position + Vector3(0.0, 0.5, 0.0), 0.3)
	await _walk_to(stone.global_position + Vector3(0.0, 1.5, -1.1), 0.3)
	await _walk_to(Vector3(3.5, 2.0, -0.4), 0.3)
	await _cap("2-5-bell", "beside the timed bell")
	var bell: TimedBell = _w().bells_by_key[OpenIslandsW2.RINGING_BELL]
	await _ring(OpenIslandsW2.RINGING_BELL, false)
	await _seconds(1.0)
	await _cap("2-5-bridge", "the bridge rises while the bell rings")
	var home := func() -> bool: return kit.is_wish_met()
	var rings := 1
	for i in 4800:
		if home.call():
			break
		if bell.remaining < 1.0:
			await _ring(OpenIslandsW2.RINGING_BELL, false)
			rings += 1
			if rings == 3:
				await _cap("2-5-keep-ringing", "ringing again before it stops")
		await physics_frame
	_note("2-5", "rang %d times; kit home=%s" % [rings, home.call()])
	await _until(func() -> bool: return not bell.is_ringing(), 600)
	await _seconds(0.8)
	await _walk_to(Vector3(0.9, 2.0, -2.7), 0.3)
	await _ring(OpenIslandsW2.RINGING_BELL, false)
	await _seconds(0.6)
	await _walk_to(Vector3(1.0, 4.0, -13.8), 0.5, 360)
	_note("2-5", "crossed with %.2f s left" % bell.remaining)
	await _goal_and_clear()


func _s26() -> void:
	await _read_objectives("2-6")
	var rusty := _block("rusty_lift")
	await _walk_to(Vector3(7.5, 0.0, -4.5), 0.4)
	await _aim(rusty)
	await _seconds(0.3)
	await _cap("2-6-rusty", "aiming at the rusty lift with the jump ban sign")
	for step: Array in [
		[Vector3i(0, 1, -7), Vector3(2.0, 0.0, -4.5), 0],
		[Vector3i(0, 3, -14), Vector3(2.0, 2.0, -11.5), 2],
		[Vector3i(0, 5, -21), Vector3(2.0, 4.0, -18.5), 4],
	]:
		var cell: Vector3i = step[0]
		await _walk_to(step[1] as Vector3, 0.3)
		await _give(_w().terrain_target(cell), BACK, TriggerMode.Kind.SINGLE_SHOT, false, cell)
		await _tap(&"move_back", 4)
		await _seconds(1.5)
		var y := int(step[2])
		for p: Vector3 in [
			Vector3(0.5, y, cell.z + 2.5),
			Vector3(0.5, y + 1, cell.z + 1.5),
			Vector3(0.5, y + 1, cell.z + 0.5),
			Vector3(0.5, y + 2, cell.z - 1.5)
		]:
			await _walk_to(p, 0.4)
		if y == 2:
			await _cap("2-6-shoulder", "on the shoulder after pushing two cliff edges")
	await _goal_and_clear()


# --- W3 ふわふわ浮島 ---------------------------------------------------------------


func _s31() -> void:
	await _read_objectives("3-1")
	var bunny := _creature("bunny")
	await _walk_to(Vector3(0.0, 0.0, 3.5), 0.4)
	await _give(bunny, RIGHT)
	await _give(bunny, RuleAction.Kind.JUMP)
	await _wish_met("bunny")
	await _walk_to(Vector3(-2.5, 0.0, 0.5), 0.3)
	await _recall("bunny")
	await _pick_at(Vector3(1.5, 0.0, 2.5))
	await _cap("3-1-dash", "picked up the dash")
	await _walk_to(Vector3(-2.5, 0.0, -0.3), 0.3)
	await _turn_to(0.0)
	await _cap("3-1-edge", "at the first gap (5 wide)")
	# ふつうの走り跳びで落ちると、ひとりでは世界ごとチェックポイントへ戻る（拾ったダッシュも戻る）ので試さない。
	# 幅 5 を走り跳びで越えないことは test_w2_w3_teaching が確かめる
	await _leap(Vector3(-2.5, 0.0, -0.7), Vector3(-2.5, 0.0, -7.5), 20, "3-1-takeoff")
	await _leap(Vector3(-1.3, 0.0, -9.5), Vector3(4.6, 0.0, -9.0), 20)
	await _goal_and_clear(
		[Vector3(5.5, 0.0, -7.5), Vector3(7.5, 1.0, -8.5), Vector3(7.5, 2.0, -10.5)]
	)


func _s32() -> void:
	await _read_objectives("3-2")
	await _ride(
		"north_shuttle",
		Vector3(-3.5, 1.0, 2.6),
		Vector3i(-4, 0, 1),
		Vector3i(-4, 0, 0),
		Vector3(-3.5, 1.0, -1.5)
	)
	await _cap("3-2-first-shuttle", "rode the first shuttle")
	await _ride(
		"twin_south",
		Vector3(0.5, 1.0, -4.4),
		Vector3i(0, 0, -6),
		Vector3i(0, 0, -7),
		Vector3(0.5, 1.0, -7.5)
	)
	await _cap("3-2-twins", "changing shuttles")
	var north := _block("twin_north")
	await _until(
		func() -> bool: return north.cell() == Vector3i(0, 0, -9) and north.is_grounded(), 900
	)
	await _walk_to(Vector3(0.5, 1.0, -10.5), 0.35, 120)
	await _walk_to(Vector3(5.5, 1.0, -10.5))
	await _walk_to(Vector3(5.5, 1.0, -12.5), 0.4)
	await _walk_to(Vector3(3.5, 1.0, -13.5), 0.4)
	await _give(_creature("lamb"), RIGHT)
	await _wish_met("lamb")
	await _goal_and_clear([Vector3(3.5, 1.0, -14.5)])


func _s33() -> void:
	await _read_objectives("3-3")
	await _walk_to(Vector3(4.5, 0.0, 1.5))
	await _give(_block("launcher"), THROW)
	await _bell_rang("east_bell")
	await _lift_up("tower_lift", Vector3(1.5, 0.0, -1.5), Vector3(0.5, 2.0, -5.5))
	await _leap(Vector3(0.5, 2.0, -6.0), Vector3(0.5, 2.0, -11.0))
	await _ring("north_bell")
	await _cap("3-3-north", "rang the north bell")
	await _walk_to(Vector3(-3.5, 2.0, -10.5))
	await _leap(Vector3(-3.5, 2.0, -10.0), Vector3(-3.5, 0.0, -4.5))
	await _leap(Vector3(0.5, 0.0, 6.0), Vector3(0.5, 0.0, 10.0))
	await _pick_at(Vector3(-2.5, 0.0, 14.5))
	await _leap(Vector3(0.5, 0.0, 9.0), Vector3(0.5, 0.0, 4.0))
	await _leap(Vector3(-6.0, 0.0, 0.5), Vector3(-11.8, 0.0, 0.5), 20, "3-3-west-gap")
	await _ring("west_bell")
	await _leap(Vector3(-11.0, 0.0, 0.5), Vector3(-4.5, 0.0, 0.5), 20)
	await _lift_up("tower_lift", Vector3(1.5, 0.0, -1.5), Vector3(0.5, 2.0, -5.5))
	await _leap(Vector3(0.5, 2.0, -6.0), Vector3(0.5, 2.0, -11.0))
	await _goal_and_clear([Vector3(-1.5, 2.0, -14.0)])


func _s34() -> void:
	await _read_objectives("3-4")
	var gust := Vector3(-1.5, 0.5, -2.5)
	await _walk_to(Vector3(-1.5, 0.0, 2.5), 0.25)
	await _cap("3-4-shore", "on the shore facing the gap; leaves show the wind")
	var w := _w()
	await _until(func() -> bool: return w.nature.wind_at(gust).length() < 0.1, 400)
	await _until(func() -> bool: return w.nature.wind_at(gust).length() > 0.1, 400)
	await _leap(Vector3(-1.5, 0.0, 0.0), Vector3(-1.5, 0.0, -6.5), 0, "3-4-gust")
	var bunny := _creature("bunny")
	await _walk_to(Vector3(3.5, 0.0, -10.5), 0.4)
	await _give(bunny, RIGHT)
	await _give(bunny, RuleAction.Kind.JUMP)
	await _wish_met("bunny")
	await _walk_to(Vector3(5.5, 0.0, -10.5), 0.3)
	await _recall("bunny")
	await _goal_and_clear(
		[Vector3(-3.5, 0.0, -9.5), Vector3(-3.5, 1.0, -10.5), Vector3(-3.5, 2.0, -12.5)]
	)


func _s35() -> void:
	await _read_objectives("3-5")
	await _walk_to(Vector3(5.5, 0.0, 0.5), 0.3)
	var launcher := _block("launcher")
	await _aim(launcher)
	await _seconds(0.3)
	await _cap("3-5-aim-launcher", "aiming at the far launcher on the east islet")
	await _give(launcher, THROW, TriggerMode.Kind.NONE, true)
	await _bell_rang("bridge_bell")
	await _seconds(1.0)
	await _cap("3-5-bridge", "the launcher keeps the bell ringing; the bridge is up")
	await _walk_to(Vector3(0.0, 0.0, 0.5), 0.3)
	await _walk_to(Vector3(0.0, 0.0, -10.5), 0.35, 400)
	await _walk_to(Vector3(-2.5, 0.0, -10.6), 0.3)
	await _cap("3-5-lever", "standing beside the lever")
	await _walk_to(Vector3(-0.5, 0.0, -13.5), 0.4)
	await _give(_creature("lamb"), RIGHT)
	await _wish_met("lamb")
	await _goal_and_clear(
		[Vector3(-4.5, 0.0, -12.5), Vector3(-4.5, 1.0, -13.5), Vector3(-4.5, 2.0, -15.5)]
	)


func _s36() -> void:
	await _read_objectives("3-6")
	await _ring("harbor_bell")
	await _cap("3-6-harbor", "rang the harbor bell (8 s)")
	await _ride(
		"harbor_south",
		Vector3(-2.5, 1.0, 4.4),
		Vector3i(-3, 0, 3),
		Vector3i(-3, 0, 2),
		Vector3(-2.5, 1.0, 1.5)
	)
	var north := _block("harbor_north")
	await _until(
		func() -> bool: return north.cell() == Vector3i(-3, 0, 0) and north.is_grounded(), 900
	)
	await _walk_to(Vector3(-2.5, 1.0, -1.5), 0.35, 120)
	await _pick_at(Vector3(-4.5, 1.0, -3.5))
	await _cap("3-6-gloves", "picked up the gloves")
	await _ride(
		"cloud_shuttle",
		Vector3(3.5, 1.0, -5.4),
		Vector3i(3, 0, -7),
		Vector3i(3, 0, -8),
		Vector3(3.5, 1.0, -9.5)
	)
	var critter := _creature("cloud_wish")
	await _walk_to(Vector3(-5.5, 1.0, -12.4), 0.4)
	await _give(critter, CLIMB)
	await _give(critter, RIGHT)
	await _cap("3-6-climber", "gave the creature gloves and D")
	await _wish_met("cloud_wish")
	await _walk_to(Vector3(2.0, 1.0, -13.6), 0.3)
	await _give(critter, THROW, TriggerMode.Kind.NONE, true)
	await _bell_rang("sky_bell")
	await _seconds(0.5)
	await _cap("3-6-bridge", "the nut rang the pillar bell; the sky bridge is up")
	await _walk_to(Vector3(2.0, 1.0, -25.5), 0.35, 400)
	await _goal_and_clear([Vector3(4.5, 1.0, -26.5), Vector3(4.5, 1.0, -28.5)])
