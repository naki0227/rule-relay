extends TestCase
## スイッチの仕掛けのモデル（art/scripts/build_switches.py。docs/adr/0014）が、部品ごとのメッシュを骨に結び、
## ゲームが使うアニメーションを持ち、状態の度合いに合わせて止めた姿が変わること。

## モデル → [アニメーション, 骨で動く部品]
const MODELS: Dictionary[String, Array] = {
	"pressure_plate": [[&"press"], ["Rim", "Top"]],
	"switch_door": [[&"open"], ["Gate", "Sill"]],
	"switch_lever": [[&"flip"], ["Stand", "Handle"]],
	"warp_stone": [[&"hover", &"warp"], ["Slab", "Crystal"]],
	"bell_timer": [[&"flip"], ["Foot", "Glass"]],
}
## 状態の度合いで止める仕掛け → [アニメーション, 動く骨]
const HELD: Dictionary[String, Array] = {
	"pressure_plate": [&"press", "b_top"],
	"switch_door": [&"open", "b_gate"],
	"switch_lever": [&"flip", "b_handle"],
}

var _nodes: Array[Node] = []


func after_each() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.queue_free()
	_nodes.clear()
	await tree.process_frame


func _model(model_name: String) -> Node3D:
	var model := ModelLibrary.instantiate(model_name)
	_nodes.append(model)
	tree.root.add_child(model)
	return model


func test_switch_models_are_rigged_parts_with_their_clips() -> void:
	for model_name: String in MODELS:
		var model := _model(model_name)
		assert_eq(model.find_children("*", "Skeleton3D", true, false).size(), 1, model_name)
		var player := RigPose.player_of(model)
		assert_ne(player, null, "%s has an animation player" % model_name)
		if player == null:
			continue
		for clip: StringName in MODELS[model_name][0]:
			assert_true(player.has_animation(clip), "%s has %s" % [model_name, clip])
		for part: String in MODELS[model_name][1]:
			var mesh := model.find_child(part, true, false) as MeshInstance3D
			assert_ne(mesh, null, "%s part %s" % [model_name, part])
			if mesh != null:
				assert_ne(mesh.skin, null, "%s part %s is skinned" % [model_name, part])


func test_holding_a_clip_moves_the_part_to_match_the_state() -> void:
	for model_name: String in HELD:
		var model := _model(model_name)
		var player := RigPose.player_of(model)
		var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var bone := skeleton.find_bone(String(HELD[model_name][1]))
		assert_ne(bone, -1, "%s has the moving bone" % model_name)
		var clip := HELD[model_name][0] as StringName
		RigPose.hold(player, clip, 0.0)
		var rest := skeleton.get_bone_global_pose(bone)
		RigPose.hold(player, clip, 1.0)
		var moved := skeleton.get_bone_global_pose(bone)
		assert_false(rest.is_equal_approx(moved), "%s moves when held at the end" % model_name)
		RigPose.hold(player, clip, 0.0)
		assert_true(skeleton.get_bone_global_pose(bone).is_equal_approx(rest), "and comes back")
