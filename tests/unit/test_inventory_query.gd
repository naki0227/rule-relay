extends TestCase
## 持ち物の検索・絞り込み・状態表示（企画書 7）。

const JUMP := RuleAction.Kind.JUMP
const FORWARD := RuleAction.Kind.FORWARD
const BLOCK := 10

var ledger: RuleLedger
var jump: RuleVessel
var stored_w: RuleVessel
var ban: RuleVessel


func before_each() -> void:
	ledger = RuleLedger.new()
	ledger.register_entity(BLOCK, EntityKind.Kind.BLOCK)
	jump = ledger.give_player_item(JUMP, false, 4)
	stored_w = ledger.give_player_item(FORWARD, false)
	ban = ledger.give_player_item(JUMP, true)


func labels(entries: Array[InventoryQuery.Entry]) -> Array[String]:
	var out: Array[String] = []
	for e in entries:
		out.append(e.label)
	return out


func test_empty_query_lists_hotbar_then_inventory() -> void:
	var all := InventoryQuery.search(ledger, "", InventoryQuery.Category.ALL)
	assert_eq(labels(all), ["ジャンプ", "W", "ジャンプ禁止"] as Array[String])


func test_states_are_described() -> void:
	var all := InventoryQuery.search(ledger, "", InventoryQuery.Category.ALL)
	assert_eq(all[0].state, InventoryQuery.State.ACTIVE)
	assert_eq(all[1].state, InventoryQuery.State.STORED, "abilities in the inventory do not apply")
	assert_eq(all[2].state, InventoryQuery.State.PROHIBITION_APPLIED, "prohibitions apply anywhere")
	ledger.lend(jump.id, PackedInt32Array([BLOCK]), TriggerMode.Kind.REPEAT)
	var lent := InventoryQuery.describe(ledger, jump)
	assert_eq(lent.state, InventoryQuery.State.LENT)
	assert_eq(lent.state_text, "貸出中（単体・繰り返し）")


func test_category_filters() -> void:
	var abilities := InventoryQuery.search(ledger, "", InventoryQuery.Category.ABILITY)
	assert_eq(labels(abilities), ["ジャンプ", "W"] as Array[String])
	var bans := InventoryQuery.search(ledger, "", InventoryQuery.Category.PROHIBITION)
	assert_eq(labels(bans), ["ジャンプ禁止"] as Array[String])
	var gear := InventoryQuery.search(ledger, "", InventoryQuery.Category.EQUIPMENT)
	assert_eq(gear.size(), 0, "no equipment exists yet")


func test_search_by_name_alias_and_kana() -> void:
	assert_eq(InventoryQuery.search(ledger, "jump", InventoryQuery.Category.ALL).size(), 2)
	assert_eq(InventoryQuery.search(ledger, "ジャンプ", InventoryQuery.Category.ALL).size(), 2)
	assert_eq(InventoryQuery.search(ledger, "じゃんぷ", InventoryQuery.Category.ALL).size(), 2)
	assert_eq(
		labels(InventoryQuery.search(ledger, "前進", InventoryQuery.Category.ALL)),
		["W"] as Array[String]
	)
	assert_eq(
		labels(InventoryQuery.search(ledger, "Ｗ", InventoryQuery.Category.ALL)),
		["W"] as Array[String]
	)


func test_search_by_state_and_location_with_and() -> void:
	var applied := InventoryQuery.search(ledger, "適用中", InventoryQuery.Category.ALL)
	assert_eq(labels(applied), ["ジャンプ禁止"] as Array[String])
	var hotbar := InventoryQuery.search(ledger, "ホットバー", InventoryQuery.Category.ALL)
	assert_eq(labels(hotbar), ["ジャンプ"] as Array[String])
	var both := InventoryQuery.search(ledger, "ジャンプ　禁止", InventoryQuery.Category.ALL)
	assert_eq(labels(both), ["ジャンプ禁止"] as Array[String], "full-width space separates words")
	ledger.lend(jump.id, PackedInt32Array([BLOCK]), TriggerMode.Kind.SINGLE_SHOT)
	var lent := InventoryQuery.search(ledger, "貸出中", InventoryQuery.Category.ABILITY)
	assert_eq(labels(lent), ["ジャンプ"] as Array[String])


func test_no_match() -> void:
	assert_eq(InventoryQuery.search(ledger, "ブーツ", InventoryQuery.Category.ALL).size(), 0)


func test_normalize() -> void:
	assert_eq(InventoryQuery.normalize("  ＡＢＣ　ジャンプ  Jump "), "abc じゃんぷ jump")
