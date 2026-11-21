extends TestCase
## 足もとのブロックの禁止で使えない能力は、ホットバーの枠を「使えない」表示にする（2026-11-21 本人
## 「ホットバーも使えない表示にして」。docs/adr/0003 決定 7）。乗った・降りたらすぐ変わる。

const JUMP := RuleAction.Kind.JUMP
const JUMP_SLOT := 4

var island: PrototypeIsland
var hud: Hud
var pad: RuleBlock


func before_each() -> void:
	island = PrototypeIsland.new()
	tree.root.add_child(island)
	hud = Hud.new()
	hud.world = island
	tree.root.add_child(hud)
	pad = island.add_block(Vector3i(-4, 0, 1))
	await wait_physics_frames(8)


func after_each() -> void:
	hud.queue_free()
	island.queue_free()
	await tree.process_frame


func place_player(at: Vector3) -> void:
	island.player.global_position = at
	island.player.velocity = Vector3.ZERO
	await wait_physics_frames(6)


func slot(i: int) -> HotbarSlot:
	return hud.find_children("*", "HotbarSlot", true, false)[i] as HotbarSlot


func test_the_jump_slot_dims_while_standing_on_a_jump_banned_block() -> void:
	island.ledger.place_on_entity(JUMP, true, pad.entity_id)
	assert_false(slot(JUMP_SLOT).floor_banned)
	await place_player(pad.global_position + Vector3(0.0, 0.55, 0.0))
	assert_true(slot(JUMP_SLOT).floor_banned, "dimmed while on the block")
	assert_eq(hud.hotbar_descriptions()[JUMP_SLOT], "5: ジャンプ・足もとの禁止で使えない")
	assert_false(slot(0).floor_banned, "W is not touched")
	await place_player(Vector3(-3.5, 0.05, 3.5))
	assert_false(slot(JUMP_SLOT).floor_banned, "back to normal once off the block")
	assert_eq(hud.hotbar_descriptions()[JUMP_SLOT], "5: ジャンプ")


func test_the_slot_updates_when_a_ban_lands_on_the_block_under_you() -> void:
	await place_player(pad.global_position + Vector3(0.0, 0.55, 0.0))
	assert_false(slot(JUMP_SLOT).floor_banned)
	island.ledger.place_on_entity(JUMP, true, pad.entity_id)
	await wait_physics_frames(2)
	assert_true(slot(JUMP_SLOT).floor_banned, "the ban arriving under the feet shows at once")


func test_dash_and_move_slots_follow_their_own_bans() -> void:
	island.ledger.give_player_item(RuleAction.Kind.DASH, false, 8)
	island.ledger.place_on_entity(RuleAction.Kind.DASH, true, pad.entity_id)
	island.ledger.place_on_entity(RuleAction.Kind.FORWARD, true, pad.entity_id)
	await place_player(pad.global_position + Vector3(0.0, 0.55, 0.0))
	assert_true(slot(8).floor_banned, "dash is banned under the feet")
	assert_true(slot(0).floor_banned, "so is W")
	assert_false(slot(JUMP_SLOT).floor_banned, "jump is free here")


func test_a_ban_item_in_the_hotbar_is_not_marked() -> void:
	island.ledger.give_player_item(JUMP, true, 8)  # 自分の持っている「ジャンプ禁止」の器
	island.ledger.place_on_entity(JUMP, true, pad.entity_id)
	await place_player(pad.global_position + Vector3(0.0, 0.55, 0.0))
	assert_false(slot(8).floor_banned, "only abilities are dimmed, not ban items")
