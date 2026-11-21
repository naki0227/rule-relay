extends SceneTree
## ステージの目的の一覧と、ポータルの前に戻った広場のスクリーンショット（docs/images/ux/。docs/adr/0020）。
## 撮り方は capture_range_ux.gd と同じ（lavapipe ＋ xvfb で Forward+、HUD も入ったゲーム本体の画面）:
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver vulkan --resolution 1280x720 \
##     --script res://tools/capture_objectives_ux.gd -- <state> out.png
## state: big（ステージに入った直後の大きな一覧）/ corner（途中: 鐘を鳴らした後の右上の小さな一覧）/
##        portal（「このステージから出る」で戻った直後の、ポータルの前。ゲームの画面のまま）/
##        portal_look（同じ場面で視点を振り返り、背にしたポータルを見る）/
##        pause（ステージの中の一時停止のメニュー。右に目的の一覧）
## ステージは鐘とどうぶつのある「転がる玉」（w2_rolling_shots）。

const STAGE := "w2_rolling_shots"
const PROFILE := "zz_capture_objectives"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var state := args[0] if not args.is_empty() else "big"
	var out := args[1] if args.size() > 1 else "objectives.png"
	ProgressStore.new().delete(PROFILE)
	var game := (load("res://scenes/prototype_island.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.call(&"start_solo", PROFILE)
	var director := game.get("director") as PartyDirector
	for i in 10:
		await physics_frame
	# 広場のポータルから入る（ゲームと同じ入り方）
	var hub := director.world
	hub.player.global_position = hub.def.overworld.portal(STAGE).position + Vector3(0, 0.1, 0)
	for i in 4:
		await physics_frame
	hub.interact(null)
	for i in 20:
		await physics_frame
	var w := director.world
	w.camera_rig.yaw = deg_to_rad(-20.0)
	w.camera_rig.pitch = deg_to_rad(-24.0)
	match state:
		"corner":
			for i in int((ObjectivePanel.BIG_SECONDS + 1.5) * 60.0):
				await physics_frame
			w.bells_by_key["isle_bell"].ring()
			for i in 40:
				await physics_frame
		"portal", "portal_look":
			director.request_leave_stage()
			for i in 90:
				await physics_frame
			if state == "portal_look":
				# 振り返って、背にしたポータルと立ち位置を見る（ゲームの中で視点を回したのと同じ）
				var hub_world := director.world
				hub_world.camera_rig.yaw += PI
				hub_world.camera_rig.pitch = deg_to_rad(-22.0)
				for i in 10:
					await physics_frame
		"pause":
			for i in int((ObjectivePanel.BIG_SECONDS + 1.5) * 60.0):
				await physics_frame
			var menu := (game.call(&"current_hud") as Hud).pause_menu
			menu.open()
			for i in 30:
				await process_frame
		_:
			for i in 30:
				await physics_frame
	for i in 10:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	ProgressStore.new().delete(PROFILE)
	quit()
