extends SceneTree
## 3D モデルの確認用スクリーンショット（広場・モデルの並び・巣の島のゴール）。
## 撮り方は capture_screenshot.gd と同じ（lavapipe ＋ xvfb で Forward+）:
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1600x900x24" \
##     godot --rendering-driver vulkan --resolution 1600x900 \
##     --script res://tools/capture_models.gd -- <lineup|hub|nest|pads> out.png
## lineup: 4色のプレイヤー・生き物と子ども・器のメダル・装備・目印を広場に並べる
## hub: 広場の飾り付けと入口の門 / nest: 巣の島のゴールの旗と子ども
## pads: チェックポイントの台とゴールの目印を近くから


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if not args.is_empty() else "lineup"
	var out := args[1] if args.size() > 1 else "models.png"
	var world := StageWorld.new()
	world.setup(OpenIslandsExtra.creature_nest() if mode == "nest" else StageCatalog.hub())
	root.add_child(world)
	for i in 20:
		await process_frame
	match mode:
		"lineup":
			_lineup(world)
		"hub":
			_hub(world)
		"nest":
			_nest(world)
		"pads":
			_pads(world)
	for i in 40:
		await physics_frame
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	quit()


func _lineup(world: StageWorld) -> void:
	var base := Vector3(0.0, 0.0, 0.0)
	world.player.global_position = base + Vector3(-2.4, 0.0, -1.6)
	(world.player.get_node("Visual") as Node3D).rotation.y = PI  # こちらを向かせる
	for id: int in [2, 3, 4]:
		var at := base + Vector3(-2.4 + 0.9 * (id - 1), 0.0, -1.6)
		var avatar := WorldParty.add_avatar(world, id, at)
		avatar.apply_remote(at, PI + 0.3 * (id - 2), false, true)
	for look: String in [Creature.MODEL_WISH, Creature.MODEL_KIT]:
		var x := 1.4 if look == Creature.MODEL_WISH else 2.3
		var creature := world.add_creature(base + Vector3(x, 0.0, -1.3), look)
		creature.set_physics_process(false)
		(creature.get_node("Body") as Node3D).rotation.y = PI - 0.3
	var actions: Array[RuleAction.Kind] = [
		RuleAction.Kind.JUMP,
		RuleAction.Kind.JUMP,
		RuleAction.Kind.HIGH_JUMP,
		RuleAction.Kind.CLIMB,
		RuleAction.Kind.DASH,
	]
	var parts: Array[RuleVessel.Part] = [
		RuleVessel.Part.NONE,
		RuleVessel.Part.NONE,
		RuleVessel.Part.FEET,
		RuleVessel.Part.HANDS,
		RuleVessel.Part.NONE,
	]
	for i in actions.size():
		var at := base + Vector3(-2.5 + 1.25 * i, -0.2, 0.6)
		world.ledger.place_in_world(actions[i], i == 1, at, parts[i])
	for model: Node3D in world.find_children("WorldItem*", "", true, false):
		model.set_process(false)
		for label: Node in model.find_children("*", "Label3D", false, false):
			(label as Label3D).visible = false  # 並べると重なるので、この写真では消す
		(model.get_node("Visual") as Node3D).rotation.y = 0.5
	var camera := Camera3D.new()
	camera.fov = 40.0
	world.add_child(camera)
	camera.global_position = Vector3(0.0, 2.4, 5.0)
	camera.look_at(Vector3(0.0, 0.5, -0.8))
	camera.current = true


func _hub(world: StageWorld) -> void:
	world.player.global_position = Vector3(-1.5, 0.0, 1.0)
	for id: int in [2, 3, 4]:
		var avatar := WorldParty.add_avatar(world, id, Vector3(-1.5 + 0.9 * (id - 1), 0.0, 1.4))
		avatar.remote_position = avatar.position
	world.camera_rig.yaw = deg_to_rad(10.0)
	world.camera_rig.pitch = deg_to_rad(-18.0)


func _nest(world: StageWorld) -> void:
	var goal := world.def.clear_condition.goal_area()
	var center := goal.get_center()
	world.player.global_position = Vector3(center.x + 1.5, goal.end.y + 0.5, goal.end.z + 1.5)
	world.camera_rig.yaw = deg_to_rad(20.0)
	world.camera_rig.pitch = deg_to_rad(-28.0)


func _pads(world: StageWorld) -> void:
	var pad := ModelLibrary.instantiate("checkpoint_pad")
	pad.position = Vector3(-2.2, 0.0, 0.5)
	world.add_child(pad)
	var goal := GoalMarker.new()
	goal.setup(AABB(Vector3(0.8, -0.1, -1.6), Vector3(3.0, 2.0, 3.0)))
	world.add_child(goal)
	world.player.global_position = Vector3(-2.2, 0.0, 0.5)
	(world.player.get_node("Visual") as Node3D).rotation.y = PI * 0.75
	var camera := Camera3D.new()
	camera.fov = 45.0
	world.add_child(camera)
	camera.global_position = Vector3(0.0, 3.0, 6.5)
	camera.look_at(Vector3(0.0, 1.0, -0.5))
	camera.current = true
