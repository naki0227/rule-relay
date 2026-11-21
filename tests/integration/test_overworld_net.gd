extends TestCase
## 2 人の広場（オーバーワールド）: 協力中の広場はホストの進行で決まる（参加者の自分の進行ではない）。
## 参加者はホストと同じ地形・ポータル・住む生き物を見て、自分の出現地点に立ち、ホストがポータルに入ると
## 一緒にステージへ行く。部屋の組み立ては net_party.gd（docs/adr/0013）。

const NetParty := preload("res://tests/integration/net_party.gd")

var party: NetParty


func before_each() -> void:
	party = NetParty.new(self, 2, "zz_test_overworld_net")


func after_each() -> void:
	await party.close()


func _clear_on_host(stage_id: String) -> void:
	var rewards := StageRunRewards.new(stage_id, stage_id + "#net-test")
	var statuses: Dictionary[String, int] = {"1": StageRunRewards.Status.ACTIVE}
	rewards.settle(statuses, RunMetrics.new(), 1_790_000_000)
	party.host().progress.apply_reward_event(rewards.event_for("1"), party.host().table)


func _has_bridge(def: StageDef) -> bool:
	for box: Array in def.terrain_boxes:
		var lo := box[0] as Vector3i
		var hi := box[1] as Vector3i
		if lo.x <= 25 and hi.x >= 25 and lo.z <= 0 and hi.z >= 0:
			return true
	return false


func test_two_players_share_the_hosts_overworld_and_enter_a_portal_together() -> void:
	party.host().all_stages_open = false
	party.host().all_regions_open = false
	_clear_on_host(StageCatalog.QUARRY_ID)
	await party.open(StageCatalog.HUB_ID, 38000)
	await party.join_all()
	var client := party.directors[1]
	var seen := client.world.def
	assert_false(client.progress.has_cleared(StageCatalog.QUARRY_ID), "the client never cleared it")
	assert_true(_has_bridge(seen), "the client sees the bridge opened by the host's clear")
	assert_true(seen.overworld.portal(StageCatalog.BELL_ID).open, "same open portals as the host")
	assert_false(seen.overworld.portal(StageCatalog.THREE_BELLS_ID).open)
	assert_ne(seen.overworld.resident(StageCatalog.QUARRY_ID), null, "same residents as the host")
	var spawn := client.world.spawn_for(party.pid(1))
	assert_lt(client.world.player.global_position.distance_to(spawn), 1.0, "own spawn point")
	# ホストが導入のポータルに入ると、2 人とも導入へ
	var host_world := party.world(0)
	var intro := host_world.def.overworld.portal(StageCatalog.INTRO_ID)
	host_world.player.global_position = intro.position + Vector3(0.0, 0.1, 0.0)
	await wait_physics_frames(4)
	host_world.interact(null)
	await party.until(
		func() -> bool: return client.stage_id == StageCatalog.INTRO_ID, "the client follows"
	)
	assert_eq(party.host().lifecycle.formal_participants().size(), 2)
