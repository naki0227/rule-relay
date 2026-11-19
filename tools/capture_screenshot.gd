extends SceneTree
## メインシーンを描画して、範囲・繰り返しを付与した状態のスクリーンショットを保存する。
## GPU のない Linux ではソフトウェア描画で撮れる。ゲームと同じ Forward+ で撮るには
## Vulkan のソフトウェア実装（mesa-vulkan-drivers の lavapipe）を使う:
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1600x900x24" \
##     godot --rendering-driver vulkan --resolution 1600x900 \
##     --script res://tools/capture_screenshot.gd -- out.png
## opengl3 でも撮れるが、互換レンダラーなので色が白っぽく出る（実際の見た目ではない）:
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 \
##     --resolution 1600x900 --script res://tools/capture_screenshot.gd -- out.png
## 提出用の画面写真は Windows 実機で撮り直す（ソフトウェア描画は見た目が異なる場合がある）。


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if not args.is_empty() else "screenshot.png"
	var scene := (load("res://scenes/prototype_island.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 30:
		await process_frame
	var island := scene.get_node("Island") as PrototypeIsland
	island.camera_rig.yaw = deg_to_rad(-15.0)
	island.camera_rig.pitch = deg_to_rad(-25.0)
	island.player.global_position = Vector3(4.0, 0.0, -2.0)
	for i in 20:
		await physics_frame
	island.select_slot(4)
	island.cycle_mode()
	island.lend_to(island.row[0], true)
	for i in 50:
		await physics_frame
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	quit()
