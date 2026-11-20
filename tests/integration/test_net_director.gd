extends TestCase
## 2人のオンライン協力の進行（ホストと参加者を同じプロセスの中で別々の物理世界に作り、ENet でつなぐ）。
## ステージへ一緒に入る・死亡観戦・全員復活・途中参加は次の全員リセットで合流・クリアで両方に報酬。

const HOST_PROFILE := "zz_test_net_host"
const CLIENT_PROFILE := "zz_test_net_client"
const A := RuleLedger.PLAYER_ID
const B := 2

var host_side: Node
var client_side: Node
var host: PartyDirector
var client: PartyDirector
var host_net: NetWorld
var client_net: NetWorld
var port: int


func before_each() -> void:
	for p: String in [HOST_PROFILE, CLIENT_PROFILE]:
		ProgressStore.new().delete(p)
	host_side = _side("HostSide")
	client_side = _side("ClientSide")
	host = _director(host_side, HOST_PROFILE)
	client = _director(client_side, CLIENT_PROFILE)
	host_net = _net(host_side)
	client_net = _net(client_side)
	host.enter_stage(StageCatalog.HUB_ID)
	host_net.world = host.world
	port = 33000 + randi() % 3000
	var server := ENetMultiplayerPeer.new()
	assert_eq(server.create_server(port, 4), OK)
	host_net.start_host(server, "host-key")
	host.attach_net(host_net)
	await wait_physics_frames(3)


func after_each() -> void:
	host_net.close()
	client_net.close()
	for side: Node in [host_side, client_side]:
		tree.set_multiplayer(null, side.get_path())
		side.queue_free()
	await tree.process_frame
	for p: String in [HOST_PROFILE, CLIENT_PROFILE]:
		ProgressStore.new().delete(p)


func _side(side_name: String) -> Node:
	var side := Node.new()
	side.name = side_name
	tree.root.add_child(side)
	tree.set_multiplayer(SceneMultiplayer.new(), side.get_path())
	return side


## 物理の世界を分けるため、進行役（とその下のステージ）は専用の SubViewport に入れる。
func _director(side: Node, profile: String) -> PartyDirector:
	var viewport := SubViewport.new()
	viewport.name = "View"
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	side.add_child(viewport)
	var director := PartyDirector.new()
	director.profile = profile
	viewport.add_child(director)
	return director


func _net(side: Node) -> NetWorld:
	var net := NetWorld.new()
	side.add_child(net)
	return net


## 参加者として入る（ハブを受け取ってから NetWorld を組み立てる）。
func _join() -> void:
	client.prepare_client()
	client_net.world = client.world
	client.attach_net(client_net)
	var peer := ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", port), OK)
	client_net.start_client(peer, "bob-key")
	await _until(func() -> bool: return client.world != null and client.world.player.player_id == B)
	await wait_physics_frames(10)


func _until(condition: Callable) -> void:
	for i in 420:
		if condition.call():
			return
		await tree.physics_frame
	fail("timed out")


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
	var ledge_top := Vector3(0.5, float(StageCatalog.INTRO_LEDGE_MAX.y + 1) + 0.1, -7.5)
	host.world.player.global_position = ledge_top
	await _until(func() -> bool: return host.last_clear_text != "")
	await _until(func() -> bool: return client.progress.has_cleared(StageCatalog.INTRO_ID))
	assert_true(host.progress.has_cleared(StageCatalog.INTRO_ID))
	assert_true(ProgressStore.new().exists(CLIENT_PROFILE), "the client saved its own progress")
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
