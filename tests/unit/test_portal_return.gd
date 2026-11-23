extends TestCase
## 広場へ戻ったときの立ち位置（Overworld.return_spots・PortalReturn。docs/adr/0020）と、
## メニューの「広場へもどる」の投票の数え方（StageLeaveVote）。


func _states() -> Array[OverworldState]:
	var states: Array[OverworldState] = [
		OverworldState.first_visit(),
		OverworldState.everything(false),
		OverworldState.everything(true),
	]
	for cleared in _w1_progress():
		states.append(OverworldState.of(cleared, false, false, false))
		states.append(OverworldState.of(cleared, true, true, false))
	return states


## はじまりの草原（W1）のステージの順。
func _w1_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for slot in CampaignPlan.built_slots(CampaignPlan.worlds()[0]):
		ids.append(slot.stage_id)
	return ids


## W1 を 1 つずつクリアした進み具合（1-1 だけ、1-1 と 1-2、…。最後の 1 つの手前まで）。
func _w1_progress() -> Array[PackedStringArray]:
	var ids := _w1_ids()
	var result: Array[PackedStringArray] = []
	for k in range(1, ids.size()):
		result.append(ids.slice(0, k))
	return result


## カメラ（camera_point）から point が画面に入っているか（PortalSpots.VISIBLE_ANGLE の中）。
func _on_screen(spot: Vector3, yaw: float, point: Vector3) -> bool:
	var cam := PortalSpots.camera_point(spot, yaw)
	var look := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	var to := Vector2(point.x - cam.x, point.z - cam.z)
	return absf(Vector2(look.x, look.z).angle_to(to)) <= PortalSpots.VISIBLE_ANGLE + 0.001


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


## 戻った直後のカメラ（人の 5.5 m 後ろ）が、どの門にも入り込まず、カメラから人への視線も門を横切らない
## （門が画面をふさがない）。正面の先・横や斜めのどちらに立つポータルでも同じ。
func test_the_camera_after_a_return_stays_clear_of_every_arch() -> void:
	for state in _states():
		var def := Overworld.build(state)
		for p in def.overworld.portals:
			var center := Vector2(p.position.x, p.position.z)
			for spot in p.returns:
				var cam := PortalSpots.camera_point(spot, p.return_view_yaw)
				assert_true(
					PortalSpots.camera_clear_of_gates(cam, def), "%s: camera clear" % p.stage_id
				)
				var sight := Geometry2D.get_closest_point_to_segment(
					center, Vector2(cam.x, cam.z), Vector2(spot.x, spot.z)
				)
				assert_gt(sight.distance_to(center), PortalSpots.SIGHT_CLEAR - 0.01, p.stage_id)
				var out := Basis(Vector3.UP, p.return_yaw) * Vector3.FORWARD
				var look := Basis(Vector3.UP, p.return_view_yaw) * Vector3.FORWARD
				# 次のポータルを見せるために振り返ることはある（2026-11-23）。それ以外は広場の側を向く
				var next := def.overworld.recommended()
				if next == null or not _on_screen(spot, p.return_view_yaw, next.position):
					assert_gt(out.dot(look), -0.01, "%s: still looking out at the hub" % p.stage_id)


## W1 のステージをクリアして広場へ戻ると、次に遊ぶ W1 のポータル（光の柱の「つぎはここ」）が、4 人どの
## カメラの画面にも入る向きで立つ（2026-11-23 本人の判断「次のポータルに向ける」）。製品版の開き方（次だけ開く）
## と試遊の版（全部開いている）の両方。カメラの条件は上の test_the_camera_after_a_return_stays_clear_of_every_arch。
func test_returning_from_a_w1_stage_faces_the_next_w1_portal() -> void:
	var ids := _w1_ids()
	for cleared in _w1_progress():
		for open_all: bool in [false, true]:
			var def := Overworld.build(OverworldState.of(cleared, open_all, open_all, false))
			var next := def.overworld.recommended()
			var expected := ids[cleared.size()]
			assert_true(next != null and next.stage_id == expected, "next is %s" % expected)
			assert_true(next.next, "the portal with the orange column")
			var back := PortalReturn.new()
			back.portal = cleared[cleared.size() - 1]
			back.choose(def, true, false)
			for spot in back.spots:
				assert_true(
					_on_screen(spot, back.yaw, next.position), "%s -> %s" % [back.portal, expected]
				)


## W1 を全部クリアした後は、本編の順で次に開いていてまだクリアしていないポータルへ向ける（光の柱は無い）。
func test_after_w1_the_next_recommended_portal_is_the_first_open_uncleared_one() -> void:
	var ids := _w1_ids()
	var def := Overworld.build(OverworldState.of(ids, true, true, false))
	var next := def.overworld.recommended()
	assert_true(next != null, "a next portal")
	assert_false(next.next, "no orange column after W1")
	assert_false(ids.has(next.stage_id), "outside W1")
	var slot := CampaignPlan.slot(next.stage_id)
	assert_false(CampaignPlan.world(slot.world_id).optional, "a main-campaign portal")
	var everything := Overworld.build(OverworldState.everything(true))
	assert_eq(everything.overworld.recommended(), null, "nothing left: keep the old view")


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
	assert_almost(back.yaw, portal.return_view_yaw, 0.001, "faces away from the portal")
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


## 「最初から」の投票が開いているときに「出る」をえらぶと、新しい「出る」の投票に置き換わる（足し合わせない）。
func test_a_vote_for_the_other_action_starts_over() -> void:
	var vote := StageLeaveVote.new()
	var three := PackedInt32Array([1, 2, 3])
	var restart := StageLeaveVote.Action.RESTART
	var leave := StageLeaveVote.Action.LEAVE
	assert_eq(vote.cast(2, three, 30.0, restart), StageLeaveVote.Result.OPENED)
	assert_eq(vote.action, restart)
	assert_eq(vote.cast(3, three, 30.0, leave), StageLeaveVote.Result.OPENED, "replaced")
	assert_eq(vote.action, leave)
	assert_eq(vote.counts(three), Vector2i(1, 2), "the restart vote is not carried over")
	assert_eq(vote.cast(2, three, 30.0, leave), StageLeaveVote.Result.PASSED)


## 門の上の文字は、カメラが近いと画面で大きくなりすぎない（LABEL_FULL_AT より近いと画面での大きさを止め、
## すぐそばでは薄くして消す）。中くらいのきょりではそのまま読める。
func test_portal_labels_do_not_grow_huge_up_close() -> void:
	var portal := OverworldPortal.new()
	portal.label = KeyLabel3D.new()
	portal.fit_label(20.0)
	assert_almost(portal.label.scale.x, 1.0, 0.001, "full size from mid range")
	assert_almost(portal.label.modulate.a, 1.0, 0.001)
	for near: float in [6.0, 4.0]:
		portal.fit_label(near)
		var on_screen := portal.label.scale.x / near
		assert_almost(on_screen, 1.0 / OverworldPortal.LABEL_FULL_AT, 0.001, "same size on screen")
	portal.fit_label(1.0)
	assert_false(portal.label.visible, "gone right next to the camera")
	portal.fit_label(OverworldPortal.LABEL_FAR_GONE_AT + 1.0)
	assert_false(portal.label.visible, "far signs are not scattered over the hub as tiny text")
	portal.fit_label(OverworldPortal.LABEL_FAR_FADE_FROM - 1.0)
	assert_almost(portal.label.modulate.a, 1.0, 0.001, "readable signs stay")
	portal.label.free()
	portal.free()
