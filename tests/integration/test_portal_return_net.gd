extends TestCase
## 2 人の協力: 参加者も同じ目的の一覧と進み具合を見る（ホストが数えて配る）。「このステージから出る」は
## ホストなら全員で、参加者なら投票。戻ると 2 人ともポータルの前に、出現地点と同じ並びで広場の側を向いて立つ。
## クリアの後も同じ。「このステージを最初から」も同じ決め方（docs/adr/0020）。部屋の組み立ては net_party.gd。

const NetParty := preload("res://tests/integration/net_party.gd")
const ROLLING := "w2_rolling_shots"

var party: NetParty


func before_each() -> void:
	party = NetParty.new(self, 2, "zz_test_portal_return_net")


func after_each() -> void:
	await party.close()


func _lines(i: int) -> PackedStringArray:
	return StageObjectives.describe_all(party.directors[i].objectives)


func _in_hub_at_portal(stage_id: String) -> bool:
	for i in party.count():
		var d := party.directors[i]
		if d.stage_id != StageCatalog.HUB_ID or d.world.def.overworld == null:
			return false
		var spot := d.world.def.overworld.portal(stage_id).returns[i]
		var at := d.world.player.global_position
		if Vector2(at.x - spot.x, at.z - spot.z).length() > 0.3:
			return false
	return true


func _assert_spread_and_facing(stage_id: String) -> void:
	var client := party.directors[1]
	var portal := client.world.def.overworld.portal(stage_id)
	var host_at := party.world(0).player.global_position
	var client_at := party.world(1).player.global_position
	assert_gt(host_at.distance_to(client_at), 0.8, "spread like the spawn points")
	assert_almost(party.world(1).camera_rig.yaw, portal.return_yaw, 0.01, "the client looks away")
	for i in party.count():
		var w := party.world(i)
		assert_eq(w.entrance_at(w.player.global_position), "", "side %d is outside the portal" % i)


func test_the_client_sees_the_same_objectives_and_live_progress() -> void:
	await party.open(StageCatalog.HUB_ID, 39000)
	await party.join_all()
	await party.enter(ROLLING)
	assert_eq(_lines(1), _lines(0), "same list on both screens")
	assert_eq(_lines(1)[2], "[ ] 全員でゴールへ 0/2", "two players are needed at the goal")
	party.world(0).bells_by_key["isle_bell"].ring()
	await party.until(
		func() -> bool: return _lines(1)[1] == "[x] 鐘を鳴らす", "the client sees the bell ring"
	)
	var goal := party.host().world.def.clear_condition.goal_area()
	await party.place(0, Vector3(goal.get_center().x, goal.position.y + 0.2, goal.get_center().z))
	await party.until(
		func() -> bool: return _lines(1)[2] == "[ ] 全員でゴールへ 1/2", "the client sees 1/2"
	)
	assert_eq(party.host().last_clear_text, "", "the kit is not home yet")


## ホストが「このステージから出る」を選ぶと、投票なしで全員がポータルの前へ戻る。
func test_the_host_leaving_takes_everyone_to_the_portal() -> void:
	await party.open(StageCatalog.HUB_ID, 39500)
	await party.join_all()
	await party.enter(ROLLING)
	party.host().request_leave_stage()
	await party.until(func() -> bool: return _in_hub_at_portal(ROLLING), "both at the portal")
	_assert_spread_and_facing(ROLLING)


## 参加者が選ぶと投票が開くだけ（ステージに残る）。ホストもえらぶと全員で出る。
func test_a_client_leaving_opens_a_vote() -> void:
	await party.open(StageCatalog.HUB_ID, 40300)
	await party.join_all()
	await party.enter(ROLLING)
	var messages: Array[String] = []
	party.world(1).message_posted.connect(func(text: String) -> void: messages.append(text))
	party.directors[1].request_leave_stage()
	await party.until(
		func() -> bool: return party.host().leave_vote.is_open(), "the host counts the vote"
	)
	assert_eq(party.host().leave_vote.counts(PackedInt32Array([1, 2])), Vector2i(1, 2))
	assert_eq(party.host().leave_vote.action, StageLeaveVote.Action.LEAVE)
	await party.until(
		func() -> bool:
			return messages.any(func(m: String) -> bool: return m.begins_with("このステージから出る投票 1 / 2")),
		"the client is told about the vote"
	)
	await wait_physics_frames(10)
	assert_eq(party.host().stage_id, ROLLING, "one vote of two is not enough")
	party.host().request_leave_stage()
	await party.until(func() -> bool: return _in_hub_at_portal(ROLLING), "both at the portal")


## 参加者の「このステージを最初から」も投票。ホストがえらぶと全員で、新しい回として作り直す。
func test_a_client_restart_is_a_vote_and_the_host_restarts_for_everyone() -> void:
	await party.open(StageCatalog.HUB_ID, 40400)
	await party.join_all()
	await party.enter(ROLLING)
	var first_run := party.host().stage_run_id
	party.world(0).bells_by_key["isle_bell"].ring()
	await party.until(func() -> bool: return _lines(1)[1] == "[x] 鐘を鳴らす", "rang")
	party.world(1).restart_island()
	await party.until(
		func() -> bool: return party.host().leave_vote.is_open(), "the host counts the vote"
	)
	assert_eq(party.host().leave_vote.action, StageLeaveVote.Action.RESTART)
	assert_eq(party.host().stage_run_id, first_run, "not yet")
	party.world(0).restart_island()
	await party.until(
		func() -> bool:
			return (
				party.directors[1].stage_run_id != first_run
				and party.directors[1].stage_id == ROLLING
				and _lines(1)[1] == "[ ] 鐘を鳴らす"
			),
		"both restarted the stage"
	)
	assert_false(party.host().leave_vote.is_open())


func test_after_a_clear_everyone_returns_to_the_portal() -> void:
	await party.open(StageCatalog.HUB_ID, 40000)
	await party.join_all()
	await party.enter(StageCatalog.INTRO_ID)
	var goal := party.host().world.def.clear_condition.goal_area()
	var center := Vector3(goal.get_center().x, goal.position.y + 0.2, goal.get_center().z)
	await party.place(1, center + Vector3(0.5, 0.0, 0.0))
	await party.place(0, center - Vector3(0.5, 0.0, 0.0))
	await party.until(func() -> bool: return party.host().last_clear_text != "", "cleared")
	await party.until(
		func() -> bool: return _in_hub_at_portal(StageCatalog.INTRO_ID),
		"both in front of the intro portal",
		int(PartyDirector.RETURN_DELAY * 60.0) + 300
	)
	_assert_spread_and_facing(StageCatalog.INTRO_ID)
