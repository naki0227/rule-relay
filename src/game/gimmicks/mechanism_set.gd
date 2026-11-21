class_name MechanismSet
extends Node3D
## ステージのスイッチの仕掛け（重さの板・扉・レバー・時の鐘・ワープの石）をまとめて動かす係（docs/adr/0014）。
## StageWorld が StageDef.mechanisms から作り、世界の子 "Mechanisms" として置く。GameWorld には
## 変数を足さず、MechanismSet.of(world) で探す（ほかの仕掛けの作業と共有ファイルでぶつからないように）。
##
## ホスト（1人用も）だけが判断する: 板の重さ・扉の開き具合・ワープ。参加者は WorldFrame で届いた状態を見せるだけ。
## チェックポイントと全員リセットは WorldSnapshot から capture / restore で記録・復元する。
## 台帳（能力・禁止）には触らない。ワープしても持ち物・付いている能力はそのまま（ルールは厳格に）。

const NODE_NAME := "Mechanisms"
## ワープした直後、そのものをワープの判断から外す秒数（参加者の位置の報告が遅れて届いても、行き来しない）。
const WARP_COOLDOWN: float = 0.6
## 仲間をワープさせた知らせ（WorldFrame の切符）を配り続ける秒数。
const TICKET_TTL: float = 1.5
## 扉に挟まないかを調べる点（足もとからの高さ）と、横の幅（体の半径）。
const PLAYER_MIDDLE: float = 0.9
const CREATURE_MIDDLE: float = 0.4
const BODY_RADIUS: float = 0.3
const LIFT := Vector3(0.0, 0.05, 0.0)

var world: GameWorld
var specs: MechanismSpecs
var plates: Array[PressurePlate] = []
var doors: Array[SwitchDoor] = []
var levers: Array[SwitchLever] = []
var timed_bells: Array[TimedBell] = []
var warps: Array[WarpStone] = []

var _sources: Dictionary[String, Node] = {}
var _warps_by_key: Dictionary[String, WarpStone] = {}
## ワープで着いたもの → 着いた石の key（その石から降りるまで、その石では移らない）。
var _locks: Dictionary[String, String] = {}
var _cooldowns: Dictionary[String, float] = {}
## 仲間をワープさせた切符: プレイヤー ID → [切符の番号, 着く位置, 経過秒]（ホスト）。
var _tickets: Dictionary[int, Array] = {}
## 参加者: 最後に従った切符の番号。
var _applied_ticket: int = -1


## w に仕掛けを組み立てる（定義が空なら何もしない）。StageWorld._ready から呼ぶ。
static func build(w: GameWorld, p_specs: MechanismSpecs) -> MechanismSet:
	if p_specs == null or p_specs.is_empty():
		return null
	var mechanisms := MechanismSet.new()
	mechanisms.name = NODE_NAME
	mechanisms.world = w
	mechanisms.specs = p_specs
	# ブロックより先に動く: 同じフレームでブロックが自分の動きを物理へ送った後に瞬間移動させると、
	# 送った動き（元の場所）で上書きされて戻ってしまう（AnimatableBody3D の同期移動）
	mechanisms.process_physics_priority = -1
	w.add_child(mechanisms)
	mechanisms._build_all()
	return mechanisms


## w の仕掛け（無ければ null）。
static func of(w: GameWorld) -> MechanismSet:
	return w.get_node_or_null(NODE_NAME) as MechanismSet if w != null else null


## 板・レバーの音波が at に届いているか（GameWorld.is_receiving_signal から。鐘は GameWorld が見る）。
static func signal_reaches(w: GameWorld, at: Vector3) -> bool:
	var m := of(w)
	if m == null:
		return false
	for plate in m.plates:
		if plate.reaches(at):
			return true
	for lever in m.levers:
		if lever.reaches(at):
			return true
	return false


## F: 手の届くレバーがあれば倒して true（足もとに拾える物があるときは、拾う方を先にする）。
static func try_interact(w: GameWorld) -> bool:
	var m := of(w)
	if m == null or w.player == null or w.nearest_world_item() != null:
		return false
	if WorldQueries.nearest_dropped(w.ledger, w.player.global_position) != -1:
		return false
	for lever in m.levers:
		if lever.within_reach(w.player.global_position):
			lever.toggle()
			w._post("レバーを%s" % ("入れました" if lever.on else "戻しました"))
			w._sound(&"block_step@4" if lever.on else &"block_step@-2", lever.global_position)
			return true
	return false


# --- 組み立て -----------------------------------------------------------------


func _build_all() -> void:
	var stage := world as StageWorld
	if stage != null:
		for key: String in stage.bells_by_key:
			_sources[key] = stage.bells_by_key[key]
	for spec in specs.plates:
		var plate := PressurePlate.new()
		plate.setup(spec)
		add_child(plate)
		plates.append(plate)
		_sources[spec.key] = plate
	for spec in specs.levers:
		var lever := SwitchLever.new()
		lever.setup(spec)
		add_child(lever)
		levers.append(lever)
		_sources[spec.key] = lever
	for spec in specs.timed_bells:
		_add_timed_bell(spec, stage)
	for spec in specs.doors:
		var door := SwitchDoor.new()
		door.setup(spec)
		add_child(door)
		doors.append(door)
		door.started_moving.connect(
			func(opening: bool) -> void:
				world._sound(&"block_step@-5" if opening else &"block_land", door.global_position)
		)
	for spec in specs.warps:
		var stone := WarpStone.new()
		stone.setup(spec)
		add_child(stone)
		warps.append(stone)
		_warps_by_key[spec.key] = stone


## 時の鐘は世界の鐘（world.bells）に入れる。信号・玉・F・記録・配信が、ふつうの鐘と同じ道を通る。
func _add_timed_bell(spec: MechanismSpecs.TimedBellSpec, stage: StageWorld) -> void:
	var bell := TimedBell.new()
	bell.name = "TimedBell_%s" % spec.key
	bell.ring_time = spec.ring_time
	bell.position = spec.position
	add_child(bell)
	world.bells.append(bell)
	timed_bells.append(bell)
	_sources[spec.key] = bell
	bell.rang.connect(func() -> void: world._sound(&"bell", bell.global_position))
	if stage != null:
		stage.bells_by_key[spec.key] = bell
		bell.rang.connect(func() -> void: stage._mark_activated(spec.key))


# --- 毎フレーム（ホスト） -------------------------------------------------------


func _physics_process(delta: float) -> void:
	if world == null or world.replica:
		return
	var bodies := _bodies()
	_tick_plates(bodies)
	_tick_doors(delta, bodies)
	_tick_warps(delta, bodies)
	for player_id: int in _tickets.keys():
		_tickets[player_id][2] = float(_tickets[player_id][2]) + delta
		if float(_tickets[player_id][2]) > TICKET_TTL:
			_tickets.erase(player_id)


## 板・扉・ワープが見るもの（プレイヤー・ブロック・生き物）。
## {key, kind, node, feet（足もと）, middle（扉の判定の点）, radius}
func _bodies() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var avatars: Array[PlayerAvatar] = []
	if world.player != null:
		avatars.append(world.player)
	avatars.append_array(world.avatars.values())
	for avatar in avatars:
		if avatar.visible:
			var at := avatar.global_position
			var body := _body("p%d" % avatar.player_id, "player", avatar, at, PLAYER_MIDDLE)
			body["weight"] = BodyTraits.weight_units(world.ledger, avatar.player_id)
			out.append(body)
	for id in world.blocks:
		var block := world.blocks[id]
		var feet := block.global_position - Vector3(0.0, RuleBlock.SIZE * 0.5, 0.0)
		var body := _body("b%d" % id, "block", block, feet, RuleBlock.SIZE * 0.5)
		body["weight"] = BodyTraits.weight_units(world.ledger, id)
		out.append(body)
	for id in world.creatures:
		var creature := world.creatures[id]
		var body := _body(
			"c%d" % id, "creature", creature, creature.global_position, CREATURE_MIDDLE
		)
		body["weight"] = BodyTraits.weight_units(world.ledger, id)
		out.append(body)
	return out


func _body(key: String, kind: String, node: Node3D, feet: Vector3, middle: float) -> Dictionary:
	var radius := 0.0 if kind == "block" else BODY_RADIUS
	return {
		"key": key,
		"kind": kind,
		"node": node,
		"feet": feet,
		"middle": feet + Vector3(0.0, middle, 0.0),
		"radius": radius,
	}


func _tick_plates(bodies: Array[Dictionary]) -> void:
	var feet: Array[Vector3] = []
	var weights: Array[float] = []
	for b in bodies:
		feet.append(b["feet"] as Vector3)
		weights.append(float(b.get("weight", 1.0)))
	for plate in plates:
		if plate.evaluate(feet, weights):
			var sound := &"block_step@2" if plate.pressed else &"block_step@-3"
			world._sound(sound, plate.global_position)


func _tick_doors(delta: float, bodies: Array[Dictionary]) -> void:
	for door in doors:
		var open := door.wants_open(_door_input(door.spec))
		if door.step(delta, open, _occupied(door.closed_box(), bodies)):
			# 扉は地形として道を変えるので、生き物に道を探し直させる
			world._notify_creatures()


## 扉の入力: つながった源のどれか（require_all なら全部）が作動しているか。
func _door_input(spec: MechanismSpecs.DoorSpec) -> bool:
	var active_count := 0
	for key in spec.sources:
		if is_source_active(key):
			active_count += 1
	return active_count == spec.sources.size() if spec.require_all else active_count > 0


## 源 key が作動しているか（板: 押されている・レバー: 入っている・鐘: 鳴っている）。
func is_source_active(key: String) -> bool:
	var source: Node = _sources.get(key)
	if source is Bell:
		return (source as Bell).is_ringing()
	if source is PressurePlate:
		return (source as PressurePlate).is_active()
	if source is SwitchLever:
		return (source as SwitchLever).is_active()
	return false


## box の中（体の幅ぶん広げる）に、誰かの判定の点があるか。
static func _occupied(box: AABB, bodies: Array[Dictionary]) -> bool:
	var inner := box.grow(-0.05)
	for b in bodies:
		var p := b["middle"] as Vector3
		var r := float(b["radius"])
		var inside_x := p.x > inner.position.x - r and p.x < inner.end.x + r
		var inside_z := p.z > inner.position.z - r and p.z < inner.end.z + r
		if inside_x and inside_z and p.y > inner.position.y and p.y < inner.end.y:
			return true
	return false


# --- ワープ -------------------------------------------------------------------


func _tick_warps(delta: float, bodies: Array[Dictionary]) -> void:
	for key: String in _cooldowns.keys():
		_cooldowns[key] -= delta
		if _cooldowns[key] <= 0.0:
			_cooldowns.erase(key)
	for stone in warps:
		var dest: WarpStone = _warps_by_key.get(stone.spec.partner)
		if dest == null:
			continue
		for b in bodies:
			if _may_warp(b, stone) and not _stone_taken(dest, bodies):
				_warp(b, stone, dest)
	_release_locks(bodies)


## b が石 stone で移れるか（乗っている・移った直後でない・その石に着いたばかりでない・止まっている）。
func _may_warp(b: Dictionary, stone: WarpStone) -> bool:
	var key := String(b["key"])
	if not stone.covers(b["feet"] as Vector3) or _cooldowns.has(key):
		return false
	if _locks.get(key, "") == stone.spec.key:
		return false
	if b["kind"] == "block":
		# ブロックは止まってマスに収まってから移る（動いている途中では移らない）
		var block := b["node"] as RuleBlock
		return block.is_grounded() and not block.is_moving_horizontally()
	return true


## 行き先の石の上に、もう誰か（何か）が乗っているか。乗っていれば、降りるまで移さない。
static func _stone_taken(dest: WarpStone, bodies: Array[Dictionary]) -> bool:
	for b in bodies:
		if dest.covers(b["feet"] as Vector3):
			return true
	return false


func _warp(b: Dictionary, from: WarpStone, dest: WarpStone) -> void:
	var at := dest.floor_point()
	match String(b["kind"]):
		"player":
			_move_player(b["node"] as PlayerAvatar, at + LIFT)
		"block":
			(b["node"] as RuleBlock).teleport(RuleBlock.cell_center(dest.spec.cell), 0.0)
		"creature":
			(b["node"] as Creature).restore_state({"position": at + LIFT, "velocity": Vector3.ZERO})
	var key := String(b["key"])
	b["middle"] = at + ((b["middle"] as Vector3) - (b["feet"] as Vector3))
	b["feet"] = at
	_locks[key] = dest.spec.key
	_cooldowns[key] = WARP_COOLDOWN
	from.flash()
	dest.flash()
	world._sound(&"dash", from.global_position)
	world._sound(&"dash", at)
	world._notify_creatures()


## 自分ならその場で、仲間ならアバターを動かして切符を出す（その人の画面が切符を見て自分を動かす）。
func _move_player(avatar: PlayerAvatar, at: Vector3) -> void:
	avatar.global_position = at
	if avatar == world.player:
		avatar.velocity = Vector3.ZERO
		return
	avatar.apply_remote(at, avatar.remote_yaw, false, true)
	_tickets[avatar.player_id] = [randi(), at, 0.0]


## 着いた石から降りた（または居なくなった）ものの印を外す。移った直後は外さない。
func _release_locks(bodies: Array[Dictionary]) -> void:
	for key: String in _locks.keys():
		if _cooldowns.has(key):
			continue
		var stone: WarpStone = _warps_by_key.get(_locks[key])
		var still := false
		for b in bodies:
			if b["key"] == key and stone != null and stone.covers(b["feet"] as Vector3):
				still = true
		if not still:
			_locks.erase(key)


# --- 記録と配信 ------------------------------------------------------------------


## チェックポイント・全員リセット用の記録（WorldSnapshot から）。
static func capture(w: GameWorld) -> Dictionary:
	var m := of(w)
	if m == null:
		return {}
	var door_states: Array = []
	for door in m.doors:
		door_states.append(door.capture_state())
	return {
		"plates": m.plates.map(func(p: PressurePlate) -> bool: return p.pressed),
		"levers": m.levers.map(func(l: SwitchLever) -> bool: return l.on),
		"doors": door_states,
		"locks": m._locks.duplicate(),
		"cooldowns": m._cooldowns.duplicate(),
	}


static func restore(w: GameWorld, state: Dictionary) -> void:
	var m := of(w)
	if m == null or state.is_empty():
		return
	var pressed := state.get("plates", []) as Array
	for i in mini(pressed.size(), m.plates.size()):
		m.plates[i].pressed = bool(pressed[i])
	var on := state.get("levers", []) as Array
	for i in mini(on.size(), m.levers.size()):
		m.levers[i].on = bool(on[i])
	var door_states := state.get("doors", []) as Array
	for i in mini(door_states.size(), m.doors.size()):
		m.doors[i].restore_state(door_states[i] as Array)
	m._locks.assign(state.get("locks", {}) as Dictionary)
	m._cooldowns.assign(state.get("cooldowns", {}) as Dictionary)
	m._tickets.clear()


## ホストが配る様子（WorldFrame の "mechanisms"）。
static func capture_frame(w: GameWorld) -> Dictionary:
	var m := of(w)
	if m == null:
		return {}
	var tickets := {}
	for player_id: int in m._tickets:
		tickets[player_id] = [m._tickets[player_id][0], m._tickets[player_id][1]]
	return {
		"plates": m.plates.map(func(p: PressurePlate) -> bool: return p.pressed),
		"levers": m.levers.map(func(l: SwitchLever) -> bool: return l.on),
		"doors": m.doors.map(func(d: SwitchDoor) -> float: return d.open_amount),
		"warps": m.warps.map(func(s: WarpStone) -> int: return s.flashes),
		"tickets": tickets,
	}


## 参加者の画面に反映する。通信から来た値なので、形と型を確かめてから使う。
static func apply_frame(w: GameWorld, data: Dictionary) -> void:
	var m := of(w)
	if m == null or data.is_empty():
		return
	var pressed := _list(data, "plates")
	for i in mini(pressed.size(), m.plates.size()):
		m.plates[i].pressed = bool(pressed[i])
	var on := _list(data, "levers")
	for i in mini(on.size(), m.levers.size()):
		m.levers[i].on = bool(on[i])
	var amounts := _list(data, "doors")
	for i in mini(amounts.size(), m.doors.size()):
		if typeof(amounts[i]) == TYPE_FLOAT:
			m.doors[i].set_remote_amount(float(amounts[i]))
	var flashes := _list(data, "warps")
	for i in mini(flashes.size(), m.warps.size()):
		if typeof(flashes[i]) == TYPE_INT and int(flashes[i]) > m.warps[i].flashes:
			m.warps[i].flashes = int(flashes[i])
			m.warps[i].show_flash()
	var tickets: Variant = data.get("tickets", {})
	if typeof(tickets) != TYPE_DICTIONARY or w.player == null:
		return
	m._follow_ticket((tickets as Dictionary).get(w.player.player_id))


static func _list(data: Dictionary, key: String) -> Array:
	var value: Variant = data.get(key, [])
	return value as Array if typeof(value) == TYPE_ARRAY else []


## 参加者: ホストが自分をワープさせた切符に従う（同じ切符には一度だけ）。
func _follow_ticket(ticket: Variant) -> void:
	if typeof(ticket) != TYPE_ARRAY or (ticket as Array).size() < 2:
		return
	var t := ticket as Array
	if typeof(t[0]) != TYPE_INT or typeof(t[1]) != TYPE_VECTOR3 or int(t[0]) == _applied_ticket:
		return
	_applied_ticket = int(t[0])
	world.player.global_position = t[1] as Vector3
	world.player.velocity = Vector3.ZERO
