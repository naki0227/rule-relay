extends SceneTree
## 広場（オーバーワールド）のスクリーンショット（docs/images/overworld/）。撮り方は capture_models.gd と同じ
## （lavapipe ＋ xvfb で Forward+）:
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver vulkan --resolution 1280x720 \
##     --script res://tools/capture_overworld.gd -- <state> <view> out.png
## state: first（製品版の初めて: 何もクリアしていない・地方は閉じている）/ all（全部開けて全部クリア）
## view: spawn（出現地点の後ろから）/ aerial（上から全体）/ meadow（草原を斜め上から）/ portal（門の近く）/
##       village（クリアで建った建物と住む生き物）/ puzzle（草原の西の高台と札の門）

const MAX_STEP_FRAMES := 90


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var state_name := args[0] if not args.is_empty() else "first"
	var view := args[1] if args.size() > 1 else "spawn"
	var out := args[2] if args.size() > 2 else "overworld.png"
	var state := (
		OverworldState.first_visit() if state_name == "first" else OverworldState.everything(true)
	)
	var world := StageWorld.new()
	world.setup(Overworld.build(state))
	root.add_child(world)
	for i in 30:
		await process_frame
	var camera := Camera3D.new()
	world.add_child(camera)
	match view:
		"aerial":
			_look(camera, Vector3(2.0, 92.0, 62.0), Vector3(2.0, 0.0, -26.0), 50.0)
			for node in world.find_children("*", "WorldEnvironment", false, false):
				(node as WorldEnvironment).environment.fog_enabled = false  # 遠くまで見せる
		"meadow":
			_look(camera, Vector3(16.0, 20.0, 30.0), Vector3(0.0, 0.0, -2.0), 55.0)
		"portal":
			world.player.global_position = Vector3(-1.0, 0.0, 7.5)
			_look(camera, Vector3(3.0, 3.2, 13.0), Vector3(1.5, 1.4, 4.0), 50.0)
		"village":
			_look(camera, Vector3(-9.0, 5.5, 9.5), Vector3(1.0, 1.0, -3.0), 52.0)
		"puzzle":
			_look(camera, Vector3(-2.0, 13.0, 26.0), Vector3(-14.0, 1.0, 11.0), 55.0)
		_:
			camera.queue_free()
			world.camera_rig.yaw = 0.0
			world.camera_rig.pitch = deg_to_rad(-14.0)
	for i in MAX_STEP_FRAMES:
		await physics_frame
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	quit()


func _look(camera: Camera3D, from: Vector3, at: Vector3, fov: float) -> void:
	camera.fov = fov
	camera.far = 400.0
	camera.global_position = from
	camera.look_at(at)
	camera.current = true
