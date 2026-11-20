extends TestCase
## ホストの報酬台帳（引き継ぎ仕様 5.2 の真理値表、受け入れテスト候補 17〜20・22 の報酬部分）。
## ステージ固有のクリア条件（「全員到達」など）の判定はステージ側の責務で、ここでは扱わない。

const ACTIVE := StageRunRewards.Status.ACTIVE
const DEAD := StageRunRewards.Status.DEAD_SPECTATING
const DISCONNECTED := StageRunRewards.Status.DISCONNECTED
const WAITING := StageRunRewards.Status.WAITING_SPECTATOR
const LEFT_BEFORE := StageRunRewards.Status.LEFT_BEFORE_CLEAR
const LEFT_AFTER := StageRunRewards.Status.LEFT_AFTER_CLEAR
const STAGE := "prototype_island"
const RUN := "run-7f3a"
const CLEARED_AT := 1_790_000_000

var rewards: StageRunRewards
var table: RewardTable


func before_each() -> void:
	rewards = StageRunRewards.new(STAGE, RUN)
	table = RewardTable.provisional()


func _metrics() -> RunMetrics:
	return RunMetrics.create(95.5, 6, 2)


func _settle(statuses: Dictionary[String, int]) -> bool:
	return rewards.settle(statuses, _metrics(), CLEARED_AT)


# --- 5.2 の真理値表（1行ずつ） --------------------------------------------------


func test_row_active_participant_is_rewarded() -> void:
	_settle({"a": ACTIVE})
	assert_true(rewards.is_eligible("a"))
	assert_eq(rewards.event_for("a")["reward_event_id"], StageRunRewards.make_event_id(RUN, "a"))


func test_row_dead_spectator_is_rewarded() -> void:
	_settle({"a": ACTIVE, "b": DEAD})
	assert_true(rewards.is_eligible("b"), "death alone is not a reward condition")


func test_row_disconnected_participant_is_rewarded() -> void:
	_settle({"a": ACTIVE, "b": DISCONNECTED})
	assert_true(rewards.is_eligible("b"))
	assert_true(rewards.pending_keys().has("b"))


func test_row_waiting_spectator_is_not_rewarded() -> void:
	_settle({"a": ACTIVE, "w": WAITING})
	assert_false(rewards.is_eligible("w"))
	assert_true(rewards.event_for("w").is_empty())
	assert_eq(rewards.status_of("w"), WAITING)


func test_row_left_before_clear_is_not_rewarded() -> void:
	_settle({"a": ACTIVE, "b": LEFT_BEFORE})
	assert_false(rewards.is_eligible("b"), "explicit leave differs from disconnect")


func test_row_left_after_clear_keeps_reward() -> void:
	_settle({"a": ACTIVE, "b": ACTIVE})
	rewards.mark_left_after_clear("b")
	assert_eq(rewards.status_of("b"), LEFT_AFTER)
	assert_true(rewards.is_eligible("b"), "leaving after clear never revokes")
	assert_true(rewards.pending_keys().has("b"), "still waiting for delivery")
	var other := StageRunRewards.new(STAGE, "run-2")
	other.settle({"c": LEFT_AFTER}, _metrics(), CLEARED_AT)
	assert_true(other.is_eligible("c"), "status given as left-after-clear stays eligible")


func test_mark_left_does_not_make_ineligible_people_eligible() -> void:
	_settle({"a": ACTIVE, "w": WAITING})
	rewards.mark_left_after_clear("w")
	assert_eq(rewards.status_of("w"), WAITING)
	assert_false(rewards.is_eligible("w"))


# --- 受け入れテスト候補 17〜20 ---------------------------------------------------


func test_17_three_dead_spectators_and_last_one_clears_all_four_rewarded() -> void:
	_settle({"a": DEAD, "b": DEAD, "c": DEAD, "d": ACTIVE})
	assert_eq(rewards.eligible_keys(), PackedStringArray(["a", "b", "c", "d"]))
	assert_eq(rewards.metrics().party_size, 4, "party size counts eligible participants")


func test_18_waiting_spectator_gets_reward_after_joining_at_reset() -> void:
	_settle({"a": ACTIVE, "w": WAITING})
	assert_false(rewards.is_eligible("w"))
	# 全員リセットで正式に合流した後の次の走行では、ACTIVE として渡される
	var next_run := StageRunRewards.new(STAGE, "run-next")
	next_run.settle({"a": ACTIVE, "w": ACTIVE}, _metrics(), CLEARED_AT + 300)
	assert_true(next_run.is_eligible("w"))
	assert_eq(rewards.metrics().party_size, 1, "waiting spectator is not counted")


func test_19_disconnected_player_gets_reward_once_on_reconnect() -> void:
	_settle({"a": ACTIVE, "b": DISCONNECTED})
	var sent_now := rewards.events_to_send(PackedStringArray(["a"]))
	assert_eq(sent_now.size(), 1, "only connected players are sent to right away")
	assert_eq(sent_now[0]["player_key"], "a")
	# B が戻る（部屋は残っている）
	var on_reconnect := rewards.events_to_send(PackedStringArray(["a", "b"]))
	assert_eq(on_reconnect.size(), 2, "A has not acknowledged yet either")
	var progress_b := PlayerProgress.new()
	var event_b := rewards.event_for("b")
	var first := progress_b.apply_reward_event(event_b, table)
	assert_eq(first.outcome, PlayerProgress.Outcome.APPLIED)
	# 返事が届く前にもう一度送られても、二重には付与しない
	var again := progress_b.apply_reward_event(rewards.event_for("b"), table)
	assert_eq(again.outcome, PlayerProgress.Outcome.DUPLICATE)
	assert_true(again.should_acknowledge())
	assert_true(rewards.acknowledge("b", str(event_b["reward_event_id"])))
	assert_true(rewards.is_delivered("b"))
	assert_eq(progress_b.clear_count(STAGE), 1)
	assert_eq(rewards.events_to_send(PackedStringArray(["b"])).size(), 0)


func test_20_left_before_clear_gets_nothing_left_after_keeps() -> void:
	_settle({"a": ACTIVE, "b": LEFT_BEFORE})
	assert_eq(rewards.events_to_send(PackedStringArray(["a", "b"])).size(), 1)
	var after := StageRunRewards.new(STAGE, "run-after")
	after.settle({"a": ACTIVE, "b": ACTIVE}, _metrics(), CLEARED_AT)
	var event_b := after.event_for("b")
	after.mark_left_after_clear("b")
	assert_eq(after.event_for("b"), event_b, "same reward after leaving")


# --- 再送・冪等・引き継ぎ（受け入れテスト候補 22 の報酬部分） -----------------------


func test_event_id_is_deterministic_per_run_and_player() -> void:
	_settle({"a": ACTIVE, "b": ACTIVE})
	var again := StageRunRewards.new(STAGE, RUN)
	again.settle({"b": DEAD, "a": ACTIVE}, _metrics(), CLEARED_AT)
	assert_eq(again.event_for("a")["reward_event_id"], rewards.event_for("a")["reward_event_id"])
	assert_ne(rewards.event_for("a")["reward_event_id"], rewards.event_for("b")["reward_event_id"])


func test_settle_only_once() -> void:
	assert_true(_settle({"a": ACTIVE}))
	assert_false(_settle({"a": ACTIVE, "b": ACTIVE}), "second clear of the same run is ignored")
	assert_false(rewards.is_eligible("b"))


func test_settle_rejects_missing_ids_and_bad_metrics() -> void:
	var no_run := StageRunRewards.new(STAGE, "")
	assert_false(no_run.settle({"a": ACTIVE}, _metrics(), CLEARED_AT))
	assert_false(rewards.settle({"a": ACTIVE}, RunMetrics.create(-1.0, 0, 0), CLEARED_AT))
	assert_false(rewards.settle({"a": ACTIVE}, null, CLEARED_AT))
	assert_false(rewards.is_settled())


func test_unknown_status_and_empty_key_are_ignored() -> void:
	_settle({"a": ACTIVE, "": ACTIVE, "x": 99})
	assert_eq(rewards.eligible_keys(), PackedStringArray(["a"]))
	assert_eq(rewards.status_of("x"), -1)


func test_acknowledge_needs_matching_event_id() -> void:
	_settle({"a": ACTIVE})
	assert_false(rewards.acknowledge("a", "other-run/a"))
	assert_false(rewards.acknowledge("w", StageRunRewards.make_event_id(RUN, "w")))
	assert_false(rewards.is_delivered("a"))
	var event_id := StageRunRewards.make_event_id(RUN, "a")
	assert_true(rewards.acknowledge("a", event_id))
	assert_true(rewards.acknowledge("a", event_id), "duplicate ack is harmless")
	assert_true(rewards.pending_keys().is_empty())


func test_handover_to_new_host_keeps_ids_and_delivery() -> void:
	_settle({"a": ACTIVE, "b": DISCONNECTED, "w": WAITING})
	rewards.acknowledge("a", StageRunRewards.make_event_id(RUN, "a"))
	var parsed: Variant = JSON.parse_string(JSON.stringify(rewards.to_dict()))
	var restored := StageRunRewards.from_dict(parsed as Dictionary)
	assert_true(restored != null)
	assert_true(restored.is_settled())
	assert_eq(restored.event_for("b"), rewards.event_for("b"), "same event after handover")
	assert_true(restored.is_delivered("a"))
	assert_eq(restored.pending_keys(), PackedStringArray(["b"]))
	assert_eq(restored.status_of("w"), WAITING)
	assert_false(restored.settle({"w": ACTIVE}, _metrics(), CLEARED_AT), "cannot re-settle")
	# 新ホストが再送しても、すでに受け取った人には二重に付かない
	var progress_a := PlayerProgress.new()
	progress_a.apply_reward_event(rewards.event_for("a"), table)
	var resent := progress_a.apply_reward_event(restored.event_for("a"), table)
	assert_eq(resent.outcome, PlayerProgress.Outcome.DUPLICATE)


func test_from_dict_rejects_wrong_shape() -> void:
	assert_true(StageRunRewards.from_dict({"statuses": []}) == null)
	var bad := {"stage_id": STAGE, "stage_run_id": RUN, "settled": true, "metrics": {}}
	assert_true(StageRunRewards.from_dict(bad) == null)
	var unsettled := StageRunRewards.from_dict({"stage_id": STAGE, "stage_run_id": RUN})
	assert_false(unsettled.is_settled())
