extends TestCase
## 広場へ戻ると、入ったステージのポータルの前に、広場の側を向いて立つ（クリア・メニューの「広場へもどる」・
## 次の起動）。戻ってすぐはそのポータルに入り直さない。ステージの目的の一覧は鐘・どうぶつ・ゴールで埋まる
## （docs/adr/0020）。2 人の協力は test_portal_return_net.gd。

const PROFILE := "zz_test_portal_return"
const ROLLING := "w2_rolling_shots"
const PEAK := "w6_warp_stones"

var director: PartyDirector


func before_each() -> void:
	ProgressStore.new().delete(PROFILE)
	director = _make_director()
	director.enter_stage(StageCatalog.HUB_ID)
	await wait_physics_frames(5)


func after_each() -> void:
	if is_instance_valid(director):
		director.queue_free()
	await tree.process_frame
	ProgressStore.new().delete(PROFILE)


func _make_director() -> PartyDirector:
	var made := PartyDirector.new()
	made.profile = PROFILE
	tree.root.add_child(made)
	return made


func _player() -> PlayerAvatar:
	return director.world.player


func _portal(stage_id: String) -> OverworldLayout.PortalSpec:
	return director.world.def.overworld.portal(stage_id)


func _put(at: Vector3) -> void:
	_player().global_position = at
	_player().velocity = Vector3.ZERO
	await wait_physics_frames(4)


## 広場のポータルの箱の中で F（ゲームと同じ入り方）。
func _enter_by_portal(stage_id: String) -> void:
	await _put(_portal(stage_id).position + Vector3(0.0, 0.1, 0.0))
	director.world.interact(null)
	await wait_physics_frames(5)


## 戻った直後: 自分（プレイヤー 1）はポータルの前の 1 番目の立ち位置で、ポータルに背を向けている。
func _assert_in_front_of(stage_id: String) -> void:
	assert_false(director.in_stage(), "back in the overworld")
	var portal := _portal(stage_id)
	var at := _player().global_position
	var spot := portal.returns[0]
	assert_lt(Vector2(at.x - spot.x, at.z - spot.z).length(), 0.3, "in front of %s" % stage_id)
	assert_eq(director.world.entrance_at(at), "", "not inside any portal")
	assert_almost(director.world.camera_rig.yaw, portal.return_yaw, 0.01, "looks away")
	assert_almost(_player().facing(), portal.return_yaw, 0.01, "the body faces away too")


func test_clearing_a_stage_returns_to_its_portal() -> void:
	await _enter_by_portal(StageCatalog.INTRO_ID)
	assert_eq(director.stage_id, StageCatalog.INTRO_ID)
	var goal := director.world.def.clear_condition.goal_area()
	await _put(Vector3(goal.get_center().x, goal.position.y + 0.2, goal.get_center().z))
	await wait_physics_frames(5)
	assert_ne(director.last_clear_text, "", "cleared")
	assert_true(director.in_stage(), "the celebration stays on the stage first")
	await wait_physics_frames(int(PartyDirector.RETURN_DELAY * 60.0) + 10)
	_assert_in_front_of(StageCatalog.INTRO_ID)


func test_leaving_from_the_menu_returns_to_its_portal() -> void:
	await _enter_by_portal(ROLLING)
	assert_eq(director.stage_id, ROLLING)
	director.request_leave_stage()
	await wait_physics_frames(5)
	_assert_in_front_of(ROLLING)


## 高い地方（霧の峰、高さ 4）のポータルでも、その前の地面に立つ（落ちない）。
func test_a_portal_on_a_raised_region_keeps_its_height() -> void:
	director.enter_stage(PEAK)
	await wait_physics_frames(5)
	director.request_leave_stage()
	await wait_physics_frames(60)
	_assert_in_front_of(PEAK)
	assert_almost(_player().global_position.y, 4.0, 0.2, "standing on the plateau")
	assert_true(_player().is_on_floor())


func test_no_instant_re_entry_right_after_returning() -> void:
	await _enter_by_portal(ROLLING)
	director.request_leave_stage()
	await wait_physics_frames(3)
	# すぐにポータルの箱に入って F を押しても、入り直さない
	await _enter_by_portal(ROLLING)
	assert_eq(director.stage_id, StageCatalog.HUB_ID, "the grace keeps the party outside")
	await wait_physics_frames(int(PortalReturn.GRACE * 60.0) + 5)
	director.world.interact(null)
	await wait_physics_frames(5)
	assert_eq(director.stage_id, ROLLING, "the portal works again after the grace")


## 広場の中で入り直す（ステージから来ていない）ときは、これまでどおり出現地点。
func test_reentering_the_hub_from_the_hub_uses_the_spawn() -> void:
	await _enter_by_portal(ROLLING)
	director.request_leave_stage()
	await wait_physics_frames(3)
	director.enter_stage(StageCatalog.HUB_ID)
	await wait_physics_frames(3)
	var spawn := director.world.spawn_for(RuleLedger.PLAYER_ID)
	assert_lt(_player().global_position.distance_to(spawn), 0.5, "the usual spawn point")


func test_the_next_session_starts_at_the_last_portal() -> void:
	director.enter_stage(StageCatalog.BELL_ID)
	await wait_physics_frames(3)
	assert_eq(
		ProgressStore.new().load_progress(PROFILE).progress.last_portal(), StageCatalog.BELL_ID
	)
	director.queue_free()
	await tree.process_frame
	director = _make_director()
	director.enter_stage(StageCatalog.HUB_ID)
	await wait_physics_frames(5)
	_assert_in_front_of(StageCatalog.BELL_ID)


func test_objectives_fill_as_the_bell_rings_the_animal_arrives_and_the_player_reaches_the_goal(
) -> void:
	director.enter_stage(ROLLING)
	await wait_physics_frames(5)
	var w := director.world
	assert_eq(
		StageObjectives.describe_all(director.objectives),
		PackedStringArray(["[ ] どうぶつを巣へ", "[ ] 鐘を鳴らす", "[ ] ゴールへ"])
	)
	w.bells_by_key["isle_bell"].ring()
	await wait_physics_frames(3)
	assert_eq(director.objectives[1].describe(), "[x] 鐘を鳴らす", "the bell rang")
	var kit: Creature = w.creatures[int(w.entity_ids["kit"])]
	kit.global_position = OpenIslandsW2.ROLLING_NEST.get_center()
	await wait_physics_frames(3)
	assert_eq(director.objectives[0].describe(), "[x] どうぶつを巣へ", "the kit is home")
	assert_eq(director.last_clear_text, "", "not cleared before the goal")
	var goal := w.def.clear_condition.goal_area()
	await _put(Vector3(goal.get_center().x, goal.position.y + 0.2, goal.get_center().z))
	await wait_physics_frames(3)
	assert_eq(director.objectives[2].describe(), "[x] ゴールへ", "at the goal")
	assert_ne(director.last_clear_text, "", "and that clears the stage")
