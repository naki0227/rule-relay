extends SceneTree
## 投げたメダルのスクリーンショット（docs/images/ux/。docs/adr/0017）。撮り方は capture_range_ux.gd と同じ
## （lavapipe ＋ xvfb で Forward+、HUD も入ったゲーム本体の画面）:
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver vulkan --resolution 1280x720 \
##     --script res://tools/capture_throw_ux.gd -- <state> out.png
## state: flight（飛んでいる途中。尾が見える）/ hit（当たった直後の小さな輪）
## 場所は「押し石の小道」（1-4）の原っぱ。「投げる」をホットバーの空きに足して、左の子どもの生き物へ投げる
## （横から弧が見えるように、照準の正面ではなく画面の左の相手を選ぶ）。


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var state := args[0] if not args.is_empty() else "flight"
	var out := args[1] if args.size() > 1 else "throw.png"
	var game := (load("res://scenes/prototype_island.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.call(&"start_solo", "zz_capture")
	var director := game.get("director") as PartyDirector
	director.enter_stage("w1_push_path")
	for i in 20:
		await physics_frame
	var w := director.world
	var me := w.acting_id()
	if not w.ledger.player_can(RuleAction.Kind.THROW, me):
		for slot in RuleLedger.HOTBAR_SIZE:
			if w.ledger.hotbar_vessel(slot, me) == null:
				w.ledger.give_player_item(RuleAction.Kind.THROW, false, slot, me)
				break
	w.player.global_position = Vector3(5.5, 0.0, 7.5)
	w.camera_rig.yaw = deg_to_rad(6.0)
	w.camera_rig.pitch = deg_to_rad(-14.0)
	for i in 20:
		await physics_frame
	w.toggle_reach()
	w.select_slot(4)  # ジャンプ
	w.set_lend_mode(TriggerMode.Kind.SINGLE_SHOT)
	var creature: Creature = w.creatures.values()[0]
	w.lend_to(creature, false)
	if state == "hit":
		while not MedalThrow.flying(w).is_empty():
			await physics_frame
		for i in 3:  # 輪は 0.35 秒で消えるので、描画が追いついたらすぐ撮る
			await process_frame
	else:
		# 手を離してから、弧のなかほどまで（尾が伸びたところ）
		var after := 0
		while after < 18 and not MedalThrow.flying(w).is_empty():
			if MedalThrow.flying(w)[0].is_released():
				after += 1
			await physics_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	ProgressStore.new().delete("zz_capture")
	quit()
