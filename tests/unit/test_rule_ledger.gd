extends TestCase
## 能力トークンの一意性・禁止優先・器の扱い（企画書 11 の受け入れテスト 1, 5）。

const JUMP := RuleAction.Kind.JUMP
const FORWARD := RuleAction.Kind.FORWARD
const SINGLE := TriggerMode.Kind.SINGLE_SHOT
const REPEAT := TriggerMode.Kind.REPEAT
const BLOCK_A := 10
const BLOCK_B := 11
const CREATURE := 20

var ledger: RuleLedger
var jump_vessel: RuleVessel


func before_each() -> void:
	ledger = RuleLedger.new()
	ledger.register_entity(BLOCK_A, EntityKind.Kind.BLOCK)
	ledger.register_entity(BLOCK_B, EntityKind.Kind.BLOCK)
	ledger.register_entity(CREATURE, EntityKind.Kind.CREATURE)
	jump_vessel = ledger.give_player_item(JUMP, false, 4)


func test_player_can_jump_with_hotbar_ability() -> void:
	assert_true(ledger.player_can(JUMP))
	assert_false(ledger.player_can(FORWARD), "no W item yet")


func test_lending_jump_moves_token_and_keeps_vessel() -> void:
	var result := ledger.lend(jump_vessel.id, PackedInt32Array([BLOCK_A]), SINGLE)
	assert_eq(result, RuleLedger.LendResult.OK)
	assert_false(ledger.player_can(JUMP), "player loses jump while lent")
	assert_true(ledger.can_initiate(BLOCK_A, JUMP), "block gains jump")
	assert_false(ledger.can_initiate(BLOCK_B, JUMP))
	assert_eq(ledger.hotbar_vessel(4), jump_vessel, "vessel stays in its slot")
	assert_true(ledger.validate().is_empty(), str(ledger.validate()))


func test_token_cannot_be_lent_twice() -> void:
	ledger.lend(jump_vessel.id, PackedInt32Array([BLOCK_A]), SINGLE)
	var again := ledger.lend(jump_vessel.id, PackedInt32Array([BLOCK_B]), SINGLE)
	assert_eq(again, RuleLedger.LendResult.ALREADY_LENT)
	assert_false(ledger.can_initiate(BLOCK_B, JUMP), "no duplicate token")


func test_recall_returns_ability_to_player() -> void:
	ledger.lend(jump_vessel.id, PackedInt32Array([BLOCK_A]), REPEAT)
	var recalled := ledger.recall_from_entity(BLOCK_A)
	assert_eq(recalled.size(), 1)
	assert_true(ledger.player_can(JUMP))
	assert_false(ledger.can_initiate(BLOCK_A, JUMP))


func test_lend_requires_hotbar() -> void:
	var stored := ledger.give_player_item(FORWARD, false)
	var result := ledger.lend(stored.id, PackedInt32Array([BLOCK_A]), SINGLE)
	assert_eq(result, RuleLedger.LendResult.NOT_IN_HOTBAR)


func test_block_lend_requires_supported_mode() -> void:
	var none := ledger.lend(jump_vessel.id, PackedInt32Array([BLOCK_A]), TriggerMode.Kind.NONE)
	assert_eq(none, RuleLedger.LendResult.MODE_REQUIRED_FOR_BLOCK)
	var signal_mode := ledger.lend(
		jump_vessel.id, PackedInt32Array([BLOCK_A]), TriggerMode.Kind.SIGNAL
	)
	assert_eq(signal_mode, RuleLedger.LendResult.OK, "signal mode (with sound sources)")
	assert_eq(ledger.signal_actions(BLOCK_A), [JUMP] as Array[RuleAction.Kind])
	assert_true(ledger.repeat_actions(BLOCK_A).is_empty())


func test_creature_receives_ability_without_mode() -> void:
	var result := ledger.lend(jump_vessel.id, PackedInt32Array([CREATURE]), SINGLE)
	assert_eq(result, RuleLedger.LendResult.OK)
	assert_eq(PartyQuery.token_of_vessel(ledger, jump_vessel.id).mode, TriggerMode.Kind.NONE)
	assert_eq(ledger.pending_single_shots(JUMP).size(), 0, "creatures are not remote-triggered")


func test_cannot_lend_to_player_or_unknown() -> void:
	var to_player := ledger.lend(jump_vessel.id, PackedInt32Array([RuleLedger.PLAYER_ID]), SINGLE)
	assert_eq(to_player, RuleLedger.LendResult.CANNOT_TARGET_PLAYER)
	var unknown := ledger.lend(jump_vessel.id, PackedInt32Array([999]), SINGLE)
	assert_eq(unknown, RuleLedger.LendResult.UNKNOWN_TARGET)


func test_inventory_ability_has_no_effect_on_player() -> void:
	var stored := ledger.give_player_item(FORWARD, false)
	assert_false(ledger.player_can(FORWARD), "abilities only work from the hotbar")
	ledger.move_to_hotbar(stored.id, 0)
	assert_true(ledger.player_can(FORWARD))


func test_prohibition_applies_from_anywhere_and_wins() -> void:
	var ban := ledger.give_player_item(JUMP, true)
	assert_false(ledger.player_can(JUMP), "prohibition in inventory applies")
	ledger.move_to_hotbar(ban.id, 0)
	assert_false(ledger.player_can(JUMP), "prohibition in hotbar applies")
	assert_true(ledger.player_has_ability(JUMP), "ability is still there, just forbidden")


func test_lending_prohibition_frees_player_and_binds_block() -> void:
	var ban := ledger.give_player_item(JUMP, true, 1)
	ledger.lend(jump_vessel.id, PackedInt32Array([BLOCK_A]), REPEAT)
	var result := ledger.lend(ban.id, PackedInt32Array([BLOCK_A]), TriggerMode.Kind.NONE)
	assert_eq(result, RuleLedger.LendResult.OK)
	assert_false(ledger.player_prohibited(JUMP))
	assert_true(ledger.entity_has_ability(BLOCK_A, JUMP))
	assert_false(ledger.can_initiate(BLOCK_A, JUMP), "prohibition beats ability")


func test_placed_prohibition_is_picked_up_into_inventory() -> void:
	ledger.place_on_entity(JUMP, true, BLOCK_A)
	assert_true(ledger.entity_prohibited(BLOCK_A, JUMP))
	assert_true(ledger.player_can(JUMP))
	ledger.recall_from_entity(BLOCK_A)
	assert_false(ledger.entity_prohibited(BLOCK_A, JUMP))
	assert_false(ledger.player_can(JUMP), "picked-up prohibition applies immediately")
	assert_eq(ledger.inventory_vessels().size(), 1, "goes to the normal inventory")
	assert_true(ledger.validate().is_empty(), str(ledger.validate()))


func test_hotbar_has_nine_slots_and_swaps() -> void:
	var w := ledger.give_player_item(FORWARD, false)
	assert_false(ledger.move_to_hotbar(w.id, RuleLedger.HOTBAR_SIZE), "slot 9 does not exist")
	assert_true(ledger.move_to_hotbar(w.id, 4), "swap with jump in slot 4")
	assert_eq(ledger.hotbar_vessel(4), w)
	assert_eq(jump_vessel.location, RuleVessel.Location.INVENTORY)
	assert_false(ledger.player_can(JUMP))
	assert_true(ledger.validate().is_empty(), str(ledger.validate()))


func test_vessel_in_inventory_can_stay_lent() -> void:
	ledger.lend(jump_vessel.id, PackedInt32Array([BLOCK_A]), REPEAT)
	ledger.move_to_inventory(jump_vessel.id)
	assert_true(ledger.can_initiate(BLOCK_A, JUMP), "moving the vessel does not recall")
	ledger.recall_from_entity(BLOCK_A)
	assert_false(ledger.player_can(JUMP), "back in vessel but vessel is not on the hotbar")
