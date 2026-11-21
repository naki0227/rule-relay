extends "res://tests/integration/coop_stage_route.gd"
## 「鳴りつづける鐘」（2-5。時の鐘の初出）の協力の道（2 人のオンライン協力。部品は coop_stage_route.gd）。
## 参加者が時の鐘のそばで鳴らしつづけ、ホストが生き物に移動を渡して、生き物のあとから橋を渡る。
## 最後に参加者が橋のたもとで鳴らし、鳴りやむ前に走って渡る。
## ひとりの道は test_world2_timed_bells.gd、関所と詰みは test_world2_timed_bells_probes.gd。

const RIGHT := RuleAction.Kind.RIGHT
const STAGE_ID := "w2_timed_bells"
const BELL := OpenIslandsW2.RINGING_BELL
const BY_THE_BELL := Vector3(3.5, 2.0, -0.4)
const BRIDGE_FOOT := Vector3(0.9, 2.0, -2.7)
const FAR_BANK := Vector3(1.0, 4.0, -13.8)
## 鳴らし直すのは、残りがこの秒数を切ったとき（参加者の F がホストへ届くまでの余裕を見る）。
const RERING_BELOW := 1.5

## 前に鳴らし直してからのフレーム数（届く前に何度も押さない）。
var _since_ring: int = 999


func test_coop_one_keeps_the_bell_ringing_while_the_other_crosses_with_the_kit() -> void:
	await _start(STAGE_ID, 52587)
	await _give_kit_a_move(0)
	await _climb_to_the_terrace(0, Vector3i(10, -1, 1))
	await _walk(0, Vector3(2.0, 2.0, 0.5))
	await _climb_to_the_terrace(1, Vector3i(8, -1, 1))
	await _walk(1, BY_THE_BELL, 0.3)
	# 生き物が石の段で鐘の段へ上がり、橋を渡って巣に着くまで、参加者が鳴らしつづける
	var kit := _creature(0, "kit")
	for f in 4800:
		if OpenIslandsW2.RINGING_NEST.has_point(kit.global_position):
			break
		_tick_ringer()
		await tree.physics_frame
	assert_true(OpenIslandsW2.RINGING_NEST.has_point(kit.global_position), "the kit is home")
	assert_eq(_block(0, "walking_stone").cell(), Vector3i(0, 0, 1), "the stone walked to the bump")
	# ホストも、鳴っている間に歩いて渡る
	await _walk_ringing(0, BRIDGE_FOOT)
	await _walk_ringing(0, FAR_BANK)
	# 参加者は鳴りやむのを待ち、橋のたもとで鳴らして走って渡る
	var bell := _w(0).bells_by_key[BELL]
	await party.until(func() -> bool: return _bridge_down(0), "the bridge sinks", 600)
	await _walk(1, BRIDGE_FOOT, 0.3)
	await party.settle(1)
	_w(1).interact(_w(1).bells_by_key[BELL])
	await party.until(bell.is_ringing, "the guest rings the timed bell")
	await party.until(func() -> bool: return _bridge_up(1), "the guest sees the bridge up", 120)
	assert_true(await party.walk(1, FAR_BANK, 0.5, 360), "the guest raced across")
	print("    timed_bells (co-op): the guest crossed with %.2f s left" % bell.remaining)
	await _walk(0, Vector3(2.0, 3.0, -22.0))
	await _walk(1, Vector3(4.0, 3.0, -22.0))
	await _assert_cleared_by_everyone(STAGE_ID)


func _give_kit_a_move(i: int) -> void:
	var kit := _creature(i, "kit")
	await _walk(i, kit.global_position + Vector3(1.4, 0.0, 0.0), 0.4)
	await _lend(i, kit, RIGHT, TriggerMode.Kind.NONE)
	await _walk(i, Vector3(-0.5, 0.0, 3.5), 0.5)


## i 番目が、浜の地面のセル（上面のセル）を持ち上げ台にして鐘の段へ上がる。
func _climb_to_the_terrace(i: int, cell: Vector3i) -> void:
	await _walk(i, Vector3(cell.x + 0.5, 0.0, cell.z + 0.5), 0.25)
	await _lend(i, _w(i).terrain_target(cell), JUMP, TriggerMode.Kind.SINGLE_SHOT)
	_w(i).press_action(JUMP)
	await _ride_up(i, Vector3(cell.x + 0.5, 2.0, 0.4))


## 参加者が、ホストの画面の時の鐘の残りが少なくなったら F で鳴らし直す（1 フレーム分）。
func _tick_ringer() -> void:
	_since_ring += 1
	var bell := _w(0).bells_by_key[BELL]
	if bell.remaining < RERING_BELOW and _since_ring > 20:
		_w(1).interact(_w(1).bells_by_key[BELL])
		_since_ring = 0


## i 番目が target へ歩く（net_party.walk と同じ歩き方）。そのあいだ参加者が鐘を鳴らしつづける。
func _walk_ringing(i: int, target: Vector3) -> void:
	var me := _w(i).player
	var stuck := 0
	for f in 900:
		_tick_ringer()
		var flat := Vector3(target.x - me.global_position.x, 0.0, target.z - me.global_position.z)
		if flat.length() <= 0.4 and absf(me.global_position.y - target.y) < 0.7:
			break
		me.view_yaw = atan2(-flat.x, -flat.z)
		me.move_intent = Vector2(0.0, 1.0)
		var moving := Vector2(me.velocity.x, me.velocity.z).length() > 0.5
		stuck = 0 if moving else stuck + 1
		if stuck > 8 and me.is_on_floor():
			_w(i).press_action(JUMP)
			stuck = 0
		await tree.physics_frame
	me.move_intent = Vector2.ZERO
	assert_lt(
		Vector2(target.x - me.global_position.x, target.z - me.global_position.z).length(),
		0.5,
		"side %d walked to %s while the bell kept ringing" % [i, target]
	)


func _bridge_up(i: int) -> bool:
	for door in MechanismSet.of(_w(i)).doors:
		if not door.is_closed():
			return false
	return true


func _bridge_down(i: int) -> bool:
	for door in MechanismSet.of(_w(i)).doors:
		if not door.is_open():
			return false
	return true
