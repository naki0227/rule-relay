extends SceneTree
## ゲームプレイ動画の素材（決まった手順で遊ぶ短いクリップ）を撮る（docs/submission/video-capture.md）。
## 撮り方はほかの capture_*.gd と同じ lavapipe ＋ xvfb で、Godot の Movie Maker（--write-movie）が
## 30 fps の PNG の連番と WAV（ゲームの BGM と効果音）を書く。ふつうは包みの tools/capture_video.sh から呼ぶ:
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver vulkan --resolution 1280x720 --fixed-fps 30 \
##     --write-movie build/video/<clip>/raw/frame.png \
##     --script res://tools/capture_video.gd -- <clip> build/video/<clip>/marks.txt
## clip: CLIPS のどれか（video-plan.md の場面と対応）。marks.txt には、使う範囲（描いたフレームの番号の
## 始まりと終わり）を書く。始まりより前は準備（島の読み込み・下ごしらえ）なので、包みが切り捨てる。
## 操作はプレイヤーと同じ入力（移動のキー・視点の向き・渡す・F）で流す。準備の間だけ位置を直接置くことがある。
## 時間はフレーム数で進むので（--fixed-fps）、同じ版なら毎回同じ絵になる。

const PROFILE := "zz_capture_video"
const CLIPS: PackedStringArray = [
	"hub_walk",
	"jump_lend",
	"creature_medal",
	"range_lend",
	"throw_arc",
	"coop_jumps",
	"clear_return",
]
const FPS := 30.0
const JUMP := RuleAction.Kind.JUMP
const RIGHT := RuleAction.Kind.RIGHT
const BACK := RuleAction.Kind.BACK
const THROW := RuleAction.Kind.THROW
## 視点が目標の向きへ寄る割合（1 フレームごと）。0.1 で約 0.7 秒かけて 9 割寄る（なめらかに回す）。
const CAMERA_EASE := 0.1
## 目的地の近くでは向きを早めに合わせる（ゆっくりだと目的地のまわりを回ってしまう）。
const CAMERA_EASE_NEAR := 0.35
## 撮影用のカメラ（cine）が目標へ寄る割合。
const CINE_EASE := 0.05
const COOP_PORT_BASE := 24700
## 動物を横から追う撮影用のカメラの位置（動物から見て南東のやや上）。
const CREATURE_CAM := Vector3(3.4, 1.9, 2.6)

var game: Node
var director: PartyDirector
var w: StageWorld
var yaw_goal: float = 0.0
var pitch_goal: float = deg_to_rad(-18.0)
var _ease_rate: float = CAMERA_EASE

var _marks_path: String = ""
var _start_frame: int = -1
var _cine: Camera3D
var _cine_from: Vector3 = Vector3.ZERO
var _cine_at: Vector3 = Vector3.ZERO
var _cine_look: Vector3 = Vector3.ZERO
var _coop: RefCounted


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var clip := args[0] if not args.is_empty() else ""
	_marks_path = args[1] if args.size() > 1 else ""
	if not CLIPS.has(clip):
		printerr("capture_video: clip must be one of %s" % ", ".join(CLIPS))
		quit(2)
		return
	ProgressStore.new().delete(PROFILE)
	game = (load("res://scenes/prototype_island.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	match clip:
		"hub_walk":
			await _clip_hub_walk()
		"jump_lend":
			await _clip_jump_lend()
		"creature_medal":
			await _clip_creature_medal()
		"range_lend":
			await _clip_range_lend()
		"throw_arc":
			await _clip_throw_arc()
		"coop_jumps":
			await _clip_coop_jumps()
		"clear_return":
			await _clip_clear_return()
	_finish()


# --- クリップ ---------------------------------------------------------------------


## 広場を歩いて、ポータル（門）の並びを見せ、導入のポータルから島に入る（約 14 秒）。
func _clip_hub_walk() -> void:
	await _start_solo()
	_aim_now(0.0, -12.0)
	await _seconds(0.5)
	_begin()
	await _seconds(1.2)
	await _walk_to(Vector3(-3.5, 0.0, 6.5), 0.6)
	await _walk_to(Vector3(-3.0, 0.0, -2.5), 0.6)
	_look_toward(Vector3(-9.5, 1.5, -4.5), -10.0)  # 西の「押し石の小道」の門
	await _seconds(1.0)
	await _walk_to(Vector3(4.0, 0.0, -3.0), 0.6)
	_look_toward(Vector3(10.5, 1.5, -4.5), -10.0)  # 東の「丘の上の旗」の門
	await _seconds(1.0)
	await _walk_to(Vector3(3.5, 0.0, 3.5), 0.6)
	var intro := w.def.overworld.portal(StageCatalog.INTRO_ID).position
	await _walk_to(intro + Vector3(0.0, 0.0, 0.3), 0.3)
	await _seconds(0.4)
	w.interact(null)  # F: 門から島へ
	await _seconds(2.5)


## 導入の島: 岩棚は自分では跳べない → 窪みのブロックにジャンプを単発で貸す → 乗って持ち上がる（約 14 秒）。
func _clip_jump_lend() -> void:
	await _enter_stage(StageCatalog.INTRO_ID)
	_aim_now(0.0, -14.0)
	_begin()
	await _walk_to(Vector3(-2.0, 0.0, -4.0), 0.4)
	_look_toward(Vector3(-2.0, 2.5, -8.0), -20.0)
	await _seconds(0.6)
	w.press_action(JUMP)  # 跳んでも届かない（1.3 < 2）
	await _seconds(1.4)
	var lift := _block("lift")
	await _walk_to(Vector3(2.4, 0.0, -2.8), 0.35)  # チェックポイントの台座は避けて、ブロックの斜め前へ
	_look_toward(lift.global_position, -30.0)
	await _seconds(0.8)
	w.select_slot(_slot_of(JUMP))
	w.set_lend_mode(TriggerMode.Kind.SINGLE_SHOT)
	w.lend_to(lift, false)
	await _seconds(1.2)
	await _walk_to(lift.global_position + Vector3(0.0, 0.5, 0.0), 0.22)
	_look_toward(Vector3(0.5, 2.0, -9.0), -16.0)
	await _seconds(0.5)
	w.press_action(JUMP)  # 貸したジャンプは、乗ったブロックが使う
	await _ride_up(Vector3(0.5, 2.0, -6.6))
	_aim_toward_yaw(0.0, -32.0)  # ゴールの窪みを見下ろす（単発のジャンプはホットバーに戻っている）
	await _seconds(2.2)


## 押し石の小道: 移動だけをもらった子どもの生き物が、巣の光の柱へ向かって段のふもとまで歩き、
## 吹き出しにジャンプのメダルを出して待つ → ジャンプを渡すと段を上がる（約 15 秒。docs/adr/0019）。
func _clip_creature_medal() -> void:
	await _enter_stage("w1_push_path")
	var kit := _creature("kit")
	# 準備（映さない）: 縁を 1 マス押して 1 段の階段にし、生き物のジャンプを借りておく
	w.player.global_position = Vector3(1.5, 0.0, 0.5)
	await _physics(10)
	w.select_slot(_slot_of(BACK))
	w.set_lend_mode(TriggerMode.Kind.SINGLE_SHOT)
	w.lend_to(w.terrain_target(Vector3i(-1, 1, -1)), false)
	w.press_action(BACK)
	await _physics(80)
	w.player.global_position = kit.global_position + Vector3(1.4, 0.0, 0.0)
	await _physics(10)
	w.interact(kit)
	await _physics(4)
	_inventory_to_hotbar(JUMP)
	_aim_now(_yaw_to(kit.global_position + Vector3(-0.5, 0.0, -2.0)), -10.0)
	# 動物は小さく、肩越しの視点だと自分の体に隠れるので、横から動物を追う撮影用のカメラにする
	_cine_on(kit.global_position + CREATURE_CAM, kit.global_position + Vector3(0.0, 0.6, -1.0))
	_cine.global_position = _cine_from
	_cine_look = _cine_at
	await _seconds(0.6)
	_begin()
	await _seconds(1.0)
	w.select_slot(_slot_of(RIGHT))
	w.set_lend_mode(TriggerMode.Kind.NONE)
	w.lend_to(kit, false)  # 移動（D）だけを渡す
	for i in int(9.0 * FPS):
		if kit.bubble_key() == CreatureWishView.KEY_NEED_JUMP:
			break
		_follow(kit)
		await _frame()
	for i in int(1.0 * FPS):
		_follow(kit)
		await _frame()
	# 歩いて近づく間も、カメラは動物を追う
	var near := kit.global_position + Vector3(-1.1, 0.0, 1.6)
	for i in int(3.0 * FPS):
		var flat := Vector3(
			near.x - w.player.global_position.x, 0.0, near.z - w.player.global_position.z
		)
		if flat.length() < 0.5:
			break
		yaw_goal = atan2(-flat.x, -flat.z)
		_ease_rate = CAMERA_EASE_NEAR
		Input.action_press(&"move_forward")
		_follow(kit)
		await _frame()
	Input.action_release(&"move_forward")
	for i in int(1.2 * FPS):  # 吹き出しのジャンプのメダル
		_follow(kit)
		await _frame()
	w.select_slot(_slot_of_lendable(JUMP))
	w.lend_to(kit, false)
	for i in int(4.5 * FPS):
		_follow(kit)
		await _frame()


## 撮影用のカメラで target を追う（横の決まった位置から）。
func _follow(target: Node3D) -> void:
	_cine_from = target.global_position + CREATURE_CAM
	_cine_at = target.global_position + Vector3(0.0, 0.6, -1.0)


## 範囲で貸す: 右クリックのプレビュー（輪）→ 地面の円の中へジャンプを繰り返しで一度に貸す（約 12 秒）。
func _clip_range_lend() -> void:
	await _enter_stage("w1_push_path")
	w.player.global_position = Vector3(2.5, 0.0, 6.0)
	_aim_now(deg_to_rad(10.0), -20.0)
	await _seconds(0.6)
	_begin()
	await _seconds(0.6)
	_aim_toward_yaw(deg_to_rad(20.0), -38.0)  # 足もとの先の地面を狙う
	await _seconds(1.4)
	w.select_slot(_slot_of(JUMP))
	w.set_lend_mode(TriggerMode.Kind.REPEAT)
	w.begin_range_preview()  # 右クリックを押している間のプレビュー
	await _seconds(2.0)
	w.commit_range_preview(w.aimed_block())
	await _seconds(1.0)
	_aim_toward_yaw(deg_to_rad(-25.0), -22.0)  # ゆっくり回して、円の中が一斉に跳ねるのを見せる
	await _seconds(3.0)
	_aim_toward_yaw(deg_to_rad(40.0), -26.0)
	await _seconds(3.0)


## 投げる: メダルが弧を描いて飛び、遠くの地面のセルに当たると、そのセルが繰り返し跳ねはじめる（約 10 秒）。
func _clip_throw_arc() -> void:
	await _enter_stage("w1_push_path")
	if not w.ledger.player_can(THROW, w.acting_id()):
		w.ledger.give_player_item(THROW, false, _free_slot(), w.acting_id())
	w.player.global_position = Vector3(5.5, 0.0, 7.5)
	_aim_now(deg_to_rad(18.0), -12.0)
	await _seconds(0.6)
	_begin()
	await _seconds(0.8)
	w.toggle_reach()  # C: 触る → 投げる
	await _seconds(0.8)
	var cell := Vector3i(1, -1, 0)
	_look_toward(Vector3(cell) + Vector3(0.5, 0.5, 0.5), -14.0)
	await _seconds(1.0)
	w.select_slot(_slot_of(JUMP))
	w.set_lend_mode(TriggerMode.Kind.REPEAT)
	w.lend_to(w.terrain_target(cell), false)
	_cine_on(
		w.player.global_position + Vector3(6.0, 2.6, 1.0),
		w.player.global_position.lerp(Vector3(cell), 0.5)
	)
	while not MedalThrow.flying(w).is_empty():
		await _frame()
	await _seconds(1.0)
	_cine_at = Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	await _seconds(5.0)


## 2 人のオンライン協力（同じ PC の中で ENet の 2 端をつなぐ）: 2P がジャンプを 1P へ渡し、1P はジャンプ ×2 で
## 岩棚へ → 上から 2 つとも 2P へ渡し、2P も上がる → 2 人でゴールの窪みに入ってクリア（約 15 秒）。
## 画面は 1P（ホスト。ゲームと同じ HUD つき）で、左上に 2P の画面を小さく重ねる。
func _clip_coop_jumps() -> void:
	var port := COOP_PORT_BASE + randi() % 200
	game.call(&"start_host", PROFILE, port)
	director = game.get("director") as PartyDirector
	await _physics(10)
	var coop: Variant = (load("res://tools/capture_video_coop.gd") as GDScript).new(
		self, port, _frame
	)
	_coop = coop as RefCounted
	await _coop.call(&"join")
	director.enter_stage(StageCatalog.INTRO_ID)
	await _coop.call(&"wait_in_stage", StageCatalog.INTRO_ID)
	w = director.world
	_aim_now(0.0, -14.0)
	await _seconds(ObjectivePanel.BIG_SECONDS + 1.0)
	_begin()
	_coop.call(&"walk_to", Vector3(-1.0, 0.0, -3.2))
	await _walk_to(Vector3(-2.5, 0.0, -4.4), 0.35)
	_look_toward(Vector3(-2.5, 2.5, -8.0), -8.0)
	await _coop.call(&"until_arrived")
	await _coop.call(&"give_jumps_to_host")  # 2P → 1P（ジャンプ ×2）
	print("capture_video: 1P has %d jumps" % w.ledger.ability_count(JUMP, w.acting_id()))
	await _seconds(1.0)
	w.press_action(JUMP)
	await _ride_up(Vector3(-2.5, 2.0, -6.2))
	print("capture_video: 1P at %s" % w.player.global_position)
	_coop.call(&"walk_to", Vector3(-1.5, 0.0, -4.4))
	_aim_toward_yaw(PI, -30.0)  # 振り返って、下の 2P を見る
	await _seconds(1.0)
	await _coop.call(&"until_arrived")
	await _give_all_jumps_to(2)  # 1P → 2P（2 つとも）
	await _seconds(0.6)
	await _walk_to(Vector3(0.5, 1.1, -8.5), 0.4)  # 先にゴールの窪みへ
	_aim_toward_yaw(PI, -20.0)
	await _coop.call(&"until_arrived")
	await _coop.call(&"jump_up_and_into_goal")
	for i in int(4.0 * FPS):
		if director.last_clear_text != "":
			break
		await _frame()
	await _seconds(2.5)


## クリアしてポータルへ戻る: 岩棚の上からゴールの窪みへ降りる → クリアの表示 → 入った門の前へ戻る（約 11 秒）。
func _clip_clear_return() -> void:
	await _start_solo()
	var intro := w.def.overworld.portal(StageCatalog.INTRO_ID).position
	w.player.global_position = intro + Vector3(0.0, 0.1, 0.0)
	await _physics(4)
	w.interact(null)  # 門から入る（戻り先がこの門になる）
	await _physics(20)
	w = director.world
	w.player.global_position = Vector3(0.5, 2.0, -5.6)  # 準備: 岩棚の縁に立つ
	_aim_now(0.0, -24.0)
	await _seconds(ObjectivePanel.BIG_SECONDS + 1.0)
	_begin()
	await _seconds(0.6)
	await _walk_to(Vector3(0.5, 1.1, -8.4), 0.4)
	for i in int(3.0 * FPS):
		if director.last_clear_text != "":
			break
		await _frame()
	for i in int((PartyDirector.RETURN_DELAY + 2.0) * FPS):
		if director.stage_id == StageCatalog.HUB_ID:
			break
		await _frame()
	await _seconds(1.2)
	_aim_toward_yaw(w.camera_rig.yaw + PI, -38.0)  # 振り返ると、背にした門
	await _seconds(2.5)


# --- 始める・印 -------------------------------------------------------------------


func _start_solo() -> void:
	game.call(&"start_solo", PROFILE)
	director = game.get("director") as PartyDirector
	await _physics(20)
	w = director.world


func _enter_stage(stage_id: String) -> void:
	await _start_solo()
	director.enter_stage(stage_id)
	await _physics(20)
	w = director.world
	await _seconds(ObjectivePanel.BIG_SECONDS + 0.5)  # 入ったときの大きな目的の一覧が隅へ縮むまで


## ここから先を動画に使う（描いたフレームの番号を覚える）。
func _begin() -> void:
	_start_frame = Engine.get_frames_drawn()


func _finish() -> void:
	var end_frame := Engine.get_frames_drawn()
	if _marks_path != "":
		var file := FileAccess.open(_marks_path, FileAccess.WRITE)
		file.store_line("%d %d" % [maxi(_start_frame, 0), end_frame])
		file.close()
	print(
		(
			"capture_video: frames %d..%d (%.1f s)"
			% [_start_frame, end_frame, (end_frame - _start_frame) / FPS]
		)
	)
	if director != null and director.last_clear_text != "":
		print("capture_video: cleared (%s)" % director.last_clear_text)
	Input.action_release(&"move_forward")
	if _coop != null:
		_coop.call(&"close")
	ProgressStore.new().delete(PROFILE)
	for path: String in ["user://session/%s.key" % PROFILE, "user://session/%s_2p.key" % PROFILE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	quit()


# --- 進める（1 フレームごとに視点をなめらかに寄せる） -----------------------------


func _frame() -> void:
	if director != null and director.world != null:
		w = director.world
	if w != null and is_instance_valid(w):
		w.camera_rig.yaw = lerp_angle(w.camera_rig.yaw, yaw_goal, _ease_rate)
		w.camera_rig.pitch = lerpf(w.camera_rig.pitch, pitch_goal, _ease_rate)
	if _cine != null:
		_cine.global_position = _cine.global_position.lerp(_cine_from, CINE_EASE)
		_cine_look = _cine_look.lerp(_cine_at, CINE_EASE * 2.0)
		_cine.look_at(_cine_look)
	if _coop != null:
		_coop.call(&"step")
	await process_frame


func _seconds(seconds: float) -> void:
	for i in int(round(seconds * FPS)):
		await _frame()


## 準備のための物理フレーム（映さない区間で使う）。
func _physics(frames: int) -> void:
	for i in frames:
		await physics_frame


func _aim_now(yaw: float, pitch_degrees: float) -> void:
	yaw_goal = yaw
	pitch_goal = deg_to_rad(pitch_degrees)
	w.camera_rig.yaw = yaw
	w.camera_rig.pitch = pitch_goal


func _aim_toward_yaw(yaw: float, pitch_degrees: float) -> void:
	_ease_rate = CAMERA_EASE
	yaw_goal = yaw
	pitch_goal = deg_to_rad(pitch_degrees)


func _yaw_to(target: Vector3) -> float:
	var flat := target - w.player.global_position
	return atan2(-flat.x, -flat.z)


func _look_toward(target: Vector3, pitch_degrees: float) -> void:
	_aim_toward_yaw(_yaw_to(target), pitch_degrees)


func _cine_on(from: Vector3, at: Vector3) -> void:
	_cine = Camera3D.new()
	_cine.fov = 60.0
	w.add_child(_cine)
	var cam := w.camera_rig.camera()
	_cine.global_transform = cam.global_transform
	_cine_look = cam.global_position - cam.global_transform.basis.z * 6.0
	_cine_from = from
	_cine_at = at
	_cine.current = true


# --- 歩く・乗る（移動のキーと視点の向きだけ） -------------------------------------


## 視点を target へ向けながら前へ歩く（キーの W と同じ）。段差で止まったら跳ぶ。
func _walk_to(target: Vector3, tolerance: float = 0.4, max_seconds: float = 12.0) -> bool:
	var stuck := 0
	for i in int(max_seconds * FPS):
		var me := w.player
		var flat := Vector3(target.x - me.global_position.x, 0.0, target.z - me.global_position.z)
		if flat.length() <= tolerance and absf(me.global_position.y - target.y) < 0.7:
			break
		yaw_goal = atan2(-flat.x, -flat.z)
		_ease_rate = CAMERA_EASE_NEAR if flat.length() < 1.5 else CAMERA_EASE
		if absf(angle_difference(w.camera_rig.yaw, yaw_goal)) < 0.8:
			Input.action_press(&"move_forward")
		else:
			Input.action_release(&"move_forward")
		var moving := Vector2(me.velocity.x, me.velocity.z).length() > 0.5
		stuck = 0 if moving else stuck + 1
		if stuck > 6 and me.is_on_floor() and Input.is_action_pressed(&"move_forward"):
			w.press_action(JUMP)
			stuck = 0
		await _frame()
	Input.action_release(&"move_forward")
	_ease_rate = CAMERA_EASE
	var arrived := w.player.global_position.distance_to(target) < tolerance + 0.8
	if not arrived:
		push_warning(
			"capture_video: could not walk to %s (at %s)" % [target, w.player.global_position]
		)
	return arrived


## 持ち上がる・跳び上がる途中で、上の段の高さを越えたら onto へ歩いて移る。
func _ride_up(onto: Vector3) -> void:
	for i in int(4.0 * FPS):
		var me := w.player
		var flat := Vector3(onto.x - me.global_position.x, 0.0, onto.z - me.global_position.z)
		if flat.length() < 0.4 and me.global_position.y > onto.y - 0.2:
			break
		if me.global_position.y > onto.y - 0.1 or i < 1:
			Input.action_press(&"move_forward")
		else:
			Input.action_release(&"move_forward")
		await _frame()
	Input.action_release(&"move_forward")


# --- 台帳まわり -------------------------------------------------------------------


func _block(key: String) -> RuleBlock:
	return w.blocks[int(w.entity_ids[key])]


func _creature(key: String) -> Creature:
	return w.creatures[int(w.entity_ids[key])]


func _slot_of(action: RuleAction.Kind) -> int:
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(slot, w.acting_id())
		if v != null and w.ledger.token(v.token_id).action == action:
			return slot
	return 0


## action が器に入っていて（貸していない）渡せるスロット。
func _slot_of_lendable(action: RuleAction.Kind) -> int:
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(slot, w.acting_id())
		if v == null:
			continue
		var t := w.ledger.token(v.token_id)
		if t.action == action and not t.is_prohibition and t.is_in_vessel():
			return slot
	return _slot_of(action)


func _free_slot() -> int:
	for slot in RuleLedger.HOTBAR_SIZE:
		if w.ledger.hotbar_vessel(slot, w.acting_id()) == null:
			return slot
	return RuleLedger.HOTBAR_SIZE - 1


## 回収して通常インベントリに入った action を、ホットバーの空きへ移す（E で開いて並べるのと同じ）。
func _inventory_to_hotbar(action: RuleAction.Kind) -> void:
	for v in w.ledger.inventory_vessels(w.acting_id()):
		var t := w.ledger.token(v.token_id)
		if t.action == action and not t.is_prohibition:
			w.ledger_actions.move_to_hotbar(v.id, _free_slot())


## 1P が持っているジャンプを、全部 player_id の仲間へ渡す（1 回の操作で 1 つずつ）。
func _give_all_jumps_to(player_id: int) -> void:
	w.select_slot(_slot_of(JUMP))
	for attempt in 4:
		if w.ledger.ability_count(JUMP, w.acting_id()) == 0:
			return
		var before := w.ledger.ability_count(JUMP, player_id)
		w.lend_to(w.avatars[player_id], false)
		for i in int(3.0 * FPS):
			if w.ledger.ability_count(JUMP, player_id) > before:
				break
			await _frame()
		await _seconds(0.3)
