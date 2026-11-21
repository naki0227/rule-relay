extends "res://tests/integration/island_playthrough.gd"
## 広場（オーバーワールド）: ポータルでステージへ入る・閉じた地方がクリアで開く・願いをかなえた生き物が住む・
## 広場の能力にクリアで開いた能力が入る・小さな仕掛けを歩いて解ける（docs/adr/0013）。
## 2 人の広場は test_overworld_net.gd。

const LIFT := "ow_lift"


## そのステージをクリアしたことにする（ホストが配る報酬イベントと同じ形で、自分の進行に入れる）。
func _clear(stage_id: String) -> void:
	var rewards := StageRunRewards.new(stage_id, stage_id + "#overworld-test")
	var statuses: Dictionary[String, int] = {"1": StageRunRewards.Status.ACTIVE}
	rewards.settle(statuses, RunMetrics.new(), 1_790_000_000)
	var result := director.progress.apply_reward_event(rewards.event_for("1"), director.table)
	assert_eq(result.outcome, PlayerProgress.Outcome.APPLIED, "cleared %s" % stage_id)


func _campaign() -> void:
	director.all_stages_open = false
	director.all_regions_open = false


func _dressing() -> Node:
	return w.get_node("OverworldDressing")


func _cell_top(x: int, z: int) -> float:
	var space := w.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(x + 0.5, 20.0, z + 0.5), Vector3(x + 0.5, -20.0, z + 0.5)
	)
	query.collision_mask = Tuning.LAYER_TERRAIN
	var hit := space.intersect_ray(query)
	return (hit["position"] as Vector3).y if not hit.is_empty() else -100.0


func test_a_portal_enters_its_stage() -> void:
	await _enter(StageCatalog.HUB_ID)
	var portal := w.def.overworld.portal(StageCatalog.BELL_ID)
	assert_ne(
		_dressing().get_node_or_null("Portal_%s" % StageCatalog.BELL_ID), null, "portal model"
	)
	_me().global_position = portal.position + Vector3(0.0, 0.1, 0.0)
	await wait_physics_frames(4)
	assert_eq(w.entrance_at(_me().global_position), StageCatalog.BELL_ID)
	w.interact(null)
	await wait_physics_frames(5)
	assert_eq(director.stage_id, StageCatalog.BELL_ID, "entered the stage behind the portal")


func test_a_locked_region_opens_after_the_required_clear() -> void:
	_campaign()
	await _enter(StageCatalog.HUB_ID)
	assert_lt(_cell_top(25, 0), -50.0, "no bridge over the gap to the bell vale")
	var portal := w.def.overworld.portal(StageCatalog.BELL_ID)
	assert_false(portal.open)
	_me().global_position = portal.position + Vector3(0.0, 0.1, 0.0)
	await wait_physics_frames(4)
	w.interact(null)
	await wait_physics_frames(5)
	assert_eq(director.stage_id, StageCatalog.HUB_ID, "the locked portal does not open")
	_clear(StageCatalog.QUARRY_ID)
	await _enter(StageCatalog.HUB_ID)
	assert_almost(_cell_top(25, 0), 0.0, 0.05, "the bridge appeared")
	assert_true(w.def.overworld.portal(StageCatalog.BELL_ID).open, "the first portal there opens")
	_me().global_position = Vector3(20.5, 0.1, 0.5)
	assert_true(await _walk_to(Vector3(31.5, 0.0, 0.5)), "walked across the new bridge")


func test_a_rescued_creature_moves_in_after_the_clear() -> void:
	await _enter(StageCatalog.HUB_ID)
	assert_eq(_dressing().find_children("Resident_*", "", false, false).size(), 0)
	_clear(StageCatalog.HILL_ID)
	await _enter(StageCatalog.HUB_ID)
	var resident := _dressing().get_node_or_null("Resident_%s" % StageCatalog.HILL_ID)
	assert_ne(resident, null, "the hill top's creature lives in the overworld")
	var home := w.def.overworld.resident(StageCatalog.HILL_ID).home
	assert_ne(resident.find_children("*", "Skeleton3D", true, false).size(), 0, "a rigged model")
	assert_eq((resident as OverworldResident).rig.current, RigAnimator.HAPPY, "happy to arrive")
	await wait_physics_frames(400)
	var pos := (resident as Node3D).global_position
	assert_lt(Vector2(pos.x - home.x, pos.z - home.z).length(), 1.8, "wanders near home")
	var building := _dressing().find_children("Building_*", "", true, false)
	assert_eq(building.size(), 1, "a building went up")
	var mark := _dressing().get_node("Portal_%s" % StageCatalog.HILL_ID).find_child(
		"ClearedMark", true, false
	)
	assert_true((mark as Node3D).visible, "the cleared portal shows its mark")


func test_overworld_loadout_has_unlocked_abilities() -> void:
	await _enter(StageCatalog.HUB_ID)
	assert_eq(_slot_of(THROW), -1, "no throw before the bell valley")
	assert_false(w.ledger.player_can(RuleAction.Kind.HIGH_JUMP))
	_clear(StageCatalog.BELL_ID)
	_clear(StageCatalog.HILL_ID)
	await _enter(StageCatalog.HUB_ID)
	assert_ne(_slot_of(THROW), -1, "throw is on the hotbar")
	assert_true(w.ledger.player_can(RuleAction.Kind.HIGH_JUMP), "boots are worn in the overworld")
	assert_ne(_slot_of(JUMP), -1, "moves and jump stay")


## 草原の西の高台: 窪みのブロックにジャンプを貸して乗り、上の見晴らしの発見に着く（歩いて解く）。
func test_the_ledge_puzzle_is_solved_by_walking() -> void:
	await _enter(StageCatalog.HUB_ID)
	var lift := _block(LIFT)
	var top := Vector3(-15.5, 2.0, 8.5)
	assert_false(await _try_walk_to(top, 0.4, 300), "a plain jump does not reach the ledge")
	await _lift_up(LIFT, lift.global_position + Vector3(1.4, 0.5, 0.0), top)
	await _walk_to(top, 0.4, 240)
	await wait_physics_frames(3)
	assert_true(w.found_secrets.has("ledge"), "found the lookout on the ledge")
	assert_true(w.ledger.player_can(JUMP), "the single shot came back")


## 鐘の扉: 鐘を鳴らすと、扉のブロックが信号の W で北のくぼみへすべり、庭に入れる。
func test_the_bell_door_opens_when_the_bell_rings() -> void:
	await _enter(StageCatalog.HUB_ID)
	var door := _block("ow_bell_door")
	var start := door.global_position
	await _walk_to(Overworld.BELL_AT + Vector3(-1.2, 0.0, 0.8), 0.4)
	w.interact(w.bells_by_key["ow_bell"])
	await wait_physics_frames(240)
	assert_lt(door.global_position.z, start.z - 0.9, "the door slid into its niche")
	# 扉のマス（z -13〜-12）の真ん中の列を東へ歩いて、庭の中（寄り道の門の前）へ
	await _walk_to(Vector3(13.5, 0.0, -12.5), 0.3)
	var inside := Vector3(18.5, 0.0, -12.5)
	assert_true(await _walk_to(inside, 0.5, 600), "walked into the yard")
	assert_true(w.found_secrets.has("o1"), "found the gate of the optional world")
