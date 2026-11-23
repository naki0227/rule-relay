extends SceneTree
## W1 で教える場面ごとのスクリーンショット（docs/images/w1-teaching/。docs/w1-teaching.md の 7 章）。
## 撮り方は capture_objectives_ux.gd と同じ（lavapipe ＋ xvfb で Forward+、HUD も入ったゲーム本体の画面）:
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver vulkan --resolution 1280x720 \
##     --script res://tools/capture_w1_teaching.gd -- <beat> out.png
## beat: hub / intro_jump / intro_lend / relay_take / relay_bouncer / steps_push / steps_critter /
##       path_ground / hill_throw / hill_equip / quarry_ban
## 案内は初めての人と同じ記録（新しい記録の名前）で出す。前の場面で覚えたはずの案内だけ、慣れたことにしてから撮る。

const PROFILE := "zz_capture_w1_teaching"
const HINT_FILE := "user://hints/zz_capture_w1_teaching.json"

var game: Node
var director: PartyDirector


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var beat := args[0] if not args.is_empty() else "hub"
	var out := args[1] if args.size() > 1 else "w1.png"
	_clean()
	game = (load("res://scenes/prototype_island.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.call(&"start_solo", PROFILE)
	director = game.get("director") as PartyDirector
	await _frames(10)
	if beat == "hub":
		await _frames(40)
	else:
		await _stage_beat(beat)
	for i in 10:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	_clean()
	quit()


func _stage_beat(beat: String) -> void:
	var w: StageWorld
	match beat:
		"intro_jump":
			w = await _enter(StageCatalog.INTRO_ID, ["move", "look"])
			await _put(w, Vector3(0.5, 0.1, 1.9), 0.0, -14.0)
		"intro_lend":
			w = await _enter(StageCatalog.INTRO_ID, ["move", "look", "jump"])
			var lift := _block(w, "lift")
			await _put(w, lift.global_position + Vector3(0.0, 0.6, 1.6), 0.0, -20.0)
			w.select_slot(4)
			await _aim(w, lift)
		"relay_take":
			w = await _enter(StageCatalog.RELAY_ID, ["move", "look", "jump"])
			var post := _block(w, "jump_post")
			await _put(w, post.global_position + Vector3(0.0, -0.4, 2.0), 0.0, -18.0)
			await _aim(w, post)
		"relay_bouncer":
			w = await _enter(StageCatalog.RELAY_ID, ["move", "look", "jump", "recall"])
			await _put(w, Vector3(-0.5, 1.1, -2.5), deg_to_rad(-25.0), -6.0)
			await _frames(50)
		"steps_push":
			w = await _enter("w1_lift_steps", ["move", "look", "jump"])
			await _put(w, Vector3(-3.5, 0.1, 1.2), 0.0, -2.0)
		"steps_critter":
			w = await _enter("w1_lift_steps", ["move", "look", "jump", "push"])
			var critter := _creature(w, "critter")
			await _put(w, critter.global_position + Vector3(2.4, 0.1, 1.2), 0.0, -18.0)
			w.interact(critter)  # 動物のジャンプを借りた後（移動が無いので待っている）
			await _aim(w, critter)
		"path_ground":
			w = await _enter("w1_push_path", ["move", "look", "jump"])
			await _put(w, Vector3(-2.5, 0.1, 1.6), 0.0, -8.0)
		"hill_throw":
			w = await _enter(StageCatalog.HILL_ID, ["move", "look", "jump"])
			await _put(w, Vector3(9.3, 0.1, 4.6), -PI * 0.5, -6.0)
			await _aim(w, _creature(w, "islet_critter"))
		"hill_equip":
			w = await _enter(StageCatalog.HILL_ID, ["move", "look", "jump", "throw"])
			await _put(w, Vector3(7.5, 3.1, -5.4), PI * 0.5, -10.0)
			w.interact(null)
			await _put(w, Vector3(8.5, 3.1, -3.0), deg_to_rad(150.0), -12.0)
		"quarry_ban":
			w = await _enter(StageCatalog.QUARRY_ID, ["move", "look", "jump", "throw"])
			var stone := _block(w, "stone_a")
			await _put(w, stone.global_position + Vector3(0.0, 0.6, 0.0), 0.0, -30.0)
			await _frames(30)


func _enter(stage_id: String, learned: Array[String]) -> StageWorld:
	director.enter_stage(stage_id)
	await _frames(10)
	var hud := game.call(&"current_hud") as Hud
	for key in learned:
		for i in HintMemory.LEARN_AFTER:
			hud.hints.used(key)
	# 入った直後の目的の札が小さくなってから（案内はその後に出る）
	await _frames(int((ObjectivePanel.BIG_SECONDS + 1.2) * 60.0))
	return director.world


func _put(w: StageWorld, at: Vector3, yaw: float, pitch_degrees: float) -> void:
	w.player.global_position = at
	w.player.velocity = Vector3.ZERO
	w.camera_rig.yaw = yaw
	w.camera_rig.pitch = deg_to_rad(pitch_degrees)
	await _frames(12)


## カメラを target へ向け、照準が合うまで向きを少しずつ変える（マウスで狙うのと同じ。遠い相手は照準の補助が
## 効かないので、細かく探す）。
func _aim(w: StageWorld, target: Node3D) -> void:
	var eye := w.player.global_position + Vector3(0.0, CameraRig.PIVOT_HEIGHT, 0.0)
	var dir := (target.global_position - eye).normalized()
	var base_yaw := atan2(-dir.x, -dir.z)
	var base_pitch := asin(dir.y)
	for step in 49:
		var dyaw := deg_to_rad(float(step % 7 - 3) * 0.8)
		var dpitch := deg_to_rad(float(step / 7 - 3) * 0.8)
		w.camera_rig.yaw = base_yaw + dyaw
		w.camera_rig.pitch = clampf(base_pitch + dpitch, CameraRig.MIN_PITCH, CameraRig.MAX_PITCH)
		await _frames(2)
		if w.aimed_block() == target:
			break
	await _frames(6)


func _block(w: StageWorld, key: String) -> RuleBlock:
	return w.blocks[int(w.entity_ids[key])]


func _creature(w: StageWorld, key: String) -> Creature:
	return w.creatures[int(w.entity_ids[key])]


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _clean() -> void:
	ProgressStore.new().delete(PROFILE)
	for path: String in [HINT_FILE, HINT_FILE + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
