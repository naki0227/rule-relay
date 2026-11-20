extends TestCase
## 1人用の進行（ハブ → 入口 → 導入ステージ → 落ちる → 自動で戻る → ジャンプを貸してクリア →
## 報酬を保存 → ハブへ戻る）。オンラインでも同じ PartyDirector を使う（docs/adr/0010）。

const PROFILE := "zz_test_director"
const JUMP := RuleAction.Kind.JUMP
const JUMP_SLOT := 4

var director: PartyDirector


func before_each() -> void:
	ProgressStore.new().delete(PROFILE)
	director = PartyDirector.new()
	director.profile = PROFILE
	tree.root.add_child(director)
	director.enter_stage(StageCatalog.HUB_ID)
	await wait_physics_frames(5)


func after_each() -> void:
	director.queue_free()
	await tree.process_frame
	ProgressStore.new().delete(PROFILE)


func _player() -> PlayerAvatar:
	return director.world.player


func _put(at: Vector3) -> void:
	_player().global_position = at
	_player().velocity = Vector3.ZERO
	await wait_physics_frames(4)


func _enter_intro() -> void:
	var entrance: StageDef.EntranceSpec = director.world.def.entrances[0]
	assert_eq(entrance.stage_id, StageCatalog.INTRO_ID)
	await _put(entrance.position + Vector3(0.0, 0.1, 0.0))
	director.world.interact(null)
	await wait_physics_frames(5)


func test_hub_entrance_starts_the_stage() -> void:
	assert_false(director.in_stage())
	await _enter_intro()
	assert_true(director.in_stage())
	assert_eq(director.stage_id, StageCatalog.INTRO_ID)
	assert_true(director.world.ledger.player_can(JUMP), "intro starts with jump")
	assert_eq(director.lifecycle.formal_participants(), PackedInt32Array([1]))


func test_solo_fall_resets_to_the_start() -> void:
	await _enter_intro()
	await _put(Vector3(0.0, Tuning.FALL_LIMIT_Y - 2.0, 0.0))
	await wait_physics_frames(5)
	assert_eq(director.lifecycle.reset_count(), 1, "solo death resets automatically")
	assert_false(director.is_spectating(), "solo is never stuck spectating")
	assert_gt(_player().global_position.y, -1.0, "back on the island")


func test_checkpoint_becomes_shared_and_is_used_for_resets() -> void:
	await _enter_intro()
	await _put(director.world.def.checkpoints[0] + Vector3(0.0, 0.1, 0.0))
	assert_eq(director.lifecycle.latest_checkpoint(), "cp0")
	await _put(Vector3(0.0, Tuning.FALL_LIMIT_Y - 2.0, 0.0))
	await wait_physics_frames(5)
	var cp := director.world.def.checkpoints[0]
	assert_lt(_player().global_position.distance_to(cp), 2.5, "reset to the checkpoint")


func test_vote_reset_in_solo_passes_with_one_vote() -> void:
	await _enter_intro()
	director.request_vote()
	await wait_physics_frames(3)
	assert_eq(director.lifecycle.reset_count(), 1)


func test_lending_jump_to_the_lift_clears_and_saves_rewards() -> void:
	await _enter_intro()
	var w := director.world
	var lift := w.blocks[int(w.entity_ids["lift"])]
	await _put(lift.global_position + Vector3(0.0, 0.6, 1.4))
	w.select_slot(JUMP_SLOT)
	assert_true(w.set_lend_mode(TriggerMode.Kind.REPEAT))
	assert_eq(w.lend_to(lift, false), RuleLedger.LendResult.OK)
	assert_false(w.ledger.player_can(JUMP), "the player gave up jump")
	await _put(lift.global_position + Vector3(0.0, 0.6, 0.0))
	for i in 240:
		if director.last_clear_text != "":
			break
		# ブロックが跳んだ頂点で岩棚の上へ歩く
		var above_ledge := _player().global_position.y > 2.05
		_player().move_intent = Vector2(0.0, 1.0) if above_ledge else Vector2.ZERO
		_player().view_yaw = 0.0
		await tree.physics_frame
	_player().move_intent = Vector2.ZERO
	assert_ne(director.last_clear_text, "", "cleared by reaching the ledge")
	assert_true(director.progress.has_cleared(StageCatalog.INTRO_ID), "reward applied")
	assert_true(ProgressStore.new().exists(PROFILE), "progress saved")
	await wait_physics_frames(int(PartyDirector.RETURN_DELAY * 60.0) + 10)
	assert_false(director.in_stage(), "back to the hub")


## 製品版の入口（all_stages_open = false）: 最初のステージは開いていて、次は前をクリアするまで閉じている。
func test_locked_entrances_open_in_order_of_target_time() -> void:
	director.all_stages_open = false
	var second: StageDef.EntranceSpec = director.world.def.entrances[1]
	await _put(second.position + Vector3(0.0, 0.1, 0.0))
	director.world.interact(null)
	await wait_physics_frames(5)
	assert_eq(director.stage_id, StageCatalog.HUB_ID, "the second stage is locked")
	await _enter_intro()
	assert_eq(director.stage_id, StageCatalog.INTRO_ID, "the first stage is always open")


func test_room_option_reaches_every_stage_ledger() -> void:
	assert_false(director.world.ledger.allow_prohibition_to_player, "off by default")
	director.allow_prohibition_to_player = true
	await _enter_intro()
	assert_true(director.world.ledger.allow_prohibition_to_player, "the new stage keeps the option")
