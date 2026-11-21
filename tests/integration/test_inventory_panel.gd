extends TestCase
## 持ち物画面: 検索・絞り込み・状態表示と、ホットバーとの出し入れ。

var ledger: RuleLedger
var panel: InventoryPanel
var jump: RuleVessel
var ban: RuleVessel
var stored_w: RuleVessel


func before_each() -> void:
	ledger = RuleLedger.new()
	jump = ledger.give_player_item(RuleAction.Kind.JUMP, false, 4)
	stored_w = ledger.give_player_item(RuleAction.Kind.FORWARD, false)
	ban = ledger.give_player_item(RuleAction.Kind.JUMP, true)
	panel = InventoryPanel.new()
	panel.ledger = ledger
	tree.root.add_child(panel)
	panel.open()


func after_each() -> void:
	panel.queue_free()
	await tree.process_frame


func test_lists_everything_with_icons() -> void:
	assert_eq(panel.visible_vessel_ids(), PackedInt32Array([jump.id, stored_w.id, ban.id]))
	assert_false(
		panel.is_typing(), "opening does not focus the search box (number keys work at once)"
	)


func test_search_and_category_narrow_the_list() -> void:
	panel.set_query("ジャンプ", InventoryQuery.Category.ALL)
	assert_eq(panel.visible_vessel_ids(), PackedInt32Array([jump.id, ban.id]))
	panel.set_query("ジャンプ", InventoryQuery.Category.PROHIBITION)
	assert_eq(panel.visible_vessel_ids(), PackedInt32Array([ban.id]))
	panel.set_query("", InventoryQuery.Category.EQUIPMENT)
	assert_eq(panel.visible_vessel_ids().size(), 0)


func test_move_selected_to_hotbar_and_back() -> void:
	panel.set_query("前進", InventoryQuery.Category.ALL)
	assert_true(panel.select_vessel(stored_w.id))
	assert_true(panel.move_selected_to_hotbar(0))
	assert_true(ledger.player_can(RuleAction.Kind.FORWARD), "W works once on the hotbar")
	assert_true(panel.move_selected_to_inventory())
	assert_false(ledger.player_can(RuleAction.Kind.FORWARD), "and stops working when stored")


func test_storing_a_prohibition_keeps_it_applied() -> void:
	panel.set_query("禁止", InventoryQuery.Category.ALL)
	panel.select_vessel(ban.id)
	panel.move_selected_to_hotbar(8)
	assert_true(ledger.player_prohibited(RuleAction.Kind.JUMP))
	panel.move_selected_to_inventory()
	assert_true(
		ledger.player_prohibited(RuleAction.Kind.JUMP), "cannot dodge a prohibition by moving it"
	)


func test_selection_survives_refresh() -> void:
	panel.select_vessel(ban.id)
	panel.refresh()
	assert_eq(panel.selected_vessel_id(), ban.id)


func test_every_token_kind_has_an_icon() -> void:
	for is_ban: bool in [false, true]:
		for action: RuleAction.Kind in RuleAction.ALL:
			var t := RuleToken.new()
			t.action = action
			t.is_prohibition = is_ban
			assert_ne(ItemIcons.for_token(t), null, "%s %s" % [action, is_ban])


func test_bag_grid_shows_only_bag_items() -> void:
	assert_eq(panel.bag_vessel_ids(), PackedInt32Array([stored_w.id, ban.id]))
	panel.drop_on_hotbar(stored_w.id, 2)
	panel.refresh()
	assert_eq(panel.bag_vessel_ids(), PackedInt32Array([ban.id]), "moved out of the bag")
	assert_true(ledger.player_can(RuleAction.Kind.FORWARD))


func test_drag_between_hotbar_slots_swaps() -> void:
	var w := stored_w
	panel.drop_on_hotbar(w.id, 0)
	panel.drop_on_hotbar(jump.id, 0)  # ジャンプ（5番）を1番へ → W は 5番へ
	assert_eq(ledger.hotbar_vessel(0), jump)
	assert_eq(ledger.hotbar_vessel(4), w)
	assert_true(ledger.validate().is_empty(), str(ledger.validate()))


func test_drop_into_bag_turns_ability_off_but_not_prohibition() -> void:
	panel.drop_into_bag(jump.id)
	assert_false(ledger.player_can(RuleAction.Kind.JUMP), "ability stops in the bag")
	panel.drop_on_hotbar(ban.id, 8)
	panel.drop_into_bag(ban.id)
	assert_true(ledger.player_prohibited(RuleAction.Kind.JUMP), "prohibition still applies")


func test_lent_items_stay_in_place_and_are_listed_by_reference() -> void:
	ledger.register_entity(10, EntityKind.Kind.BLOCK)
	ledger.lend(jump.id, PackedInt32Array([10]), TriggerMode.Kind.REPEAT)
	panel.refresh()
	assert_eq(panel.visible_vessel_ids().count(jump.id), 1, "not duplicated")
	panel.set_query("", InventoryQuery.Category.LENT)
	assert_eq(panel.visible_vessel_ids(), PackedInt32Array([jump.id]))
	assert_eq(ledger.hotbar_vessel(4), jump, "the vessel stays on the hotbar while lent")
	assert_true(panel.select_vessel(jump.id))
	assert_eq(panel.detail_title(), "ジャンプ")


func test_large_bag_stays_fast() -> void:
	for i in 3000:
		ledger.give_player_item(RuleAction.ALL[i % RuleAction.ALL.size()], i % 7 == 0)
	var started := Time.get_ticks_usec()
	panel.refresh()
	var refresh_ms := (Time.get_ticks_usec() - started) / 1000.0
	assert_eq(panel.bag_vessel_ids().size(), 3002)
	assert_lt(refresh_ms, 400.0, "refresh with 3000 items took %.1f ms" % refresh_ms)
	await tree.process_frame
	var grid := panel.find_children("*", "ItemGrid", true, false)[0] as ItemGrid
	var rows := grid.visible_rows()
	assert_lt(float(rows.y - rows.x), 20.0, "only the visible rows are drawn")
	started = Time.get_ticks_usec()
	panel.set_query("禁止", InventoryQuery.Category.ALL)
	assert_lt((Time.get_ticks_usec() - started) / 1000.0, 400.0, "search stays responsive")
