extends TestCase
## 装備は「入れ物」（docs/adr/0018。2026-11-21 本人の要望）:
## - 身につけている（装備欄にあり、中に能力が入っている）ときだけ効く。ホットバー・かばんでは効かない
## - 身につけている装備からは渡せない（EQUIPPED_CANNOT_LEND。同日の本人の訂正）
## - ホットバーの装備から渡すと、中の能力だけが移り、入れ物はその枠に残る（空になる）
## - F で回収すると、能力はその入れ物へ戻る（入れ物がいまどこにあっても）。身につけていれば効き目も戻る
## - 単発の自動返還も入れ物へ戻る。禁止は上位のまま。チェックポイントは入れ物と能力を別々に戻す

const BOOTS := RuleAction.Kind.HIGH_JUMP
const JUMP := RuleAction.Kind.JUMP
const BLOCK := 100
const FEET := RuleVessel.Part.FEET
const B := 2

var ledger: RuleLedger
var boots: RuleVessel


func before_each() -> void:
	ledger = RuleLedger.new()
	ledger.register_entity(BLOCK, EntityKind.Kind.BLOCK)
	boots = ledger.place_in_world(BOOTS, false, Vector3.ZERO, FEET, "ジャンプブーツ")
	ledger.pickup(boots.id)


func token() -> RuleToken:
	return ledger.token(boots.token_id)


func lend_boots() -> RuleLedger.LendResult:
	return ledger.lend(boots.id, PackedInt32Array([BLOCK]), TriggerMode.Kind.SINGLE_SHOT)


func test_unworn_equipment_has_no_effect_and_worn_equipment_does() -> void:
	assert_false(ledger.player_can(BOOTS), "in the bag: no effect")
	ledger.move_to_hotbar(boots.id, 0)
	assert_false(ledger.player_can(BOOTS), "in the hotbar: still no effect")
	assert_eq(ledger.ability_count(BOOTS), 0, "not counted either")
	ledger.equip(boots.id)
	assert_true(ledger.player_can(BOOTS), "worn: works")
	assert_eq(ledger.ability_count(BOOTS), 1)


func test_worn_equipment_cannot_be_lent() -> void:
	ledger.equip(boots.id)
	assert_eq(lend_boots(), RuleLedger.LendResult.EQUIPPED_CANNOT_LEND)
	var by_token := ledger.lend_token(
		boots.token_id, RuleLedger.PLAYER_ID, PackedInt32Array([BLOCK]), TriggerMode.Kind.NONE
	)
	assert_eq(by_token, RuleLedger.LendResult.EQUIPPED_CANNOT_LEND, "the token path refuses too")
	ledger.register_player(B)
	var given := ledger.give_to_player(boots.token_id, RuleLedger.PLAYER_ID, B)
	assert_eq(given, RuleLedger.LendResult.EQUIPPED_CANNOT_LEND, "nor can it be handed over")
	assert_true(token().is_in_vessel(), "the ability stays inside")
	assert_true(ledger.player_can(BOOTS), "and keeps working")
	var shown := WorldQueries.describe(token(), RuleLedger.LendResult.EQUIPPED_CANNOT_LEND, false)
	assert_true(shown.contains("身につけている装備"), "the message says why: %s" % shown)
	assert_true(shown.contains("ホットバー"), "and how: %s" % shown)


func test_lending_from_hotbar_equipment_moves_only_the_ability() -> void:
	ledger.move_to_hotbar(boots.id, 3)
	assert_eq(lend_boots(), RuleLedger.LendResult.OK)
	assert_eq(ledger.hotbar_vessel(3), boots, "the shell stays in its hotbar slot")
	assert_true(ledger.entity_has_ability(BLOCK, BOOTS), "the block has the ability")
	assert_eq(token().mode, TriggerMode.Kind.NONE, "boots are a held ability on a block")
	var entry := InventoryQuery.describe(ledger, boots)
	assert_eq(entry.state, InventoryQuery.State.LENT)
	assert_true(entry.state_text.begins_with("空"), "shown as an empty shell: %s" % entry.state_text)
	assert_eq(entry.label, "ジャンプブーツ", "still named as the equipment")
	assert_true(ledger.validate().is_empty())


func test_an_empty_shell_can_be_worn_but_works_only_after_recall() -> void:
	ledger.move_to_hotbar(boots.id, 3)
	lend_boots()
	assert_eq(ledger.equip(boots.id), RuleLedger.EquipResult.OK, "wearing the empty shell is fine")
	assert_false(ledger.player_can(BOOTS), "an empty shell does nothing")
	assert_true(ledger.recall(boots.token_id), "F")
	assert_true(token().is_in_vessel(), "back inside the shell")
	assert_eq(ledger.equipped_vessel(FEET), boots, "the shell did not move")
	assert_true(ledger.player_can(BOOTS), "worn and full: the effect is back")
	assert_true(ledger.validate().is_empty())


func test_recall_follows_the_shell_wherever_it_is_now() -> void:
	ledger.move_to_hotbar(boots.id, 3)
	lend_boots()
	ledger.move_to_inventory(boots.id)
	ledger.recall_from_entity(BLOCK)
	assert_true(token().is_in_vessel())
	assert_eq(boots.location, RuleVessel.Location.INVENTORY, "the shell is still in the bag")
	assert_false(ledger.player_can(BOOTS), "not worn, so no effect")
	ledger.equip(boots.id)
	assert_true(ledger.player_can(BOOTS))


## 装備の能力は、いまの品（高跳び・登る）ではブロックに「持たせる」能力で、単発にはならない。
## 単発になる能力の装備でも同じ規則で入れ物へ戻ることを、跳ねる靴（足の装備に跳ぶ）で確かめる。
func test_a_single_shot_returns_into_the_shell() -> void:
	var springs := ledger.place_in_world(JUMP, false, Vector3.ZERO, FEET, "跳ねる靴")
	ledger.pickup(springs.id)
	ledger.move_to_hotbar(springs.id, 1)
	var t := ledger.token(springs.token_id)
	assert_eq(
		ledger.lend(springs.id, PackedInt32Array([BLOCK]), TriggerMode.Kind.SINGLE_SHOT),
		RuleLedger.LendResult.OK
	)
	assert_eq(t.mode, TriggerMode.Kind.SINGLE_SHOT)
	ledger.equip(springs.id)  # 空のまま履いた
	assert_false(ledger.player_can(JUMP), "empty shell: no jump from it")
	var results: Array[BlockRules.Attempt] = [BlockRules.Attempt.SUCCESS]
	assert_true(ledger.complete_single_shot(t.id, results))
	assert_true(t.is_in_vessel(), "the used single shot came home to the shell")
	assert_eq(ledger.equipped_vessel(FEET), springs, "in the slot the shell is now in")
	assert_true(ledger.player_can(JUMP), "worn and full again")
	assert_true(ledger.validate().is_empty())


func test_a_ban_still_overrides_worn_equipment() -> void:
	ledger.equip(boots.id)
	ledger.give_player_item(BOOTS, true)
	assert_true(ledger.player_has_ability(BOOTS))
	assert_false(ledger.player_can(BOOTS), "the ban wins")


func test_checkpoint_restores_the_shell_and_the_ability_separately() -> void:
	ledger.move_to_hotbar(boots.id, 3)
	lend_boots()
	var saved := ledger.snapshot()
	ledger.recall(boots.token_id)
	ledger.equip(boots.id)
	assert_true(ledger.player_can(BOOTS))
	ledger.restore(saved)
	var shell := ledger.vessel(boots.id)
	assert_eq(shell.location, RuleVessel.Location.HOTBAR, "the shell is back in the hotbar")
	assert_eq(shell.slot, 3)
	assert_eq(shell.item_name, "ジャンプブーツ")
	assert_true(ledger.entity_has_ability(BLOCK, BOOTS), "the ability is back on the block")
	assert_false(ledger.player_can(BOOTS))
	assert_true(ledger.validate().is_empty())


func test_handing_the_ability_to_a_teammate_leaves_the_shell() -> void:
	ledger.register_player(B)
	ledger.move_to_hotbar(boots.id, 3)
	var given := ledger.give_to_player(boots.token_id, RuleLedger.PLAYER_ID, B)
	assert_eq(given, RuleLedger.LendResult.OK)
	assert_eq(ledger.hotbar_vessel(3), boots, "the shell stays with its owner")
	assert_true(ledger.player_can(BOOTS, B), "a handed-over ability works on the teammate")
	ledger.equip(boots.id)
	assert_false(ledger.player_can(BOOTS), "the owner's empty boots do nothing")
	assert_false(ledger.recall(boots.token_id), "F only recalls from things, not from a teammate")
	ledger.give_to_player(boots.token_id, B, RuleLedger.PLAYER_ID)
	assert_true(token().is_in_vessel(), "handed back to the owner: into the shell")
	assert_true(ledger.player_can(BOOTS))
	assert_false(ledger.player_can(BOOTS, B))


## 入れ物が無くなったとき（持ち主が抜けて島に落ちた）: 能力は今までどおり、回収した人が器なしで持つ。
## その人が入れ物も拾えば、中身は入れ物へ戻る（拾った人が新しい持ち主）。複製も消滅もしない。
func test_when_the_owner_leaves_the_recaller_keeps_the_ability() -> void:
	ledger.register_player(B)
	var bobs := ledger.place_in_world(BOOTS, false, Vector3.ZERO, FEET, "ジャンプブーツ")
	ledger.pickup(bobs.id, B)
	ledger.move_to_hotbar(bobs.id, 0)
	var lent := ledger.lend(bobs.id, PackedInt32Array([BLOCK]), TriggerMode.Kind.NONE)
	assert_eq(lent, RuleLedger.LendResult.OK)
	ledger.set_player_present(B, false, Vector3(2, 0, 2))
	assert_eq(bobs.location, RuleVessel.Location.WORLD, "the shell stays on the island")
	assert_true(ledger.entity_has_ability(BLOCK, BOOTS), "the lent ability stays where it was")
	ledger.recall_from_entity(BLOCK, RuleLedger.PLAYER_ID)
	var t := ledger.token(bobs.token_id)
	assert_eq(t.carrier_id, RuleLedger.PLAYER_ID, "the recaller holds it without a shell")
	assert_true(ledger.validate().is_empty())
	ledger.pickup(bobs.id)
	assert_eq(bobs.owner_id, RuleLedger.PLAYER_ID, "the shell can be picked up too")
	assert_true(t.is_in_vessel(), "the carried ability rejoins its shell")
	assert_false(ledger.player_can(BOOTS), "in the bag now, so not in effect until worn")
	ledger.equip(bobs.id)
	assert_true(ledger.player_can(BOOTS))
	assert_eq(ledger.ability_count(BOOTS), 1, "one ability, not two")
	assert_true(ledger.validate().is_empty())
