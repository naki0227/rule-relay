extends TestCase
## 1人の永続の進行（引き継ぎ仕様 5.1、受け入れテスト候補 21・22 の報酬部分）。

const STAGE := "prototype_island"
const APPLIED := PlayerProgress.Outcome.APPLIED
const DUPLICATE := PlayerProgress.Outcome.DUPLICATE
const INVALID := PlayerProgress.Outcome.INVALID
const SHELL := "tmp_collectible_shell_1"

var progress: PlayerProgress
var table: RewardTable


func before_each() -> void:
	progress = PlayerProgress.new()
	table = RewardTable.provisional()


## 1回の走行の報酬イベント（ホストの台帳から作る）。
func _event(run_id: String, metrics: RunMetrics, party: int = 1) -> Dictionary:
	var rewards := StageRunRewards.new(STAGE, run_id)
	var statuses: Dictionary[String, int] = {}
	for i: int in party:
		statuses["p%d" % i] = StageRunRewards.Status.ACTIVE
	rewards.settle(statuses, metrics, 1_790_000_000 + run_id.length())
	return rewards.event_for("p0")


# --- 初回と周回（21） --------------------------------------------------------------


func test_first_clear_grants_area_hub_and_first_reward() -> void:
	var result := progress.apply_reward_event(
		_event("r1", RunMetrics.create(120.0, 9, 4), 2), table
	)
	assert_eq(result.outcome, APPLIED)
	assert_true(result.first_clear)
	assert_true(progress.has_cleared(STAGE))
	assert_true(progress.has_area("tmp_area_second_island"))
	assert_eq(
		progress.hub_developments(), PackedStringArray(["tmp_hub_bridge_1", "tmp_hub_lantern_1"])
	)
	assert_true(progress.cosmetics().has("tmp_cosmetic_leaf_scarf"))
	assert_eq(progress.first_clear_time(STAGE), 1_790_000_002)
	assert_eq(progress.clear_count(STAGE), 1)


func test_repeat_clear_never_regrants_first_clear_things() -> void:
	progress.apply_reward_event(_event("r1", RunMetrics.create(120.0, 9, 4), 2), table)
	var first_time := progress.first_clear_time(STAGE)
	var second := progress.apply_reward_event(
		_event("r22", RunMetrics.create(150.0, 9, 4), 2), table
	)
	assert_eq(second.outcome, APPLIED)
	assert_false(second.first_clear)
	assert_true(second.granted.is_empty(), "nothing new: %s" % str(second.granted))
	assert_eq(progress.unlocked_areas().size(), 1, "area unlocked only once")
	assert_eq(progress.hub_developments().size(), 2)
	assert_eq(progress.first_clear_time(STAGE), first_time, "first clear time is kept")
	assert_eq(progress.clear_count(STAGE), 2)


func test_repeat_clear_can_grant_condition_and_collectibles() -> void:
	progress.apply_reward_event(_event("r1", RunMetrics.create(120.0, 9, 4), 2), table)
	var picked := PackedStringArray([SHELL, "not_in_table"])
	var second := progress.apply_reward_event(
		_event("r22", RunMetrics.create(200.0, 3, 0, picked), 2), table
	)
	assert_true(second.granted.has("tmp_collectible_light_hands"), "abilities <= 3 condition")
	assert_true(second.granted.has(SHELL))
	assert_false(progress.collectibles().has("not_in_table"), "only collectibles of the table")
	assert_false(second.granted.has("tmp_cosmetic_solo_badge"), "not a solo clear")
	var solo := progress.apply_reward_event(_event("r333", RunMetrics.create(300.0, 8, 0)), table)
	assert_true(solo.granted.has("tmp_cosmetic_solo_badge"))
	var again := progress.apply_reward_event(_event("r4444", RunMetrics.create(300.0, 2, 0)), table)
	assert_true(again.granted.is_empty(), "condition rewards are also given once")


func test_unknown_stage_records_clear_without_rewards() -> void:
	var rewards := StageRunRewards.new("stage_not_in_table", "r1")
	rewards.settle({"p0": StageRunRewards.Status.ACTIVE}, RunMetrics.create(10.0, 1, 0), 5)
	var result := progress.apply_reward_event(rewards.event_for("p0"), table)
	assert_eq(result.outcome, APPLIED)
	assert_true(result.granted.is_empty())
	assert_true(progress.has_cleared("stage_not_in_table"))


# --- 記録は別々の項目（21） ---------------------------------------------------------


func test_records_are_kept_per_axis_not_combined() -> void:
	progress.apply_reward_event(_event("r1", RunMetrics.create(120.0, 9, 4), 2), table)
	# 遅いが能力を少なく使った
	var second := progress.apply_reward_event(_event("r22", RunMetrics.create(180.0, 5, 6)), table)
	assert_eq(second.improved_axes, PackedStringArray([PlayerProgress.AXIS_FEWEST_ABILITIES]))
	var fastest := progress.record(STAGE, PlayerProgress.AXIS_FASTEST)
	assert_almost(float(fastest["value"]), 120.0, 0.001)
	assert_eq(fastest["party_size"], 2, "record remembers party size of that run")
	assert_eq(fastest["stage_run_id"], "r1")
	var fewest := progress.record(STAGE, PlayerProgress.AXIS_FEWEST_ABILITIES)
	assert_eq(int(fewest["value"]), 5)
	assert_eq(fewest["party_size"], 1)
	assert_eq(int(progress.record(STAGE, PlayerProgress.AXIS_FEWEST_HAND_OFFS)["value"]), 4)
	assert_eq(progress.party_sizes_cleared(STAGE), PackedInt32Array([1, 2]))


func test_equal_value_keeps_earlier_record() -> void:
	progress.apply_reward_event(_event("r1", RunMetrics.create(100.0, 5, 1)), table)
	var tie := progress.apply_reward_event(_event("r22", RunMetrics.create(100.0, 5, 1)), table)
	assert_true(tie.improved_axes.is_empty())
	assert_eq(progress.record(STAGE, PlayerProgress.AXIS_FASTEST)["stage_run_id"], "r1")


# --- 冪等（22） ---------------------------------------------------------------------


func test_same_event_twice_is_ignored() -> void:
	var event := _event("r1", RunMetrics.create(120.0, 9, 4, PackedStringArray([SHELL])))
	assert_eq(progress.apply_reward_event(event, table).outcome, APPLIED)
	var before := progress.to_dict()
	var again := progress.apply_reward_event(event.duplicate(true), table)
	assert_eq(again.outcome, DUPLICATE)
	assert_false(again.first_clear)
	assert_eq(progress.to_dict(), before, "nothing changes on re-send")
	assert_eq(progress.clear_count(STAGE), 1)
	assert_eq(progress.applied_event_count(), 1)


func test_malformed_event_changes_nothing() -> void:
	var good := _event("r1", RunMetrics.create(120.0, 9, 4))
	var no_id := good.duplicate(true)
	no_id.erase("reward_event_id")
	var bad_metrics := good.duplicate(true)
	bad_metrics["metrics"] = {"clear_seconds": "fast"}
	var no_stage := good.duplicate(true)
	no_stage["stage_id"] = ""
	for event: Dictionary in [no_id, bad_metrics, no_stage, {}]:
		var result := progress.apply_reward_event(event, table)
		assert_eq(result.outcome, INVALID)
		assert_false(result.should_acknowledge())
	assert_false(progress.has_cleared(STAGE))
	assert_eq(progress.applied_event_count(), 0)


func test_late_delivery_of_older_run_is_a_repeat() -> void:
	# 切断中の古い走行の報酬が、新しい走行より後に届いても初回の物は増えない
	progress.apply_reward_event(_event("new-run", RunMetrics.create(90.0, 4, 1)), table)
	var late := progress.apply_reward_event(_event("old", RunMetrics.create(80.0, 9, 9)), table)
	assert_eq(late.outcome, APPLIED)
	assert_false(late.first_clear)
	assert_eq(progress.clear_count(STAGE), 2)
	assert_eq(progress.unlocked_areas().size(), 1)


# --- 報酬表 -------------------------------------------------------------------------


func test_provisional_table_is_valid_and_has_no_ability_boosts() -> void:
	assert_true(table.errors().is_empty(), str(table.errors()))
	for key: String in RewardTable.FIRST_CLEAR_KEYS:
		for id: String in table.first_clear_rewards(STAGE, key):
			assert_true(id.begins_with("tmp_"), "provisional ids are marked: %s" % id)


func test_table_rejects_permanent_ability_boosts() -> void:
	var bad := (
		RewardTable
		. new(
			{
				STAGE:
				{
					"first_clear": {"abilities": ["jump_x4"], "areas": ["tmp_a"]},
					"conditions":
					[
						{"id": "speed", "kind": "ability_boost", "axis": "hand_offs", "at_most": 1},
						{"id": "ok", "kind": "cosmetic", "axis": "hand_offs", "at_most": 1},
					],
				}
			}
		)
	)
	assert_eq(bad.errors().size(), 2, str(bad.errors()))
	assert_true(bad.first_clear_rewards(STAGE, "abilities").is_empty())
	assert_eq(bad.conditions(STAGE).size(), 1, "only the cosmetic condition is used")
	var result := progress.apply_reward_event(_event("r1", RunMetrics.create(1.0, 0, 0)), bad)
	assert_false(result.granted.has("jump_x4"))
	assert_false(result.granted.has("speed"))
	assert_true(result.granted.has("ok"))


# --- 保存の形 -----------------------------------------------------------------------


func test_json_round_trip() -> void:
	progress.apply_reward_event(_event("r1", RunMetrics.create(120.5, 9, 4), 3), table)
	progress.apply_reward_event(
		_event("r22", RunMetrics.create(99.25, 2, 0, PackedStringArray([SHELL]))), table
	)
	var parsed: Variant = JSON.parse_string(JSON.stringify(progress.to_dict()))
	var restored := PlayerProgress.from_dict(parsed as Dictionary)
	assert_true(restored != null)
	assert_eq(restored.to_dict(), progress.to_dict())
	assert_eq(restored.clear_count(STAGE), 2)
	assert_eq(restored.party_sizes_cleared(STAGE), PackedInt32Array([1, 3]))
	assert_true(restored.has_applied(StageRunRewards.make_event_id("r1", "p0")))
	var resend := restored.apply_reward_event(_event("r1", RunMetrics.create(1.0, 0, 0)), table)
	assert_eq(resend.outcome, DUPLICATE, "applied ids survive save and load")


func test_from_dict_rejects_wrong_types() -> void:
	assert_true(PlayerProgress.from_dict({"stages": []}) == null)
	assert_true(PlayerProgress.from_dict({"areas": "tmp_area"}) == null)
	assert_true(PlayerProgress.from_dict({"stages": {"s": 3}}) == null)
	var empty := PlayerProgress.from_dict({})
	assert_true(empty != null)
	assert_true(empty.cleared_stages().is_empty())
