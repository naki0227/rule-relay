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
	assert_true(panel.is_typing(), "search box has focus when opened")


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
