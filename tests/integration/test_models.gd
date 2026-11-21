extends TestCase
## 3D モデル（art/scripts/build_cast.py・build_markers.py・build_hub_props.py）が読み込めて、
## ゲームが探す名前のノードを持ち、使う場所に差し込まれていること。

const MODELS: Array[String] = [
	"traveler",
	"creature_wish",
	"creature_kit",
	"goal_flag",
	"goal_corner",
	"checkpoint_pad",
	"entrance_gate",
	"vessel_medal",
	"ban_medal",
	"jump_boots",
	"climbing_gloves",
	"dash_feather",
	"hub_lamp",
	"hub_fence",
	"hub_planter",
	"hub_bench",
	"critter_bunny",
	"critter_lamb",
	"portal_arch",
	"ow_house",
	"ow_windmill",
	"ow_fountain",
	"ow_garden",
	"ow_lookout",
	"ow_stall",
]
## 骨格付きのモデル（art/scripts/rig.py）と、ゲームが再生するアニメーション（2026-11-21 本人の指示）。
const RIGGED: Dictionary[String, Array] = {
	"traveler": [&"idle", &"walk", &"jump", &"happy"],
	"creature_wish": [&"idle", &"walk", &"happy"],
	"creature_kit": [&"idle", &"walk", &"happy"],
	"critter_bunny": [&"idle", &"walk", &"happy"],
	"critter_lamb": [&"idle", &"walk", &"happy"],
}
## 骨格付きのモデルの部品（別々のメッシュのまま骨で動かす）。
const PARTS: Dictionary[String, Array] = {
	"traveler": ["Body", "Head", "ArmL", "ArmR", "LegL", "LegR"],
	"creature_wish": ["Body", "WingL", "WingR", "FootL", "FootR", "Sprout"],
	"critter_bunny": ["Body", "Head", "EarL", "EarR", "Tail", "FootL", "FootR"],
	"critter_lamb": ["Body", "Head", "EarL", "EarR", "Tail", "LegFL", "LegFR", "LegBL", "LegBR"],
}

var _nodes: Array[Node] = []


func after_each() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.queue_free()
	_nodes.clear()
	await tree.process_frame


func _keep(node: Node) -> Node:
	_nodes.append(node)
	return node


func _token(action: RuleAction.Kind, prohibition: bool) -> RuleToken:
	var t := RuleToken.new()
	t.action = action
	t.is_prohibition = prohibition
	return t


func test_every_model_loads_with_a_mesh() -> void:
	for model_name in MODELS:
		var model := ModelLibrary.instantiate(model_name)
		assert_ne(model, null, "%s loads" % model_name)
		if model == null:
			continue
		var meshes := model.find_children("*", "MeshInstance3D", true, false)
		assert_false(meshes.is_empty(), "%s has a mesh" % model_name)
		model.free()


func test_moving_models_have_a_skeleton_and_their_animations() -> void:
	for model_name: String in RIGGED:
		var model := ModelLibrary.instantiate(model_name)
		_keep(model)
		var skeletons := model.find_children("*", "Skeleton3D", true, false)
		assert_eq(skeletons.size(), 1, "%s has a skeleton" % model_name)
		var players := model.find_children("*", "AnimationPlayer", true, false)
		assert_eq(players.size(), 1, "%s has an animation player" % model_name)
		if players.is_empty():
			continue
		var player := players[0] as AnimationPlayer
		for clip: StringName in RIGGED[model_name]:
			assert_true(player.has_animation(clip), "%s has %s" % [model_name, clip])
		for part: String in PARTS.get(model_name, []):
			var mesh := model.find_child(part, true, false) as MeshInstance3D
			assert_ne(mesh, null, "%s part %s" % [model_name, part])
			if mesh != null:
				assert_ne(
					mesh.skin, null, "%s part %s is skinned to the skeleton" % [model_name, part]
				)


func test_windmill_and_portal_move_by_animation() -> void:
	for pair: Array in [["ow_windmill", &"spin"], ["portal_arch", &"swirl"]]:
		var model := ModelLibrary.instantiate(String(pair[0]))
		_keep(model)
		var players := model.find_children("*", "AnimationPlayer", true, false)
		assert_false(players.is_empty(), "%s has an animation" % pair[0])
		if not players.is_empty():
			assert_true((players[0] as AnimationPlayer).has_animation(pair[1] as StringName))


func test_player_model_has_joints_and_takes_each_players_color() -> void:
	var model := ModelLibrary.instantiate("traveler")
	_keep(model)
	for joint: String in ["Body", "Head", "ArmL", "ArmR", "LegL", "LegR"]:
		assert_ne(model.find_child(joint, true, false), null, "joint %s" % joint)
	for player_id in range(1, 5):
		ArtPalette.tint_player(model, player_id)
		var color := _override_color(model, ArtPalette.ACCENT)
		assert_eq(color, ArtPalette.PLAYER_COLORS[player_id - 1], "player %d color" % player_id)
	assert_eq(ArtPalette.player_index(5), 0, "fifth player reuses the first color")


func test_avatar_color_follows_player_id() -> void:
	var avatar := PlayerAvatar.new()
	_keep(avatar)
	tree.root.add_child(avatar)
	avatar.player_id = 3
	assert_eq(_override_color(avatar, ArtPalette.ACCENT), ArtPalette.PLAYER_COLORS[2])


func test_goal_marker_has_flag_corners_and_floor() -> void:
	var marker := GoalMarker.new()
	_keep(marker)
	marker.setup(AABB(Vector3(-1.0, -0.1, -1.0), Vector3(3.0, 2.0, 2.0)))
	tree.root.add_child(marker)
	assert_ne(marker.find_child("Flag", true, false), null, "flag cloth to sway")
	var corners := marker.find_children("Corner*", "", false, false)
	assert_eq(corners.size(), 4, "a light on each corner")
	assert_ne(marker.get_node_or_null("Floor"), null)
	assert_almost(marker.position.y, 0.0, 0.001, "stands on the floor of the area")


func test_world_items_pick_a_model_by_token() -> void:
	assert_eq(WorldItem.model_for(_token(RuleAction.Kind.JUMP, false)), "vessel_medal")
	assert_eq(WorldItem.model_for(_token(RuleAction.Kind.JUMP, true)), "ban_medal")
	assert_eq(WorldItem.model_for(_token(RuleAction.Kind.HIGH_JUMP, false)), "jump_boots")
	assert_eq(WorldItem.model_for(_token(RuleAction.Kind.CLIMB, false)), "climbing_gloves")
	assert_eq(WorldItem.model_for(_token(RuleAction.Kind.DASH, false)), "dash_feather")
	assert_eq(WorldItem.model_for(_token(RuleAction.Kind.DASH, true)), "ban_medal")


func test_medal_shows_the_action_glyph_on_both_faces() -> void:
	var item := WorldItem.new()
	_keep(item)
	var vessel := RuleVessel.new()
	vessel.id = 7
	item.setup(vessel, _token(RuleAction.Kind.DASH, true))
	var glyphs := item.find_children("Glyph*", "Sprite3D", true, false)
	assert_eq(glyphs.size(), 2)
	assert_eq((glyphs[0] as Sprite3D).texture.resource_path, "res://assets/icons/glyph_dash.png")


func test_kit_uses_its_own_model() -> void:
	var world := GameWorld.new()
	_keep(world)
	tree.root.add_child(world)
	var kit := world.add_creature(Vector3.ZERO, Creature.MODEL_KIT)
	var model := kit.find_child("Model", true, false)
	assert_ne(model, null)
	assert_ne(model.find_child("Kit", true, false), null, "child creature mesh")


## 広場（オーバーワールド）は飾り付けられ、入口はどれもワープの門（ポータル）。閉じた門は渦が灰色。
func test_overworld_is_dressed_and_entrances_are_portals() -> void:
	var world := StageWorld.new()
	_keep(world)
	world.setup(Overworld.build(OverworldState.first_visit()))
	tree.root.add_child(world)
	var dressing := world.get_node_or_null("OverworldDressing")
	assert_ne(dressing, null)
	assert_gt(dressing.get_node("Props").get_child_count(), 40, "trees, flowers, lamps, benches")
	var portals := dressing.find_children("Portal_*", "OverworldPortal", false, false)
	assert_eq(portals.size(), world.def.entrances.size(), "one portal per entrance")
	var intro := dressing.get_node("Portal_%s" % StageCatalog.INTRO_ID) as OverworldPortal
	var relay := dressing.get_node("Portal_%s" % StageCatalog.RELAY_ID) as OverworldPortal
	assert_true(intro.is_open())
	assert_true(intro.caption().contains("はじめはここから"))
	assert_false(relay.is_open())
	assert_true(relay.caption().contains("まだ開いていない"))
	var swirl_color := _override_color(relay, "SwirlDeep")
	assert_eq(swirl_color, OverworldPortal.DIM_SWIRL, "a locked portal is dim")
	var teasers := dressing.find_children("Teaser_*", "OverworldPortal", false, false)
	assert_eq(teasers.size(), 3, "a sealed gate for each optional world")


func _override_color(root: Node, material_name: String) -> Color:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for i in mesh_instance.mesh.get_surface_count():
			var base := mesh_instance.mesh.surface_get_material(i) as StandardMaterial3D
			if base != null and base.resource_name == material_name:
				var tinted := mesh_instance.get_surface_override_material(i) as StandardMaterial3D
				return tinted.albedo_color if tinted != null else Color.BLACK
	return Color.BLACK
