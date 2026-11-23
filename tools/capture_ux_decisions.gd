extends SceneTree
## 2026-11-23 の本人の判断（カメラの支点・戻ったら次のポータルへ向ける）の前後の画面（docs/images/ux/）。
## 撮り方は capture_objectives_ux.gd と同じ（lavapipe ＋ xvfb で Forward+、HUD も入ったゲーム本体の画面）:
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver vulkan --resolution 1280x720 \
##     --script res://tools/capture_ux_decisions.gd -- <state> out.png
## state: ledge（1-4「押し石の小道」の段の真下で、縁のセルを見上げる。見上げ 22 度）/
##        hub（1-1 をクリアして広場へ戻った直後の、ゲームの画面のまま）
## 前の画面は、変える前の main に同じスクリプトを置いて撮る（このスクリプトは main にもある呼び口だけを使う）。

const PROFILE := "zz_capture_ux_decisions"
const PATH := "w1_push_path"
## 1-4 の段の真下（段の南の壁から 0.6 m。教える場所の 2 m 東。教える場所の真後ろには子どもの生き物がいて、
## カメラの手前をふさぐので、少しずらした）
const BELOW_LEDGE := Vector3(-0.5, 0.0, 0.6)


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var state := args[0] if not args.is_empty() else "ledge"
	var out := args[1] if args.size() > 1 else "ux.png"
	ProgressStore.new().delete(PROFILE)
	var game := (load("res://scenes/prototype_island.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.call(&"start_solo", PROFILE)
	var director := game.get("director") as PartyDirector
	await _frames(10)
	match state:
		"hub":
			await _clear_intro(director)
		_:
			await _look_up_at_the_ledge(director)
	for i in 10:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	ProgressStore.new().delete(PROFILE)
	quit()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## 広場のポータルから 1-1 に入り、ゴールに立ってクリアし、広場へ戻るのを待つ。
func _clear_intro(director: PartyDirector) -> void:
	var hub := director.world
	hub.player.global_position = (
		hub.def.overworld.portal(StageCatalog.INTRO_ID).position + Vector3(0, 0.1, 0)
	)
	await _frames(4)
	hub.interact(null)
	await _frames(20)
	var w := director.world
	var goal := w.def.clear_condition.goal_area()
	w.player.global_position = Vector3(
		goal.get_center().x, goal.position.y + 0.2, goal.get_center().z
	)
	w.player.velocity = Vector3.ZERO
	await _frames(int(PartyDirector.RETURN_DELAY * 60.0) + 60)


## 1-4 の段の真下に立ち、北を向いて 22 度見上げる（はじめての 10 分の通しの before-42 と同じ見上げ方）。
func _look_up_at_the_ledge(director: PartyDirector) -> void:
	director.enter_stage(PATH)
	await _frames(10)
	var w := director.world
	w.player.global_position = BELOW_LEDGE
	w.player.velocity = Vector3.ZERO
	w.camera_rig.yaw = 0.0
	w.camera_rig.pitch = deg_to_rad(22.0)
	# 入った直後の大きな目的の札が縮むまで待つ
	await _frames(int((ObjectivePanel.BIG_SECONDS + 1.0) * 60.0))
	w.camera_rig.yaw = 0.0
	w.camera_rig.pitch = deg_to_rad(22.0)
	await _frames(10)
