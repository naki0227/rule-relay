extends TestCase
## 持ち物の画面の動かし方（2026-11-21 本人）: 開いても検索欄にフォーカスしない、指して 1〜9 でホットバーへ、
## クリックで持ち上げてクリックで置く（空なら移る・器があれば入れ替える）、取り消し、ドラッグでの入れ替え。

const JUMP := RuleAction.Kind.JUMP
const FORWARD := RuleAction.Kind.FORWARD

var ledger: RuleLedger
var panel: InventoryPanel
var jump: RuleVessel
var stored_w: RuleVessel
var stored_a: RuleVessel
var boots: RuleVessel


func before_each() -> void:
	ledger = RuleLedger.new()
	jump = ledger.give_player_item(JUMP, false, 4)
	stored_w = ledger.give_player_item(FORWARD, false)
	stored_a = ledger.give_player_item(RuleAction.Kind.LEFT, false)
	boots = ledger.place_in_world(RuleAction.Kind.HIGH_JUMP, false, Vector3.ZERO)
	boots.part = RuleVessel.Part.FEET
	boots.item_name = "ジャンプブーツ"
	ledger.pickup(boots.id)
	panel = InventoryPanel.new()
	panel.ledger = ledger
	tree.root.add_child(panel)
	panel.open()


func after_each() -> void:
	panel.queue_free()
	await tree.process_frame


func test_opening_does_not_focus_the_search_box() -> void:
	assert_false(panel.is_typing())
	var search := panel.find_children("*", "LineEdit", true, false)[0] as LineEdit
	search.grab_focus()
	assert_true(panel.is_typing(), "clicking it gives it focus")
	assert_true(panel.handle_escape(), "Esc leaves the search box first")
	assert_false(panel.is_typing())


func test_hover_and_number_moves_and_swaps() -> void:
	panel.hover(stored_w.id)
	assert_true(panel.number_key(0), "hovered bag item to hotbar 1")
	assert_eq(ledger.hotbar_vessel(0), stored_w)
	panel.hover(stored_a.id)
	assert_true(panel.number_key(4), "onto the jump in hotbar 5")
	assert_eq(ledger.hotbar_vessel(4), stored_a, "moved in")
	assert_eq(jump.location, RuleVessel.Location.INVENTORY, "the jump swapped into the bag")
	panel.hover(stored_a.id)
	assert_true(panel.number_key(4), "already there: nothing happens")
	assert_eq(ledger.hotbar_vessel(4), stored_a)
	panel.hover(stored_w.id)
	panel.number_key(4)
	assert_eq(ledger.hotbar_vessel(4), stored_w, "hotbar to hotbar swaps")
	assert_eq(ledger.hotbar_vessel(0), stored_a)
	assert_true(ledger.validate().is_empty(), str(ledger.validate()))


func test_click_then_click_moves_into_an_empty_slot_and_swaps() -> void:
	assert_true(panel.click_hotbar(4), "picked the jump")
	assert_true(panel.is_holding())
	assert_true(panel.click_hotbar(7), "placed on empty slot 8")
	assert_false(panel.is_holding())
	assert_eq(ledger.hotbar_vessel(7), jump)
	assert_eq(ledger.hotbar_vessel(4), null)
	# かばん → ホットバーの器の上: 入れ替わる
	panel.click_bag(stored_w.id)
	panel.click_hotbar(7)
	assert_eq(ledger.hotbar_vessel(7), stored_w)
	assert_eq(jump.location, RuleVessel.Location.INVENTORY)
	# ホットバー → かばんの器の上: 入れ替わる
	panel.click_hotbar(7)
	panel.click_bag(stored_a.id)
	assert_eq(ledger.hotbar_vessel(7), stored_a, "the bag item took the hotbar slot")
	assert_eq(stored_w.location, RuleVessel.Location.INVENTORY)
	# ホットバー → かばんの空いた所
	panel.click_hotbar(7)
	panel.click_bag(-1)
	assert_eq(ledger.hotbar_vessel(7), null)
	assert_eq(stored_a.location, RuleVessel.Location.INVENTORY)
	assert_true(ledger.validate().is_empty(), str(ledger.validate()))


func test_cancel_by_same_slot_right_click_or_escape() -> void:
	panel.click_hotbar(4)
	panel.click_hotbar(4)
	assert_false(panel.is_holding(), "the same slot again cancels")
	assert_eq(ledger.hotbar_vessel(4), jump, "nothing moved")
	panel.click_bag(stored_w.id)
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	panel._input(right)
	assert_false(panel.is_holding(), "right click cancels")
	panel.click_bag(stored_w.id)
	assert_true(panel.handle_escape(), "Esc cancels a pick")
	assert_false(panel.is_holding())
	assert_eq(stored_w.location, RuleVessel.Location.INVENTORY)


func test_equipment_goes_to_the_matching_equip_slot_only() -> void:
	panel.click_bag(stored_w.id)
	assert_false(panel.click_equip(3), "not equipment")
	assert_true(panel.last_message.contains("装備品ではない"), panel.last_message)
	panel.click_bag(boots.id)
	assert_false(panel.click_equip(2), "boots are not for hands")
	assert_true(panel.last_message.contains("足"), panel.last_message)
	panel.click_bag(boots.id)
	assert_true(panel.click_equip(3), "feet")
	assert_eq(ledger.equipped_vessel(RuleVessel.Part.FEET), boots, "placing it there wears it")
	assert_true(ledger.player_can(RuleAction.Kind.HIGH_JUMP))


func test_an_empty_shell_can_still_be_moved() -> void:
	ledger.register_entity(10, EntityKind.Kind.BLOCK)
	ledger.move_to_hotbar(boots.id, 2)
	ledger.lend(boots.id, PackedInt32Array([10]), TriggerMode.Kind.NONE)
	panel.refresh()
	panel.hover(boots.id)
	assert_true(panel.number_key(6), "the lent-out shell moves")
	assert_eq(ledger.hotbar_vessel(6), boots)
	assert_true(ledger.entity_has_ability(10, RuleAction.Kind.HIGH_JUMP), "the ability stays put")
	ledger.recall_from_entity(10)
	assert_true(ledger.token(boots.token_id).is_in_vessel(), "and F still finds the shell")


func test_drag_onto_an_occupied_slot_swaps() -> void:
	ledger.move_to_hotbar(stored_w.id, 0)
	assert_true(panel.drop_on_hotbar(jump.id, 0))
	assert_eq(ledger.hotbar_vessel(0), jump)
	assert_eq(ledger.hotbar_vessel(4), stored_w, "swapped")
	assert_true(panel.drop_into_bag(jump.id, stored_a.id), "onto a bag item")
	assert_eq(ledger.hotbar_vessel(0), stored_a, "the bag item took its place")
	assert_eq(jump.location, RuleVessel.Location.INVENTORY)
	assert_true(ledger.validate().is_empty(), str(ledger.validate()))
