extends TestCase
## 2人のオンライン協力で、範囲の組の1マス移動（docs/adr/0003 決定 6）と、足もとの禁止（決定 7）が両方の画面で
## 同じに見える。組の移動はホストが決め、参加者は位置を受け取るだけ。足もとの禁止は、自分のアバターを動かす
## 画面（参加者なら参加者の画面）が、受け取った台帳とブロックで判断するので、跳んでから戻されることはない。

const NetParty := preload("res://tests/integration/net_party.gd")
const A := RuleLedger.PLAYER_ID
const D := RuleAction.Kind.RIGHT
const JUMP := RuleAction.Kind.JUMP
## 導入ステージの出現地点の北東の、平らな地面の上（上面 y = 0）。東（D）の x = 5 も地面。
const SQUARE: Array[Vector3i] = [
	Vector3i(3, 0, 1), Vector3i(4, 0, 1), Vector3i(3, 0, 2), Vector3i(4, 0, 2)
]

var party: NetParty
var host: PartyDirector
var client: PartyDirector


func before_each() -> void:
	party = NetParty.new(self, 2, "zz_test_group_move_net")
	host = party.directors[0]
	client = party.directors[1]
	await party.open(StageCatalog.HUB_ID, 36100)
	await party.join(1)
	await party.enter(StageCatalog.INTRO_ID)


func after_each() -> void:
	await party.close()


## 同じブロックを両方の画面に置く（参加者の側はホストから位置を受け取るだけ）。
func add_both(cell: Vector3i) -> Array[RuleBlock]:
	var on_host := host.world.add_block(cell)
	var on_client := client.world.add_block(cell)
	on_client.remote = true
	assert_eq(on_host.entity_id, on_client.entity_id, "same id on both screens")
	return [on_host, on_client]


func test_a_2x2_group_move_shows_the_same_on_both_screens() -> void:
	var hosts: Array[RuleBlock] = []
	var clients: Array[RuleBlock] = []
	for cell in SQUARE:
		var pair := add_both(cell)
		hosts.append(pair[0])
		clients.append(pair[1])
	await wait_physics_frames(10)
	var ids := PackedInt32Array()
	for b in hosts:
		ids.append(b.entity_id)
	var v := host.world.ledger.hotbar_vessel(3, A)  # D
	var spec := {"center": hosts[0].global_position, "radius": 5.0, "layer": 0}
	assert_eq(
		host.world.ledger.lend(v.id, ids, TriggerMode.Kind.SINGLE_SHOT, spec),
		RuleLedger.LendResult.OK
	)
	await party.until(func() -> bool: return party.converged(), "ledger synced")
	host.world.press_action(D)
	for b in hosts:
		assert_true(b.is_moving_horizontally(), "%s moves in the same host tick" % b.name)
	await wait_physics_frames(int(60 * Tuning.BLOCK_STEP_DURATION) + 30)
	for i in SQUARE.size():
		assert_eq(hosts[i].cell(), SQUARE[i] + Vector3i(1, 0, 0), "host: the square shifted east")
	await party.until(
		func() -> bool:
			for i in SQUARE.size():
				if clients[i].global_position.distance_to(hosts[i].global_position) > 0.02:
					return false
			return true,
		"the client sees the same square"
	)
	for i in SQUARE.size():
		assert_eq(clients[i].cell(), SQUARE[i] + Vector3i(1, 0, 0), "client: no gap")


func test_a_client_on_a_jump_banned_block_cannot_jump_and_is_not_snapped() -> void:
	var pair := add_both(Vector3i(2, 0, 3))
	await wait_physics_frames(6)
	host.world.ledger.place_on_entity(JUMP, true, pair[0].entity_id)
	await party.until(func() -> bool: return party.converged(), "ledger synced")
	var me := client.world.player
	me.global_position = pair[1].global_position + Vector3(0.0, 0.55, 0.0)
	me.velocity = Vector3.ZERO
	await wait_physics_frames(10)
	assert_true(me.floor_bans.has(JUMP), "the client sees the ban under its own feet")
	var start := me.global_position.y
	client.world.press_action(JUMP)
	var top := start
	for i in 40:
		await tree.physics_frame
		top = maxf(top, me.global_position.y)
	assert_lt(top - start, 0.1, "the client never left the block (nothing to snap back)")
	await party.settle(1)
	var seen := host.world.avatars[client.world.player.player_id].global_position
	assert_almost(seen.y, me.global_position.y, 0.15, "the host sees it standing there")
	# 降りれば跳べる
	me.global_position = Vector3(0.5, 0.05, 5.5)
	await wait_physics_frames(10)
	start = me.global_position.y
	client.world.press_action(JUMP)
	top = start
	for i in 40:
		await tree.physics_frame
		top = maxf(top, me.global_position.y)
	assert_gt(top - start, 1.0, "off the block the client jumps")
