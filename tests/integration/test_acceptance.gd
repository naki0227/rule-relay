extends TestCase
## 企画書 11「最低限の受け入れテスト」1〜7 を、番号どおりに島の上で確かめる。
## 個々の詳しい場合分けは、ほかのテスト（test_rule_ledger・test_island_mechanics など）にある。

const JUMP := RuleAction.Kind.JUMP
const JUMP_SLOT := 4

var island: PrototypeIsland


func before_each() -> void:
	island = PrototypeIsland.new()
	tree.root.add_child(island)
	await wait_physics_frames(10)


func after_each() -> void:
	island.queue_free()
	await tree.process_frame


func place_player(at: Vector3) -> void:
	island.player.global_position = at
	island.player.velocity = Vector3.ZERO
	island.player.move_intent = Vector2.ZERO
	island.player.view_yaw = 0.0
	await wait_physics_frames(6)


func jump_tokens() -> int:
	var count := 0
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := island.ledger.hotbar_vessel(slot)
		if v != null and island.ledger.token(v.token_id).action == JUMP:
			count += 1
	for v in island.ledger.inventory_vessels():
		if island.ledger.token(v.token_id).action == JUMP:
			count += 1
	return count


## 1. Jump トークンをブロックに貸すと、本人のジャンプは消え、対象だけが発動できる。器は残り複製されない。
func test_1_lending_jump_moves_the_token_and_keeps_the_vessel() -> void:
	var block := island.row[0]
	await place_player(block.global_position + Vector3(-1.5, -0.5, 1.5))
	island.select_slot(JUMP_SLOT)
	var vessel := island.selected_vessel()
	assert_eq(island.lend_to(block, false), RuleLedger.LendResult.OK)
	assert_false(island.ledger.player_can(JUMP), "the player's jump is gone")
	assert_true(island.ledger.can_initiate(block.entity_id, JUMP), "only the target can jump")
	assert_false(island.ledger.can_initiate(island.row[2].entity_id, JUMP))
	assert_eq(island.ledger.hotbar_vessel(JUMP_SLOT), vessel, "the vessel stays in slot 5")
	assert_eq(jump_tokens(), 1, "no copy was made")
	assert_true(island.ledger.validate().is_empty())


## 2. 中央ブロックだけジャンプ禁止なら、左右だけが同時に跳ぶ。
func test_2_only_the_prohibited_middle_stays_down() -> void:
	await place_player(Vector3(4.5, 0.0, -2.5))
	island.select_slot(JUMP_SLOT)
	assert_eq(island.lend_to(island.row[0], true), RuleLedger.LendResult.OK)
	island.press_action(JUMP)
	var takeoff := {}
	var tops := {}
	for i in 60:
		await tree.physics_frame
		for b in island.row:
			tops[b] = maxf(float(tops.get(b, 0.0)), b.global_position.y)
			if b.global_position.y > 0.55 and not takeoff.has(b):
				takeoff[b] = i
	assert_gt(float(tops[island.row[0]]), 1.5)
	assert_gt(float(tops[island.row[2]]), 1.5)
	assert_lt(float(tops[island.row[1]]), 0.6, "the middle one is prohibited")
	assert_eq(takeoff[island.row[0]], takeoff[island.row[2]], "left and right at the same time")


## 3. 半径内の1層の全ブロックだけが対象。生き物は範囲から能力を受け取らない。
func test_3_range_takes_every_block_of_one_layer_only() -> void:
	var stacked := island.add_block(Vector3i(4, 1, -5))  # 中央の上に積んだ（1つ上の層）
	await wait_physics_frames(10)
	island.creature.global_position = island.row[1].global_position + Vector3(0.0, -0.5, 1.5)
	await wait_physics_frames(5)
	var selection := island.range_selection(island.row[1])
	var ids := selection["ids"] as PackedInt32Array
	assert_false(ids.has(stacked.entity_id), "one layer up is not included")
	assert_false(ids.has(island.creature.entity_id), "creatures are never range targets")
	# 同じ層のブロックは、円の中なら「全部」入り、外なら入らない
	var center := island.row[1].global_position
	for id in island.blocks:
		var block := island.blocks[id]
		var flat := Vector2(block.global_position.x - center.x, block.global_position.z - center.z)
		var inside := flat.length() <= BlockRules.DEFAULT_RANGE_RADIUS + 0.01
		var same_layer := block.cell().y == island.row[1].cell().y
		assert_eq(ids.has(id), inside and same_layer, block.name)
	for b in island.row:
		assert_true(ids.has(b.entity_id), "%s is in the layer" % b.name)


## 5.3（受け入れテスト 3 の補足）範囲付与は、範囲内のどこからでも F で一括回収できる。
func test_3b_range_recall_with_f_from_the_edge() -> void:
	await place_player(Vector3(4.5, 0.0, -2.5))
	island.select_slot(JUMP_SLOT)
	island.set_lend_mode(TriggerMode.Kind.REPEAT)
	assert_eq(island.lend_to(island.row[0], true), RuleLedger.LendResult.OK)
	var t := island.ledger.token(island.selected_vessel().token_id)
	assert_gt(t.holder_ids.size(), 2)
	await place_player(Vector3(0.5, 0.0, -3.0))  # 範囲の中心から3.4ほど離れた端
	island.interact(null)  # どのブロックも狙っていない
	assert_false(t.is_lent(), "one F brings the single token back from every block")
	assert_true(island.ledger.player_can(JUMP))


## 4. 単発は対応キーで1回成功後に返る。繰り返し／信号は自動返還しない。音が途絶えても信号トークンは残る。
func test_4_single_shot_returns_repeat_and_signal_do_not() -> void:
	var block := island.row[0]
	await place_player(block.global_position + Vector3(-1.5, -0.5, 1.5))
	island.select_slot(JUMP_SLOT)
	island.set_lend_mode(TriggerMode.Kind.SINGLE_SHOT)
	island.lend_to(block, false)
	await wait_physics_frames(20)
	var t := island.ledger.token(island.selected_vessel().token_id)
	assert_true(t.is_lent(), "not fired by itself after lending")
	island.press_action(JUMP)
	await wait_physics_frames(2)
	assert_false(t.is_lent(), "returned after one success")
	await wait_physics_frames(80)

	island.set_lend_mode(TriggerMode.Kind.REPEAT)
	island.lend_to(block, false)
	await wait_physics_frames(int(60 * Tuning.REPEAT_PERIOD * 2.5))
	assert_true(t.is_lent(), "repeat keeps it")
	island.ledger.recall(t.id)
	await wait_physics_frames(80)

	island.set_lend_mode(TriggerMode.Kind.SIGNAL)
	island.lend_to(block, false)
	await wait_physics_frames(int(60 * Tuning.REPEAT_PERIOD * 2.0))
	assert_true(t.is_lent(), "signal keeps it while sounding")
	island.sound_source.teleport(Vector3(-8.5, 0.5, 4.5), 0.0)
	await wait_physics_frames(int(60 * Tuning.REPEAT_PERIOD * 2.0))
	assert_false(island.is_receiving_signal(block.entity_id))
	assert_true(t.is_lent(), "the sound stopped, the signal token stays")


## 4 の補足（2026-11-19 本人の判断）: 発動できない単発（ジャンプ禁止のブロックに渡した）も、
## 起動したら発動したのと同じ扱いで戻る。
func test_4b_single_shot_that_cannot_fire_still_comes_back() -> void:
	var middle := island.row[1]
	await place_player(middle.global_position + Vector3(0.0, -0.5, 1.5))
	island.select_slot(JUMP_SLOT)
	island.set_lend_mode(TriggerMode.Kind.SINGLE_SHOT)
	assert_eq(island.lend_to(middle, false), RuleLedger.LendResult.OK)
	assert_false(island.ledger.player_can(JUMP))
	island.press_action(JUMP)
	await wait_physics_frames(30)
	assert_lt(middle.global_position.y, 0.6, "prohibited: it did not jump")
	assert_true(island.ledger.player_can(JUMP), "but the jump came back")


## 5. 通常インベントリの能力は本人に効かず、禁止はどこにあっても効く。ホットバーは9枠。
func test_5_bag_abilities_do_nothing_and_prohibitions_bind_anywhere() -> void:
	var jump_vessel := island.ledger.hotbar_vessel(JUMP_SLOT)
	island.ledger.move_to_inventory(jump_vessel.id)
	assert_false(island.ledger.player_can(JUMP), "an ability in the bag does not work")
	island.ledger.move_to_hotbar(jump_vessel.id, JUMP_SLOT)
	assert_true(island.ledger.player_can(JUMP))
	await place_player(island.row[1].global_position + Vector3(0.0, -0.5, 1.5))
	island.interact(island.row[1])  # 中央の「ジャンプ禁止」を拾う → 通常インベントリへ
	assert_false(island.ledger.player_can(JUMP), "the prohibition binds from the bag")
	for v in island.ledger.inventory_vessels():
		var t := island.ledger.token(v.token_id)
		if t.is_prohibition:
			island.ledger.move_to_hotbar(v.id, 8)
	assert_false(island.ledger.player_can(JUMP), "and from the hotbar")
	assert_eq(RuleLedger.HOTBAR_SIZE, 9)
	assert_false(island.ledger.move_to_hotbar(jump_vessel.id, 9), "no tenth slot")


## 6. F 保存 → 地形・能力を変更 → Esc 復帰で、すべて保存時点に戻る。
func test_6_save_change_restore_brings_back_everything() -> void:
	await place_player(island.checkpoint_center)
	island.player.velocity = Vector3.ZERO
	await wait_physics_frames(5)
	island.interact(null)  # チェックポイントで F
	assert_eq(island.checkpoint_save_count(), 1)
	var saved_ledger := JSON.stringify(island.ledger.snapshot(), "", true)
	var mover_cell := island.mover.cell()
	var creature_at := island.creature.global_position
	# 世界を変える: W を渡して青緑を動かす、生き物にジャンプ、ブーツを拾う
	await place_player(island.mover.global_position + Vector3(-1.5, -0.5, 0.0))
	island.select_slot(0)
	island.set_lend_mode(TriggerMode.Kind.REPEAT)
	island.lend_to(island.mover, false)
	island.select_slot(JUMP_SLOT)
	await place_player(island.creature.global_position + Vector3(-1.5, 0.0, 0.0))
	island.lend_to(island.creature, false)
	await place_player(PrototypeIsland.BOOTS_AT)
	island.interact(null)
	await wait_physics_frames(int(60 * Tuning.REPEAT_PERIOD * 3))
	assert_ne(island.mover.cell(), mover_cell)
	# Esc（メニュー）でチェックポイントへ
	island.restore_checkpoint()
	await wait_physics_frames(3)
	assert_eq(JSON.stringify(island.ledger.snapshot(), "", true), saved_ledger, "all tokens back")
	assert_eq(island.mover.cell(), mover_cell, "terrain back")
	assert_lt(island.creature.global_position.distance_to(creature_at), 0.1, "creature back")
	assert_lt(island.player.global_position.distance_to(island.checkpoint_center), 0.2)
	assert_eq(island.nearest_world_item(), null, "boots are back on the islet, not here")
	assert_eq(island.ledger.world_vessels().size(), 2)
	assert_true(island.ledger.validate().is_empty())


## 7. 手動の正解手順以外で高台に到達してもクリアできる（到達を評価する）。
## ここでは「装備で登る」と「ジャンプ禁止を拾って跳ねる足場に乗る」の2通り（ほかは test_island_mechanics）。
func test_7a_goal_by_climbing_with_gloves() -> void:
	await place_player(PrototypeIsland.GLOVES_AT)
	var gloves := island.nearest_world_item()
	island.interact(null)
	assert_eq(island.ledger.equip(gloves.id), RuleLedger.EquipResult.OK)
	await place_player(Vector3(2.5, 0.0, -4.3))
	for i in 300:
		island.player.move_intent = Vector2(0.0, 1.0)
		await tree.physics_frame
		if island.goal_cleared:
			break
	assert_true(island.goal_cleared)


func test_7b_goal_by_riding_the_bouncer_while_prohibited() -> void:
	await place_player(Vector3(0.5, 0.0, -6.0))
	island.interact(island.bouncer)
	assert_false(island.ledger.player_can(JUMP), "the player cannot jump at all")
	await place_player(island.bouncer.global_position + Vector3(0.0, 0.5, 0.0))
	for i in 400:
		await tree.physics_frame
		var high := island.player.global_position.y > 2.6
		island.player.move_intent = Vector2(1.0, 0.0) if high else Vector2.ZERO
		if island.goal_cleared:
			break
	assert_true(island.goal_cleared)
