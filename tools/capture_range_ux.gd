extends SceneTree
## 地面に範囲で渡す場面のスクリーンショット（docs/images/ux/）。撮り方は capture_overworld.gd と同じ
## （lavapipe ＋ xvfb で Forward+、HUD も入ったゲーム本体の画面）:
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver vulkan --resolution 1280x720 \
##     --script res://tools/capture_range_ux.gd -- <state> out.png
## state: preview（右クリックを押している間のプレビュー）/ lent（繰り返しで地面へ範囲付与した後）/
##        wish（子どもの生き物のそば: 巣の光の柱・頭の上の印・願いの一文）/
##        wall（移動だけをもらった生き物が、巣に近い段のふもとまで歩き、吹き出しにジャンプのメダルを出す。ADR 0019）/
##        nest（始まりの場所から、遠くの巣のモデルと光の柱を見る。ADR 0019 の 10）
## 場所は「押し石の小道」（1-4）の原っぱ。


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var state := args[0] if not args.is_empty() else "preview"
	var out := args[1] if args.size() > 1 else "range.png"
	var game := (load("res://scenes/prototype_island.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.call(&"start_solo", "zz_capture")
	var director := game.get("director") as PartyDirector
	director.enter_stage("w1_push_path")
	for i in 20:
		await physics_frame
	var w := director.world
	if state == "wish":
		await _capture_wish(w, out)
		return
	if state == "wall":
		await _capture_wall(w, out)
		return
	if state == "nest":
		await _capture_nest(w, out)
		return
	w.player.global_position = Vector3(2.5, 0.0, 4.5)
	w.camera_rig.yaw = deg_to_rad(20.0)
	w.camera_rig.pitch = deg_to_rad(-38.0)
	for i in 20:
		await physics_frame
	w.select_slot(4)  # ジャンプ
	w.set_lend_mode(TriggerMode.Kind.REPEAT)
	if state == "lent":
		w.lend_to(w.aimed_block(), true)
		for i in 6:  # 繰り返しの最初のジャンプの前（範囲の円が地面に見えている間）
			await physics_frame
	else:
		w.begin_range_preview()
	for i in 10:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	ProgressStore.new().delete("zz_capture")
	quit()


func _capture_wish(w: StageWorld, out: String) -> void:
	w.player.global_position = Vector3(-1.0, 0.0, 6.0)
	w.camera_rig.yaw = deg_to_rad(10.0)
	w.camera_rig.pitch = deg_to_rad(-12.0)
	for i in 60:
		await physics_frame
	for i in 10:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	ProgressStore.new().delete("zz_capture")
	quit()


## 縁を削って 1 段の階段を作り、子どもの生き物のジャンプを借りてから D だけを渡す（ADR 0019）。
func _capture_wall(w: StageWorld, out: String) -> void:
	var kit := w.creatures[int(w.entity_ids["kit"])]
	w.player.global_position = Vector3(1.5, 0.0, 0.5)
	for i in 10:
		await physics_frame
	w.select_slot(2)  # S
	w.set_lend_mode(TriggerMode.Kind.SINGLE_SHOT)
	w.lend_to(w.terrain_target(Vector3i(-1, 1, -1)), false)
	w.press_action(RuleAction.Kind.BACK)
	for i in 60:
		await physics_frame
	w.player.global_position = kit.global_position + Vector3(1.4, 0.0, 0.0)
	for i in 10:
		await physics_frame
	w.interact(kit)  # 生き物のジャンプを借りる
	w.select_slot(3)  # D
	w.set_lend_mode(TriggerMode.Kind.NONE)
	w.lend_to(kit, false)
	for i in 600:
		if kit.bubble_key() == CreatureWishView.KEY_NEED_JUMP:
			break
		await physics_frame
	w.player.global_position = kit.global_position + Vector3(-1.1, 0.0, 1.6)
	w.camera_rig.yaw = deg_to_rad(-14.0)
	w.camera_rig.pitch = deg_to_rad(-4.0)
	for i in 40:
		await physics_frame
	for i in 10:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	ProgressStore.new().delete("zz_capture")
	quit()


## 始まりの場所から巣のほうを見る（巣のモデル・光の柱が島の向こうから見える）。
func _capture_nest(w: StageWorld, out: String) -> void:
	w.camera_rig.yaw = deg_to_rad(0.0)
	w.camera_rig.pitch = deg_to_rad(-12.0)
	for i in 40:
		await physics_frame
	for i in 10:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	ProgressStore.new().delete("zz_capture")
	quit()
