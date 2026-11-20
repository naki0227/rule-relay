extends TestCase
## ホスト移譲: ホスト A・参加者 B・C（同じプロセスの中で別々の通信と物理の世界）。A が落ちると、
## 残った中で ID がいちばん小さい B が新しいホストになり、C は B へつなぎ直す。
## 能力の貸し借り・ステージ・チームの状態は、A が最後に配った状態から続く（複製しない）。

const JUMP := RuleAction.Kind.JUMP
const JUMP_SLOT := 4

var sides: Array[Node] = []
var directors: Array[PartyDirector] = []
var nets: Array[NetWorld] = []
var migrations: Array[HostMigration] = []
var port: int


func before_each() -> void:
	sides.clear()
	directors.clear()
	nets.clear()
	migrations.clear()
	port = 38000 + randi() % 2000
	for i in 3:
		_make_side(i)
	var host := directors[0]
	host.enter_stage(StageCatalog.INTRO_ID)
	nets[0].world = host.world
	var server := ENetMultiplayerPeer.new()
	assert_eq(server.create_server(port, 4), OK)
	nets[0].start_host(server, "key-a")
	host.attach_net(nets[0])
	for i: int in [1, 2]:
		await _join(i)
	await _until(func() -> bool: return host.world.ledger.players().size() == 3)
	host.request_vote()  # 途中参加の B・C を合流させる
	await _until(func() -> bool: return host.lifecycle.formal_participants().size() == 3)
	await wait_physics_frames(20)


func after_each() -> void:
	for migration in migrations:
		migration.net = null
	for net in nets:
		net.close()
	for side in sides:
		tree.set_multiplayer(null, side.get_path())
		side.queue_free()
	await tree.process_frame
	for i in 3:
		ProgressStore.new().delete("zz_test_migration_%d" % i)


func _make_side(i: int) -> void:
	var side := Node.new()
	side.name = "Side%d" % i
	tree.root.add_child(side)
	tree.set_multiplayer(SceneMultiplayer.new(), side.get_path())
	var view := SubViewport.new()
	view.name = "View"
	view.own_world_3d = true
	view.size = Vector2i(16, 16)
	side.add_child(view)
	var director := PartyDirector.new()
	director.profile = "zz_test_migration_%d" % i
	view.add_child(director)
	var net := NetWorld.new()
	side.add_child(net)
	var migration := HostMigration.new()
	migration.director = director
	migration.net = net
	migration.port = port
	migration.session_key = "key-%s" % ["a", "b", "c"][i]
	side.add_child(migration)
	sides.append(side)
	directors.append(director)
	nets.append(net)
	migrations.append(migration)


func _join(i: int) -> void:
	directors[i].prepare_client()
	nets[i].world = directors[i].world
	directors[i].attach_net(nets[i])
	var peer := ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", port), OK)
	nets[i].start_client(peer, migrations[i].session_key)
	migrations[i].watch()
	await _until(func() -> bool: return directors[i].world.player.player_id == i + 1)
	await _until(func() -> bool: return directors[i].stage_id == StageCatalog.INTRO_ID)


func _until(condition: Callable) -> void:
	for i in 900:
		if condition.call():
			return
		await tree.physics_frame
	fail("timed out")


func test_elect_picks_the_lowest_remaining_player() -> void:
	assert_eq(HostMigration.elect({2: "a", 3: "b"}, 1), 2)
	assert_eq(HostMigration.elect({1: "a", 3: "b"}, 1), 3)
	assert_eq(HostMigration.elect({}, 1), -1)


func test_second_player_takes_over_and_the_state_continues() -> void:
	var b := directors[1]
	var c := directors[2]
	# B がリフトにジャンプを繰り返しで貸しておく（移譲後も B が貸したまま残るはず）
	var lift_id := int(b.world.entity_ids["lift"])
	var lift := b.world.blocks[lift_id]
	b.world.player.global_position = lift.global_position + Vector3(0.0, 0.6, 1.4)
	await _until(
		func() -> bool:
			var host_lift := directors[0].world.blocks[lift_id]
			return (
				directors[0].world.avatars[2].global_position.distance_to(host_lift.global_position)
				< 2.5
			)
	)
	b.world.select_slot(JUMP_SLOT)
	b.world.set_lend_mode(TriggerMode.Kind.REPEAT)
	b.world.lend_to(lift, false)
	await _until(func() -> bool: return directors[0].world.ledger.can_initiate(lift_id, JUMP))
	await _until(func() -> bool: return not migrations[2].package.is_empty())
	await wait_physics_frames(int(HostMigration.PACKAGE_PERIOD * 60.0) + 10)
	# ホスト A が落ちる
	nets[0].close()
	await _until(func() -> bool: return b.is_authority())
	await _until(func() -> bool: return not migrations[2].migrating)
	await _until(func() -> bool: return nets[1].session.peer_of_player(3) != -1)
	assert_eq(c.world.player.player_id, 3, "C keeps its player id")
	assert_true(b.world.ledger.can_initiate(lift_id, JUMP), "B's lend survived the migration")
	var t := b.world.ledger.tokens_on(lift_id).filter(
		func(x: RuleToken) -> bool: return x.lender_id == 2
	)
	assert_eq(t.size(), 1, "exactly one token, still lent by B")
	await _until(func() -> bool: return c.world.ledger.can_initiate(lift_id, JUMP))
	assert_eq(b.lifecycle.state_of(1), PartyLifecycle.State.DISCONNECTED, "A is disconnected")
	await _until(func() -> bool: return b.lifecycle.state_of(3) == PartyLifecycle.State.ACTIVE)
	assert_eq(c.stage_id, StageCatalog.INTRO_ID)
