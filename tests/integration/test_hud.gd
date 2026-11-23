extends TestCase
## 画面表示: テーマ・書体の読み込み、ホットバーの状態、知らせの数、ブロックの上のアイコン。

var island: PrototypeIsland
var hud: Hud


func before_each() -> void:
	island = PrototypeIsland.new()
	tree.root.add_child(island)
	hud = Hud.new()
	hud.world = island
	tree.root.add_child(hud)
	await wait_physics_frames(5)


func after_each() -> void:
	tree.paused = false
	hud.queue_free()
	island.queue_free()
	await tree.process_frame


func test_theme_uses_bundled_font_with_weights() -> void:
	var theme := UiTheme.get_theme()
	assert_ne(theme.default_font, null)
	var bold := UiTheme.bold() as FontVariation
	assert_true(
		bold.base_font.get_font_name().contains("Zen Maru Gothic"), bold.base_font.get_font_name()
	)
	var light := UiTheme.font(400) as FontVariation
	assert_ne(bold.base_font, light.base_font, "bold and medium are separate faces")
	assert_false(bold.fallbacks.is_empty(), "missing glyphs fall back to an OS font")
	assert_eq(UiTheme.font(700), UiTheme.bold(), "font variations are cached")


func test_palette_is_warm_and_soft() -> void:
	# 生成りの地は明るく、文字はこげ茶（真っ黒にしない）。状態の色は種類ごとに分ける
	assert_gt(UiTheme.CREAM.get_luminance(), 0.9)
	assert_lt(UiTheme.INK.get_luminance(), 0.3)
	assert_gt(UiTheme.INK.get_luminance(), 0.05, "not pure black")
	assert_gt(UiTheme.CREAM.r, UiTheme.CREAM.b, "warm, not grey")
	var states := [UiTheme.SUN, UiTheme.LEAF, UiTheme.HONEY, UiTheme.BAN]
	for i in states.size():
		for j in range(i + 1, states.size()):
			assert_gt(
				absf((states[i] as Color).h - (states[j] as Color).h) * 360.0,
				8.0,
				"state colours are distinguishable"
			)


func test_minimum_text_size_survives_720p() -> void:
	# 1280x720 では 2/3 に縮むので、最小の文字でも 12px 以上を保つ
	assert_gt(UiTheme.SIZE_SMALL * 720.0 / 1080.0, 11.9)


func test_hotbar_describes_state_in_words() -> void:
	var lines := hud.hotbar_descriptions()
	assert_eq(lines[4], "5: ジャンプ")
	island.player.global_position = Vector3(3.5, 0.0, -3.0)
	await wait_physics_frames(3)
	island.select_slot(4)
	island.lend_to(island.row[0], false)
	assert_eq(hud.hotbar_descriptions()[4], "5: ジャンプ・貸出中（単発）")
	island.ledger.give_player_item(RuleAction.Kind.JUMP, true, 8)
	assert_eq(hud.hotbar_descriptions()[8], "9: ジャンプ禁止・適用中")
	assert_eq(hud.hotbar_descriptions()[7], "8: 空")


func test_toasts_are_capped() -> void:
	for i in 7:
		hud.toasts.push("msg %d" % i)
	var shown := hud.toasts.messages()
	assert_eq(shown.size(), ToastStack.MAX_TOASTS)
	assert_eq(shown[-1], "msg 6", "newest stays")


func test_blocks_show_token_icons() -> void:
	var middle := island.row[1]  # レベルに置かれたジャンプ禁止
	var icons := middle.find_children("*", "Sprite3D", true, false)
	assert_eq(icons.size(), 1)
	assert_eq(
		(icons[0] as Sprite3D).texture.resource_path, "res://assets/icons/prohibition_jump.png"
	)


func test_goal_banner_appears() -> void:
	assert_false(_texts(hud).has(Hud.GOAL_TITLE))
	island.goal_reached.emit()
	await tree.process_frame
	assert_true(_texts(hud).has(Hud.GOAL_TITLE))
	assert_false(_texts(hud).has("高台に到達しました"), "not the prototype wording")


## 案内は 1 つだけ（docs/w1-teaching.md）。狙った相手といまの状況で、いちばん要るものが出て、慣れたら消える。
func test_context_prompt_follows_the_target_until_learned() -> void:
	for key: String in ["move", "look", "jump"]:
		for i in HintMemory.LEARN_AFTER:
			hud.hints.used(key)
	island.select_slot(0)
	hud.update_context(island.row[0], true, false)
	assert_eq(hud.context_actions(), PackedStringArray(["Wを渡す"]), "one hint naming the ability")
	island.select_slot(4)
	hud.update_context(island.row[0], true, false)
	assert_eq(hud.context_actions(), PackedStringArray(["ジャンプを渡す"]))
	hud.update_context(island.row[1], true, false)  # ジャンプ禁止が置かれている
	assert_eq(hud.context_actions(), PackedStringArray(["禁止を取る"]), "a ban is taken with F")
	hud.update_context(null, false, true)
	assert_eq(hud.context_actions(), PackedStringArray(["ここで保存"]))
	for i in HintMemory.LEARN_AFTER:
		hud.hints.used("lend")
	hud.update_context(island.row[0], true, false)
	assert_eq(hud.context_actions().size(), 0, "hint disappears once learned")
	hud.update_context(null, false, false)
	assert_eq(hud.context_actions().size(), 0, "nothing aimed, nothing shown")


## 2 つ以上の案内が当てはまっても、出すのは 1 つだけ（貸した単発を使う > 取り戻す）。
func test_only_one_hint_at_a_time() -> void:
	for key: String in ["move", "look", "jump"]:
		for i in HintMemory.LEARN_AFTER:
			hud.hints.used(key)
	island.player.global_position = island.row[0].global_position + Vector3(0.0, 0.5, 1.4)
	await wait_physics_frames(3)
	island.select_slot(4)
	assert_eq(island.lend_to(island.row[0], false), RuleLedger.LendResult.OK)
	hud.update_context(island.row[0], true, false)
	assert_eq(hud.context_actions(), PackedStringArray(["貸したジャンプを使う"]))
	for i in HintMemory.LEARN_AFTER:
		hud.hints.used("fire")
	hud.update_context(island.row[0], true, false)
	assert_eq(hud.context_actions(), PackedStringArray(["取り戻す"]), "my own lent jump")
	assert_eq(hud.context_keys(), PackedStringArray(["F"]))


func _texts(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for label in node.find_children("*", "Label", true, false):
		if not label.is_queued_for_deletion() and (label as Label).is_visible_in_tree():
			out.append((label as Label).text)
	return out
