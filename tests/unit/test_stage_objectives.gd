extends TestCase
## ステージの目的の一覧（StageObjectives。docs/adr/0018）: どのステージのクリア条件からも、空でなく、
## 仮の文の無い一覧ができる。進み具合は鐘・どうぶつ・ゴールに来た人の数で埋まる。

const KNOWN_TEXTS: PackedStringArray = [
	StageObjectives.TEXT_ANIMAL,
	StageObjectives.TEXT_CARRY,
	StageObjectives.TEXT_BELL,
	StageObjectives.TEXT_TIMED_BELL,
	StageObjectives.TEXT_HEIGHT,
	StageObjectives.TEXT_GOAL,
]


## 仮の文・内部の名前（key）・書式の残りが出ていないか。
func _placeholder(text: String) -> bool:
	var ascii_word := RegEx.create_from_string("[A-Za-z_]{2,}")
	return (
		text.strip_edges() == ""
		or ascii_word.search(text) != null
		or text.contains("%")
		or text.contains("?")
		or text.contains("？")
		or text.contains("仮")
	)


func test_every_stage_has_objectives_without_placeholder_text() -> void:
	var stages := StageCatalog.all_stages()
	assert_gt(stages.size(), 50.0, "W1-W7 and the optional worlds")
	for def in stages:
		var items := StageObjectives.build(def)
		assert_false(items.is_empty(), "%s has objectives" % def.stage_id)
		if items.is_empty():
			continue
		assert_eq(items[-1].icon, StageObjectives.Icon.GOAL, "%s ends with the goal" % def.stage_id)
		for item in items:
			assert_ne(item.icon, StageObjectives.Icon.OTHER, "%s: %s" % [def.stage_id, item.text])
			assert_false(_placeholder(item.text), "%s: '%s'" % [def.stage_id, item.text])
			assert_false(_placeholder(item.label()), "%s: '%s'" % [def.stage_id, item.label()])
			assert_gt(item.total, 0.0, "%s: %s counts something" % [def.stage_id, item.text])
			var custom := item.conditions[0].objective_text != ""
			assert_true(custom or KNOWN_TEXTS.has(item.text), "%s: %s" % [def.stage_id, item.text])


## W1〜W7・寄り道で使っている条件の種類が全部、一覧に出る（鐘・時の鐘・どうぶつ・運ぶ物・ゴール）。
func test_every_condition_kind_in_the_campaign_has_a_line() -> void:
	var seen: Dictionary[int, bool] = {}
	for def in StageCatalog.all_stages():
		for item in StageObjectives.build(def):
			seen[item.icon] = true
	for icon: StageObjectives.Icon in [
		StageObjectives.Icon.ANIMAL,
		StageObjectives.Icon.CARRY,
		StageObjectives.Icon.BELL,
		StageObjectives.Icon.TIMED_BELL,
		StageObjectives.Icon.GOAL,
	]:
		assert_true(seen.has(icon), "icon %d appears in some stage" % icon)
	assert_false(seen.has(StageObjectives.Icon.OTHER), "no unnamed condition")


func test_the_keystone_uses_its_own_text() -> void:
	var fort := StageCatalog.by_id("ruined_fort")
	var texts := PackedStringArray()
	for item in StageObjectives.build(fort):
		texts.append(item.text)
	assert_true(texts.has("要石を窪みへ"), str(texts))
	assert_true(texts.has(StageObjectives.TEXT_BELL), str(texts))


## 見本: 鐘 2 つ・どうぶつ 1 匹・ゴール。同じ種類はまとめて「0/2」と数える。
func _sample() -> StageDef:
	var def := StageDef.new()
	def.stage_id = "sample"
	def.bells = [
		StageDef.BellSpec.new("bell_a", Vector3.ZERO), StageDef.BellSpec.new("bell_b", Vector3.ONE)
	]
	def.creatures = [StageDef.CreatureSpec.new("lamb", Vector3(5, 0, 5))]
	var parts: Array[ClearCondition] = [
		ClearCondition.activate("bell_a"),
		ClearCondition.carry_object("lamb", AABB(Vector3(10, -1, 10), Vector3(2, 2, 2))),
		ClearCondition.activate("bell_b"),
		ClearCondition.all_at_goal(AABB(Vector3(-2, -1, -2), Vector3(4, 3, 4))),
	]
	def.clear_condition = ClearCondition.all_of(parts)
	return def


func test_lines_group_by_kind_in_a_fixed_order() -> void:
	var items := StageObjectives.build(_sample())
	assert_eq(items.size(), 3)
	assert_eq(items[0].text, StageObjectives.TEXT_ANIMAL)
	assert_eq(items[1].label(), "鐘を鳴らす 0/2")
	assert_eq(items[2].label(), "ゴールへ", "nobody counted yet: the solo wording")


func test_progress_fills_as_bells_ring_animals_arrive_and_players_gather() -> void:
	var def := _sample()
	var items := StageObjectives.build(def)
	var snapshot := {
		"positions": {1: Vector3(20, 0, 20), 2: Vector3(20, 0, 20), 3: Vector3(20, 0, 20)},
		"active": PackedInt32Array([1, 2, 3]),
		"entities": {"lamb": Vector3(5, 0, 5)},
		"activated": PackedStringArray(),
	}
	StageObjectives.measure(items, snapshot)
	assert_eq(
		StageObjectives.describe_all(items),
		PackedStringArray(["[ ] どうぶつを巣へ", "[ ] 鐘を鳴らす 0/2", "[ ] 全員でゴールへ 0/3"])
	)
	snapshot["activated"] = PackedStringArray(["bell_a"])
	StageObjectives.measure(items, snapshot)
	assert_eq(items[1].label(), "鐘を鳴らす 1/2")
	snapshot["activated"] = PackedStringArray(["bell_a", "bell_b"])
	snapshot["entities"] = {"lamb": Vector3(11, 0, 11)}
	(snapshot["positions"] as Dictionary)[1] = Vector3(0, 0, 0)
	(snapshot["positions"] as Dictionary)[2] = Vector3(0.5, 0, 0)
	var counts := StageObjectives.measure(items, snapshot)
	assert_true(items[0].is_met(), "the lamb is in its nest")
	assert_true(items[1].is_met(), "both bells rang")
	assert_eq(items[2].label(), "全員でゴールへ 2/3")
	assert_false(items[2].is_met())
	assert_eq(counts, PackedInt32Array([1, 1, 2, 2, 2, 3]))
	# 参加者は数えずに、届いた数を入れるだけ
	var replica := StageObjectives.build(def)
	StageObjectives.apply(replica, counts)
	assert_eq(StageObjectives.describe_all(replica), StageObjectives.describe_all(items))


func test_dead_players_are_not_needed_at_the_goal() -> void:
	var items := StageObjectives.build(_sample())
	var snapshot := {
		"positions": {1: Vector3.ZERO, 2: Vector3(30, -40, 0)},
		"active": PackedInt32Array([1]),
		"entities": {},
		"activated": PackedStringArray(),
	}
	StageObjectives.measure(items, snapshot)
	assert_true(items[2].is_met(), "the only living player is at the goal")
	assert_eq(items[2].label(), "ゴールへ")


func test_the_hub_has_no_objectives() -> void:
	assert_true(StageObjectives.build(StageCatalog.hub()).is_empty())
