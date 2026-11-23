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


## 吹き出しと願いの一文は、門の文字と同じく近いと画面での大きさを止め、2 m 前後で消える。画面の端から半分ほど
## はみ出しても消える（2026-11-23。段の真下でカメラのすぐ前の生き物の一文と吹き出しが、画面の端で大きく切れていた）。
func test_wish_bubble_and_text_stay_small_and_fade_up_close_or_off_screen() -> void:
	assert_almost(CreatureWishView.near_fit(20.0).x, 1.0, 0.001, "full size from mid range")
	assert_almost(CreatureWishView.near_fit(4.0).x, 4.0 / OverworldPortal.LABEL_FULL_AT, 0.001)
	assert_almost(CreatureWishView.near_fit(4.0).y, 1.0, 0.001, "readable at 4 m")
	assert_almost(CreatureWishView.near_fit(1.8).y, 0.0, 0.001, "gone under 2 m")
	var view := Vector2(1280, 720)
	assert_almost(
		CreatureWishView.on_screen_alpha(Vector2(640, 360), Vector2(100, 40), view), 1.0, 0.001
	)
	var edge := CreatureWishView.on_screen_alpha(Vector2(20, 360), Vector2(100, 40), view)
	assert_lt(edge, 0.5, "fading when most of it is past the edge")
	assert_almost(
		CreatureWishView.on_screen_alpha(Vector2(-50, 360), Vector2(100, 40), view), 0.0, 0.001
	)
	# ゲームの中: 子どもの生き物の真後ろ 1.5 m にカメラが来ると、吹き出しも一文も消える
	await _enter(PATH_ID)
	var kit := _creature("kit")
	kit.show_wish(true)
	# ゲームのカメラ（ばねの先）の代わりに、置いた場所から動かないカメラで見る
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.current = true
	var head := kit.global_position + Vector3(0.0, 2.0, 0.0)
	cam.global_position = head + Vector3(0.0, 0.0, 1.5)
	cam.look_at(head)
	await wait_physics_frames(3)
	var view_node := kit.wish_view()
	assert_lt(view_node.bubble_fit().y, 0.01, "the bubble fades right in front of the camera")
	assert_lt(view_node.wish_fit().y, 0.01, "so does the wish text")
	assert_lt(view_node.held_fit().y, 0.01, "and the held-ability medal over its head")
	# 6 m 離れて正面に見ると、出ていて、画面での大きさは止まっている（近づいても大きくならない）
	cam.global_position = head + Vector3(0.0, 0.0, 6.0)
	cam.look_at(head)
	await wait_physics_frames(3)
	assert_almost(view_node.bubble_fit().y, 1.0, 0.01, "shown at 6 m")
	assert_lt(view_node.bubble_fit().x, 1.0, "the screen size is clamped")
	# 横を向いて、生き物が画面の端の外へ出ると消える
	cam.look_at(head + Vector3(-6.0, 0.0, 0.0))
	await wait_physics_frames(3)
	assert_lt(view_node.wish_fit().y, 0.01, "off screen: faded")
	cam.queue_free()


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
	assert_true(marker.is_beam_shown(), "the beam is up")
	assert_ne(marker.nest_model(), null, "a nest model on the floor")
	assert_eq(kit.nest_tint, WishMarker.TINTS[0], "the kit's colour")


## 巣へ運ぶ生き物がいるステージはどれも、巣ごとに巣のモデルと光の柱を 1 つずつ建てる（2026-11-21 本人
## 「巣がどこかもわかりにくい」）。同じ箱を行き先にする生き物（4-4 の群れ）は 1 つの巣を分け合い、
## 違う巣は違う色になる。生き物の巣の色は、その巣の柱の色。
func test_every_nest_stage_builds_a_nest_model_and_a_beam() -> void:
	var checked := 0
	for def in StageCatalog.all_stages():
		var boxes: Array[AABB] = []
		var nest_keys: Array[String] = []
		for c in def.creatures:
			var box := def.clear_condition.carry_area(c.key)
			if not box.has_volume():
				continue
			nest_keys.append(c.key)
			if not boxes.any(func(b: AABB) -> bool: return b.is_equal_approx(box)):
				boxes.append(box)
		if boxes.is_empty():
			continue
		checked += 1
		var world := StageWorld.new()
		world.setup(def)
		tree.root.add_child(world)
		await wait_physics_frames(2)
		var markers := world.find_children("WishMarker*", "WishMarker", false, false)
		assert_eq(markers.size(), boxes.size(), "%s: one nest per box" % def.stage_id)
		var tints := {}
		for node in markers:
			var marker := node as WishMarker
			var model := marker.nest_model()
			assert_ne(model, null, "%s: a nest model" % def.stage_id)
			if model != null:
				assert_false(
					model.find_children("*", "MeshInstance3D", true, false).is_empty(),
					"%s: the nest model has a mesh" % def.stage_id
				)
				assert_almost(
					model.global_position.y,
					marker.floor_center().y,
					0.01,
					"%s: on the nest floor" % def.stage_id
				)
				assert_true(
					marker.box.grow(0.01).has_point(model.global_position + Vector3.UP * 0.05),
					"%s: inside the nest box" % def.stage_id
				)
			assert_true(marker.is_beam_shown(), "%s: a beam over the nest" % def.stage_id)
			tints[marker.tint.to_html()] = true
		assert_eq(tints.size(), markers.size(), "%s: each nest has its own colour" % def.stage_id)
		for key in nest_keys:
			var c := world.creatures[int(world.entity_ids[key])]
			var mine := markers.filter(
				func(m: Node) -> bool: return (m as WishMarker).creatures.has(c)
			)
			assert_eq(mine.size(), 1, "%s: %s belongs to one nest" % [def.stage_id, key])
			if mine.size() == 1:
				assert_eq(c.nest_tint, (mine[0] as WishMarker).tint, "the creature's nest colour")
		world.queue_free()
		await tree.process_frame
	assert_gt(checked, 10, "many stages have nests")


## 光の柱は遠くからははっきり、巣に近づくと薄くなり、間近では消える（謎を隠さない）。
## 近く〜中くらいのきょりでは、画面の真ん中の縦の帯と上の帯（ステージの名前・目的の札）で柱を薄くする。
## 1-4 の原っぱから見ると、柱が画面を縦に横切って照準と上の札に重なっていた（はじめての 10 分の通し）。
## 遠くからの目印としては、画面のどこでもそのまま。
func test_nest_beam_clears_the_crosshair_and_the_top_banner_at_mid_range() -> void:
	var mid := 15.0
	assert_lt(WishMarker.beam_screen_fade(Vector2(0.5, 0.5), mid), 0.15, "faded over the crosshair")
	assert_lt(WishMarker.beam_screen_fade(Vector2(0.8, 0.03), mid), 0.15, "faded under the banner")
	assert_almost(
		WishMarker.beam_screen_fade(Vector2(0.8, 0.5), mid), 1.0, 0.001, "off to the side"
	)
	assert_almost(WishMarker.beam_screen_fade(Vector2(0.5, 0.5), 40.0), 1.0, 0.001, "far: landmark")
	assert_almost(WishMarker.beam_screen_fade(Vector2(0.5, 0.03), 40.0), 1.0, 0.001)
	# 柱の材質にも、同じ値が入っている（広場の「つぎはここ」の柱は画面で薄くしない）
	var marker := WishMarker.new()
	marker.box = AABB(Vector3(-1.0, 0.0, -1.0), Vector3(2.0, 2.0, 2.0))
	tree.root.add_child(marker)
	await wait_physics_frames(1)
	var beam := marker.get_node(^"Beam") as MeshInstance3D
	var mat := beam.material_override as ShaderMaterial
	assert_eq(float(mat.get_shader_parameter("screen_fade")), 1.0)
	assert_eq(float(mat.get_shader_parameter("center_fade_far")), WishMarker.CENTER_FADE_FAR)
	marker.queue_free()
	await tree.process_frame


func test_nest_beam_fades_up_close() -> void:
	assert_eq(WishMarker.beam_fade(1.0), 0.0, "gone right at the nest")
	assert_eq(WishMarker.beam_fade(WishMarker.FADE_NEAR), 0.0)
	assert_lt(WishMarker.beam_fade(8.0), 1.0, "fading on the way")
	assert_gt(WishMarker.beam_fade(8.0), 0.0)
	assert_eq(WishMarker.beam_fade(20.0), 1.0, "clear from across the island")
	assert_gt(WishMarker.BEAM_HEIGHT, 15.0, "tall enough to see over the ledges")


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
	assert_eq(hud.wish_pointer.tint, kit.nest_tint, "in the colour of the kit's nest")
	hud.update_wish_pointer(null)
	assert_false(hud.wish_pointer.visible, "no focused animal: no arrow")
	hud.queue_free()
	await tree.process_frame


## 1-4: 縁を削って 1 段の階段を作り、子どもの生き物のジャンプを借りてから移動（D）だけを渡す。生き物は完全な道が
## 無くても巣のほうへ歩き、階段のふもとで止まって、吹き出しにジャンプのメダルを出す（2026-11-21 本人
## 「W で壁の前まで行って、ジャンプもあればな」）。ジャンプを渡すと判断し直し、階段を跳んで段へ上がる。
func test_kit_heads_for_the_nest_and_asks_for_a_jump_then_climbs() -> void:
	await _enter(PATH_ID)
	var kit := _creature("kit")
	await _walk_to(Vector3(1.5, 0.0, 0.5), 0.3)
	_lend(w.terrain_target(Vector3i(-1, 1, -1)), _slot_of(BACK), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(BACK)
	await wait_physics_frames(60)
	await _walk_to(kit.global_position + Vector3(1.4, 0.0, 0.0), 0.4)
	var start := kit.global_position
	w.interact(kit)  # 生き物のジャンプを借りる
	await wait_physics_frames(2)
	assert_false(w.ledger.entity_has_ability(kit.entity_id, JUMP), "the kit has no jump now")
	_lend(kit, _slot_of(RIGHT), TriggerMode.Kind.NONE)
	for i in 400:
		if kit.bubble_key() == CreatureWishView.KEY_NEED_JUMP:
			break
		await tree.physics_frame
	assert_eq(kit.shown_needs(), [JUMP] as Array[RuleAction.Kind], "a jump medal in the bubble")
	assert_lt(kit.global_position.z, start.z - 2.0, "walked toward the nest first")
	assert_lt(kit.global_position.z, 1.0, "at the foot of the carved step")
	assert_lt(kit.global_position.y, 0.3, "still on the meadow")
	await _walk_to(kit.global_position + Vector3(1.4, 0.0, 0.6), 0.4)
	_lend(kit, _slot_of(JUMP), TriggerMode.Kind.NONE)
	var ledge := AABB(Vector3(-7.0, 1.9, -6.0), Vector3(15.0, 1.0, 6.0))
	assert_true(await _wait_creature_in("kit", ledge, 900), "hops up the step once it has a jump")
	assert_ne(kit.bubble_key(), CreatureWishView.KEY_NEED_JUMP, "no longer asks for a jump")
