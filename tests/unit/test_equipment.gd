extends TestCase
## 装備（企画書 7）: 部位ごとに1個、装備中だけ本人に効く、装備中は付与できない、
## 未装備なら付与できる、貸している装備も装備はできるが回収まで能力は効かない（2026-11-19 本人の判断）。

const BOOTS := RuleAction.Kind.HIGH_JUMP
const CLIMB := RuleAction.Kind.CLIMB
const BLOCK := 100
const FEET := RuleVessel.Part.FEET
const HANDS := RuleVessel.Part.HANDS

var ledger: RuleLedger
var boots: RuleVessel


func before_each() -> void:
	ledger = RuleLedger.new()
	ledger.register_entity(BLOCK, EntityKind.Kind.BLOCK)
	boots = ledger.place_in_world(BOOTS, false, Vector3.ZERO, FEET, "ジャンプブーツ")
	ledger.pickup(boots.id)


func test_equipment_only_works_while_equipped() -> void:
	assert_false(ledger.player_can(BOOTS), "in the bag: no effect")
	ledger.move_to_hotbar(boots.id, 0)
	assert_false(ledger.player_can(BOOTS), "in the hotbar but not worn: no effect")
	assert_eq(ledger.equip(boots.id), RuleLedger.EquipResult.OK)
	assert_eq(ledger.equipped_vessel(FEET), boots)
	assert_true(ledger.player_can(BOOTS), "worn: works")
	assert_eq(ledger.hotbar_vessel(0), null, "moved out of the hotbar")
	assert_true(ledger.unequip(boots.id))
	assert_false(ledger.player_can(BOOTS))
	assert_eq(ledger.vessel(boots.id).location, RuleVessel.Location.INVENTORY)


func test_equipped_ability_cannot_be_lent() -> void:
	ledger.equip(boots.id)
	var result := ledger.lend(boots.id, PackedInt32Array([BLOCK]), TriggerMode.Kind.NONE)
	assert_eq(result, RuleLedger.LendResult.EQUIPPED_CANNOT_LEND)


func test_lent_equipment_can_be_worn_but_does_not_work_until_recalled() -> void:
	ledger.move_to_hotbar(boots.id, 2)
	var result := ledger.lend(boots.id, PackedInt32Array([BLOCK]), TriggerMode.Kind.SINGLE_SHOT)
	assert_eq(result, RuleLedger.LendResult.OK)
	assert_eq(ledger.token(boots.token_id).mode, TriggerMode.Kind.NONE, "a held ability")
	assert_true(ledger.entity_has_ability(BLOCK, BOOTS))
	assert_eq(ledger.equip(boots.id), RuleLedger.EquipResult.OK, "wearing it is allowed")
	assert_eq(ledger.equipped_vessel(FEET), boots)
	assert_false(ledger.player_can(BOOTS), "but the lent ability does not work on the wearer")
	assert_true(ledger.entity_has_ability(BLOCK, BOOTS), "the block keeps it")
	assert_true(ledger.validate().is_empty())
	ledger.recall(boots.token_id)
	assert_true(ledger.player_can(BOOTS), "works once recalled")


func test_one_item_per_part_swaps_back_to_where_it_came_from() -> void:
	var spare := ledger.place_in_world(BOOTS, false, Vector3.ZERO, FEET, "予備のブーツ")
	ledger.pickup(spare.id)
	ledger.equip(boots.id)
	ledger.move_to_hotbar(spare.id, 3)
	assert_eq(ledger.equip(spare.id), RuleLedger.EquipResult.OK)
	assert_eq(ledger.equipped_vessel(FEET), spare)
	assert_eq(ledger.hotbar_vessel(3), boots, "the old boots take the freed hotbar slot")
	assert_true(ledger.validate().is_empty())


func test_parts_are_independent_and_non_equipment_is_refused() -> void:
	var gloves := ledger.place_in_world(CLIMB, false, Vector3.ZERO, HANDS, "グローブ")
	ledger.pickup(gloves.id)
	ledger.equip(boots.id)
	ledger.equip(gloves.id)
	assert_true(ledger.player_can(BOOTS) and ledger.player_can(CLIMB))
	var plain := ledger.give_player_item(RuleAction.Kind.JUMP, false, 0)
	assert_eq(ledger.equip(plain.id), RuleLedger.EquipResult.NOT_EQUIPMENT)
	var lying := ledger.place_in_world(CLIMB, false, Vector3.ZERO, HANDS, "落ちているグローブ")
	assert_eq(ledger.equip(lying.id), RuleLedger.EquipResult.NOT_CARRIED)


func test_equipment_survives_snapshot_and_restore() -> void:
	ledger.equip(boots.id)
	var saved := ledger.snapshot()
	ledger.unequip(boots.id)
	ledger.restore(saved)
	assert_eq(ledger.equipped_vessel(FEET).id, boots.id)
	assert_eq(ledger.vessel(boots.id).item_name, "ジャンプブーツ")
	assert_true(ledger.player_can(BOOTS))


func test_search_finds_equipment_by_category_and_words() -> void:
	ledger.equip(boots.id)
	var found := InventoryQuery.search(ledger, "", InventoryQuery.Category.EQUIPMENT)
	assert_eq(found.size(), 1)
	assert_eq(found[0].state, InventoryQuery.State.EQUIPPED)
	assert_eq(found[0].label, "ジャンプブーツ")
	assert_eq(InventoryQuery.search(ledger, "装備 足", InventoryQuery.Category.ALL).size(), 1)
	assert_eq(InventoryQuery.search(ledger, "ブーツ", InventoryQuery.Category.ALL).size(), 1)
