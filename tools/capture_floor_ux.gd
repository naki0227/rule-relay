extends SceneTree
## 地面に範囲で渡したときの窪みと、2×2 の組の1マス移動のスクリーンショット（docs/images/ux/）。
## 撮り方は capture_range_ux.gd と同じ（lavapipe ＋ xvfb で Forward+、HUD も入ったゲーム本体の画面）:
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver vulkan --resolution 1280x720 \
##     --script res://tools/capture_floor_ux.gd -- <state> out.png
## state: dent（地面の円に範囲でジャンプを渡して跳ばせた最中。抜けた跡が見える）/
##        square（2×2 のブロックに範囲で D を渡して押した、動いている途中）
## 場所は「押し石の小道」（1-4）の原っぱ。


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var state := args[0] if not args.is_empty() else "dent"
	var out := args[1] if args.size() > 1 else "floor.png"
	var game := (load("res://scenes/prototype_island.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.call(&"start_solo", "zz_capture")
	var director := game.get("director") as PartyDirector
	director.enter_stage("w1_push_path")
	for i in 20:
		await physics_frame
	var w := director.world
	if state == "square":
		await _square(w)
	else:
		await _dent(w)
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	ProgressStore.new().delete("zz_capture")
	quit()


func _dent(w: StageWorld) -> void:
	# 原っぱ（高さ 0）の南の端から北を見る。原っぱの真ん中へ範囲でジャンプを渡す（自分は円の外）
	w.player.global_position = Vector3(0.5, 0.0, 7.6)
	w.camera_rig.pitch = deg_to_rad(-48.0)
	for i in 20:
		await physics_frame
	w.select_slot(4)  # ジャンプ
	var token := w.selected_vessel().token_id
	WorldLending.lend_token(
		w,
		token,
		w.acting_id(),
		w.terrain_target(Vector3i(0, -1, 1)),
		true,
		TriggerMode.Kind.SINGLE_SHOT
	)
	for i in 4:
		await physics_frame
	w.press_action(RuleAction.Kind.JUMP)
	for i in 26:  # 円が跳び上がって、抜けた跡が見えている間
		await physics_frame


func _square(w: StageWorld) -> void:
	var blocks: Array[RuleBlock] = []
	for cell: Vector3i in [
		Vector3i(1, 0, 1), Vector3i(2, 0, 1), Vector3i(1, 0, 2), Vector3i(2, 0, 2)
	]:
		blocks.append(w.add_block(cell, Color(0.45, 0.76, 0.72)))
	w.player.global_position = Vector3(1.5, 0.0, 6.0)
	w.camera_rig.yaw = deg_to_rad(0.0)
	w.camera_rig.pitch = deg_to_rad(-30.0)
	for i in 20:
		await physics_frame
	var ids := PackedInt32Array()
	for b in blocks:
		ids.append(b.entity_id)
	var v := w.ledger.hotbar_vessel(3)  # D
	var spec := {"center": blocks[0].global_position, "radius": 5.0, "layer": 0}
	w.ledger.lend(v.id, ids, TriggerMode.Kind.SINGLE_SHOT, spec)
	w.press_action(RuleAction.Kind.RIGHT)
	for i in 13:  # 1マス移動の半分ほど
		await physics_frame
