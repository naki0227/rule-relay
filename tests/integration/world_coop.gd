extends TestCase
## ワールド 3・4 の協力の道を、2 人のオンライン協力（ホスト＋参加者。net_party.gd）で通す共通部品
## （ファイル名が test_ で始まらないので、これ自体は実行されない）。どちらの人も、移動の入力と向き
## （move_intent / view_yaw）・キー（press_action）・F（interact）・渡す（lend_to）だけで動く。瞬間移動しない。
## 参加者の操作はホストへの依頼になり、結果はホストの台帳から届く（届くまで待つ）。

const NetParty := preload("res://tests/integration/net_party.gd")
const JUMP := RuleAction.Kind.JUMP
const DASH := RuleAction.Kind.DASH
const THROW := RuleAction.Kind.THROW
const FORWARD := RuleAction.Kind.FORWARD
const LEFT := RuleAction.Kind.LEFT
const BACK := RuleAction.Kind.BACK
const RIGHT := RuleAction.Kind.RIGHT
const CLIMB := RuleAction.Kind.CLIMB
const HEAVY := RuleAction.Kind.HEAVY

var party: NetParty


func after_each() -> void:
	if party != null:
		await party.close()


func _start(stage_id: String, port: int) -> void:
	party = NetParty.new(self, 2, "zz_test_world34_coop")
	await party.open(StageCatalog.HUB_ID, port)
	await party.join_all()
	await party.enter(stage_id)


func _w(i: int) -> StageWorld:
	return party.world(i)


func _me(i: int) -> PlayerAvatar:
	return party.world(i).player


func _host() -> StageWorld:
	return party.world(0)


func _face(i: int, target: Vector3) -> void:
	var flat := target - _me(i).global_position
	_me(i).view_yaw = atan2(-flat.x, -flat.z)


func _walk(i: int, target: Vector3, tolerance: float = 0.35, frames: int = 900) -> bool:
	return await party.walk(i, target, tolerance, frames)


## その人のホットバーで action のスロット（無ければ -1）。
func _slot(i: int, action: RuleAction.Kind) -> int:
	var ledger := _w(i).ledger
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := ledger.hotbar_vessel(slot, party.pid(i))
		if v != null and ledger.token(v.token_id).action == action:
			return slot
	return -1


func _free_slot(i: int) -> int:
	for slot in RuleLedger.HOTBAR_SIZE:
		if _w(i).ledger.hotbar_vessel(slot, party.pid(i)) == null:
			return slot
	return -1


## その人の画面での、key のブロック・生き物のノード。
func _node(i: int, key: String) -> Node3D:
	var id := int(_w(i).entity_ids[key])
	if _w(i).blocks.has(id):
		return _w(i).blocks[id]
	return _w(i).creatures[id]


## i が自分の action を target（key のブロック・生き物、または仲間の番号 j を表す int）へ渡す。
func _give(
	i: int,
	target: Variant,
	action: RuleAction.Kind,
	by_throw: bool = false,
	mode: TriggerMode.Kind = TriggerMode.Kind.NONE
) -> void:
	await party.settle(i)
	var w := _w(i)
	var node: Node3D = (
		w.avatars[party.pid(int(target))] if target is int else _node(i, String(target))
	)
	if target is int:
		await party.settle(int(target))
	var slot := _slot(i, action)
	assert_ne(slot, -1, "side %d has %s" % [i, action])
	var before := party.ledger_digest(0)
	w.select_slot(slot)
	w.set_lend_mode(mode)
	if by_throw and not w.throw_mode:
		w.toggle_reach()
	w.lend_to(node, false)
	if w.throw_mode:
		w.toggle_reach()
	await party.until(func() -> bool: return party.ledger_digest(0) != before, "side %d gives" % i)
	await party.until(party.converged, "after giving")


## i が足もとの落ちている器（at）を拾い、ホットバーの空きへ置く。
func _pick(i: int, at: Vector3, action: RuleAction.Kind) -> void:
	assert_true(await _walk(i, at, 0.5), "side %d walks to the item" % i)
	await party.settle(i)
	var pid := party.pid(i)
	var before := (
		_w(i)
		. ledger
		. all_vessels()
		. filter(func(v: RuleVessel) -> bool: return _held_by(v, pid))
		. size()
	)
	_w(i).interact(null)
	# 拾った器は、ホットバーに空きがあればそこへ入る（2026-11-23）。かばんに入ったときだけ並べる
	var found := func() -> RuleVessel:
		for v in _w(i).ledger.inventory_vessels(pid):
			if _w(i).ledger.token(v.token_id).action == action:
				return v
		return null
	var picked := func() -> bool:
		var now := _w(i).ledger.all_vessels().filter(
			func(v: RuleVessel) -> bool: return _held_by(v, pid)
		)
		return now.size() > before
	await party.until(picked, "side %d picks up" % i)
	var vessel: RuleVessel = found.call()
	if vessel != null:
		_w(i).ledger_actions.move_to_hotbar(vessel.id, _free_slot(i))
	await party.until(func() -> bool: return _slot(i, action) != -1, "on side %d's hotbar" % i)


static func _held_by(v: RuleVessel, pid: int) -> bool:
	return v.owner_id == pid and v.location != RuleVessel.Location.WORLD


## i が target（ノード）に F を押す（鐘を鳴らす・回収する）。
func _interact(i: int, key: String) -> void:
	await party.settle(i)
	var before := party.ledger_digest(0)
	_w(i).interact(_node(i, key))
	await party.until(func() -> bool: return party.ledger_digest(0) != before, "side %d F" % i)
	await party.until(party.converged, "after F")


## 単発で渡したブロックの行動を、i のキーで起動する。
func _fire(i: int, action: RuleAction.Kind) -> void:
	_w(i).press_action(action)
	await wait_physics_frames(45)


## 谷の手前（edge）から land へ走って跳び、dash_frames 後に空中でダッシュする（i 自身の画面で動く）。
func _dash_jump(i: int, edge: Vector3, land: Vector3, dash_frames: int = 22) -> bool:
	assert_true(await _walk(i, edge, 0.25), "side %d at the edge" % i)
	_face(i, land)
	_me(i).move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(4)
	_w(i).press_action(JUMP)
	await wait_physics_frames(dash_frames)
	_face(i, land)
	_w(i).press_action(DASH)
	return await _walk(i, land, 0.6, 240)


## 生き物が願いの場所（ホストの画面）に入るまで待つ。
func _wait_in(key: String, box: AABB, frames: int = 1800) -> bool:
	var critter := _host().creatures[int(_host().entity_ids[key])]
	for f in frames:
		if box.has_point(critter.global_position):
			return true
		await tree.physics_frame
	return false


func _wish_box(key: String) -> AABB:
	for part in _host().def.clear_condition.parts:
		if part.kind == ClearCondition.Kind.CARRY_OBJECT and part.target_key == key:
			return part.area
	return AABB()


func _wait_wish(key: String) -> bool:
	return await _wait_in(key, _wish_box(key))


## ホストの画面の扉・橋が閉じた（橋なら架かった）か。
func _door_closed(key: String) -> bool:
	for door in MechanismSet.of(_host()).doors:
		if door.spec.key == key:
			return door.is_closed()
	return false


func _wait_door(key: String, closed: bool) -> bool:
	return await party.until(
		func() -> bool: return _door_closed(key) == closed, "door %s closed=%s" % [key, closed]
	)


## i が往復足場（key）に乗って向こうへ渡る（i の画面のブロックの位置で判断する）。
func _ride(
	i: int, key: String, from: Vector3, board: Vector3i, off_cell: Vector3i, off_to: Vector3
) -> void:
	assert_true(await _walk(i, from, 0.3), "side %d waits on the shore" % i)
	var block := _node(i, key) as RuleBlock
	var at := func(cell: Vector3i) -> bool:
		return block.global_position.distance_to(RuleBlock.cell_center(cell)) < 0.05
	await party.until(func() -> bool: return at.call(board), "%s comes to %s" % [key, board])
	await _walk(i, RuleBlock.cell_center(board) + Vector3(0.0, 0.5, 0.0), 0.25, 60)
	await party.until(func() -> bool: return at.call(off_cell), "%s carries side %d" % [key, i])
	assert_true(await _walk(i, off_to, 0.35, 120), "side %d steps off %s" % [i, key])


## 2 人がゴールの窪みに入り、クリアするのを待つ。spots は窪みの中の立ち位置（人ごと）。
func _both_in_goal(spots: Array[Vector3]) -> void:
	for i in 2:
		assert_true(await _walk(i, spots[i]), "side %d walks into the goal" % i)
	var host := party.host()
	assert_true(
		await party.until(func() -> bool: return host.last_clear_text != "", "the stage clears"),
		"cleared together"
	)
	print("    %s (2 players): %s" % [host.stage_id, host.last_clear_text])


## 跳ばずに、縁の手前 edge から land へ向かって地上でダッシュする（i 自身の画面で動く）。
func _ground_dash(i: int, edge: Vector3, land: Vector3) -> bool:
	assert_true(await _walk(i, edge, 0.2), "side %d at the edge" % i)
	_face(i, land)
	_me(i).move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(1)
	_w(i).press_action(DASH)
	await wait_physics_frames(30)
	return await _walk(i, land, 0.5, 200)


## i が鐘（key）に F を押して鳴らす（ホストの画面で鳴るまで待つ）。
func _ring(i: int, key: String) -> void:
	var bell := _w(i).bells_by_key[key]
	var flat := _me(i).global_position - bell.global_position
	flat.y = 0.0
	assert_true(await _walk(i, bell.global_position + flat.normalized() * 1.4, 0.5))
	await party.settle(i)
	_face(i, bell.global_position)
	_w(i).interact(bell)
	await party.until(
		func() -> bool: return _host().activated.has(key), "side %d rings %s" % [i, key]
	)
