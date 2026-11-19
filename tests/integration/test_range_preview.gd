extends TestCase
## 範囲付与のプレビューと、円形 UI で選ぶ発動方式（企画書 8 の要検証項目）。

const JUMP_SLOT := 4

var island: PrototypeIsland


func before_each() -> void:
	island = PrototypeIsland.new()
	tree.root.add_child(island)
	await wait_physics_frames(10)
	island.player.global_position = Vector3(4.5, 0.0, -2.5)
	await wait_physics_frames(5)
	island.select_slot(JUMP_SLOT)


func after_each() -> void:
	island.queue_free()
	await tree.process_frame


func test_preview_matches_the_actual_range_lend() -> void:
	island.begin_range_preview()
	var preview := island.update_range_preview(island.row[0])
	var ids := preview["ids"] as PackedInt32Array
	assert_true(ids.size() >= 3, "row blocks are in range")
	for id in ids:
		assert_true(island.blocks[id].is_previewed(), "previewed block %d is marked" % id)
	assert_false(island.mover.is_previewed() and not ids.has(island.mover.entity_id))

	var result := island.commit_range_preview(island.row[0])
	assert_eq(result, RuleLedger.LendResult.OK)
	var t := island.ledger.token(island.selected_vessel().token_id)
	assert_eq(t.holder_ids, ids, "lend targets exactly what the preview showed")
	assert_false(island.is_range_preview_active())
	for block: RuleBlock in island.blocks.values():
		assert_false(block.is_previewed(), "preview marks are cleared after commit")


func test_preview_does_not_change_ownership() -> void:
	var before := island.ledger.snapshot()
	island.begin_range_preview()
	island.update_range_preview(island.row[0])
	assert_eq(island.ledger.snapshot(), before, "preview is read-only")
	assert_true(island.ledger.player_can(RuleAction.Kind.JUMP))


func test_cancel_leaves_nothing_behind() -> void:
	island.begin_range_preview()
	island.update_range_preview(island.row[0])
	island.cancel_range_preview()
	assert_false(island.is_range_preview_active())
	assert_true(island.ledger.player_can(RuleAction.Kind.JUMP), "nothing was lent")
	for block: RuleBlock in island.blocks.values():
		assert_false(block.is_previewed())


func test_preview_explains_why_it_cannot_lend() -> void:
	island.begin_range_preview()
	var no_target := island.update_range_preview(null)
	assert_eq((no_target["ids"] as PackedInt32Array).size(), 0)
	assert_ne(String(no_target["reason"]), "")

	island.player.global_position = Vector3(0.5, 0.0, 6.0)
	await wait_physics_frames(3)
	var too_far := island.preview_range(island.row[0])
	assert_true(String(too_far["reason"]).contains("届きません"))

	island.player.global_position = Vector3(4.5, 0.0, -2.5)
	await wait_physics_frames(3)
	island.ledger.give_player_item(RuleAction.Kind.JUMP, true, 8)
	island.select_slot(8)
	var ban := island.preview_range(island.row[0])
	assert_true(String(ban["reason"]).contains("禁止"), "prohibitions cannot be range-lent")


func test_all_three_modes_can_be_selected() -> void:
	assert_true(island.set_lend_mode(TriggerMode.Kind.SIGNAL))
	assert_eq(island.lend_mode, TriggerMode.Kind.SIGNAL)
	assert_true(island.set_lend_mode(TriggerMode.Kind.REPEAT))
	assert_eq(island.lend_mode, TriggerMode.Kind.REPEAT)
	island.cycle_mode()
	assert_eq(island.lend_mode, TriggerMode.Kind.SIGNAL, "Q: repeat -> signal")
	island.cycle_mode()
	assert_eq(island.lend_mode, TriggerMode.Kind.SINGLE_SHOT, "Q: signal -> single shot")


func test_radial_menu_drag_selects_mode() -> void:
	var menu := RadialMenu.new()
	tree.root.add_child(menu)
	menu.open(TriggerMode.Kind.SINGLE_SHOT)
	menu.drag(Vector2(20, 10))
	assert_eq(menu.picked_index(), -1, "inside the dead zone nothing is picked")
	menu.drag(Vector2(60, 40))
	assert_eq(RadialSelector.MODES[menu.picked_index()], TriggerMode.Kind.REPEAT)
	menu.drag(Vector2(0, -900))
	assert_eq(menu.offset.length(), RadialMenu.MAX_DRAG, "drag is clamped")
	menu.queue_free()
