extends TestCase
## 重い・浮く・泳ぐの数え方（BodyTraits）と、風・水の置き方の決まり（NatureLayout）。docs/adr/0015。

const HEAVY := RuleAction.Kind.HEAVY
const FLOAT := RuleAction.Kind.FLOAT
const SWIM := RuleAction.Kind.SWIM
const ME := RuleLedger.PLAYER_ID
const BLOCK := 100

var ledger: RuleLedger


func before_each() -> void:
	ledger = RuleLedger.new()
	ledger.register_entity(BLOCK, EntityKind.Kind.BLOCK)


func test_new_actions_are_passive_and_labelled() -> void:
	for action: RuleAction.Kind in [HEAVY, FLOAT, SWIM]:
		assert_true(RuleAction.ALL.has(action), "%s is in ALL" % action)
		assert_false(RuleAction.is_triggered(action), "passive: no trigger mode on blocks")
		assert_ne(RuleAction.label(action), "?")
		assert_false(InventoryQuery.action_words(action).is_empty(), "searchable")
		var v := ledger.give_player_item(action, false)
		assert_true(ItemIcons.for_token(ledger.token(v.token_id)) != null, "has an icon")
	assert_eq(RuleAction.label(HEAVY), "重い")
	assert_eq(RuleAction.motif_semitone(SWIM), 26)


func test_holding_heavy_makes_a_player_heavy() -> void:
	assert_false(BodyTraits.is_heavy(ledger, ME))
	assert_eq(BodyTraits.weight_units(ledger, ME), 1.0, "a normal player weighs one person")
	ledger.give_player_item(HEAVY, false, 0)
	assert_true(BodyTraits.is_heavy(ledger, ME))
	assert_eq(BodyTraits.weight_units(ledger, ME), 4.0, "heavy x1 weighs four people")
	ledger.give_player_item(HEAVY, false, 1)
	assert_eq(BodyTraits.weight_units(ledger, ME), 8.0, "heavy x2 weighs eight")


func test_heavy_in_the_bag_does_not_count() -> void:
	ledger.give_player_item(HEAVY, false, -1)
	assert_false(BodyTraits.is_heavy(ledger, ME), "abilities only work from the hotbar")


func test_heavy_and_float_cancel_by_count() -> void:
	ledger.give_player_item(HEAVY, false, 0)
	ledger.give_player_item(FLOAT, false, 1)
	assert_eq(BodyTraits.weight(ledger, ME), 0, "one each cancels out")
	assert_false(BodyTraits.is_heavy(ledger, ME))
	assert_eq(BodyTraits.float_level(ledger, ME), 0)
	ledger.give_player_item(FLOAT, false, 2)
	assert_eq(BodyTraits.float_level(ledger, ME), 1, "two floats beat one heavy")


func test_a_prohibition_switches_a_trait_off() -> void:
	ledger.give_player_item(SWIM, false, 0)
	assert_eq(BodyTraits.swim_level(ledger, ME), 1)
	ledger.give_player_item(SWIM, true, -1)
	assert_eq(BodyTraits.swim_level(ledger, ME), 0, "a SWIM ban in hand means sinking")


func test_blocks_count_the_tokens_they_hold() -> void:
	ledger.place_on_entity(FLOAT, false, BLOCK, TriggerMode.Kind.NONE)
	ledger.place_on_entity(FLOAT, false, BLOCK, TriggerMode.Kind.NONE)
	assert_eq(BodyTraits.float_level(ledger, BLOCK), 2)
	ledger.place_on_entity(HEAVY, false, BLOCK, TriggerMode.Kind.NONE)
	assert_eq(BodyTraits.weight(ledger, BLOCK), -1)
	assert_eq(BodyTraits.weight(ledger, 9999), 0, "unknown ids are plain")


func test_lending_heavy_to_a_block_needs_no_trigger_mode() -> void:
	var v := ledger.give_player_item(HEAVY, false, 0)
	var result := ledger.lend(v.id, PackedInt32Array([BLOCK]), TriggerMode.Kind.SINGLE_SHOT)
	assert_eq(result, RuleLedger.LendResult.OK)
	assert_eq(ledger.token(v.token_id).mode, TriggerMode.Kind.NONE, "a trait, not an action")
	assert_true(BodyTraits.is_heavy(ledger, BLOCK))
	assert_false(BodyTraits.is_heavy(ledger, ME), "lent away")


func test_float_slows_the_fall_by_count() -> void:
	assert_eq(NatureTuning.fall_limit(0), INF)
	assert_almost(NatureTuning.fall_limit(1), NatureTuning.FLOAT_FALL_SPEED, 0.001)
	assert_almost(NatureTuning.fall_limit(2), NatureTuning.FLOAT_FALL_SPEED / 2.0, 0.001)


func test_pulsing_wind_blows_on_its_beat() -> void:
	var layout := NatureLayout.new()
	var wind := layout.add_pulsing_wind(
		Vector3i.ZERO, Vector3i(3, 1, 3), Vector3i(1, 0, 0), 4.0, 1.5
	)
	assert_true(wind.is_blowing(0.5))
	assert_false(wind.is_blowing(2.0))
	assert_true(wind.is_blowing(4.2), "it repeats")
	wind.phase = 2.0
	assert_true(wind.is_blowing(2.5), "phase shifts the beat")
	assert_true(layout.add_wind(Vector3i.ZERO, Vector3i.ONE, Vector3i(0, 0, -1)).is_blowing(99.0))


func test_water_surface_and_contents() -> void:
	var water := NatureLayout.WaterSpec.new(Vector3i(0, -2, 0), Vector3i(2, -1, 2))
	assert_almost(water.surface_y(), -0.2, 0.001)
	assert_eq(water.float_bottom(), -1.0, "a floating block's top meets the banks")
	assert_true(water.contains(Vector3(1.5, -0.5, 1.5)))
	assert_true(water.contains(Vector3(1.5, -30.0, 1.5)), "bottomless")
	assert_false(water.contains(Vector3(1.5, 0.0, 1.5)), "above the surface")
	assert_false(water.contains(Vector3(3.2, -0.5, 1.5)), "beside the water")


func test_layout_problems_keep_water_bottomless() -> void:
	var layout := NatureLayout.new()
	layout.add_water(Vector3i(0, -1, 0), Vector3i(2, -1, 2))
	var open: Array = [[Vector3i(-3, -1, 0), Vector3i(-1, -1, 2), "grass"]]
	assert_true(layout.problems(open).is_empty(), "%s" % layout.problems(open))
	var floored: Array = [[Vector3i(0, -3, 0), Vector3i(2, -3, 2), "rock"]]
	assert_false(layout.problems(floored).is_empty(), "ground under the water")
	layout.add_wind(Vector3i.ZERO, Vector3i.ONE, Vector3i(1, 0, 1))
	layout.add_current(Vector3i(5, -1, 0), Vector3i(6, -1, 0), Vector3i(0, 1, 0))
	assert_eq(layout.problems(open).size(), 2, "diagonal wind and vertical current")


func test_stage_def_reports_nature_problems() -> void:
	var def := StageCatalog.intro_jump_lend()
	assert_true(def.problems().is_empty())
	def.nature.add_water(Vector3i(0, -1, 0), Vector3i(0, -1, 0))
	assert_true(def.problems().size() > 0, "the intro has ground there")
