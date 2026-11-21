extends RefCounted
## スイッチの仕掛け（docs/adr/0014）の見本の配置。結合テストだけが使う（キャンペーンのステージではない。
## ファイル名が test_ で始まらないので、これ自体は実行されない）。StageCatalog.test_stages に登録すると、
## PartyDirector（1人用も協力も）で入れる。
##
## 平らな草の島（上面 y = 0、x・z は -10〜10）。z = -4 に高さ 2 の岩の壁があり、4 つの扉で北へ抜ける:
## - x = -6 duo_gate: 2 枚の板（plate_l・plate_r）を同時に押している間だけ開く（2 人で、または人とブロックで）
## - x = -3 toggle_gate: 板 plate_t を踏むたびに開く ↔ 閉じる（切り替えの扉。降りても開いたまま）
## - x =  0 gate: 板 plate_a を押している間だけ開く。南のブロック crate を板に乗せれば、ひとりでも抜けられる
## - x =  6 lever_gate: レバー lever が入っている間だけ開く（レバー自体が持続のスイッチ）
## - x =  9 bell_gate: 時の鐘 clock（2 秒）が鳴っている間だけ開く
## ほかに: 押すと半径 3 に音波を出す板 pulse_plate とブロック pusher、時の鐘の近くのブロック chime、
## ワープの石 warp_a ↔ warp_b（壁の南北）と、片道の warp_one → warp_exit（出口だけの石）、生き物 critter。
## ゴールは壁の北（x -2〜2、z -9〜-6）。

const ID := "zz_switch_demo"

const PLATE_A := Vector3(2.5, 0.0, -0.5)
const PLATE_L := Vector3(-7.5, 0.0, -0.5)
const PLATE_R := Vector3(-3.5, 0.0, -0.5)
const PULSE_PLATE := Vector3(-7.5, 0.0, 5.5)
const PLATE_T := Vector3(-2.5, 0.0, 1.5)
const LEVER := Vector3(7.5, 0.0, -2.5)
const CLOCK := Vector3(9.5, 0.0, 1.5)
const CLOCK_TIME := 2.0
## ワープの石は島の東西の端（出現地点から板・レバー・鐘へ歩く道を踏まない場所）。
const WARP_A := Vector3(-8.5, 0.0, 2.5)
const WARP_B := Vector3(-8.5, 0.0, -7.5)
const WARP_ONE := Vector3(9.5, 0.0, 8.5)
const WARP_EXIT := Vector3(9.5, 0.0, -7.5)
## 扉の南・北の立ち位置（x は扉の列の中心）。
const SOUTH_Z := -2.5
const NORTH_Z := -6.0


static func register() -> void:
	StageCatalog.test_stages[ID] = build


static func unregister() -> void:
	StageCatalog.test_stages.erase(ID)


static func build() -> StageDef:
	var def := StageDef.new()
	def.stage_id = ID
	def.display_name = "スイッチの見本"
	def.target_minutes = 1
	def.terrain_boxes = [
		[Vector3i(-10, -1, -10), Vector3i(10, -1, 10), "grass"],
		[Vector3i(-10, 0, -4), Vector3i(-7, 1, -4), "rock"],
		[Vector3i(-5, 0, -4), Vector3i(-4, 1, -4), "rock"],
		[Vector3i(-2, 0, -4), Vector3i(-1, 1, -4), "rock"],
		[Vector3i(1, 0, -4), Vector3i(5, 1, -4), "rock"],
		[Vector3i(7, 0, -4), Vector3i(8, 1, -4), "rock"],
		[Vector3i(10, 0, -4), Vector3i(10, 1, -4), "rock"],
	]
	def.spawn_points = [
		Vector3(-1.5, 0.1, 8.5),
		Vector3(-0.5, 0.1, 9.5),
		Vector3(0.5, 0.1, 8.5),
		Vector3(1.5, 0.1, 9.5)
	]
	def.blocks = [
		StageDef.BlockSpec.new("crate", Vector3i(2, 0, 1)),
		StageDef.BlockSpec.new("pusher", Vector3i(-6, 0, 5)),
		StageDef.BlockSpec.new("chime", Vector3i(8, 0, 3)),
	]
	def.creatures = [StageDef.CreatureSpec.new("critter", Vector3(-9.5, 0.0, 9.5))]
	(
		def
		. set_loadout_for_all(
			[
				RuleAction.Kind.FORWARD,
				RuleAction.Kind.LEFT,
				RuleAction.Kind.BACK,
				RuleAction.Kind.RIGHT,
				RuleAction.Kind.JUMP,
			]
		)
	)
	def.clear_condition = ClearCondition.all_at_goal(
		AABB(Vector3(-2.0, -0.1, -9.0), Vector3(4.0, 3.0, 3.0))
	)
	_add_mechanisms(def.mechanisms)
	return def


static func _add_mechanisms(m: MechanismSpecs) -> void:
	m.plates = [
		MechanismSpecs.PlateSpec.new("plate_a", Vector3i(2, 0, -1)),
		MechanismSpecs.PlateSpec.new("plate_l", Vector3i(-8, 0, -1)),
		MechanismSpecs.PlateSpec.new("plate_r", Vector3i(-4, 0, -1)),
		MechanismSpecs.PlateSpec.new("pulse_plate", Vector3i(-8, 0, 5)),
		MechanismSpecs.PlateSpec.new("plate_t", Vector3i(-3, 0, 1)),
	]
	m.plates[3].signal_radius = 3.0
	m.levers = [MechanismSpecs.LeverSpec.new("lever", LEVER)]
	m.timed_bells = [MechanismSpecs.TimedBellSpec.new("clock", CLOCK, CLOCK_TIME)]
	var duo := MechanismSpecs.DoorSpec.new(
		"duo_gate", Vector3i(-6, 0, -4), PackedStringArray(["plate_l", "plate_r"])
	)
	duo.require_all = true
	var toggle := MechanismSpecs.DoorSpec.new(
		"toggle_gate", Vector3i(-3, 0, -4), PackedStringArray(["plate_t"])
	)
	toggle.mode = MechanismSpecs.DoorMode.TOGGLE
	m.doors = [
		duo,
		toggle,
		MechanismSpecs.DoorSpec.new("gate", Vector3i(0, 0, -4), PackedStringArray(["plate_a"])),
		MechanismSpecs.DoorSpec.new("lever_gate", Vector3i(6, 0, -4), PackedStringArray(["lever"])),
		MechanismSpecs.DoorSpec.new("bell_gate", Vector3i(9, 0, -4), PackedStringArray(["clock"])),
	]
	m.warps = [
		MechanismSpecs.WarpSpec.new("warp_a", Vector3i(-9, 0, 2), "warp_b"),
		MechanismSpecs.WarpSpec.new("warp_b", Vector3i(-9, 0, -8), "warp_a"),
		MechanismSpecs.WarpSpec.new("warp_one", Vector3i(9, 0, 8), "warp_exit"),
		MechanismSpecs.WarpSpec.new("warp_exit", Vector3i(9, 0, -8)),
	]
