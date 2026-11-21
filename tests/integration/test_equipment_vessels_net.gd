extends TestCase
## 2人（ホストと参加者）で装備の入れ物と持ち物の画面（docs/adr/0018）: 参加者がホットバーのブーツから渡しても
## 入れ物は参加者の枠に残り、F で入れ物へ戻り、身につけるとホストの台帳でも効く。持ち物の画面の
## 「クリックで持ち上げて置く」も、参加者の依頼としてホストで適用され、入れ替えが両方にそろう。

const BOOTS := RuleAction.Kind.HIGH_JUMP
const A := RuleLedger.PLAYER_ID
const B := 2
const JUMP_SLOT := 4

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
	var port := 33000 + randi() % 3000
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


func _until(condition: Callable) -> void:
	for i in 360:
		if condition.call():
			return
		await tree.physics_frame
	fail("timed out waiting for the network")


func _place_client(at: Vector3) -> void:
	client_world.player.global_position = at
	client_world.player.velocity = Vector3.ZERO
	await _until(func() -> bool: return host_world.avatars[B].global_position.distance_to(at) < 0.3)


## ホストの台帳で、参加者にジャンプブーツを1つ持たせる（ホットバーの slot）。
func _give_client_boots(slot: int) -> int:
	var boots := host_world.ledger.place_in_world(
		BOOTS, false, Vector3.ZERO, RuleVessel.Part.FEET, "ジャンプブーツ"
	)
	host_world.ledger.pickup(boots.id, B)
	host_world.ledger.move_to_hotbar(boots.id, slot)
	await _until(func() -> bool: return client_world.ledger.hotbar_vessel(slot, B) != null)
	return boots.id


func test_client_lends_from_hotbar_boots_and_recalls_into_the_shell() -> void:
	var boots_id := await _give_client_boots(7)
	var block := client_world.row[0]
	var host_block := host_world.row[0]
	await _place_client(block.global_position + Vector3(-1.6, -0.5, 1.0))
	client_world.select_slot(7)
	client_world.lend_to(block, false)
	await _until(
		func() -> bool: return host_world.ledger.entity_has_ability(host_block.entity_id, BOOTS)
	)
	assert_eq(host_world.ledger.hotbar_vessel(7, B).id, boots_id, "the shell stays in B's slot")
	await _until(
		func() -> bool: return client_world.ledger.entity_has_ability(block.entity_id, BOOTS)
	)
	var shown := InventoryQuery.describe(client_world.ledger, client_world.ledger.vessel(boots_id))
	assert_true(shown.state_text.begins_with("空"), "the client sees an empty shell")
	assert_true(client_world.ledger_actions.equip(boots_id), "wear the empty shell")
	await _until(
		func() -> bool: return host_world.ledger.equipped_vessel(RuleVessel.Part.FEET, B) != null
	)
	assert_false(host_world.ledger.player_can(BOOTS, B), "empty: no effect")
	client_world.interact(block)
	await _until(func() -> bool: return host_world.ledger.player_can(BOOTS, B))
	assert_true(host_world.ledger.token(host_world.ledger.vessel(boots_id).token_id).is_in_vessel())
	await _until(func() -> bool: return client_world.ledger.player_can(BOOTS, B))
	assert_true(host_world.ledger.validate().is_empty())


func test_client_worn_boots_cannot_be_lent() -> void:
	var boots_id := await _give_client_boots(7)
	var v := host_world.ledger.vessel(boots_id)
	assert_true(client_world.ledger_actions.equip(boots_id))
	await _until(func() -> bool: return host_world.ledger.player_can(BOOTS, B))
	var cmd := PartyCommand.lend(
		v.token_id, PackedInt32Array([host_world.row[0].entity_id]), TriggerMode.Kind.NONE
	)
	var out := PartyCommand.apply(host_world.ledger, B, cmd)
	assert_eq(int(out["detail"]), RuleLedger.LendResult.EQUIPPED_CANNOT_LEND)
	assert_true(host_world.ledger.player_can(BOOTS, B), "still worn and working")


func test_client_moves_items_with_click_and_place() -> void:
	var stored := host_world.ledger.give_player_item(RuleAction.Kind.CLIMB, false, -1, B)
	var jump_id := host_world.ledger.hotbar_vessel(JUMP_SLOT, B).id
	await _until(func() -> bool: return client_world.ledger.vessel(stored.id) != null)
	var panel := InventoryPanel.new()
	panel.ledger = client_world.ledger
	panel.actions = client_world.ledger_actions
	panel.player_id = B
	client_side.add_child(panel)
	panel.open()
	assert_true(panel.click_bag(stored.id), "picked from the bag")
	assert_true(panel.click_hotbar(JUMP_SLOT), "placed on the jump")
	await _until(
		func() -> bool:
			return (
				host_world.ledger.hotbar_vessel(JUMP_SLOT, B) != null
				and host_world.ledger.hotbar_vessel(JUMP_SLOT, B).id == stored.id
			)
	)
	var jump := host_world.ledger.vessel(jump_id)
	assert_eq(jump.location, RuleVessel.Location.INVENTORY, "the jump swapped into B's bag")
	await _until(
		func() -> bool:
			return client_world.ledger.vessel(jump_id).location == RuleVessel.Location.INVENTORY
	)
	var was_first := host_world.ledger.hotbar_vessel(0, B)
	panel.hover(jump_id)
	panel.number_key(0)
	await _until(func() -> bool: return host_world.ledger.vessel(jump_id).slot == 0)
	assert_eq(host_world.ledger.hotbar_vessel(0, B).id, jump_id, "hover + 1 from the client")
	if was_first != null:
		assert_eq(was_first.location, RuleVessel.Location.INVENTORY, "slot 1's item swapped out")
	assert_true(host_world.ledger.validate().is_empty())
	panel.queue_free()
