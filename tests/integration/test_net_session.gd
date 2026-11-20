extends TestCase
## 2つの部屋の端（ホストと参加者）を同じプロセスの中で ENet（127.0.0.1）でつなぎ、
## 能力の受け渡し・F 回収がホスト権威で両方の台帳にそろうことを確かめる（docs/adr/0006）。

const JUMP := RuleAction.Kind.JUMP
const REPEAT := TriggerMode.Kind.REPEAT
const A := RuleLedger.PLAYER_ID
const B := 2
const BLOCK := 10

var host_side: Node
var client_side: Node
var host: NetSession
var client: NetSession
var host_ledger: RuleLedger
var port: int


func before_each() -> void:
	host_side = _side("HostSide")
	client_side = _side("ClientSide")
	host = _session(host_side)
	client = _session(client_side)
	host_ledger = RuleLedger.new()
	host_ledger.register_entity(BLOCK, EntityKind.Kind.BLOCK)
	host_ledger.give_player_item(JUMP, false, 0, A)
	port = 27000 + randi() % 3000
	var server := ENetMultiplayerPeer.new()
	assert_eq(server.create_server(port, 4), OK, "server on port %d" % port)
	host.host(server, host_ledger, "host-key")
	await _connect_client(client, "bob-key")
	host_ledger.give_player_item(JUMP, false, 0, B)
	host.publish()
	await _until(func() -> bool: return client.generation == host.generation)


func after_each() -> void:
	host.close()
	client.close()
	tree.set_multiplayer(null, host_side.get_path())
	tree.set_multiplayer(null, client_side.get_path())
	host_side.queue_free()
	client_side.queue_free()
	await tree.process_frame


func _side(side_name: String) -> Node:
	var side := Node.new()
	side.name = side_name
	tree.root.add_child(side)
	tree.set_multiplayer(SceneMultiplayer.new(), side.get_path())
	return side


func _session(side: Node) -> NetSession:
	var session := NetSession.new()
	session.name = "Session"
	side.add_child(session)
	return session


func _connect_client(session: NetSession, key: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", port), OK)
	session.join(peer, key)
	await _until(func() -> bool: return session.player_id != -1 and session.generation > 0)


## 条件が真になるまで待つ（最大 5 秒）。
func _until(condition: Callable) -> void:
	for i in 300:
		if condition.call():
			return
		await tree.process_frame
	fail("timed out waiting for the network")


func _in_sync() -> void:
	await _until(func() -> bool: return client.generation == host.generation)
	assert_eq(client.ledger.snapshot(), host_ledger.snapshot(), "both ledgers agree")


func _b_jump_token() -> int:
	return host_ledger.hotbar_vessel(0, B).token_id


func test_client_joins_as_player_two_and_gets_the_state() -> void:
	assert_eq(client.player_id, B)
	assert_eq(client.ledger.players(), PackedInt32Array([A, B]))
	await _in_sync()


func test_client_gives_its_jump_to_the_host() -> void:
	client.send(PartyCommand.give(_b_jump_token(), A))
	await _until(func() -> bool: return host_ledger.ability_count(JUMP, A) == 2)
	assert_eq(host_ledger.ability_count(JUMP, B), 0)
	await _in_sync()
	assert_eq(client.ledger.ability_count(JUMP, A), 2, "client sees the result too")


func test_client_recalls_what_the_host_lent() -> void:
	var a_token := host_ledger.hotbar_vessel(0, A).token_id
	host.send(PartyCommand.lend(a_token, PackedInt32Array([BLOCK]), REPEAT))
	await _in_sync()
	client.send(PartyCommand.recall_entity(BLOCK))
	await _until(func() -> bool: return host_ledger.ability_count(JUMP, B) == 2)
	assert_false(host_ledger.player_can(JUMP, A), "F recall goes to the client, not back to A")
	await _in_sync()


func test_resent_request_is_applied_only_once() -> void:
	var command := PartyCommand.give(_b_jump_token(), A)
	var seq := client.send(command)
	await _until(func() -> bool: return host_ledger.ability_count(JUMP, A) == 2)
	host.send(PartyCommand.give(_b_jump_token(), B))
	await _until(func() -> bool: return host_ledger.ability_count(JUMP, B) == 1)
	var replies: Array[int] = []
	client.result_received.connect(func(s: int, _r: Dictionary) -> void: replies.append(s))
	client.resend(seq, command)
	await _until(func() -> bool: return replies.has(seq))
	assert_eq(host_ledger.ability_count(JUMP, A), 1, "the resend did not give it again")
	assert_eq(host_ledger.ability_count(JUMP, B), 1)


func test_refused_request_changes_nothing() -> void:
	var a_token := host_ledger.hotbar_vessel(0, A).token_id
	var results: Array[Dictionary] = []
	client.result_received.connect(func(_s: int, r: Dictionary) -> void: results.append(r))
	var before := host.generation
	client.send(PartyCommand.give(a_token, B))
	await _until(func() -> bool: return not results.is_empty())
	assert_eq(int(results[0]["result"]), PartyCommand.Result.REFUSED, "B cannot give A's jump")
	assert_eq(host.generation, before, "no new state")
	assert_true(host_ledger.player_can(JUMP, A))


func test_stale_state_is_ignored() -> void:
	var old := host_ledger.snapshot()
	var old_generation := host.generation
	client.send(PartyCommand.give(_b_jump_token(), A))
	await _until(func() -> bool: return host_ledger.ability_count(JUMP, A) == 2)
	await _in_sync()
	client._state(old_generation, old)
	assert_eq(client.ledger.ability_count(JUMP, A), 2, "older generation does not roll back")


func test_reconnect_keeps_player_and_tokens() -> void:
	client.send(PartyCommand.give(_b_jump_token(), A))
	await _until(func() -> bool: return host_ledger.ability_count(JUMP, A) == 2)
	await _in_sync()
	client.close()
	await _until(func() -> bool: return host.multiplayer.get_peers().is_empty())
	assert_true(host_ledger.players().has(B), "a disconnect is not a leave")
	var again := _session(_side("ClientSide2"))
	await _connect_client(again, "bob-key")
	assert_eq(again.player_id, B, "same key, same player")
	assert_eq(again.ledger.ability_count(JUMP, A), 2)
	again.close()
	tree.set_multiplayer(null, again.get_parent().get_path())
	again.get_parent().queue_free()
