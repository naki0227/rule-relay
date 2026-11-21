extends TestCase
## スイッチの仕掛け（docs/adr/0014）を 2 人のオンライン協力で確かめる（ホスト権威）。
## 板の重さ・扉の開き具合・レバー・時の鐘はホストが決め、参加者の画面には WorldFrame で届く。
## 参加者のワープは、ホストが出す切符（WorldFrame）で参加者自身の画面が自分を動かす。
## 部屋の組み立ては net_party.gd、見本の配置は switch_demo.gd。

const NetParty := preload("res://tests/integration/net_party.gd")
const Demo := preload("res://tests/integration/switch_demo.gd")

var party: NetParty


func before_each() -> void:
	Demo.register()
	party = NetParty.new(self, 2, "zz_test_switch_net")
	await party.open(StageCatalog.HUB_ID, 36000)
	await party.join_all()
	await party.enter(Demo.ID)


func after_each() -> void:
	await party.close()
	Demo.unregister()


func _mech(i: int) -> MechanismSet:
	return MechanismSet.of(party.world(i))


func _door(i: int, key: String) -> SwitchDoor:
	for door in _mech(i).doors:
		if door.spec.key == key:
			return door
	return null


## 両方の画面で、扉 key がそろって開いた（閉じた）か。
func _both(key: String, open: bool) -> bool:
	for i in 2:
		var door := _door(i, key)
		if (door.open_amount if open else 1.0 - door.open_amount) < 0.99:
			return false
	return true


func test_two_players_hold_the_two_plate_door_and_both_screens_agree() -> void:
	await party.walk(0, Demo.PLATE_L)
	await wait_physics_frames(40)
	assert_true(_both("duo_gate", false), "one player is not enough")
	await party.walk(1, Demo.PLATE_R)
	await party.settle(1)
	assert_true(
		await party.until(func() -> bool: return _both("duo_gate", true), "opens on both screens")
	)
	assert_true(_mech(1).plates[2].pressed, "the client sees its plate pressed")
	await party.walk(1, Demo.PLATE_R + Vector3(0.0, 0.0, 3.0))
	assert_true(
		await party.until(func() -> bool: return _both("duo_gate", false), "closes on both screens")
	)


func test_the_client_walks_through_a_door_the_host_holds_open() -> void:
	# ホストが左の板に立ち、右の板にはブロックを置く（どちらも人でなくてよい）
	await party.walk(0, Demo.PLATE_L)
	var crate := party.world(0).blocks[int(party.world(0).entity_ids["crate"])]
	crate.teleport(RuleBlock.cell_center(Vector3i(-4, 0, -1)), 0.0)
	assert_true(
		await party.until(func() -> bool: return _both("duo_gate", true), "open on both screens")
	)
	await party.walk(1, Vector3(-5.5, 0.0, Demo.SOUTH_Z))
	assert_true(await party.walk(1, Vector3(-5.5, 0.0, Demo.NORTH_Z)), "the client passes")
	await party.settle(1)
	assert_lt(party.host().world.avatar_of(2).global_position.z, -5.0, "the host sees it too")


func test_the_client_pulls_the_lever_and_the_host_decides() -> void:
	await party.walk(1, Demo.LEVER + Vector3(0.0, 0.0, 0.8))
	await party.settle(1)
	party.world(1).interact(null)
	assert_true(
		await party.until(func() -> bool: return _mech(0).levers[0].on, "the host flips the lever")
	)
	assert_true(
		await party.until(
			func() -> bool: return _mech(1).levers[0].on, "the client sees it flipped"
		)
	)
	assert_true(
		await party.until(func() -> bool: return _both("lever_gate", true), "the door follows")
	)


func test_the_client_warps_on_its_own_screen_by_the_host_ticket() -> void:
	await party.walk(1, Demo.WARP_A + Vector3(0.0, 0.0, 1.5))
	var me := party.world(1).player
	# 最後の一歩は置くだけ（歩き続けると、移った先から元の石へ歩いて戻ろうとする）
	me.global_position = Demo.WARP_A + Vector3(0.0, 0.05, 0.0)
	me.velocity = Vector3.ZERO
	assert_true(
		await party.until(
			func() -> bool: return absf(me.global_position.z - Demo.WARP_B.z) < 0.3,
			"the client is moved to the partner stone"
		)
	)
	await party.settle(1)
	await wait_physics_frames(60)
	assert_lt(absf(me.global_position.z - Demo.WARP_B.z), 0.3, "no bounce back")
	assert_lt(
		absf(party.host().world.avatar_of(2).global_position.z - Demo.WARP_B.z),
		0.3,
		"the host sees the client at the partner stone"
	)
	assert_true(_mech(1).warps[1].flashes > 0, "the client sees the stone light up")


func test_timed_bell_counts_down_on_both_screens_and_reset_vote_restores_all() -> void:
	await party.walk(1, Demo.CLOCK + Vector3(0.0, 0.0, 1.4))
	await party.settle(1)
	party.world(1).interact(_mech(1).timed_bells[0])
	var client_bell := _mech(1).timed_bells[0]
	assert_true(
		await party.until(func() -> bool: return client_bell.is_ringing(), "rings on the client")
	)
	assert_true(_mech(0).timed_bells[0].is_ringing(), "the host rang it")
	assert_true(
		await party.until(func() -> bool: return _both("bell_gate", true), "the door opens")
	)
	assert_true(
		await party.until(
			func() -> bool: return client_bell.remaining_fraction() < 0.6, "the countdown shrinks"
		)
	)
	# レバーも入れてから、全員リセットの投票で、ステージの始めの状態に戻す
	await party.walk(0, Demo.LEVER + Vector3(0.0, 0.0, 0.8))
	party.world(0).interact(null)
	assert_true(
		await party.until(func() -> bool: return _both("lever_gate", true), "lever door open")
	)
	party.host().request_vote()
	party.directors[1].request_vote()
	assert_true(
		await party.until(func() -> bool: return party.host().lifecycle.reset_count() == 1, "reset")
	)
	assert_true(
		await party.until(
			func() -> bool: return not _mech(0).levers[0].on, "lever back on the host"
		)
	)
	assert_true(
		await party.until(
			func() -> bool: return not _mech(1).levers[0].on and _both("lever_gate", false),
			"both screens show the start again"
		)
	)
