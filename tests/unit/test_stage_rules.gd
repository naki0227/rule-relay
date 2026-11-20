extends TestCase
## ステージの定義・クリア条件・開始時の配置・人数別補助・ステージ終了（2026-11-20 引き継ぎ仕様 2-3・2-6〜2-8・
## 3.1・6、受け入れ 10・17・23）。ルール層だけを検査する（物理・ノードは使わない）。

const JUMP := RuleAction.Kind.JUMP
const THROW := RuleAction.Kind.THROW
const FORWARD := RuleAction.Kind.FORWARD
const SINGLE := TriggerMode.Kind.SINGLE_SHOT
const REPEAT := TriggerMode.Kind.REPEAT
const OK := RuleLedger.LendResult.OK
const A := RuleLedger.PLAYER_ID
const B := 2
const C := 3
const D := 4

var ledger: RuleLedger


func before_each() -> void:
	ledger = RuleLedger.new()


func _valid() -> void:
	assert_true(ledger.validate().is_empty(), str(ledger.validate()))


func _join(ids: Array[int]) -> PackedInt32Array:
	for id in ids:
		if id != A:
			ledger.register_player(id)
	return PackedInt32Array(ids)


func _start(def: StageDef, ids: Array[int]) -> StageLoadout:
	var players := _join(ids)
	var loadout := StageLoadout.new(def, StageLoadout.register_entities(ledger, def))
	loadout.apply(ledger, players)
	return loadout


func _count(action: RuleAction.Kind) -> int:
	var n := 0
	for t in ledger.all_tokens():
		if t.action == action:
			n += 1
	return n


func _snapshot(positions: Dictionary, active: Array[int]) -> Dictionary:
	return {"positions": positions, "active": PackedInt32Array(active)}


# --- クリア条件 ---------------------------------------------------------------


func test_reach_height_needs_an_active_player_high_inside_the_area() -> void:
	var c := ClearCondition.reach_height(AABB(Vector3(0, 0, 0), Vector3(4, 5, 4)), 2.0)
	assert_true(c.is_met(_snapshot({A: Vector3(1, 2, 1)}, [A])), "on the ledge")
	assert_true(c.is_met(_snapshot({A: Vector3(1, 1.97, 1)}, [A])), "physics sinks a little")
	assert_false(c.is_met(_snapshot({A: Vector3(1, 1.5, 1)}, [A])), "too low")
	assert_false(c.is_met(_snapshot({A: Vector3(6, 3, 1)}, [A])), "high but elsewhere")
	assert_true(c.is_met(_snapshot({A: Vector3(1, 0, 1), B: Vector3(2, 2, 2)}, [A, B])), "anyone")


func test_reach_height_ignores_dead_spectators() -> void:
	var c := ClearCondition.reach_height(AABB(Vector3(0, 0, 0), Vector3(4, 5, 4)), 2.0)
	var positions := {A: Vector3(1, 2, 1), B: Vector3(9, 0, 9)}
	assert_false(c.is_met(_snapshot(positions, [B])), "A's body is up there but A is dead")
	assert_false(c.is_met(_snapshot(positions, [])), "nobody alive")


func test_all_at_goal_requires_every_active_player() -> void:
	var c := ClearCondition.all_at_goal(AABB(Vector3(0, 0, 0), Vector3(4, 3, 4)))
	var inside := Vector3(1, 1, 1)
	var outside := Vector3(8, 0, 8)
	assert_true(c.is_met(_snapshot({A: inside, B: inside}, [A, B])))
	assert_false(c.is_met(_snapshot({A: inside, B: outside}, [A, B])), "one at goal is not enough")
	assert_false(c.is_met(_snapshot({A: inside}, [A, B])), "an active player without a body")
	assert_false(c.is_met(_snapshot({}, [])), "nobody alive never clears")


func test_all_at_goal_does_not_wait_for_dead_spectators() -> void:
	# 4人のうち3人が死亡観戦。最後の1人がゴールに入ればクリア（受け入れ 17）
	var c := ClearCondition.all_at_goal(AABB(Vector3(0, 0, 0), Vector3(4, 3, 4)))
	var positions := {
		A: Vector3(9, -5, 9), B: Vector3(9, 0, 9), C: Vector3(9, 0, 9), D: Vector3(1, 1, 1)
	}
	assert_true(c.is_met(_snapshot(positions, [D])))
	assert_false(c.is_met(_snapshot(positions, [C, D])), "a living player outside")


## ゴールにまだ来ていない人（試遊 G5。HUD の情報だけ）。2人で1人がゴールにいれば、もう1人の ID。
## 2人ともいれば空。ゴールだけの条件で誰も入っていなければ出さない。島の条件がそろえば出す。
func test_goal_stragglers_for_two_players() -> void:
	var goal := AABB(Vector3(0, 0, 0), Vector3(4, 3, 4))
	var c := ClearCondition.all_at_goal(goal)
	var inside := Vector3(1, 1, 1)
	var outside := Vector3(8, 0, 8)
	assert_eq(c.goal_stragglers(_snapshot({A: inside, B: outside}, [A, B])), _ids([B]))
	assert_eq(c.goal_stragglers(_snapshot({A: inside, B: inside}, [A, B])), _ids([]))
	assert_eq(c.goal_stragglers(_snapshot({A: outside, B: outside}, [A, B])), _ids([]))
	assert_eq(c.goal_stragglers(_snapshot({A: inside, B: outside}, [A])), _ids([]), "B is dead")
	var bell := ClearCondition.all_of([ClearCondition.activate("bell"), c] as Array[ClearCondition])
	var snap := _snapshot({A: outside, B: outside}, [A, B])
	assert_eq(bell.goal_stragglers(snap), _ids([]), "bell not rung, nobody in the goal")
	snap["activated"] = PackedStringArray(["bell"])
	assert_eq(bell.goal_stragglers(snap), _ids([A, B]), "the island part is done")
	assert_eq(ClearCondition.activate("bell").goal_stragglers(snap), _ids([]), "no goal")


func _ids(values: Array[int]) -> PackedInt32Array:
	return PackedInt32Array(values)


func test_carry_object_and_activate() -> void:
	var carry := ClearCondition.carry_object("crate", AABB(Vector3(0, 0, 0), Vector3(2, 2, 2)))
	assert_true(carry.is_met({"entities": {"crate": Vector3(1, 0.5, 1)}}))
	assert_false(carry.is_met({"entities": {"crate": Vector3(5, 0.5, 1)}}))
	assert_false(carry.is_met({"entities": {"other": Vector3(1, 0.5, 1)}}), "missing object")
	var ring := ClearCondition.activate("valley_bell")
	assert_false(ring.is_met({"activated": PackedStringArray()}))
	assert_false(ring.is_met({"activated": PackedStringArray(["other_bell"])}))
	assert_true(ring.is_met({"activated": PackedStringArray(["valley_bell"])}))
	assert_false(ClearCondition.none().is_met({"activated": PackedStringArray(["valley_bell"])}))


# --- 定義 ---------------------------------------------------------------------


func test_catalog_definitions_are_consistent() -> void:
	var defs := StageCatalog.all_stages()
	defs.append(StageCatalog.hub())
	for def in defs:
		assert_true(def.problems().is_empty(), "%s: %s" % [def.stage_id, def.problems()])
		assert_eq(StageCatalog.by_id(def.stage_id).stage_id, def.stage_id)
	assert_eq(StageCatalog.all_stages().size(), 12)
	var minutes: Array[int] = []
	for def in StageCatalog.all_stages():
		minutes.append(def.target_minutes)
	var sorted := minutes.duplicate()
	sorted.sort()
	assert_eq(minutes, sorted, "stages are listed from the shortest target time")
	assert_false(minutes.has(0), "every stage has a target time")
	assert_eq(StageCatalog.by_id("nope"), null)


## どのステージも「島の条件＋生きている全員がゴールに集まる」（docs/adr/0011 決定 9）。
## 島の条件（ゴール以外の部分）はステージごとに違う（ゴールだけ・鐘・要石を運ぶ）。
func test_stages_use_different_clear_conditions() -> void:
	var kinds := {}
	for def in StageCatalog.all_stages():
		assert_true(def.clear_condition.goal_area().has_volume(), "%s has a goal" % def.stage_id)
		if def.clear_condition.kind == ClearCondition.Kind.ALL_AT_GOAL:
			kinds[ClearCondition.Kind.NONE] = true
		for part in def.clear_condition.parts:
			if part.kind != ClearCondition.Kind.ALL_AT_GOAL:
				kinds[part.kind] = true
	assert_gt(kinds.size(), 2, "the stages' own conditions differ")
	assert_eq(StageCatalog.hub().clear_condition.kind, ClearCondition.Kind.NONE)
	assert_false(StageCatalog.hub().clear_condition.goal_area().has_volume(), "the hub has no goal")


func test_goal_area_is_found_inside_all_of() -> void:
	var goal := AABB(Vector3(0, 0, 0), Vector3(2, 3, 2))
	var parts: Array[ClearCondition] = [
		ClearCondition.activate("bell"), ClearCondition.all_at_goal(goal)
	]
	# 数える箱は、水平にカプセルの半径（0.3）だけ内側へ縮める（goal-probes G3）
	var counted := AABB(Vector3(0.3, 0, 0.3), Vector3(1.4, 3, 1.4))
	assert_eq(ClearCondition.all_of(parts).goal_area(), counted)
	assert_eq(ClearCondition.all_at_goal(goal).goal_area(), counted)
	assert_false(ClearCondition.activate("bell").goal_area().has_volume())


func test_hub_has_an_entrance_for_every_stage() -> void:
	var hub := StageCatalog.hub()
	assert_true(hub.is_hub())
	var ids := PackedStringArray()
	for e in hub.entrances:
		ids.append(e.stage_id)
		assert_true(e.area.has_point(e.position + Vector3(0, 0.5, 0)), "entrance inside its area")
		var ground: Array = hub.terrain_boxes[0]
		var on_ground := (
			e.position.x >= float((ground[0] as Vector3i).x)
			and e.position.x <= float((ground[1] as Vector3i).x + 1)
		)
		assert_true(on_ground, "entrance for %s stands on the hub ground" % e.stage_id)
	for def in StageCatalog.all_stages():
		assert_true(ids.has(def.stage_id), "entrance for %s" % def.stage_id)


func test_problems_reports_broken_definitions() -> void:
	var def := StageDef.new()
	def.blocks = [
		StageDef.BlockSpec.new("x", Vector3i.ZERO), StageDef.BlockSpec.new("x", Vector3i.ONE)
	]
	def.world_items = [StageDef.PlacementSpec.on_block(JUMP, "missing", REPEAT)]
	var text := str(def.problems())
	var expected_texts: Array[String] = [
		"stage_id", "spawn points", "used twice", "unknown block", "clear", "gather at a goal"
	]
	for expected in expected_texts:
		assert_true(text.contains(expected), "reports %s: %s" % [expected, text])


# --- 開始時の配置 -------------------------------------------------------------


func test_intro_loadout_for_one_to_four_players() -> void:
	var everyone: Array[int] = [A, B, C, D]
	for n in range(1, 5):
		ledger = RuleLedger.new()
		var ids: Array[int] = everyone.slice(0, n)
		var loadout := _start(StageCatalog.intro_jump_lend(), ids)
		for p in ids:
			for slot in 5:
				assert_ne(ledger.hotbar_vessel(slot, p), null, "%d players: slot %d" % [n, slot])
			assert_eq(
				PartyQuery.token_of_vessel(ledger, ledger.hotbar_vessel(4, p).id).action, JUMP
			)
			assert_true(ledger.player_can(JUMP, p))
			assert_false(ledger.player_has_ability(THROW, p), "no throw: lend by touch")
		assert_eq(ledger.all_tokens().size(), 5 * n, "%d players: no helpers in the intro" % n)
		assert_eq(loadout.headcount, n)
		_valid()


func test_bell_valley_prohibits_jump_for_everyone() -> void:
	_start(StageCatalog.bell_valley(), [A, B, C])
	for p: int in [A, B, C]:
		assert_true(ledger.player_prohibited(JUMP, p))
		assert_false(ledger.player_can(JUMP, p))
		assert_true(ledger.player_can(THROW, p))
	_valid()


func test_relay_helpers_depend_on_headcount() -> void:
	var expected := {1: 1, 2: 1, 3: 1, 4: 2}
	var everyone: Array[int] = [A, B, C, D]
	for n: int in expected:
		ledger = RuleLedger.new()
		var ids: Array[int] = everyone.slice(0, n)
		var loadout := _start(StageCatalog.relay_carry(), ids)
		assert_eq(loadout.helper_token_ids().size(), expected[n], "%d players" % n)
		assert_eq(ledger.world_vessels().size(), expected[n])
		assert_eq(_count(JUMP), expected[n], "jump exists only as helpers")
		for p in ids:
			assert_false(ledger.player_can(JUMP, p), "nobody starts with jump")
		_valid()


func test_block_and_creature_tokens_are_placed() -> void:
	var def := _helper_test_stage()
	var critter := StageDef.CreatureSpec.new("critter", Vector3(2, 0, 2))
	critter.tokens = [StageDef.TokenSpec.new(FORWARD)]
	def.creatures = [critter]
	def.blocks[0].tokens = [StageDef.TokenSpec.new(JUMP, true)]
	var loadout := _start(def, [A])
	assert_true(ledger.entity_prohibited(loadout.entity_ids["pad"], JUMP))
	assert_true(ledger.can_initiate(loadout.entity_ids["critter"], FORWARD))
	assert_eq(loadout.entity_ids["critter"], GameWorld.FIRST_CREATURE_ID, "same ids as GameWorld")
	assert_eq(loadout.entity_ids["pad"], GameWorld.FIRST_BLOCK_ID)
	_valid()


# --- 人数別補助の作り直し（受け入れ 10） ---------------------------------------


## 3人なら補助4個（世界3・ブロック1）、4人なら世界2個の試験用ステージ。
func _helper_test_stage() -> StageDef:
	var def := StageDef.new()
	def.stage_id = "helper_test"
	def.spawn_points = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	def.blocks = [StageDef.BlockSpec.new("pad", Vector3i(0, 0, 0))]
	def.blocks.append(StageDef.BlockSpec.new("pad2", Vector3i(1, 0, 0)))
	var hotbar: Array[RuleAction.Kind] = [FORWARD, JUMP]
	def.set_loadout_for_all(hotbar)
	var three := [
		StageDef.PlacementSpec.in_world(JUMP, Vector3(1, 0, 1)),
		StageDef.PlacementSpec.in_world(JUMP, Vector3(2, 0, 1)),
		StageDef.PlacementSpec.in_world(JUMP, Vector3(3, 0, 1)),
		StageDef.PlacementSpec.on_block(JUMP, "pad", REPEAT),
	]
	var four := [
		StageDef.PlacementSpec.in_world(THROW, Vector3(1, 0, 2)),
		StageDef.PlacementSpec.in_world(THROW, Vector3(2, 0, 2)),
	]
	def.helpers = {3: three, 4: four}
	def.clear_condition = ClearCondition.activate("x")
	return def


## 補助を「仲間の手元」「ブロックへ範囲で付与中」「束ねて持っている」「回収して器の中」にばらまく。
func _scatter_helpers(loadout: StageLoadout) -> void:
	var helpers := loadout.helper_token_ids()
	var world := ledger.world_vessels()
	assert_eq(world.size(), 3)
	# 1個目: A が拾ってホットバーへ → B へ渡す（B が器なしで持つ）
	ledger.pickup(world[0].id, A)
	ledger.move_to_hotbar(world[0].id, 8)
	assert_eq(ledger.give_to_player(world[0].token_id, A, B), OK)
	# 2個目: C が拾って2つのブロックへ範囲の単発で付与
	ledger.pickup(world[1].id, C)
	ledger.move_to_hotbar(world[1].id, 8)
	var pads := PackedInt32Array([loadout.entity_ids["pad"], loadout.entity_ids["pad2"]])
	var range_spec := {"center": Vector3(1, 0, 0), "radius": 2.0, "layer": 0}
	assert_eq(ledger.lend(world[1].id, pads, SINGLE, range_spec), OK)
	# 3個目: B が拾ってホットバーへ（受け取った1個と自分の1個と合わせて ×3）
	ledger.pickup(world[2].id, B)
	ledger.move_to_hotbar(world[2].id, 7)
	assert_eq(ledger.ability_count(JUMP, B), 3, "B stacks own + 2 helpers")
	# 4個目: ブロックに置かれた補助を A が F で回収（A の通常インベントリに器ができる）
	assert_true(ledger.recall(helpers[3], A))
	_valid()


func test_rebuild_helpers_three_to_four_removes_scattered_helpers() -> void:
	var loadout := _start(_helper_test_stage(), [A, B, C])
	var old_helpers := loadout.helper_token_ids()
	assert_eq(old_helpers.size(), 4)
	_scatter_helpers(loadout)
	# 4人目が入っても、その場では補助は変わらない（引き継ぎ仕様 2-7）
	ledger.register_player(D)
	assert_eq(loadout.helper_token_ids(), old_helpers, "no change until the full reset")
	var before := ledger.all_tokens().size()
	loadout.rebuild_helpers(ledger, 4)
	for id in old_helpers:
		assert_eq(ledger.token(id), null, "old helper %d is gone" % id)
	var fresh := loadout.helper_token_ids()
	assert_eq(fresh.size(), 2)
	for id in fresh:
		assert_false(old_helpers.has(id), "ids are not reused")
		assert_eq(ledger.token(id).action, THROW)
	assert_eq(ledger.all_tokens().size(), before - 4 + 2)
	assert_eq(_count(JUMP), 3, "only the players' own jumps remain")
	assert_eq(ledger.ability_count(JUMP, B), 1, "B's stack drops back to x1")
	assert_eq(ledger.tokens_on(loadout.entity_ids["pad"]).size(), 0, "range lend is gone")
	assert_eq(ledger.hotbar_vessel(8, A), null, "A's emptied slot is freed")
	assert_eq(ledger.inventory_vessels(A).size(), 0, "the recalled helper's vessel is gone")
	assert_eq(ledger.world_vessels().size(), 2)
	assert_eq(loadout.headcount, 4)
	_valid()


func test_rebuild_to_the_same_headcount_does_not_duplicate() -> void:
	var loadout := _start(StageCatalog.relay_carry(), [A, B])
	for i in 3:
		loadout.rebuild_helpers(ledger, 2)
	assert_eq(_count(JUMP), 1)
	assert_eq(loadout.helper_token_ids().size(), 1)
	_valid()


func test_helper_state_follows_a_checkpoint_restore() -> void:
	var loadout := _start(_helper_test_stage(), [A, B, C])
	var saved_ledger := ledger.snapshot()
	var saved_state := loadout.capture_state()
	loadout.rebuild_helpers(ledger, 4)
	# 全員リセット: 台帳と補助の記録を同じチェックポイントへ戻してから、いまの人数で作り直す
	ledger.restore(saved_ledger)
	loadout.restore_state(saved_state)
	assert_eq(loadout.helper_token_ids().size(), 4)
	ledger.register_player(D)
	loadout.rebuild_helpers(ledger, 4)
	assert_eq(_count(JUMP), 3, "the 3-player helpers from the checkpoint are removed too")
	assert_eq(_count(THROW), 2)
	_valid()


# --- ステージ終了（引き継ぎ仕様 2-8・受け入れ 23） ------------------------------


func test_end_stage_clears_every_stage_token() -> void:
	var loadout := _start(_helper_test_stage(), [A, B, C])
	_scatter_helpers(loadout)
	assert_eq(ledger.give_to_player(ledger.hotbar_vessel(1, C).token_id, C, A), OK)
	StageLoadout.end_stage(ledger)
	assert_eq(ledger.all_tokens().size(), 0, "nothing is carried out of the stage")
	assert_eq(ledger.all_vessels().size(), 0)
	assert_eq(ledger.players(), PackedInt32Array([A, B, C]), "players stay in the party")
	assert_false(ledger.has_entity(loadout.entity_ids["pad"]), "stage blocks are gone")
	for p: int in [A, B, C]:
		assert_eq(ledger.ability_count(JUMP, p), 0)
	_valid()
	# ハブへ戻って、そのまま次の配置ができる
	var hub := StageLoadout.new(StageCatalog.hub(), {})
	hub.apply(ledger, ledger.players())
	assert_true(ledger.player_can(JUMP, B))
	_valid()


func test_new_stage_after_end_stage_has_fresh_ids() -> void:
	var first := _start(StageCatalog.relay_carry(), [A, B])
	var old_ids := first.helper_token_ids()
	StageLoadout.end_stage(ledger)
	var def := StageCatalog.relay_carry()
	var second := StageLoadout.new(def, StageLoadout.register_entities(ledger, def))
	second.apply(ledger, ledger.players())
	for id in second.helper_token_ids():
		assert_false(old_ids.has(id), "token ids keep increasing across stages")
	_valid()


# --- 解けるかの目安（地形の高さと調整値だけ。物理は使わない） --------------------


## (x, z) の列で、いちばん上の地形の上面の高さ。地形が無ければ -INF。
func _top_at(def: StageDef, x: int, z: int) -> float:
	var top := -INF
	for box: Array in def.terrain_boxes:
		var lo := box[0] as Vector3i
		var hi := box[1] as Vector3i
		if x >= lo.x and x <= hi.x and z >= lo.z and z <= hi.z:
			top = maxf(top, float(hi.y + 1))
	return top


func _cell_is_free(def: StageDef, cell: Vector3i) -> bool:
	for box: Array in def.terrain_boxes:
		var lo := box[0] as Vector3i
		var hi := box[1] as Vector3i
		if AABB(Vector3(lo), Vector3(hi - lo + Vector3i.ONE)).has_point(
			Vector3(cell) + Vector3(0.5, 0.5, 0.5)
		):
			return false
	return true


func test_intro_geometry_teaches_lending_jump() -> void:
	var def := StageCatalog.intro_jump_lend()
	var ground := _top_at(def, 0, 4)
	var step := _top_at(def, 0, 0)
	var ledge := _top_at(def, 0, -6)
	assert_eq(ground, 0.0)
	assert_lt(step - ground, Tuning.PLAYER_JUMP_HEIGHT, "the small step can be jumped")
	assert_gt(ledge - ground, Tuning.PLAYER_JUMP_HEIGHT, "the ledge cannot be jumped")
	assert_gt(ledge - step, 0.0)
	assert_gt(_top_at(def, -4, 0), -INF, "the step can be walked around")
	assert_eq(_top_at(def, -4, 0), ground)
	# ブロックは窪みに収まり、上面が地面と同じ高さ（跳べなくても乗れる）
	var lift := def.block("lift").cell
	assert_true(_cell_is_free(def, lift), "the lift cell is not inside terrain")
	assert_eq(_top_at(def, lift.x, lift.z), float(lift.y), "the lift rests on the pit floor")
	assert_lt(absf(float(lift.y + 1) - ground), Tuning.STEP_ASSIST_HEIGHT, "walk onto the lift")
	# ブロックは岩棚の目の前で、乗ってジャンプすれば届く（余裕 0.4 以上）
	assert_eq(_top_at(def, lift.x, lift.z - 1), ledge, "the ledge is right behind the lift")
	assert_gt(float(lift.y + 1) + Tuning.BLOCK_JUMP_HEIGHT, ledge + 0.4)
	# ゴールは岩棚の上の窪み（1 段下げ、まわりに縁が残る）。全員がここに集まればクリア
	assert_eq(def.clear_condition.kind, ClearCondition.Kind.ALL_AT_GOAL)
	var goal := def.clear_condition.area
	var hollow := _top_at(def, 0, -8)
	assert_eq(hollow, ledge - 1.0, "the goal is one step below the ledge")
	assert_lt(ledge - hollow, Tuning.PLAYER_JUMP_HEIGHT, "own jump climbs out of the hollow")
	assert_gt(ledge - hollow, Tuning.STEP_ASSIST_HEIGHT, "not a mere step")
	# 南（登り口の側）の縁は 2 マス（goal-probes G1）。北・東西にも縁が残る
	for edge: Vector2i in [
		Vector2i(0, -10), Vector2i(-3, -8), Vector2i(3, -8), Vector2i(0, -7), Vector2i(0, -6)
	]:
		assert_eq(_top_at(def, edge.x, edge.y), ledge, "lip at %s" % edge)
	assert_true(goal.has_point(Vector3(0.5, hollow, -8.0)), "standing in the hollow")
	assert_false(goal.has_point(Vector3(0.5, ledge, -5.5)), "the lip is outside the goal")
	# 縁の角に乗って体の中心が窪みの上へ 0.22 出ても、ゴールに数えない（goal-probes G3）
	assert_false(goal.has_point(Vector3(0.5, ledge, -7.22)), "the rim corner is outside the goal")
	# 2人以上: ジャンプ×2 で自分で届く（到達高度は数に比例して 2.6）
	assert_gt(Tuning.PLAYER_JUMP_HEIGHT * 2.0, ledge - ground)
	var spawn := def.spawn_point(0)
	assert_eq(_top_at(def, floori(spawn.x), floori(spawn.z)), ground)


func test_relay_goal_is_one_jump_high_and_jump_is_shared() -> void:
	var def := StageCatalog.relay_carry()
	var rise := _top_at(def, 0, -5) - _top_at(def, 0, 0)
	assert_eq(rise, 1.0)
	assert_lt(rise, Tuning.PLAYER_JUMP_HEIGHT)
	for n in range(1, 5):
		assert_gt(def.helpers_for(n).size(), 0, "%d players get at least one jump" % n)
	assert_false(def.loadout_for(0).has(JUMP))


func test_bell_cannot_be_touched_from_the_shore() -> void:
	var def := StageCatalog.bell_valley()
	var bell := def.bells[0].position
	var chest_at_edge := Vector3(StageCatalog.BELL_SHORE_MAX_X + 1, 1.0, bell.z)
	assert_gt(chest_at_edge.distance_to(bell), Tuning.TOUCH_REACH + RuleBlock.SIZE * 0.5)
	for x in range(StageCatalog.BELL_SHORE_MAX_X + 1, floori(bell.x) - 1):
		assert_eq(_top_at(def, x, floori(bell.z)), -INF, "the valley at x=%d has no floor" % x)
	# 発射台は東向きで、鐘と同じ列・玉が届く距離（試作島と同程度の 5〜6 マス）
	var launcher := def.block("launcher")
	assert_eq(launcher.launcher_direction, Vector3i(1, 0, 0))
	assert_eq(float(launcher.cell.z) + 0.5, bell.z)
	assert_lt(bell.x - (float(launcher.cell.x) + 0.5), 6.5)
	assert_true(def.prohibitions.has(JUMP))
	assert_true(def.loadout_for(0).has(THROW))
