extends "res://tests/integration/island_playthrough.gd"
## 生き物の願いの見せ方（2026-11-21 本人「どうぶつがなにをもとめてるのかがわかりにくい」）:
## 行き先（巣）の光の柱と、画面の外なら縁の矢印・頭の上の足りない能力・近づいたときの願いの一文。
## 参加者の画面で同じに見えることは test_world1_coop.gd。

const BACK := RuleAction.Kind.BACK
const RIGHT := RuleAction.Kind.RIGHT
const PATH_ID := "w1_push_path"


func _marker() -> WishMarker:
	var found := w.find_children("WishMarker*", "WishMarker", false, false)
	return found[0] as WishMarker if not found.is_empty() else null


func test_kit_has_its_nest_and_a_default_wish() -> void:
	await _enter(PATH_ID)
	var kit := _creature("kit")
	assert_eq(kit.wish_box, OpenIslandsW1.PATH_NEST, "the nest from the clear condition")
	assert_eq(kit.wish_text(), "高いところの巣へ行きたい")
	var marker := _marker()
	assert_true(marker != null, "a beam over the nest")
	await wait_physics_frames(2)
	assert_true(marker.visible)
	assert_almost(marker.global_position.y, 4.0, 0.05, "on the nest floor (height 4)")


## ステージの定義の wish_text があれば、それを出す。
func test_stage_wish_text_overrides_the_default() -> void:
	var def := OpenIslandsW1.push_path()
	def.creatures[0].wish_text = "お花畑の向こうへ行きたい"
	var world := StageWorld.new()
	world.setup(def)
	tree.root.add_child(world)
	await wait_physics_frames(2)
	var kit := world.creatures[int(world.entity_ids["kit"])]
	assert_eq(kit.wish_text(), "お花畑の向こうへ行きたい")
	world.queue_free()
	await tree.process_frame


func test_clear_condition_finds_the_carry_area() -> void:
	var box := AABB(Vector3(1, 2, 3), Vector3(2, 2, 2))
	var cond := ClearCondition.all_of(
		[ClearCondition.carry_object("kit", box), ClearCondition.all_at_goal(AABB())]
	)
	assert_eq(cond.carry_area("kit"), box)
	assert_false(cond.carry_area("other").has_volume())


## 一文は、狙ったか近くにいる生き物1匹だけに出す。
func test_wish_text_shows_when_near_or_aimed() -> void:
	await _enter(PATH_ID)
	var kit := _creature("kit")
	await _walk_to(Vector3(6.5, 0.0, 6.5), 0.4)
	assert_true(WorldQueries.wish_focus(w, null) == null, "too far: no wish text")
	assert_eq(WorldQueries.wish_focus(w, kit), kit, "aimed at from afar")
	await _walk_to(kit.global_position + Vector3(2.0, 0.0, 0.0), 0.4)
	assert_eq(WorldQueries.wish_focus(w, null), kit, "near")
	kit.show_wish(true)
	assert_true(kit.is_wish_shown())
	kit.show_wish(false)
	assert_false(kit.is_wish_shown())


## 巣が画面の外なら縁に矢印、画面の中なら出さない。
func test_pointer_shows_the_nest_only_when_it_is_off_screen() -> void:
	await _enter(PATH_ID)
	var kit := _creature("kit")
	var hud := Hud.new()
	hud.world = w
	tree.root.add_child(hud)
	var cam := w.camera_rig.camera()
	var nest := OpenIslandsW1.PATH_NEST.get_center()
	cam.global_position = Vector3(0.0, 8.0, 6.0)
	cam.look_at(nest)
	hud.update_wish_pointer(kit)
	assert_false(hud.wish_pointer.visible, "the nest is on screen")
	cam.look_at(Vector3(0.0, 8.0, 20.0))  # 巣に背を向ける
	hud.update_wish_pointer(kit)
	assert_true(hud.wish_pointer.visible, "the nest is behind: an arrow on the edge")
	hud.update_wish_pointer(null)
	assert_false(hud.wish_pointer.visible, "no focused animal: no arrow")
	hud.queue_free()
	await tree.process_frame


## 移動はあるがジャンプが無く、1 段の階段の前にいるときは「ジャンプが足りない」の印。
func test_bubble_names_the_missing_jump() -> void:
	await _enter(PATH_ID)
	var kit := _creature("kit")
	await _walk_to(Vector3(1.5, 0.0, 0.5), 0.3)
	_lend(w.terrain_target(Vector3i(-1, 1, -1)), _slot_of(BACK), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(BACK)
	await wait_physics_frames(60)
	await _walk_to(kit.global_position + Vector3(1.4, 0.0, 0.0), 0.4)
	w.interact(kit)  # 生き物のジャンプを借りる
	await wait_physics_frames(2)
	assert_false(w.ledger.entity_has_ability(kit.entity_id, JUMP), "the kit has no jump now")
	_lend(kit, _slot_of(RIGHT), TriggerMode.Kind.NONE)
	for i in 300:
		if kit.bubble_key() == CreatureWishView.KEY_NEED_JUMP:
			break
		await tree.physics_frame
	assert_eq(kit.bubble_key(), CreatureWishView.KEY_NEED_JUMP, "it asks for a jump")
