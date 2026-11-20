extends TestCase
## ダッシュ: 方向キーの向き（無ければ体の向き）へマス単位でまっすぐ水平に突進し、途中の穴は落ちずに
## 抜ける。W/A/D のどれかが要り、後ろ向きには突進しない（どちらも 2026-11-20 本人）。

const DASH := RuleAction.Kind.DASH

var world: GameWorld


func before_each() -> void:
	world = GameWorld.new()
	tree.root.add_child(world)
	# 南の台（z 0〜3）と北の台（z -5〜-2）の間に、幅 2 マスの底なしの谷（z -2〜-1 は空ける）
	(
		world
		. build_terrain(
			[
				[Vector3i(-2, -1, 0), Vector3i(2, -1, 3), "grass"],
				[Vector3i(-2, -1, -6), Vector3i(2, -1, -3), "grass"],
			]
		)
	)
	world.spawn_player(Vector3(0.5, 0.0, 0.5))
	world.ledger.give_player_item(RuleAction.Kind.FORWARD, false, 0)
	world.ledger.give_player_item(DASH, false, 1)
	await wait_physics_frames(10)


func after_each() -> void:
	world.queue_free()
	await tree.process_frame


func test_dash_crosses_a_gap() -> void:
	world.player.view_yaw = 0.0
	world.player.move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(1)
	world.press_action(DASH)
	assert_true(world.player.is_dashing())
	await wait_physics_frames(30)
	world.player.move_intent = Vector2.ZERO
	await wait_physics_frames(20)
	assert_lt(world.player.global_position.z, -2.0, "landed on the far side")
	assert_gt(world.player.global_position.y, -0.5, "did not fall")


func test_without_dash_the_gap_is_deadly() -> void:
	var v := world.ledger.hotbar_vessel(1)
	world.ledger.move_to_inventory(v.id)
	world.player.view_yaw = 0.0
	world.player.move_intent = Vector2(0.0, 1.0)
	world.press_action(DASH)
	assert_false(world.player.is_dashing(), "no dash ability on the hotbar")
	await wait_physics_frames(60)
	assert_lt(world.player.global_position.y, -1.0, "walked into the gap")


func test_two_dashes_go_twice_as_far() -> void:
	world.ledger.give_player_item(DASH, false, 2)
	assert_eq(world.ledger.ability_count(DASH), 2)
	world.player.view_yaw = 0.0
	var start := world.player.global_position.z
	world.press_action(DASH)
	await wait_physics_frames(40)
	assert_almost(start - world.player.global_position.z, 6.0, 0.6, "3 cells x 2")


func test_a_block_dashes_north_over_the_gap() -> void:
	var block := world.add_block(Vector3i(0, 0, 0))
	await wait_physics_frames(10)
	block.perform(DASH)
	await wait_physics_frames(40)
	assert_almost(block.global_position.z, 0.5 - 3.0, 0.1, "three cells north")
	assert_gt(block.global_position.y, 0.0, "it did not fall in the gap while dashing")


func test_no_dash_without_w_a_or_d() -> void:
	var v := world.ledger.hotbar_vessel(0)
	world.ledger.move_to_inventory(v.id)
	world.ledger.give_player_item(RuleAction.Kind.BACK, false, 0)
	world.player.view_yaw = 0.0
	world.press_action(DASH)
	assert_false(world.player.is_dashing(), "S alone does not allow a dash")


func test_holding_s_does_not_dash_backward() -> void:
	world.ledger.give_player_item(RuleAction.Kind.BACK, false, 2)
	world.player.view_yaw = 0.0
	world.player.move_intent = Vector2(0.0, -1.0)
	var start := world.player.global_position.z
	world.press_action(DASH)
	assert_true(world.player.is_dashing(), "W is owned, so it dashes the way the body faces")
	await wait_physics_frames(1)
	world.player.move_intent = Vector2.ZERO
	await wait_physics_frames(40)
	assert_lt(world.player.global_position.z, start, "went forward, not backward")


## ダッシュの音（dash、3回目の候補 T17）: 突進が始まったときに1回だけ、自分の位置から鳴る。
## 能力が無くて突進しなかった押下では鳴らない。
func test_dash_sound_plays_once_when_the_dash_starts() -> void:
	var heard: Array[StringName] = []
	world.sound_requested.connect(
		func(event: StringName, _at: Vector3, positional: bool) -> void:
			heard.append(StringName("%s:%s" % [event, "world" if positional else "ui"]))
	)
	world.player.view_yaw = 0.0
	world.press_action(DASH)
	assert_true(world.player.is_dashing())
	assert_eq(heard.count(&"dash:world"), 1, "dash sound on the press that starts the dash")
	var v := world.ledger.hotbar_vessel(1)
	world.ledger.move_to_inventory(v.id)
	await wait_physics_frames(60)
	world.press_action(DASH)
	assert_eq(heard.count(&"dash:world"), 1, "no sound without the dash ability")
