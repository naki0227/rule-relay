extends TestCase
## 2人のオンライン協力の進行（ホストと参加者を同じプロセスの中で別々の物理世界に作り、ENet でつなぐ）。
## ステージへ一緒に入る・死亡観戦・全員復活・途中参加は次の全員リセットで合流・クリアで両方に報酬。
## 部屋の組み立ては net_party.gd（3〜4人のテストと共通）。

const NetParty := preload("res://tests/integration/net_party.gd")
const A := RuleLedger.PLAYER_ID
const B := 2

var party: NetParty
var host: PartyDirector
var client: PartyDirector
var host_net: NetWorld
var client_net: NetWorld


func before_each() -> void:
	party = NetParty.new(self, 2, "zz_test_net")
	host = party.directors[0]
	client = party.directors[1]
	host_net = party.nets[0]
	client_net = party.nets[1]
	await party.open(StageCatalog.HUB_ID, 33000)


func after_each() -> void:
	await party.close()


## 参加者として入る（ハブを受け取ってから NetWorld を組み立てる）。
func _join() -> void:
	await party.join(1)
	await wait_physics_frames(10)


func _until(condition: Callable) -> void:
	await party.until(condition, "", 420)


func _go_intro() -> void:
	host.enter_stage(StageCatalog.INTRO_ID)
	await _until(func() -> bool: return client.stage_id == StageCatalog.INTRO_ID)
	await _until(
		func() -> bool: return client.world.ledger.ability_count(RuleAction.Kind.JUMP, B) == 1
	)
	await wait_physics_frames(10)


func _drop_client() -> void:
	client.world.player.global_position = Vector3(0.0, Tuning.FALL_LIMIT_Y - 3.0, 0.0)
	client.world.player.velocity = Vector3.ZERO


func test_party_enters_a_stage_together() -> void:
	await _join()
	await _go_intro()
	assert_eq(client.world.def.stage_id, StageCatalog.INTRO_ID)
	assert_eq(host.lifecycle.formal_participants(), PackedInt32Array([A, B]))
	assert_true(client.world.replica, "the client's stage follows the host")
	assert_true(host.world.avatars.has(B))
	# 参加者は自分の出現地点に立つ（1人目の出現地点に重ならない）
	var spawn := client.world.spawn_for(B)
	assert_lt(client.world.player.global_position.distance_to(spawn), 0.5, "B at its own spawn")


func test_death_spectates_and_revive_brings_back_without_rewinding() -> void:
	await _join()
	await _go_intro()
	await _until(func() -> bool: return host.world.avatars[B].global_position.y > -1.0)
	_drop_client()
	await _until(func() -> bool: return client.is_spectating())
	assert_eq(host.lifecycle.state_of(B), PartyLifecycle.State.DEAD_SPECTATING)
	var cp := host.world.def.checkpoints[0]
	host.world.player.global_position = cp + Vector3(0.0, 0.1, 0.0)
	await wait_physics_frames(5)
	host.world.interact(null)
	await _until(func() -> bool: return not client.is_spectating())
	await _until(func() -> bool: return client.world.player.global_position.distance_to(cp) < 3.0)
	assert_eq(host.lifecycle.reset_count(), 0, "revive is not a reset")


func test_mid_stage_joiner_waits_until_the_reset_vote() -> void:
	host.enter_stage(StageCatalog.INTRO_ID)
	await wait_physics_frames(5)
	await _join()
	assert_eq(client.stage_id, StageCatalog.INTRO_ID, "the joiner gets the current stage")
	assert_eq(host.lifecycle.state_of(B), PartyLifecycle.State.WAITING_SPECTATOR)
	await _until(func() -> bool: return client.is_spectating())
	host.request_vote()
	await _until(func() -> bool: return host.lifecycle.state_of(B) == PartyLifecycle.State.ACTIVE)
	assert_eq(host.lifecycle.headcount(), 2)
	await _until(
		func() -> bool: return client.world.ledger.ability_count(RuleAction.Kind.JUMP, B) == 1
	)
	await _until(func() -> bool: return not client.is_spectating())


func test_clear_gives_rewards_to_both_players() -> void:
	await _join()
	await _go_intro()
	# 岩棚の上のゴールの窪み（上面 y = 1）に2人とも置く（クリアは生きている全員がゴールに集まること）
	var in_goal := Vector3(0.5, float(StageCatalog.INTRO_GOAL_MAX.y + 1) + 0.1, -7.5)
	host.world.player.global_position = in_goal
	client.world.player.global_position = in_goal + Vector3(-1.0, 0.0, 0.0)
	await _until(func() -> bool: return host.last_clear_text != "")
	await _until(func() -> bool: return client.progress.has_cleared(StageCatalog.INTRO_ID))
	assert_true(host.progress.has_cleared(StageCatalog.INTRO_ID))
	assert_true(ProgressStore.new().exists(client.profile), "the client saved its own progress")
	await _until(func() -> bool: return client.stage_id == StageCatalog.HUB_ID)


## 参加者が部屋を出たら、その人の手元は島に残る（拾える）。消えないので、人数に合わせた島が解けなくならない。
func test_leaving_player_leaves_their_items_on_the_island() -> void:
	await _join()
	await _go_intro()
	await _until(func() -> bool: return host.world.avatars[B].global_position.y > -1.0)
	var before := host.world.ledger.world_vessels().size()
	client.leave_room()
	await _until(func() -> bool: return not host.world.ledger.players().has(B))
	var dropped := host.world.ledger.world_vessels()
	assert_gt(dropped.size(), before, "B's vessels are on the ground")
	for v in dropped:
		assert_gt(v.world_position.y, -0.6, "dropped on solid ground, not into the void")
	assert_eq(host.world.ledger.validate(), PackedStringArray(), "nothing was copied or lost")


## 2026-11-20 本人の判断（docs/adr/0011 決定 9）: クリアは「島の条件＋生きている全員がゴールに集まる」。
## 丘の上の旗で、1人だけゴールに入ってもクリアしない・2人とも入るとクリアすることを、
## 頂上の縁から窪みのゴールへ歩いて入る操作で確かめる。
func test_hill_top_clears_only_when_both_players_gather_at_the_goal() -> void:
	await _join()
	host.enter_stage(StageCatalog.HILL_ID)
	await _until(func() -> bool: return client.stage_id == StageCatalog.HILL_ID)
	await _until(
		func() -> bool: return client.world.ledger.ability_count(RuleAction.Kind.JUMP, B) == 1
	)
	await wait_physics_frames(10)
	# 東の小島の動物は巣に着いたことにする（投げて渡す道は test_open_islands。ここは「2 人がそろう」を見る）
	var critter := host.world.creatures[int(host.world.entity_ids["islet_critter"])] as Creature
	var nest := OpenIslands.HILL_NEST.get_center()
	critter.restore_state({"position": Vector3(nest.x, 0.0, nest.z), "velocity": Vector3.ZERO})
	var goal := host.world.def.clear_condition.goal_area()
	var center := goal.get_center()
	# 頂上の南の縁（ゴールの外）に2人を置く
	host.world.player.global_position = Vector3(0.5, 4.1, -4.5)
	client.world.player.global_position = Vector3(-0.5, 4.1, -4.5)
	await wait_physics_frames(20)
	assert_eq(host.last_clear_text, "", "nobody is in the goal yet")
	await _walk_into(host.world.player, Vector3(center.x + 0.6, goal.position.y + 0.1, center.z))
	assert_true(goal.has_point(host.world.player.global_position), "the host is in the goal")
	await wait_physics_frames(60)
	assert_eq(host.last_clear_text, "", "one of two players at the goal does not clear")
	await _walk_into(client.world.player, Vector3(center.x - 0.6, goal.position.y + 0.1, center.z))
	await _until(func() -> bool: return host.last_clear_text != "")
	assert_true(host.progress.has_cleared(StageCatalog.HILL_ID), "both at the goal clears")
	await _until(func() -> bool: return client.progress.has_cleared(StageCatalog.HILL_ID))


## お知らせの音（ui_notice、3回目の候補 T21）: 全員リセットの投票が始まったときと時間切れのときに、
## ホストと参加者の両方の画面で UI の音として鳴る。開いている投票への2票目では鳴らない。
func test_vote_start_and_expiry_play_the_notice_on_every_screen() -> void:
	await _join()
	await _go_intro()
	host.lifecycle.vote_time_limit = 2.0  # 時間切れを待つ時間を短くする（本番は 30 秒）
	var host_heard: Array[StringName] = []
	var client_heard: Array[StringName] = []
	host.world.sound_requested.connect(
		func(event: StringName, _at: Vector3, positional: bool) -> void:
			if not positional:
				host_heard.append(event)
	)
	client.world.sound_requested.connect(
		func(event: StringName, _at: Vector3, positional: bool) -> void:
			if not positional:
				client_heard.append(event)
	)
	client.request_vote()
	await _until(func() -> bool: return client_heard.has(&"ui_notice"))
	assert_eq(host_heard.count(&"ui_notice"), 1, "the host hears the vote start")
	client.request_vote()  # 同じ人の2票目（開いている投票）
	await wait_physics_frames(10)
	assert_eq(host_heard.count(&"ui_notice"), 1, "a vote on an open poll is not a new notice")
	await _until(func() -> bool: return not host.lifecycle.is_vote_open())
	await _until(func() -> bool: return client_heard.count(&"ui_notice") == 2)
	assert_eq(host_heard.count(&"ui_notice"), 2, "the host hears the expiry")
	assert_eq(host.lifecycle.reset_count(), 0, "one of two votes expired without a reset")


## アバターを target へ歩かせる（移動の入力と向きだけを与える。瞬間移動しない）。
func _walk_into(avatar: PlayerAvatar, target: Vector3) -> void:
	for i in 300:
		var flat := Vector3(
			target.x - avatar.global_position.x, 0.0, target.z - avatar.global_position.z
		)
		if flat.length() <= 0.3 and absf(avatar.global_position.y - target.y) < 0.5:
			break
		avatar.view_yaw = atan2(-flat.x, -flat.z)
		avatar.move_intent = Vector2(0.0, 1.0)
		await tree.physics_frame
	avatar.move_intent = Vector2.ZERO
	await wait_physics_frames(5)
