extends TestCase
## 広場へ戻ったときの立ち位置（Overworld.return_spots・PortalReturn。docs/adr/0018）と、
## メニューの「広場へもどる」の投票の数え方（StageLeaveVote）。


func _states() -> Array[OverworldState]:
	return [
		OverworldState.first_visit(),
		OverworldState.everything(false),
		OverworldState.everything(true),
	]


## どのポータルにも 4 人分の立ち位置があり、どれもポータルと同じ高さで、ポータルから向く向きの先にあり、
## 入口の箱の外（ほとんどのポータルは正面の先。崖の縁に近いポータルは横や斜め）。
func test_every_portal_has_four_spots_in_front_of_it_outside_every_entrance() -> void:
	for state in _states():
		var def := Overworld.build(state)
		for p in def.overworld.portals:
			assert_eq(p.returns.size(), StageDef.MAX_PLAYERS, "%s has return spots" % p.stage_id)
			var ahead := Basis(Vector3.UP, p.return_yaw) * Vector3.FORWARD
			for spot in p.returns:
				assert_almost(spot.y, p.position.y, 0.01, "%s: same height" % p.stage_id)
				assert_gt((spot - p.position).dot(ahead), 2.0, "%s: facing away" % p.stage_id)
				for e in def.entrances:
					var inside := e.area.grow(0.35).has_point(spot + Vector3(0.0, 0.1, 0.0))
					assert_false(inside, "%s: spot %s is in %s" % [p.stage_id, spot, e.stage_id])
			for i in range(1, p.returns.size()):
				assert_gt(p.returns[i].distance_to(p.returns[i - 1]), 0.6, "spread out")


## 草原と鐘の谷の最初のポータルは、正面の先に立つ（広場の側を向く）。
func test_open_portals_put_the_party_straight_ahead() -> void:
	var def := Overworld.build(OverworldState.everything(false))
	for id: String in [StageCatalog.INTRO_ID, StageCatalog.HILL_ID]:
		var p := def.overworld.portal(id)
		assert_almost(p.return_yaw, p.facing, 0.001, "%s: straight ahead" % id)


## 広場が育っても（クリアで建物・住む生き物が増えても）、立ち位置はポータルの前のまま。
func test_spots_stay_put_when_the_overworld_grows() -> void:
	var before := Overworld.build(OverworldState.everything(false))
	var after := Overworld.build(OverworldState.everything(true))
	assert_gt(after.overworld.buildings().size(), 0.0, "buildings went up")
	for p in before.overworld.portals:
		assert_eq(after.overworld.portal(p.stage_id).returns, p.returns, p.stage_id)


func test_choose_puts_the_party_in_front_of_the_stage_it_left() -> void:
	var def := Overworld.build(OverworldState.everything(false))
	var portal := def.overworld.portal(StageCatalog.BELL_ID)
	var back := PortalReturn.new()
	back.portal = StageCatalog.BELL_ID
	back.choose(def, true, false)
	assert_eq(back.spots, portal.returns)
	assert_almost(back.yaw, portal.return_yaw, 0.001, "faces away from the portal")
	assert_eq(back.spot_for(3, Vector3.ZERO), portal.returns[2], "same order as the spawn points")
	assert_true(back.blocks(StageCatalog.BELL_ID), "no instant re-entry")
	assert_false(back.blocks(StageCatalog.INTRO_ID), "other portals stay open")
	back.tick(PortalReturn.GRACE + 0.1)
	assert_false(back.blocks(StageCatalog.BELL_ID), "open again after the grace")
	# 広場の中で入り直した（ステージから来ていない）ときは出現地点
	back.choose(def, false, false)
	assert_true(back.spots.is_empty())
	assert_eq(back.spot_for(1, Vector3(9, 9, 9)), Vector3(9, 9, 9))


func test_first_visit_uses_the_saved_portal_only_when_it_is_open() -> void:
	var locked := Overworld.build(OverworldState.first_visit())
	var back := PortalReturn.new()
	back.portal = StageCatalog.BELL_ID
	back.choose(locked, false, true)
	assert_true(back.spots.is_empty(), "a locked portal is not a start point")
	back.portal = StageCatalog.INTRO_ID
	back.choose(locked, false, true)
	assert_eq(back.spots, locked.overworld.portal(StageCatalog.INTRO_ID).returns)


func test_the_last_portal_is_saved_with_the_progress() -> void:
	var progress := PlayerProgress.new()
	assert_eq(progress.last_portal(), "")
	assert_true(progress.set_last_portal(StageCatalog.BELL_ID))
	assert_false(progress.set_last_portal(StageCatalog.BELL_ID), "unchanged")
	var loaded := PlayerProgress.from_dict(progress.to_dict())
	assert_eq(loaded.last_portal(), StageCatalog.BELL_ID)
	var old := PlayerProgress.from_dict({"stages": {}})
	assert_eq(old.last_portal(), "", "old saves have no last portal")


func test_leave_vote_needs_a_majority() -> void:
	var vote := StageLeaveVote.new()
	var solo := PackedInt32Array([1])
	assert_eq(vote.cast(1, solo, 30.0), StageLeaveVote.Result.PASSED, "solo leaves at once")
	var three := PackedInt32Array([1, 2, 3])
	assert_eq(vote.cast(4, three, 30.0), StageLeaveVote.Result.IGNORED, "not a voter")
	assert_eq(vote.cast(1, three, 30.0), StageLeaveVote.Result.OPENED)
	assert_eq(vote.counts(three), Vector2i(1, 2))
	assert_false(vote.tick(10.0))
	assert_eq(vote.cast(3, three, 30.0), StageLeaveVote.Result.PASSED, "2 of 3")
	assert_eq(vote.cast(2, three, 30.0), StageLeaveVote.Result.OPENED, "a new vote")
	assert_true(vote.tick(31.0), "times out")
	assert_eq(vote.counts(three), Vector2i.ZERO)
