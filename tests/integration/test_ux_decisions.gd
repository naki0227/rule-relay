extends TestCase
## 2026-11-23 の本人の判断（はじめての 10 分の通しの「本人に決めてほしいこと」）のうち、遊ぶ人の入力を通して
## 確かめるもの。入力はゲームと同じ PlayerInput を通す（Input.parse_input_event / Input.action_press）。
## - 単発で貸した W/A/S/D を起動した押し下げでは、自分は歩かない（「動かした瞬間は自分は歩かない」）。
##   押し続けると PlayerInput.WALK_AFTER_FIRE 秒の後にふつうに歩く
## ほかの 3 つ: カメラの支点は test_camera_pivot.gd、広場へ戻ったときの向きは test_portal_return.gd と
## tests/unit/test_portal_return.gd、拾った能力の行き先は test_first_ten_minutes.gd と
## test_throw_pickup_shuttle.gd。

const PROFILE := "zz_test_ux_decisions"
const BACK := RuleAction.Kind.BACK
## 1-3 の頂の上の石 2（縁から押し落とす石）。頂は高さ 4、南の縁は z = -7。
const SUMMIT_Y := 4.0
const SUMMIT_EDGE_Z := -7.0

var game: GameRoot


func before_each() -> void:
	ProgressStore.new().delete(PROFILE)
	InputMap.load_from_project_settings()
	InputMode.using_pad = false
	game = GameRoot.new()
	tree.root.add_child(game)
	InputMap.load_from_project_settings()
	game.start_solo(PROFILE)
	await wait_physics_frames(5)
	game.director.enter_stage("w1_lift_steps")
	await wait_physics_frames(5)


func after_each() -> void:
	Input.action_release(&"move_back")
	game.shutdown()
	game.queue_free()
	await tree.process_frame
	ProgressStore.new().delete(PROFILE)
	for path: String in ["user://hints/%s.json" % PROFILE, "user://hints/%s.json.tmp" % PROFILE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _w() -> StageWorld:
	return game.director.world


func _stone() -> RuleBlock:
	return _w().blocks[int(_w().entity_ids["stone_high"])]


## 頂の上の at に、北（-Z）を向いて立つ（S で歩くと南の縁へ向かう）。
func _stand(at: Vector3) -> void:
	var me := _w().player
	me.global_position = at
	me.velocity = Vector3.ZERO
	_w().camera_rig.yaw = 0.0
	await wait_physics_frames(6)


## 石 2 に S を単発で渡す。
func _lend_s_to_the_stone() -> void:
	var w := _w()
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(slot, w.acting_id())
		if v != null and w.ledger.token(v.token_id).action == BACK:
			w.select_slot(slot)
	w.set_lend_mode(TriggerMode.Kind.SINGLE_SHOT)
	assert_eq(w.lend_to(_stone(), false), RuleLedger.LendResult.OK, "lent S to the stone")
	assert_eq(w.ledger.pending_single_shots(BACK, w.acting_id()).size(), 1)


## S のキーを押す（PlayerInput が受け取る押し下げ）。
func _key(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## 崖の縁（南の縁の 0.5 m 手前）で、貸した S を押して石を動かしても、自分は縁へ歩かない。
func test_pushing_a_stone_at_the_cliff_edge_leaves_the_player_in_place() -> void:
	await _stand(Vector3(-2.5, SUMMIT_Y, SUMMIT_EDGE_Z - 0.5))
	await _lend_s_to_the_stone()
	var start := _w().player.global_position
	var stone_start := _stone().global_position
	_key(&"move_back", true)
	await wait_physics_frames(8)  # ふつうのタップ（0.13 秒）
	assert_true(game.current_input().walk_held_back(&"move_back"), "this press does not walk")
	_key(&"move_back", false)
	await wait_physics_frames(40)
	var me := _w().player
	assert_lt(_flat(me.global_position, start), 0.05, "stayed put at the edge")
	assert_almost(me.global_position.y, SUMMIT_Y, 0.1, "did not step off the cliff")
	assert_gt(_stone().global_position.z, stone_start.z + 0.5, "the stone moved one cell south")


## 押したまま持ち続けると、WALK_AFTER_FIRE 秒の後はふつうに歩く。離して押し直しても歩く。
func test_holding_the_key_after_the_push_walks() -> void:
	await _stand(Vector3(-2.5, SUMMIT_Y, -11.5))
	await _lend_s_to_the_stone()
	var start := _w().player.global_position
	_key(&"move_back", true)
	var frames_held_back := 0
	for i in int(PlayerInput.WALK_AFTER_FIRE * 60.0) + 30:
		await tree.physics_frame
		if game.current_input().walk_held_back(&"move_back"):
			frames_held_back += 1
	_key(&"move_back", false)
	await wait_physics_frames(10)
	var walked := _w().player.global_position.z - start.z
	assert_gt(walked, 0.5, "walked south while holding the key")
	assert_almost(
		float(frames_held_back), PlayerInput.WALK_AFTER_FIRE * 60.0, 3.0, "held back ~0.25 s"
	)
	# 貸した単発はもう戻っているので、押し直した S はふつうに歩く
	var again := _w().player.global_position
	_key(&"move_back", true)
	await wait_physics_frames(12)
	assert_false(game.current_input().walk_held_back(&"move_back"), "nothing lent: just walks")
	_key(&"move_back", false)
	await wait_physics_frames(4)
	assert_gt(_w().player.global_position.z, again.z + 0.2, "walked on the plain press")
