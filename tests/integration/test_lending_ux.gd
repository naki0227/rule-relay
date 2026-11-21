extends "res://tests/integration/island_playthrough.gd"
## 渡しやすさ（2026-11-21、本人が「押し石の小道」（1-4）を初めて遊んだときの不満から）:
## - 照準の補助: 少し外れても、近くの生き物・ブロックを選ぶ。隠れているもの・届かないものは選ばない
## - 移動をもらった生き物は、上がれない段のふもとまで歩いて、吹き出しに「道が要る」（階段）を出す（動かないように見せない）

const BACK := RuleAction.Kind.BACK
const PATH_ID := "w1_push_path"
## 1-4 の子どもの生き物のふもと（原っぱの、段の壁のとなりの列）。
const KIT_FOOT := AABB(Vector3(-7.0, -0.2, 0.0), Vector3(15.0, 0.8, 1.0))
const LEDGE := AABB(Vector3(-7.0, 1.9, -6.0), Vector3(15.0, 1.0, 6.0))

var _toasts: PackedStringArray = []


func _enter_path() -> void:
	await _enter(PATH_ID)
	_toasts.clear()
	w.message_posted.connect(func(text: String) -> void: _toasts.append(text))


## 生き物についての知らせ（足りないものは吹き出しだけで見せ、知らせは出さない。2026-11-21 本人）。
func _creature_toasts() -> PackedStringArray:
	var found: PackedStringArray = []
	for text in _toasts:
		if text.contains("生き物"):
			found.append(text)
	return found


## カメラを from に置いて at を向け、その場で照準の先を調べる（同じフレームのうちに。
## カメラの台は次のフレームで元に戻す）。
func _aim_from(from: Vector3, at: Vector3) -> Node3D:
	var cam := w.camera_rig.camera()
	cam.global_position = from
	cam.look_at(at)
	# 肩越しのずれ（h_offset）の分だけカメラをずらして、照準（画面の中央）の光線が from から at を通るようにする
	cam.global_position = from - cam.global_basis.x * cam.h_offset
	return w.aimed_block()


## 画面の中央から point までの距離（画面の高さに対する割合）。
func _screen_offset(point: Vector3) -> float:
	var cam := w.camera_rig.camera()
	var size := cam.get_viewport().get_visible_rect().size
	return cam.unproject_position(point).distance_to(size * 0.5) / size.y


# --- 照準の補助 -------------------------------------------------------------------


## 生き物の少し横の地面を狙っても、生き物が選ばれる（地形のセルより優先）。
func test_aim_slightly_off_the_creature_still_selects_it() -> void:
	await _enter_path()
	var kit := _creature("kit")
	await _walk_to(kit.global_position + Vector3(2.0, 0.0, 1.0), 0.4)
	var center := AimAssist.aim_point(kit)
	var eye := center + Vector3(3.0, 4.5, 6.5)
	# 生き物のすぐ横（体の半径 0.3 より外）を通って、後ろの地面に当たる照準
	var beside := center + (center - eye).cross(Vector3.UP).normalized() * 0.45
	var target := _aim_from(eye, beside)
	assert_lt(_screen_offset(center), AimAssist.RADIUS_RATIO, "the kit is near the crosshair")
	assert_eq(target, kit, "the assist picked the kit instead of the ground")


## ブロック（窪みのブロック）も、少し外れた照準で選べる。
func test_aim_slightly_off_a_block_still_selects_it() -> void:
	await _enter_path()
	var lift := _block("meadow_lift")
	await _walk_to(lift.global_position + Vector3(2.0, 0.5, 1.5), 0.4)
	var top := lift.global_position + Vector3(0.0, 0.5, 0.0)
	var beside := top + Vector3(0.0, 0.0, 0.8)
	var target := _aim_from(top + Vector3(1.5, 4.5, 6.0), beside)
	assert_lt(_screen_offset(top), AimAssist.RADIUS_RATIO, "the lift is near the crosshair")
	assert_eq(target, lift, "the assist picked the lift block")


## 段の上から見て、段の縁の陰に隠れた生き物は選ばない（壁越しには渡せない）。地形のセルになる。
func test_aim_does_not_pick_an_occluded_creature() -> void:
	await _enter_path()
	var kit := _creature("kit")
	await _walk_to(kit.global_position + Vector3(1.5, 0.0, 0.0), 0.4)
	var center := AimAssist.aim_point(kit)
	var eye := Vector3(center.x, 2.5, -3.5)  # 段（高さ 2）の上。生き物は段の縁の陰
	assert_false(AimAssist.is_visible_from(w, eye, kit), "the ledge hides the kit")
	var target := _aim_from(eye, center)
	assert_ne(target, kit, "no lending through the ledge")
	assert_true(target is TerrainCell, "the ray hit the ledge itself")


## 届かない生き物は、照準の近くでも選ばない（届く距離の規則は変えない）。
func test_aim_does_not_pick_a_creature_out_of_reach() -> void:
	await _enter_path()
	var kit := _creature("kit")
	await _walk_to(Vector3(6.5, 0.0, 6.5), 0.4)
	assert_false(w.is_within_reach(kit), "too far to touch")
	var center := AimAssist.aim_point(kit)
	var target := _aim_from(center + Vector3(2.5, 3.5, 5.0), center + Vector3(0.5, -0.35, 0.0))
	assert_ne(target, kit)


## 近くに生き物もブロックも無ければ、これまでどおり地形のセルを狙える。
func test_aim_at_open_ground_still_targets_the_terrain_cell() -> void:
	await _enter_path()
	await _walk_to(Vector3(4.5, 0.0, 5.5), 0.4)
	var ground := Vector3(5.5, 0.0, 3.5)
	var target := _aim_from(ground + Vector3(1.0, 4.0, 4.0), ground)
	assert_true(target is TerrainCell, "a terrain cell")
	assert_eq((target as TerrainCell).cell, Vector3i(5, -1, 3))


# --- 移動をもらった生き物の見せ方（1-4） -------------------------------------------------


## 移動が無い生き物は、吹き出しに移動のメダルを出して待ち、狙うと「移動の能力を渡すと歩き出す」を出す（慣れるまで）。
func test_kit_without_a_move_asks_for_one() -> void:
	await _enter_path()
	var kit := _creature("kit")
	await wait_physics_frames(100)
	assert_eq(kit.bubble_key(), CreatureWishView.KEY_NEED_MOVE, "asks for a move")
	assert_eq(kit.shown_needs(), [FORWARD] as Array[RuleAction.Kind], "the move medal")
	assert_true(kit.shows_nest_in_bubble(), "and a tiny nest next to it")
	var hud := Hud.new()
	hud.world = w
	tree.root.add_child(hud)
	for key: String in ["move", "look"]:
		for i in HintMemory.LEARN_AFTER:
			hud.hints.used(key)
	hud.update_context(kit, true, false)
	assert_true(hud.context_actions().has("移動の能力を渡すと歩き出す"))
	assert_eq(hud.context_target_name(), "子どもの生き物", "names the aimed creature")
	for i in HintMemory.LEARN_AFTER:
		hud.hints.used("creature_move")
	hud.update_context(kit, true, false)
	assert_false(hud.context_actions().has("移動の能力を渡すと歩き出す"), "gone once learned")
	hud.queue_free()


## 移動（A。自分の W は歩くのに残す。生き物の W/A/S/D は向きが基準なので、どれでも同じに歩く）を渡すと、
## 段のふもとまで歩いて、吹き出しに「道が要る」（階段）を出す（知らせの文は出さない）。縁のセルを押して階段を作ると段へ上がり、
## 溝を埋めると巣まで行く。
func test_kit_walks_to_the_step_then_continues_once_the_path_is_built() -> void:
	await _enter_path()
	var kit := _creature("kit")
	var start := kit.global_position
	await _walk_to(kit.global_position + Vector3(1.4, 0.0, 0.0), 0.4)
	_lend(kit, _slot_of(LEFT), TriggerMode.Kind.NONE)
	assert_true(await _wait_creature_in("kit", KIT_FOOT, 400), "walked to the foot of the step")
	assert_lt(kit.global_position.distance_to(start), 4.0, "only a few steps along the meadow")
	for i in 300:
		if kit.is_stuck():
			break
		await tree.physics_frame
	assert_lt(kit.global_position.distance_to(start), 4.0, "stopped at the foot nearest the nest")
	assert_lt(kit.global_position.y, 0.3, "still on the meadow")
	assert_true(kit.is_stuck(), "stuck at the step")
	assert_eq(kit.bubble_key(), CreatureWishView.KEY_PATH, "stairs in the bubble")
	assert_true(kit.shown_needs().is_empty(), "no ability helps here")
	assert_true(_creature_toasts().is_empty(), "no toast: the bubble says it")
	# 階段を削る（段の縁のセルを南へ押す）
	await _walk_to(Vector3(1.5, 0.0, 0.5), 0.3)
	_lend(w.terrain_target(Vector3i(-1, 1, -1)), _slot_of(BACK), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(BACK)
	assert_true(await _wait_creature_in("kit", LEDGE, 900), "hopped up the carved stairs")
	# 段の上から、花畑の南の縁のセルを溝へ押し落とす
	await _walk_to(Vector3(-0.5, 1.0, 0.5))
	await _walk_to(Vector3(-0.5, 2.0, -2.5))
	await _walk_to(Vector3(5.5, 2.0, -5.6), 0.3)
	_lend(w.terrain_target(Vector3i(5, 2, -8)), _slot_of(BACK), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(BACK)
	assert_true(
		await _wait_creature_in("kit", OpenIslandsW1.PATH_NEST, 2400), "the kit reached its nest"
	)
	assert_true(_creature_toasts().is_empty(), "still no toast")
	await wait_physics_frames(30)
	assert_eq(kit.bubble_key(), CreatureWishView.KEY_HAPPY, "happy at the nest")
	var markers := w.find_children("WishMarker*", "WishMarker", false, false)
	var marker := markers[0] as WishMarker
	assert_false(marker.is_beam_shown(), "the nest beam goes away once the wish is met")
	assert_true(marker.nest_model().visible, "the nest itself stays: it is the kit's home")
	assert_false(kit.shows_nest_in_bubble(), "no nest in the bubble any more")
