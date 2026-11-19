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
		bold.base_font.get_font_name().contains("Noto Sans JP"), bold.base_font.get_font_name()
	)
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	assert_eq(int(bold.variation_opentype[wght]), 700, "weight axis set with the OpenType tag")
	var light := UiTheme.font(100) as FontVariation
	assert_gt(
		bold.get_string_size("WWW", HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x,
		light.get_string_size("WWW", HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x,
		"the weight actually changes the glyphs"
	)
	assert_false(bold.fallbacks.is_empty(), "missing glyphs fall back to an OS font")
	assert_eq(UiTheme.font(700), UiTheme.bold(), "font variations are cached")


func test_palette_is_neutral_with_one_accent() -> void:
	# 文字は温かい白（真っ白ではない）、面は暗い半透明、強調色は金1つ
	assert_lt(UiTheme.TEXT.get_luminance(), 0.99)
	assert_gt(UiTheme.TEXT.get_luminance(), 0.85)
	assert_lt(UiTheme.SURFACE.v, 0.15)
	assert_lt(UiTheme.SURFACE.a, 0.9, "surfaces stay translucent over the world")
	assert_gt(UiTheme.ACCENT.s, 0.3)


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
	assert_false(_texts(hud).has("高台に到達しました"))
	island.goal_reached.emit()
	await tree.process_frame
	assert_true(_texts(hud).has("高台に到達しました"))


func test_context_prompt_follows_the_target() -> void:
	hud.update_context(island.row[0], true, false)
	var texts := _texts(hud)
	assert_true(texts.has("渡す"))
	assert_false(texts.has("回収"), "nothing to recall on an empty block")
	hud.update_context(island.row[1], true, false)  # ジャンプ禁止が置かれている
	await tree.process_frame
	assert_true(_texts(hud).has("回収"))
	hud.update_context(null, false, true)
	await tree.process_frame
	assert_true(_texts(hud).has("保存"))


func _texts(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for label in node.find_children("*", "Label", true, false):
		if not label.is_queued_for_deletion() and (label as Label).is_visible_in_tree():
			out.append((label as Label).text)
	return out
