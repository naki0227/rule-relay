extends TestCase
## 島を2つ（ホストと参加者）同じプロセスの中で別々の物理世界に作り、ENet（127.0.0.1）でつなぐ。
## 参加者の画面での操作（ブロックへ付与・F 回収・仲間へ渡す・単発のキー）がホストで実行され、
## 両方の台帳と画面にそろうことを確かめる（docs/adr/0006）。

const JUMP := RuleAction.Kind.JUMP
const JUMP_SLOT := 4
const A := RuleLedger.PLAYER_ID
const B := 2

var host_side: Node
var client_side: Node
var host_world: PrototypeIsland
var client_world: PrototypeIsland
var host_net: NetWorld
var client_net: NetWorld


func before_each() -> void:
	host_side = _side("HostSide")
	client_side = _side("ClientSide")
	host_world = _island(host_side)
	client_world = _island(client_side)
	host_net = _net(host_side, host_world)
	client_net = _net(client_side, client_world)
	host_net.give_starting_items = host_world.give_starting_items
	await wait_physics_frames(5)
	var port := 30000 + randi() % 3000
	var server := ENetMultiplayerPeer.new()
	assert_eq(server.create_server(port, 4), OK)
	host_net.start_host(server, "host-key")
	var peer := ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", port), OK)
	client_net.start_client(peer, "bob-key")
	await _until(func() -> bool: return client_world.player.player_id == B)
	await _until(func() -> bool: return client_world.ledger.hotbar_vessel(JUMP_SLOT, B) != null)
	await wait_physics_frames(10)


func after_each() -> void:
	host_net.close()
	client_net.close()
	for side: Node in [host_side, client_side]:
		tree.set_multiplayer(null, side.get_path())
		side.queue_free()
	await tree.process_frame


func _side(side_name: String) -> Node:
	var side := Node.new()
	side.name = side_name
	tree.root.add_child(side)
	tree.set_multiplayer(SceneMultiplayer.new(), side.get_path())
	return side


## 物理の世界を分けるため、島はそれぞれ専用の SubViewport（own_world_3d）に入れる。
func _island(side: Node) -> PrototypeIsland:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	side.add_child(viewport)
	var island := PrototypeIsland.new()
	viewport.add_child(island)
	return island


func _net(side: Node, island: GameWorld) -> NetWorld:
	var net := NetWorld.new()
	net.world = island
	side.add_child(net)
	return net


## 条件が真になるまで待つ（最大 6 秒）。
func _until(condition: Callable) -> void:
	for i in 360:
		if condition.call():
			return
		await tree.physics_frame
	fail("timed out waiting for the network")


## 参加者のアバターを、ホストの島の中の位置へ置く（ホストの画面にも届くまで待つ）。
func _place_client(at: Vector3) -> void:
	client_world.player.global_position = at
	client_world.player.velocity = Vector3.ZERO
	await _until(func() -> bool: return host_world.avatars[B].global_position.distance_to(at) < 0.3)


func _near(block: RuleBlock) -> Vector3:
	return block.global_position + Vector3(-1.6, -0.5, 1.0)


func test_both_sides_see_each_other() -> void:
	assert_true(host_world.avatars.has(B), "host shows the client's avatar")
	assert_true(client_world.avatars.has(A), "client shows the host's avatar")
	assert_eq(client_world.ledger.players(), PackedInt32Array([A, B]))
	assert_eq(host_world.ledger.ability_count(JUMP, B), 1, "the client got starting items")
	assert_true(client_world.replica)
	assert_true(client_world.bouncer.remote, "client blocks follow the host")


func test_client_movement_reaches_the_host() -> void:
	var target := client_world.player.global_position + Vector3(1.0, 0.0, 0.5)
	await _place_client(target)
	assert_lt(host_world.avatars[B].global_position.distance_to(target), 0.3)


func test_host_block_moves_on_the_client_screen() -> void:
	var to := host_world.bouncer.global_position + Vector3(0.0, 2.0, 0.0)
	host_world.bouncer.teleport(to, 0.0)
	await _until(func() -> bool: return client_world.bouncer.global_position.distance_to(to) < 0.6)


func test_client_lends_to_a_block_through_the_host() -> void:
	var block := client_world.row[0]
	await _place_client(_near(block))
	client_world.select_slot(JUMP_SLOT)
	assert_true(client_world.set_lend_mode(TriggerMode.Kind.REPEAT))
	client_world.lend_to(block, false)
	var host_block := host_world.row[0]
	await _until(func() -> bool: return host_world.ledger.can_initiate(host_block.entity_id, JUMP))
	var t := host_world.ledger.tokens_on(host_block.entity_id)[0]
	assert_eq(t.lender_id, B, "the client is the lender")
	await _until(func() -> bool: return client_world.ledger.can_initiate(block.entity_id, JUMP))
	assert_false(client_world.player.ledger.player_can(JUMP, B), "the client lost its jump")


func test_client_recalls_what_the_host_lent() -> void:
	var host_block := host_world.row[0]
	host_world.player.global_position = _near(host_block)
	await wait_physics_frames(3)
	host_world.select_slot(JUMP_SLOT)
	host_world.set_lend_mode(TriggerMode.Kind.REPEAT)
	assert_eq(host_world.lend_to(host_block, false), RuleLedger.LendResult.OK)
	await _place_client(_near(client_world.row[0]))
	await _until(
		func() -> bool: return client_world.ledger.can_initiate(host_block.entity_id, JUMP)
	)
	client_world.interact(client_world.row[0])
	await _until(func() -> bool: return host_world.ledger.ability_count(JUMP, B) == 2)
	assert_false(host_world.ledger.player_can(JUMP, A), "F recall goes to the client")
	await _until(func() -> bool: return client_world.ledger.ability_count(JUMP, B) == 2)


func test_client_gives_its_jump_to_the_host() -> void:
	await _place_client(host_world.player.global_position + Vector3(1.0, 0.0, 0.0))
	await _until(func() -> bool: return client_world.avatars[A].global_position.y > -5.0)
	client_world.select_slot(JUMP_SLOT)
	client_world.lend_to(client_world.avatars[A], false)
	await _until(func() -> bool: return host_world.ledger.ability_count(JUMP, A) == 2)
	assert_eq(host_world.ledger.ability_count(JUMP, B), 0)
	assert_eq(host_world.player.jump_height(), Tuning.PLAYER_JUMP_HEIGHT * 2.0, "jump x2")


func test_client_single_shot_fires_on_the_host_and_returns() -> void:
	var block := client_world.row[0]
	await _place_client(_near(block))
	client_world.select_slot(JUMP_SLOT)
	client_world.set_lend_mode(TriggerMode.Kind.SINGLE_SHOT)
	client_world.lend_to(block, false)
	var host_block := host_world.row[0]
	await _until(func() -> bool: return host_world.ledger.can_initiate(host_block.entity_id, JUMP))
	await _until(func() -> bool: return client_world.ledger.can_initiate(block.entity_id, JUMP))
	var start_y := host_block.global_position.y
	client_world.press_action(JUMP)
	await _until(func() -> bool: return host_block.global_position.y > start_y + 0.5)
	await _until(func() -> bool: return host_world.ledger.ability_count(JUMP, B) == 1)
	assert_false(host_world.ledger.can_initiate(host_block.entity_id, JUMP), "returned to B")


func test_client_lends_to_a_terrain_cell_and_sees_it_become_a_block() -> void:
	var cell := Vector3i(-2, -1, 2)
	assert_true(host_world.terrain.has_cell(cell), "the island has this terrain cell")
	await _place_client(Vector3(cell) + Vector3(0.5, 1.0, 1.8))
	client_world.select_slot(JUMP_SLOT)
	client_world.set_lend_mode(TriggerMode.Kind.REPEAT)
	client_world.lend_to(client_world.terrain_target(cell), false)
	await _until(func() -> bool: return host_world.promoted.has(cell))
	var id := host_world.promoted[cell]
	assert_true(host_world.ledger.can_initiate(id, JUMP), "the cell got the client's jump")
	await _until(func() -> bool: return client_world.promoted.has(cell))
	assert_true(client_world.blocks[id].remote, "the client's copy follows the host")
