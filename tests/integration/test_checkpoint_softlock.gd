extends TestCase
## 詰み防止の結合テスト: 保存の拒否、ひとつ前・最初への復帰、落ちたブロックの救済、
## 移動途中の保存、Esc メニュー（企画書 9）。

const JUMP := RuleAction.Kind.JUMP

var island: PrototypeIsland


func before_each() -> void:
	island = PrototypeIsland.new()
	tree.root.add_child(island)
	await wait_physics_frames(10)


func after_each() -> void:
	tree.paused = false
	island.queue_free()
	await tree.process_frame


func stand_on_checkpoint() -> void:
	island.player.global_position = island.checkpoint_center
	island.player.velocity = Vector3.ZERO
	await wait_physics_frames(6)


func test_save_on_the_pad() -> void:
	await stand_on_checkpoint()
	assert_true(island.save_checkpoint())
	assert_eq(island.checkpoint_save_count(), 1)


func test_save_is_refused_mid_air() -> void:
	await stand_on_checkpoint()
	island.press_action(JUMP)
	await wait_physics_frames(10)
	assert_false(island.player.is_on_floor())
	assert_false(island.save_checkpoint(), "no save while airborne")
	assert_eq(island.checkpoint_save_count(), 0)


func test_save_is_refused_when_player_could_never_walk_again() -> void:
	await stand_on_checkpoint()
	for action: RuleAction.Kind in CheckpointPolicy.MOVE_ACTIONS:
		island.ledger.move_to_inventory(island.ledger.hotbar_vessel(int(action)).id)
	assert_false(island.save_checkpoint())
	assert_eq(island.checkpoint_save_count(), 0)


func test_previous_checkpoint_undoes_a_bad_save() -> void:
	await stand_on_checkpoint()
	island.save_checkpoint()  # 良い保存
	# 悪い状態: ジャンプ禁止を拾い、ジャンプ能力をしまってから保存してしまう（歩けるので保存は通る）
	island.player.global_position = Vector3(0.5, 0.0, -6.0)
	await wait_physics_frames(4)
	island.interact(island.bouncer)
	await stand_on_checkpoint()
	assert_true(island.save_checkpoint())
	assert_false(island.ledger.player_can(JUMP))

	assert_true(island.restore_previous_checkpoint())
	assert_true(island.ledger.player_can(JUMP), "back to the good save")
	assert_eq(island.checkpoint_save_count(), 1, "the bad save is discarded")
	island.player.global_position = Vector3(0.5, 0.0, 30.0)  # 島の外へ落ちる
	await wait_physics_frames(90)
	assert_true(island.ledger.player_can(JUMP), "falling no longer returns to the bad save")


func test_restart_island_goes_back_to_the_start() -> void:
	await stand_on_checkpoint()
	island.select_slot(4)
	island.player.global_position = Vector3(3.5, 0.0, -3.0)
	await wait_physics_frames(4)
	island.lend_to(island.row[0], false)
	await stand_on_checkpoint()
	island.save_checkpoint()
	island.restart_island()
	assert_eq(island.checkpoint_save_count(), 0)
	assert_true(island.ledger.player_can(JUMP))
	assert_eq(island.ledger.tokens_on(island.row[0].entity_id).size(), 0)
	assert_false(island.can_restore_previous_checkpoint())


func test_saving_mid_step_restores_onto_the_grid() -> void:
	await stand_on_checkpoint()
	island.select_slot(0)
	island.player.global_position = Vector3(8.5, 0.0, 0.0)
	await wait_physics_frames(4)
	island.lend_to(island.mover, false)
	island.press_action(RuleAction.Kind.FORWARD)  # 単発で北へ1マス
	await wait_physics_frames(10)  # 移動の途中
	assert_true(island.mover.is_moving_horizontally())
	var saved_state := island.mover.capture_state()
	var mid := saved_state["position"] as Vector3
	island.restore_checkpoint()  # 初期状態へ
	island.mover.restore_state(saved_state)  # 移動途中の状態を直接戻す
	assert_almost(island.mover.global_position.z, mid.z, 0.01)
	await wait_physics_frames(40)
	assert_eq(island.mover.cell(), Vector3i(8, 0, -3), "finishes the step on the grid")
	assert_almost(island.mover.global_position.z, -2.5, 0.01)


func test_block_that_falls_off_the_island_is_rescued() -> void:
	island.select_slot(4)
	island.player.global_position = Vector3(3.5, 0.0, -3.0)
	await wait_physics_frames(4)
	island.cycle_mode()
	island.lend_to(island.row[0], false)
	assert_false(island.ledger.player_can(JUMP))
	island.row[0].teleport(Vector3(30.5, 0.5, 30.5), 0.0)  # 島の外
	await wait_physics_frames(120)
	assert_eq(island.row[0].cell(), Vector3i(3, 0, -5), "back at its home cell")
	assert_true(island.ledger.player_can(JUMP), "the lent ability came back")
	assert_true(island.ledger.validate().is_empty())


func test_falling_block_blocks_saving() -> void:
	await stand_on_checkpoint()
	island.mover.teleport(Vector3(30.5, 0.5, 30.5), 0.0)
	await wait_physics_frames(30)  # 地面の高さより下まで落ちた（まだ救済される前）
	assert_lt(island.mover.global_position.y, -0.5)
	assert_false(island.save_checkpoint())


func test_pause_menu_restores_without_any_ability() -> void:
	var menu := PauseMenu.new()
	menu.world = island
	tree.root.add_child(menu)
	# 能力を全部しまっても、メニューの復帰操作は使える
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := island.ledger.hotbar_vessel(slot)
		if v != null:
			island.ledger.move_to_inventory(v.id)
	menu.open()
	assert_true(tree.paused, "the game is paused while the menu is open")
	menu.choose("restart")
	assert_true(menu.is_open(), "restart needs a second press")
	menu.choose("restart")
	assert_false(menu.is_open())
	assert_false(tree.paused)
	assert_true(island.ledger.player_can(RuleAction.Kind.FORWARD), "back to the island start")
	menu.queue_free()
