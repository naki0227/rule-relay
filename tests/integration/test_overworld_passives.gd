extends "res://tests/integration/island_playthrough.gd"
## 広場のホットバーは 9 枠なので、能力を全部開ける（W/A/S/D・ジャンプ・投げる・ダッシュ・重い・浮く・泳ぐ）と
## 泳ぐが入らなかった（docs/adr/0015 の「まだやっていないこと」）。2026-11-21 の直し方: 持っているだけで効く性質
## （重い・浮く・泳ぐ）は、広場では通常インベントリに渡す。台帳の決まり（能力が効くのはホットバーと装備欄
## だけ）は変えないので、インベントリにある間は効かず、自分でホットバーへ移すと効く。
## ホットバーに勝手に置かないのは、重いと浮くが打ち消し合い、重いと水に沈むため（置くと勝手に効いてしまう）。

const PASSIVES: Array[RuleAction.Kind] = [
	RuleAction.Kind.HEAVY, RuleAction.Kind.FLOAT, RuleAction.Kind.SWIM
]


## データ: 全部開けても、ホットバーは 9 枠に収まり、性質 3 つは通常インベントリに入る。
func test_all_abilities_fit_with_passives_in_the_inventory() -> void:
	var def := Overworld.build(OverworldState.everything(false))
	var hotbar := def.loadout_for(0)
	assert_lt(hotbar.size(), RuleLedger.HOTBAR_SIZE, "room left on the hotbar: %s" % [hotbar])
	for action in PASSIVES:
		assert_false(hotbar.has(action), "%s is not on the hotbar" % RuleAction.label(action))
		assert_true(def.start_inventory.has(action), "%s is in the inventory" % action)
	assert_true(hotbar.has(RuleAction.Kind.DASH), "dash stays on the hotbar")
	assert_true(hotbar.has(RuleAction.Kind.THROW), "throw stays on the hotbar")
	assert_true(def.problems().is_empty(), str(def.problems()))


## データ: 性質を開く前の広場は、通常インベントリが空のまま（これまでと同じ）。
func test_no_passives_before_they_are_unlocked() -> void:
	var def := Overworld.build(OverworldState.first_visit())
	assert_true(def.start_inventory.is_empty())


## 台帳: インベントリにある間は効かず、ホットバーへ移すと効く。戻すとまた効かない（決まりは変えない）。
func test_passives_work_only_after_moving_them_to_the_hotbar() -> void:
	var def := Overworld.build(OverworldState.everything(false))
	var ledger := RuleLedger.new()
	StageLoadout.new(def, StageLoadout.register_entities(ledger, def)).apply(
		ledger, PackedInt32Array([RuleLedger.PLAYER_ID])
	)
	assert_true(ledger.validate().is_empty(), str(ledger.validate()))
	for action in PASSIVES:
		assert_false(ledger.player_can(action), "%s does nothing in the bag" % action)
	assert_eq(BodyTraits.weight(ledger, RuleLedger.PLAYER_ID), 0, "neither heavy nor floating")
	var swim := _bag_vessel(ledger, RuleAction.Kind.SWIM)
	var free := _free_slot_of(ledger)
	assert_true(ledger.move_to_hotbar(swim.id, free), "swim to the free slot")
	assert_true(ledger.player_can(RuleAction.Kind.SWIM), "swimming once on the hotbar")
	assert_true(ledger.move_to_inventory(swim.id), "back to the bag")
	assert_false(ledger.player_can(RuleAction.Kind.SWIM), "and it stops working")
	assert_true(ledger.validate().is_empty(), str(ledger.validate()))


## 実際の広場（全部開けた状態）でも、性質は通常インベントリに入っていて、ホットバーへ移せる。
func test_overworld_with_everything_unlocked_gives_passives_in_the_bag() -> void:
	director.all_abilities_unlocked = true
	await _enter(StageCatalog.HUB_ID)
	var me := _me().player_id
	for action in PASSIVES:
		assert_eq(_slot_of(action), -1, "%s is not on the hotbar" % action)
		assert_ne(_bag_vessel(w.ledger, action, me), null, "%s is in the bag" % action)
	var heavy := _bag_vessel(w.ledger, RuleAction.Kind.HEAVY, me)
	assert_true(w.ledger_actions.move_to_hotbar(heavy.id, _free_slot_of(w.ledger, me)), "moved")
	assert_true(BodyTraits.is_heavy(w.ledger, me), "heavy now")


func _bag_vessel(
	ledger: RuleLedger, action: RuleAction.Kind, player_id: int = RuleLedger.PLAYER_ID
) -> RuleVessel:
	for v in ledger.inventory_vessels(player_id):
		var t := ledger.token(v.token_id)
		if t.action == action and not t.is_prohibition:
			return v
	return null


func _free_slot_of(ledger: RuleLedger, player_id: int = RuleLedger.PLAYER_ID) -> int:
	for slot in RuleLedger.HOTBAR_SIZE:
		if ledger.hotbar_vessel(slot, player_id) == null:
			return slot
	return -1
