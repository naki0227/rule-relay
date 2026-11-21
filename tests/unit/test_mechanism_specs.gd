extends TestCase
## スイッチの仕掛けの定義（MechanismSpecs）と、ノードを木に入れずに確かめられる判断（docs/adr/0014）。
## 板の重さ・扉の開け方（押している間／切り替え／逆）・石に乗っているか・扉に挟まないか。


func _def() -> StageDef:
	var def := StageDef.new()
	def.stage_id = "zz_unit"
	def.bells = [StageDef.BellSpec.new("bell", Vector3.ZERO)]
	return def


func test_an_empty_set_has_no_problems() -> void:
	var m := MechanismSpecs.new()
	assert_true(m.is_empty())
	assert_eq(m.problems(PackedStringArray(), PackedStringArray()), PackedStringArray())


func test_doors_may_listen_to_plates_levers_timed_bells_and_stage_bells() -> void:
	var def := _def()
	var m := def.mechanisms
	m.plates = [MechanismSpecs.PlateSpec.new("p", Vector3i.ZERO)]
	m.levers = [MechanismSpecs.LeverSpec.new("l", Vector3.ZERO)]
	m.timed_bells = [MechanismSpecs.TimedBellSpec.new("t", Vector3.ZERO, 2.0)]
	m.doors = [
		MechanismSpecs.DoorSpec.new(
			"d", Vector3i(0, 0, -2), PackedStringArray(["p", "l", "t", "bell"])
		)
	]
	assert_eq(m.problems(PackedStringArray(["bell"]), PackedStringArray(["bell"])).size(), 0)
	assert_false(def.problems().has("door d listens to unknown source bell"))


func test_bad_definitions_are_reported() -> void:
	var m := MechanismSpecs.new()
	m.plates = [MechanismSpecs.PlateSpec.new("dup", Vector3i.ZERO)]
	m.plates[0].required_weight = 0
	m.levers = [MechanismSpecs.LeverSpec.new("dup", Vector3.ZERO)]
	m.timed_bells = [MechanismSpecs.TimedBellSpec.new("t", Vector3.ZERO, 0.0)]
	m.doors = [
		MechanismSpecs.DoorSpec.new("d", Vector3i.ZERO, PackedStringArray(["nowhere"])),
		MechanismSpecs.DoorSpec.new("e", Vector3i.ZERO, PackedStringArray()),
	]
	m.warps = [
		MechanismSpecs.WarpSpec.new("w1", Vector3i.ZERO, "w1"),
		MechanismSpecs.WarpSpec.new("w2", Vector3i.ZERO, "missing"),
	]
	var errors := m.problems(PackedStringArray(["block"]), PackedStringArray())
	assert_true(errors.has("key dup is used twice"))
	assert_true(errors.has("plate dup needs a weight and a size"))
	assert_true(errors.has("timed bell t needs a ring time"))
	assert_true(errors.has("door d listens to unknown source nowhere"))
	assert_true(errors.has("door e has no source"))
	assert_true(errors.has("warp w1 has a bad partner w1"))
	assert_true(errors.has("warp w2 has a bad partner missing"))


func test_mechanism_keys_must_not_clash_with_stage_keys() -> void:
	var def := _def()
	def.mechanisms.plates = [MechanismSpecs.PlateSpec.new("bell", Vector3i.ZERO)]
	assert_true(def.problems().has("key bell is used twice"))


func test_a_one_way_warp_is_allowed() -> void:
	var m := MechanismSpecs.new()
	m.warps = [
		MechanismSpecs.WarpSpec.new("in", Vector3i.ZERO, "out"),
		MechanismSpecs.WarpSpec.new("out", Vector3i(5, 0, 0)),
	]
	assert_eq(m.problems(PackedStringArray(), PackedStringArray()), PackedStringArray())


# --- 板 -----------------------------------------------------------------------


func test_a_plate_counts_what_stands_on_it() -> void:
	var spec := MechanismSpecs.PlateSpec.new("p", Vector3i(2, 0, 3))
	spec.size = Vector2i(2, 1)
	spec.required_weight = 2
	var plate := PressurePlate.new()
	plate.setup(spec)
	assert_true(plate.covers(Vector3(2.1, 0.0, 3.5)))
	assert_true(plate.covers(Vector3(3.9, 0.2, 3.5)), "the footprint is 2 wide")
	assert_false(plate.covers(Vector3(4.1, 0.0, 3.5)))
	assert_false(plate.covers(Vector3(2.5, 0.6, 3.5)), "jumping over is not standing")
	var one: Array[Vector3] = [Vector3(2.5, 0.0, 3.5)]
	assert_false(plate.evaluate(one), "one is not heavy enough")
	assert_false(plate.pressed)
	var two: Array[Vector3] = [Vector3(2.5, 0.0, 3.5), Vector3(3.5, 0.0, 3.5)]
	assert_true(plate.evaluate(two), "two press it (changed)")
	assert_true(plate.pressed)
	assert_false(plate.evaluate(two), "no change while both stay")
	plate.free()


## 「重い」を持つもの1つで、2人分の板も沈む（BodyTraits.weight_units。2026-11-21 ギミック2本をつないだ）。
func test_one_heavy_body_presses_a_two_person_plate() -> void:
	var spec := MechanismSpecs.PlateSpec.new("p", Vector3i(0, 0, 0))
	spec.required_weight = 2
	var plate := PressurePlate.new()
	plate.setup(spec)
	var one: Array[Vector3] = [Vector3(0.5, 0.0, 0.5)]
	var light: Array[float] = [1.0]
	assert_false(plate.evaluate(one, light), "one light body is not enough")
	var heavy: Array[float] = [BodyTraits.weight_units(_heavy_ledger(), RuleLedger.PLAYER_ID)]
	assert_true(plate.evaluate(one, heavy), "one heavy body presses it")
	plate.free()


func _heavy_ledger() -> RuleLedger:
	var ledger := RuleLedger.new()
	ledger.give_player_item(RuleAction.Kind.HEAVY, false, 0)
	return ledger


# --- 扉 -----------------------------------------------------------------------


func _door(mode: MechanismSpecs.DoorMode, inverted: bool = false) -> SwitchDoor:
	var spec := MechanismSpecs.DoorSpec.new("d", Vector3i.ZERO, PackedStringArray(["s"]))
	spec.mode = mode
	spec.inverted = inverted
	var door := SwitchDoor.new()
	door.setup(spec)
	return door


func test_a_held_door_follows_its_input() -> void:
	var door := _door(MechanismSpecs.DoorMode.HELD)
	assert_false(door.wants_open(false))
	assert_true(door.wants_open(true))
	assert_false(door.wants_open(false))
	door.free()


func test_an_inverted_door_closes_while_its_input_is_on() -> void:
	var door := _door(MechanismSpecs.DoorMode.HELD, true)
	assert_true(door.wants_open(false))
	assert_false(door.wants_open(true))
	door.free()


func test_a_toggle_door_flips_on_each_new_press() -> void:
	var door := _door(MechanismSpecs.DoorMode.TOGGLE)
	assert_false(door.wants_open(false))
	assert_true(door.wants_open(true), "first press opens")
	assert_true(door.wants_open(true), "holding does not flip again")
	assert_true(door.wants_open(false), "releasing keeps it open")
	assert_false(door.wants_open(true), "the next press closes")
	door.free()


func test_a_closing_door_waits_while_occupied_but_opens_anyway() -> void:
	var door := _door(MechanismSpecs.DoorMode.HELD)
	door.open_amount = 1.0
	door.heading_open = true
	door.step(0.1, false, true)
	assert_almost(door.open_amount, 1.0, 0.001, "does not close on someone")
	door.step(0.1, false, false)
	assert_lt(door.open_amount, 1.0, "closes once clear")
	door.open_amount = 0.0
	door.step(0.1, true, true)
	assert_gt(door.open_amount, 0.0, "opening never waits")
	door.free()


func test_someone_in_the_doorway_is_found_by_the_middle_of_the_body() -> void:
	var box := AABB(Vector3(0, 0, -4), Vector3(1, 2, 1))
	var inside: Array[Dictionary] = [{"middle": Vector3(0.5, 0.9, -3.5), "radius": 0.3}]
	var beside: Array[Dictionary] = [{"middle": Vector3(1.2, 0.9, -3.5), "radius": 0.3}]
	var away: Array[Dictionary] = [{"middle": Vector3(1.5, 0.9, -3.5), "radius": 0.3}]
	var on_top: Array[Dictionary] = [{"middle": Vector3(0.5, 2.9, -3.5), "radius": 0.3}]
	assert_true(MechanismSet._occupied(box, inside))
	assert_true(MechanismSet._occupied(box, beside), "the body reaches into the doorway")
	assert_false(MechanismSet._occupied(box, away))
	assert_false(MechanismSet._occupied(box, on_top), "standing on a closed door is not inside")


# --- ワープの石 -------------------------------------------------------------------


func test_a_warp_stone_covers_its_one_cell() -> void:
	var stone := WarpStone.new()
	stone.setup(MechanismSpecs.WarpSpec.new("w", Vector3i(-2, 1, 3), "x"))
	assert_eq(stone.floor_point(), Vector3(-1.5, 1.0, 3.5))
	assert_true(stone.covers(Vector3(-1.9, 1.0, 3.1)))
	assert_false(stone.covers(Vector3(-0.9, 1.0, 3.1)))
	assert_false(stone.covers(Vector3(-1.5, 2.0, 3.5)), "standing above on something else")
	stone.free()
