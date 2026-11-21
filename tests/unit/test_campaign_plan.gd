extends TestCase
## キャンペーンの設計（CampaignPlan）と、進行から組み立てる広場（Overworld）のデータ（docs/adr/0013）。
## ノード・物理は使わない。

const HUB_GROUND_Y := 0


func _cleared(ids: Array[String]) -> PackedStringArray:
	return PackedStringArray(ids)


func _top(def: StageDef, x: int, z: int) -> int:
	var top := -100
	for box: Array in def.terrain_boxes:
		var lo := box[0] as Vector3i
		var hi := box[1] as Vector3i
		if x >= lo.x and x <= hi.x and z >= lo.z and z <= hi.z:
			top = maxi(top, hi.y + 1)
	return top


# --- 計画 -----------------------------------------------------------------------


func test_worlds_have_the_planned_shape() -> void:
	var mains := CampaignPlan.main_worlds()
	assert_true(mains.size() >= 6 and mains.size() <= 8, "6〜8 main worlds: %d" % mains.size())
	var optional := CampaignPlan.worlds().size() - mains.size()
	assert_true(optional >= 2 and optional <= 3, "2〜3 optional worlds")
	var seen := {}
	for w in CampaignPlan.worlds():
		if not w.optional:
			assert_true(w.slots.size() >= 5 and w.slots.size() <= 8, "%s has 5〜8 stages" % w.id)
			var middle := w.slots[(w.slots.size() - 1) / 2]
			assert_true(middle.hard, "%s: the middle stage is hard" % w.id)
			assert_true(w.slots[-1].hard, "%s: the last stage is hard" % w.id)
		for s in w.slots:
			assert_false(seen.has(s.stage_id), "%s is planned once" % s.stage_id)
			seen[s.stage_id] = true
			assert_ne(s.gimmick, "", "%s says what is new" % s.stage_id)


func test_every_existing_stage_has_a_slot_in_an_early_world() -> void:
	for def in StageCatalog.all_stages():
		var s := CampaignPlan.slot(def.stage_id)
		assert_ne(s, null, "%s is in the campaign" % def.stage_id)
		if s != null:
			# 寄り道のステージ（o1_1 など）だけが寄り道のワールドにあり、ほかは本編
			var optional := OptionalWorldPlan.IDS.has(s.world_id)
			assert_eq(
				CampaignPlan.world(s.world_id).optional, optional, "%s is where it belongs" % s.stage_id
			)


## 寄り道のワールドは、opened_by のクリアに加えて、広場の秘密の入口を見つけると開く（docs/campaign-plan.md）。
func test_optional_worlds_open_with_the_clear_and_the_secret_entrance() -> void:
	var o1 := CampaignPlan.world("o1")
	assert_eq(o1.slots.size(), 5, "five stages")
	for s in o1.slots:
		assert_true(s.hard, "%s is hard" % s.stage_id)
	var cleared := _cleared([CampaignPlan.required_stage(o1)])
	assert_false(CampaignPlan.is_region_open(o1, cleared), "the clear alone does not open it")
	var found := PackedStringArray(["o1"])
	assert_false(CampaignPlan.is_region_open(o1, PackedStringArray(), found), "nor the secret alone")
	assert_true(CampaignPlan.is_region_open(o1, cleared, found), "both open it")
	assert_true(CampaignPlan.is_stage_open("o1_1", cleared, found), "the first stage opens")
	assert_false(CampaignPlan.is_stage_open("o1_2", cleared, found), "the next waits for o1_1")
	assert_ne(CampaignPlan.lock_reason("o1_1", cleared), "", "says to look for the entrance")
	var later := cleared.duplicate()
	later.append("o1_1")
	assert_true(CampaignPlan.is_stage_open("o1_2", later, found))


func test_ability_schedule_unlocks_the_existing_abilities_in_order() -> void:
	var granted := PackedStringArray()
	for entry: Array in CampaignPlan.ability_schedule():
		granted.append(String(entry[1]))
	for name: String in ["HIGH_JUMP", "CLIMB", "THROW", "DASH"]:
		assert_true(granted.has(name), "%s is unlocked by a stage" % name)
	# 新しい能力（重い・浮く・泳ぐ）も台帳に入ったので、広場で開く（docs/adr/0015）
	for name: String in ["FLOAT", "HEAVY", "SWIM"]:
		assert_true(granted.has(name), "%s is planned" % name)
		assert_false(CampaignPlan.NEEDS_CODE.has(name), "%s is implemented" % name)
		assert_true(CampaignPlan.GRANT_ACTIONS.has(name), "%s can be granted" % name)
	var after := CampaignPlan.unlocked_actions(_cleared([StageCatalog.BELL_ID, "w6_warp_stones"]))
	var throw_and_float: Array[RuleAction.Kind] = [RuleAction.Kind.THROW, RuleAction.Kind.FLOAT]
	assert_eq(after, throw_and_float)


func test_regions_open_after_the_previous_worlds_last_stage() -> void:
	var bell_vale := CampaignPlan.world("w2")
	assert_false(CampaignPlan.is_region_open(bell_vale, _cleared([StageCatalog.INTRO_ID])))
	assert_true(CampaignPlan.is_region_open(bell_vale, _cleared([StageCatalog.QUARRY_ID])))
	# まだ作っていないステージで開く地方は、前のワールドで最後に作ってあるステージで代わりに開く
	var forest := CampaignPlan.world("w4")
	assert_eq(CampaignPlan.required_stage(forest), StageCatalog.FLOATING_ID)


func test_stages_open_in_campaign_order_inside_a_world() -> void:
	var none := PackedStringArray()
	assert_true(CampaignPlan.is_stage_open(StageCatalog.INTRO_ID, none), "the first stage is open")
	assert_false(CampaignPlan.is_stage_open(StageCatalog.RELAY_ID, none))
	assert_true(
		CampaignPlan.is_stage_open(StageCatalog.RELAY_ID, _cleared([StageCatalog.INTRO_ID]))
	)
	assert_false(CampaignPlan.is_stage_open(StageCatalog.BELL_ID, _cleared([StageCatalog.HILL_ID])))
	assert_ne(CampaignPlan.lock_reason(StageCatalog.BELL_ID, none), "")
	assert_eq(CampaignPlan.lock_reason(StageCatalog.INTRO_ID, none), "")


# --- 広場 -----------------------------------------------------------------------


func test_overworld_has_a_portal_for_every_stage_and_the_intro_ahead_of_spawn() -> void:
	var def := Overworld.build(OverworldState.first_visit())
	assert_true(def.problems().is_empty(), str(def.problems()))
	assert_eq(def.overworld.portals.size(), StageCatalog.all_stages().size())
	var intro := def.overworld.portal(StageCatalog.INTRO_ID)
	assert_true(intro.first and intro.open, "the intro portal is the first one and open")
	var ahead := intro.position - def.spawn_point(0)
	assert_lt(absf(ahead.x), 0.6, "straight ahead of the first spawn")
	assert_lt(ahead.z, 0.0, "to the north")
	assert_false(def.overworld.portal(StageCatalog.RELAY_ID).open, "locked until the intro")
	for p in def.overworld.portals:
		assert_eq(_top(def, floori(p.position.x), floori(p.position.z)), roundi(p.position.y))


func test_locked_regions_are_cut_off_by_geometry_until_the_clear() -> void:
	var first := Overworld.build(OverworldState.first_visit())
	assert_eq(_top(first, 25, 0), -100, "no bridge to the bell vale yet")
	assert_eq(_top(first, -22, 0), 3, "rocks block the road to the forest")
	assert_eq(_top(first, 0, -18), -100, "no stairs to the peaks yet")
	var state := OverworldState.first_visit()
	state.cleared = _cleared([StageCatalog.QUARRY_ID])
	var opened := Overworld.build(state)
	assert_eq(_top(opened, 25, 0), HUB_GROUND_Y, "the bridge appears")
	var everything := Overworld.build(OverworldState.new())
	assert_eq(_top(everything, -22, 0), HUB_GROUND_Y, "the debug option clears the rocks")
	assert_eq(_top(everything, 0, -18), 2, "and raises the stairs")


func test_cleared_stages_bring_a_resident_and_a_building() -> void:
	var state := OverworldState.first_visit()
	assert_true(Overworld.build(state).overworld.residents.is_empty())
	state.cleared = _cleared([StageCatalog.INTRO_ID, StageCatalog.HILL_ID])
	var layout := Overworld.build(state).overworld
	assert_eq(layout.residents.size(), 2)
	assert_eq(layout.resident(StageCatalog.HILL_ID).species, "wish")
	assert_eq(layout.buildings().size(), 2)
	assert_true(layout.portal(StageCatalog.HILL_ID).cleared)


func test_overworld_loadout_has_moves_jump_and_unlocked_abilities() -> void:
	var state := OverworldState.first_visit()
	var base := Overworld.build(state)
	assert_eq(base.loadout_for(0), RuleAction.BASIC)
	assert_true(base.start_equipment.is_empty())
	state.cleared = _cleared([StageCatalog.HILL_ID, StageCatalog.BELL_ID])
	var def := Overworld.build(state)
	assert_true(def.loadout_for(0).has(RuleAction.Kind.THROW), "throw after the bell valley")
	var boots: Array[RuleAction.Kind] = [RuleAction.Kind.HIGH_JUMP]
	assert_eq(def.start_equipment, boots)
	var ledger := RuleLedger.new()
	StageLoadout.new(def, StageLoadout.register_entities(ledger, def)).apply(
		ledger, PackedInt32Array([RuleLedger.PLAYER_ID])
	)
	assert_true(ledger.player_can(RuleAction.Kind.HIGH_JUMP), "boots are worn")
	assert_true(ledger.player_can(RuleAction.Kind.THROW))
	assert_true(ledger.validate().is_empty(), str(ledger.validate()))


func test_state_survives_the_network_round_trip() -> void:
	var state := OverworldState.of(_cleared([StageCatalog.INTRO_ID]), false, true, false)
	var back := OverworldState.from_dict(state.to_dict())
	assert_eq(back.cleared, state.cleared)
	assert_false(back.all_stages_open)
	assert_true(back.all_regions_open)
	var broken := OverworldState.from_dict({"cleared": 3})
	assert_true(broken.cleared.is_empty(), "a broken value becomes the default")
