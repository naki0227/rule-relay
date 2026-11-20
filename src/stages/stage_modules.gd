class_name StageModules
extends RefCounted
## 長いステージを「部屋」の組み合わせで作る部品（配置はすべて仮。docs/adr/0011）。
## 1つの部屋は、幅 7 マス（x = -3〜3）の通路を北（-Z）へ進む区画で、通路をふさぐ「壁」を
## その部屋の仕組みで越える。左右は高い壁（高さ 4）で囲み、回り込めないようにする。
## 部屋は南の端（z0）から入り、北の端の床（高さ 0）へ出る。次の部屋はそのすぐ北から始まる。
## 2つ目以降の部屋の入口にはチェックポイントを置く（1人が触れたらチーム共通）。
## 部屋の数でステージの長さを変えられるので、ステージ（＝テーマ・報酬・ハブの入口）を増やさずに長く遊べる。

## 部屋の種類。
enum Room {
	## 跳べない壁（高さ 2）。手前の窪みのブロックにジャンプを渡し、乗って越える
	JUMP_LEND,
	## 跳べない壁（高さ 2）の手前のブロックに、ジャンプとジャンプ禁止が付いている。
	## F で回収すると禁止が手元に来て自分が跳べなくなる → 禁止を別のブロックへ渡して手放す。
	## 壁の上の小段（高さ 1）は自分で跳ぶ
	LET_GO_OF_BAN,
	## 高い壁（高さ 3）。手前のブロックは信号でジャンプ×2。鐘を F で鳴らし、鳴っている間に乗る
	BELL_LIFT,
	## 跳べない壁（高さ 2）。落ちているジャンプブーツを拾って装備し、高く跳んで越える
	BOOTS,
	## 高い壁（高さ 3）。落ちているクライミンググローブを拾って装備し、壁を登る
	GLOVES,
	## 最後の部屋: 跳べない台（高さ 2）の上がゴール（ジャンプを渡したブロックで上がる）
	GOAL_PODIUM,
	## 最後の部屋: 底なしの谷の向こうの鐘を、発射台に「投げる」を渡して鳴らす（クリア条件は鐘）
	BELL_ACROSS_GAP,
	## 枝道の最後の部屋: 跳べない台（高さ 2・奥行き 5）の奥に鐘。上がって F で鳴らす（下からは届かない）
	ARM_BELL,
}

## 枝道の向き（中央の広場から）。
enum Arm { NORTH, EAST, WEST }

const HALF_WIDTH: int = 3
const WALL_HEIGHT: int = 4


## 部屋を並べてステージを作る。最後の部屋がゴール（GOAL_PODIUM か BELL_ACROSS_GAP）。
static func build(def: StageDef, rooms: Array[Room]) -> void:
	def.terrain_boxes.append([Vector3i(-HALF_WIDTH, -1, 1), Vector3i(HALF_WIDTH, -1, 5), "grass"])
	_walls(def, 5, 1)
	def.spawn_points = _spawns(Vector3(0.0, 0.0, 3.5))
	var z0 := 0
	for i in rooms.size():
		if i > 0:
			def.checkpoints.append(Vector3(-2.0, 0.0, float(z0) - 0.5))
		z0 -= _room_length(rooms[i])
		_add_room(def, rooms[i], z0 + _room_length(rooms[i]), "r%d" % i)


## 部屋ごとの長さ（マス）。
static func _room_length(room: Room) -> int:
	match room:
		Room.LET_GO_OF_BAN:
			return 12
		Room.BELL_LIFT:
			return 9
		Room.BELL_ACROSS_GAP:
			return 12
		Room.ARM_BELL:
			return 10
	return 8


## 部屋の南の端（z0）から北へ置く。z は北ほど小さい。
static func _add_room(def: StageDef, room: Room, z0: int, tag: String) -> void:
	var length := _room_length(room)
	var last := z0 - length + 1
	_walls(def, z0, last)
	match room:
		Room.JUMP_LEND:
			_lift_room(def, z0, last, tag, 2, [])
		Room.LET_GO_OF_BAN:
			_ban_room(def, z0, tag)
		Room.BELL_LIFT:
			var jumps: Array[StageDef.TokenSpec] = [
				StageDef.TokenSpec.new(RuleAction.Kind.JUMP, false, TriggerMode.Kind.SIGNAL),
				StageDef.TokenSpec.new(RuleAction.Kind.JUMP, false, TriggerMode.Kind.SIGNAL),
			]
			_lift_room(def, z0, last, tag, 3, jumps)
			def.bells.append(StageDef.BellSpec.new(tag + "_bell", Vector3(2.5, 0.0, z0 - 1.5)))
		Room.BOOTS:
			_floor(def, z0, last)
			_barrier(def, z0 - 5, z0 - 6, 2)
			_item(def, RuleAction.Kind.HIGH_JUMP, Vector3(-2.0, 0.0, z0 - 2.0), 4, "ジャンプブーツ")
		Room.GLOVES:
			_floor(def, z0, last)
			_barrier(def, z0 - 5, z0 - 6, 3)
			_item(def, RuleAction.Kind.CLIMB, Vector3(-2.0, 0.0, z0 - 2.0), 3, "クライミンググローブ")
		Room.GOAL_PODIUM:
			_lift_room(def, z0, last, tag, 2, [], true)
		Room.BELL_ACROSS_GAP:
			_bell_gap_room(def, z0, tag)
		Room.ARM_BELL:
			_arm_bell_room(def, z0, tag)


## 窪みのブロック（上面が床と同じ高さ）と、その北の壁。goal なら壁の上がゴール（北へ降りない）。
static func _lift_room(
	def: StageDef,
	z0: int,
	last: int,
	tag: String,
	height: int,
	tokens: Array[StageDef.TokenSpec],
	goal: bool = false
) -> void:
	var pit := Vector3i(0, -1, z0 - 4)
	_floor_with_pit(def, z0, last, pit)
	var top_z := z0 - 5
	var far_z := z0 - 7 if goal else z0 - 6
	_barrier(def, top_z, far_z, height)
	var lift := StageDef.BlockSpec.new(tag + "_lift", pit)
	lift.color = Color(0.7, 0.58, 0.86)
	lift.tokens = tokens
	def.blocks.append(lift)
	if goal:
		var size := Vector3(HALF_WIDTH * 2 + 1, 3.0, absf(far_z - top_z) + 1)
		def.clear_condition = ClearCondition.reach_height(
			AABB(Vector3(-HALF_WIDTH, height - 0.1, far_z), size), float(height)
		)


## 鐘の台: 窪みのブロックで上がる台（高さ 2、奥行き 5）。鐘は奥の端（下からは触れない距離）。
static func _arm_bell_room(def: StageDef, z0: int, tag: String) -> void:
	var pit := Vector3i(0, -1, z0 - 4)
	_floor_with_pit(def, z0, z0 - 9, pit)
	_barrier(def, z0 - 5, z0 - 9, 2)
	var lift := StageDef.BlockSpec.new(tag + "_lift", pit)
	lift.color = Color(0.7, 0.58, 0.86)
	def.blocks.append(lift)
	def.bells.append(StageDef.BellSpec.new(tag + "_bell", Vector3(0.5, 2.0, z0 - 8.5)))
	# 鳴らしたら広場へ戻れる台座（来た道の壁は逆からは越えられないため）
	def.return_pads.append(Vector3(-2.0, 2.0, z0 - 7.5))


## 手分けするステージ: 中央の広場（7×7）から北・東・西へ枝道を伸ばす。各枝道の最後は ARM_BELL。
## クリアは「すべての枝道の鐘を鳴らす」。ひとりなら順番に回り、協力なら手分けできる
## （流行った協力探索ゲームの「手分けして探して、合流する」。docs/adr/0011）。
static func build_arms(def: StageDef, arms: Dictionary) -> void:
	def.terrain_boxes.append(
		[Vector3i(-HALF_WIDTH, -1, -HALF_WIDTH), Vector3i(HALF_WIDTH, -1, HALF_WIDTH), "grass"]
	)
	def.spawn_points = _spawns(Vector3(0.0, 0.0, 2.5))
	var bells: Array[ClearCondition] = []
	for arm: int in arms:
		var local := StageDef.new()
		var rooms: Array = arms[arm]
		var z0 := -HALF_WIDTH - 1
		for i in rooms.size():
			if i > 0:
				local.checkpoints.append(Vector3(-2.0, 0.0, float(z0) - 0.5))
			var room := rooms[i] as Room
			_add_room(local, room, z0, "a%d_r%d" % [arm, i])
			z0 -= _room_length(room)
		_merge_rotated(def, local, arm as Arm)
		for bell in local.bells:
			bells.append(ClearCondition.activate(bell.key))
	def.clear_condition = ClearCondition.all_of(bells)


## 北向きに作った枝道を、向きに合わせて回して足す。
static func _merge_rotated(def: StageDef, local: StageDef, arm: Arm) -> void:
	for box: Array in local.terrain_boxes:
		var a := _turn_cell(box[0] as Vector3i, arm)
		var b := _turn_cell(box[1] as Vector3i, arm)
		def.terrain_boxes.append([_min3(a, b), _max3(a, b), box[2]])
	for block in local.blocks:
		block.cell = _turn_cell(block.cell, arm)
		block.launcher_direction = Vector3i(_turn_dir(Vector3(block.launcher_direction), arm))
		def.blocks.append(block)
	for bell in local.bells:
		bell.position = _turn_point(bell.position, arm)
		def.bells.append(bell)
	for item in local.world_items:
		item.position = _turn_point(item.position, arm)
		def.world_items.append(item)
	for cp in local.checkpoints:
		def.checkpoints.append(_turn_point(cp, arm))
	for pad in local.return_pads:
		def.return_pads.append(_turn_point(pad, arm))


## マス目の回転（北の -Z を、東なら +X、西なら -X へ）。
static func _turn_cell(c: Vector3i, arm: Arm) -> Vector3i:
	match arm:
		Arm.EAST:
			return Vector3i(-c.z - 1, c.y, c.x)
		Arm.WEST:
			return Vector3i(c.z, c.y, -c.x - 1)
	return c


## 位置の回転（マス目の回転と同じ向き。連続した座標）。
static func _turn_point(p: Vector3, arm: Arm) -> Vector3:
	match arm:
		Arm.EAST:
			return Vector3(-p.z, p.y, p.x)
		Arm.WEST:
			return Vector3(p.z, p.y, -p.x)
	return p


static func _turn_dir(d: Vector3, arm: Arm) -> Vector3:
	return _turn_point(d, arm)


static func _min3(a: Vector3i, b: Vector3i) -> Vector3i:
	return Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z))


static func _max3(a: Vector3i, b: Vector3i) -> Vector3i:
	return Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))


static func _ban_room(def: StageDef, z0: int, tag: String) -> void:
	var tokens: Array[StageDef.TokenSpec] = [
		StageDef.TokenSpec.new(RuleAction.Kind.JUMP, false, TriggerMode.Kind.REPEAT),
		StageDef.TokenSpec.new(RuleAction.Kind.JUMP, true),
	]
	var pit := Vector3i(0, -1, z0 - 4)
	_floor_with_pit(def, z0, z0 - 11, pit)
	# 壁（高さ 2）の上は台地で、その先に自分で跳ぶ小段（高さ 3）、越えたら床へ降りる
	_barrier(def, z0 - 5, z0 - 8, 2)
	_barrier(def, z0 - 9, z0 - 9, 3)
	var lift := StageDef.BlockSpec.new(tag + "_lift", pit)
	lift.color = Color(0.7, 0.58, 0.86)
	lift.tokens = tokens
	def.blocks.append(lift)
	# 禁止を手放す先（入口の近く）
	def.blocks.append(StageDef.BlockSpec.new(tag + "_decoy", Vector3i(2, 0, z0 - 2)))


static func _bell_gap_room(def: StageDef, z0: int, tag: String) -> void:
	_floor(def, z0, z0 - 4)
	# z0-5〜z0-8 は底なしの谷。その向こうの小島に鐘
	def.terrain_boxes.append(
		[Vector3i(-HALF_WIDTH, -1, z0 - 11), Vector3i(HALF_WIDTH, -1, z0 - 9), "grass"]
	)
	var launcher := StageDef.BlockSpec.new(tag + "_launcher", Vector3i(0, 0, z0 - 3))
	launcher.launcher_direction = Vector3i(0, 0, -1)
	def.blocks.append(launcher)
	var bell_key := tag + "_bell"
	def.bells.append(StageDef.BellSpec.new(bell_key, Vector3(0.5, 0.0, z0 - 8.5)))
	def.clear_condition = ClearCondition.activate(bell_key)


static func _floor(def: StageDef, z0: int, last: int) -> void:
	def.terrain_boxes.append(
		[Vector3i(-HALF_WIDTH, -1, last), Vector3i(HALF_WIDTH, -1, z0), "grass"]
	)


static func _floor_with_pit(def: StageDef, z0: int, last: int, pit: Vector3i) -> void:
	def.terrain_boxes.append(
		[Vector3i(-HALF_WIDTH, -1, pit.z + 1), Vector3i(HALF_WIDTH, -1, z0), "grass"]
	)
	def.terrain_boxes.append(
		[Vector3i(-HALF_WIDTH, -1, last), Vector3i(HALF_WIDTH, -1, pit.z - 1), "grass"]
	)
	def.terrain_boxes.append(
		[Vector3i(-HALF_WIDTH, -1, pit.z), Vector3i(pit.x - 1, -1, pit.z), "grass"]
	)
	def.terrain_boxes.append(
		[Vector3i(pit.x + 1, -1, pit.z), Vector3i(HALF_WIDTH, -1, pit.z), "grass"]
	)
	def.terrain_boxes.append([pit + Vector3i(0, -1, 0), pit + Vector3i(0, -1, 0), "rock"])


## 通路をふさぐ壁（z_south〜z_north、高さ height。上面が height）。
static func _barrier(def: StageDef, z_south: int, z_north: int, height: int) -> void:
	def.terrain_boxes.append(
		[Vector3i(-HALF_WIDTH, 0, z_north), Vector3i(HALF_WIDTH, height - 1, z_south), "rock"]
	)


## 通路の左右の高い壁。
static func _walls(def: StageDef, z0: int, last: int) -> void:
	for x: int in [-HALF_WIDTH - 1, HALF_WIDTH + 1]:
		def.terrain_boxes.append([Vector3i(x, -1, last), Vector3i(x, WALL_HEIGHT - 1, z0), "rock"])


static func _item(
	def: StageDef, action: RuleAction.Kind, at: Vector3, part: int, item_name: String
) -> void:
	var spec := StageDef.PlacementSpec.in_world(action, at)
	spec.part = part as RuleVessel.Part
	spec.item_name = item_name
	def.world_items.append(spec)


static func _spawns(center: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for dx: float in [-1.5, -0.5, 0.5, 1.5]:
		result.append(center + Vector3(dx, 0.0, 0.0))
	return result
