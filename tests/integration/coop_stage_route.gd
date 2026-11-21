extends TestCase
## 新しいステージの協力の道（2 人のオンライン協力）を通す部品（ファイル名が test_ で始まらないので、これ自体は
## 実行されない）。ホストと参加者を同じプロセスの中で別々の物理世界に作り、ENet でつなぐ（net_party.gd）。
## 出現地点から先は、全員が移動の入力と向き（move_intent / view_yaw）とキー（press_action）、画面の操作
## （渡す・回収する・拾う・持ち物を並べる）だけで進む。瞬間移動はしない。

const NetParty := preload("res://tests/integration/net_party.gd")
const JUMP := RuleAction.Kind.JUMP

var party: NetParty


func after_each() -> void:
	if party != null:
		await party.close()


func _start(stage_id: String, port: int, players: int = 2) -> void:
	party = NetParty.new(self, players, "zz_test_coop_%s" % stage_id)
	await party.open(StageCatalog.HUB_ID, port)
	await party.join_all()
	await party.enter(stage_id)


func _w(i: int) -> StageWorld:
	return party.world(i)


func _walk(i: int, target: Vector3, tolerance: float = 0.35) -> void:
	assert_true(await party.walk(i, target, tolerance), "side %d walks to %s" % [i, target])


func _walk_route(i: int, route: Array[Vector3]) -> void:
	for p in route:
		await _walk(i, p)


## i 番目のホットバーで、action が器に入っている（貸していない・仲間に渡していない）スロット（無ければ -1）。
func _slot(i: int, action: RuleAction.Kind) -> int:
	var w := _w(i)
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(slot, party.pid(i))
		if v == null:
			continue
		var t := w.ledger.token(v.token_id)
		if t.action == action and not t.is_prohibition and t.is_in_vessel():
			return slot
	return -1


func _free_slot(i: int) -> int:
	for slot in RuleLedger.HOTBAR_SIZE:
		if _w(i).ledger.hotbar_vessel(slot, party.pid(i)) == null:
			return slot
	return -1


## i 番目が、自分の画面の target（ブロック・生き物・地形のセル）へ action を mode で渡す。
## 届くかはホストの画面の位置で決まるので、位置がホストに届いてから渡し、台帳がそろうまで待つ。
func _lend(i: int, target: Node3D, action: RuleAction.Kind, mode: TriggerMode.Kind) -> void:
	await party.settle(i)
	var w := _w(i)
	var slot := _slot(i, action)
	assert_ne(slot, -1, "side %d has %s to lend" % [i, action])
	w.select_slot(slot)
	w.set_lend_mode(mode)
	var before := party.ledger_digest(i)
	assert_eq(w.lend_to(target, false), RuleLedger.LendResult.OK, "side %d lends" % i)
	await party.until(
		func() -> bool: return party.ledger_digest(i) != before, "side %d's lend arrives" % i
	)
	await party.until(party.converged, "after side %d lends" % i)


## i 番目が、ブロックか地形のセルへ移動を単発で渡し、キーで 1 マス押す。
func _push(i: int, target: Node3D, action: RuleAction.Kind) -> void:
	await _lend(i, target, action, TriggerMode.Kind.SINGLE_SHOT)
	_w(i).press_action(action)
	await wait_physics_frames(45)
	await party.until(party.converged, "after side %d pushes" % i)


## i 番目の画面のブロック（key）が、止まって床に着くまで待つ。
func _settle_block(i: int, key: String) -> void:
	var block := _block(i, key)
	await party.until(
		func() -> bool: return block.is_grounded() and not block.is_moving_horizontally(),
		"%s comes to rest" % key
	)


## i 番目が持っている action を 1 つ、j 番目へ渡す（仲間へ渡す）。
func _give(i: int, j: int, action: RuleAction.Kind) -> void:
	await party.settle(i)
	await party.settle(j)
	var w := _w(i)
	var before := _w(j).ledger.ability_count(action, party.pid(j))
	# 自分の器に無ければ、空の枠を選ぶ（仲間から受け取って持っている能力を渡す。GameWorld._give_to）
	var slot := _slot(i, action)
	w.select_slot(slot if slot != -1 else _free_slot(i))
	assert_eq(w.lend_to(w.avatars[party.pid(j)], false), RuleLedger.LendResult.OK, "give")
	await party.until(
		func() -> bool: return _w(j).ledger.ability_count(action, party.pid(j)) > before,
		"side %d gives %s to side %d" % [i, action, j]
	)
	await party.until(party.converged, "after giving")


## i 番目が F を押す（target が null なら足もとの器を拾う）。拾った・回収した物は通常インベントリに入るので、
## action の器をホットバーの空きへ移す（E で開いて並べるのと同じ）。
func _interact_and_hold(i: int, target: Node3D, action: RuleAction.Kind) -> void:
	await party.settle(i)
	var w := _w(i)
	var before := party.ledger_digest(i)
	w.interact(target)
	await party.until(func() -> bool: return party.ledger_digest(i) != before, "F arrives")
	await party.until(party.converged, "after F")
	for v in w.ledger.inventory_vessels(party.pid(i)):
		var t := w.ledger.token(v.token_id)
		if t.action == action and not t.is_prohibition:
			assert_true(w.ledger_actions.move_to_hotbar(v.id, _free_slot(i)), "to the hotbar")
	await party.until(
		func() -> bool: return _slot(i, action) != -1, "side %d holds %s" % [i, action]
	)
	await party.until(party.converged, "after moving to the hotbar")


## i 番目の画面のブロック（key）。
func _block(i: int, key: String) -> RuleBlock:
	return _w(i).blocks[int(_w(i).entity_ids[key])]


func _creature(i: int, key: String) -> Creature:
	return _w(i).creatures[int(_w(i).entity_ids[key])]


## ホストの画面で、生き物が箱の中に入るまで待つ。
func _wait_creature_in(key: String, box: AABB, frames: int = 2400) -> bool:
	var critter := _creature(0, key)
	return await party.until(
		func() -> bool: return box.has_point(critter.global_position),
		"%s reaches %s" % [key, box],
		frames
	)


## i 番目が、窪みのブロック（key）に乗ってジャンプを単発で渡し、キーで跳ばせて上の段（onto）へ移る。
func _ride_lift(i: int, key: String, onto: Vector3) -> void:
	var lift := _block(i, key)
	await _walk(i, lift.global_position + Vector3(0.0, 0.5, 0.0), 0.25)
	await _lend(i, lift, JUMP, TriggerMode.Kind.SINGLE_SHOT)
	_w(i).press_action(JUMP)
	await _ride_up(i, onto)


## i 番目が、上昇中の台の上で、十分高くなったら上の段（onto）へ歩いて移る。
func _ride_up(i: int, onto: Vector3) -> void:
	var me := _w(i).player
	for f in 300:
		var flat := Vector3(onto.x - me.global_position.x, 0.0, onto.z - me.global_position.z)
		if flat.length() < 0.4 and me.global_position.y > onto.y - 0.2:
			break
		me.view_yaw = atan2(-flat.x, -flat.z)
		me.move_intent = Vector2(0.0, 1.0) if me.global_position.y > onto.y else Vector2.ZERO
		await tree.physics_frame
	me.move_intent = Vector2.ZERO
	assert_gt(me.global_position.y, onto.y - 0.3, "side %d rode up onto %s" % [i, onto])


## 全員がゴールにいる間にホストがクリアし、全員の進行に記録されることを確かめる。
func _assert_cleared_by_everyone(stage_id: String) -> void:
	var host := party.host()
	await party.until(func() -> bool: return host.last_clear_text != "", "%s clears" % stage_id)
	print("    %s (co-op): %s" % [stage_id, host.last_clear_text])
	for i in party.count():
		await party.until(
			func() -> bool: return party.directors[i].progress.has_cleared(stage_id),
			"side %d records the clear" % i
		)
	await party.assert_consistent("after the clear")
