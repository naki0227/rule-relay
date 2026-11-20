extends TestCase
## 操作のキーを含む表示が、割り当て直し・キーボードとパッドの切り替えにすぐ付いてくること。
## - 3D の看板（鐘・チェックポイント・入口・落ちている器）は島を作り直さなくても描き直す
## - 知らせの文はキー名ではなく目印 `{key:操作}` で運び、表示する人の割り当てで描く

var island: PrototypeIsland


func before_each() -> void:
	island = PrototypeIsland.new()
	tree.root.add_child(island)
	await wait_physics_frames(3)


func after_each() -> void:
	KeyBindings.new().apply()
	InputMode.using_pad = false
	island.queue_free()
	await tree.process_frame


func _rebind_interact(code: Key) -> void:
	var bindings := KeyBindings.new()
	assert_true(bindings.assign(&"interact", KeyBindings.Slot.KEYBOARD, "key:%d" % code).ok)
	bindings.apply()


## 島の中の、操作のキーを含む看板。
func _key_signs() -> Array[KeyLabel3D]:
	var found: Array[KeyLabel3D] = []
	for node: Node in island.find_children("*", "Label3D", true, false):
		var board := node as KeyLabel3D
		if board != null and board.template.contains(InputMode.token(&"interact")):
			found.append(board)
	return found


func _sign_starting(prefix: String) -> KeyLabel3D:
	for board: KeyLabel3D in _key_signs():
		if board.text.begins_with(prefix):
			return board
	return null


func test_resolve_replaces_tokens_and_keeps_unknown_text() -> void:
	var text := "鐘（%s で鳴らす）・%s" % [InputMode.token(&"interact"), InputMode.token(&"jump")]
	assert_eq(InputMode.resolve(text), "鐘（F で鳴らす）・Space")
	assert_eq(InputMode.resolve("{key:no_such_action} と {key:"), "{key:no_such_action} と {key:")
	assert_eq(InputMode.resolve("目印なし"), "目印なし")


func test_signs_redraw_when_bindings_change() -> void:
	var checkpoint := _sign_starting("チェックポイント")
	var bell := _sign_starting("鐘")
	assert_ne(checkpoint, null, "the checkpoint board shows the interact key")
	assert_ne(bell, null, "the bell board shows the interact key")
	if checkpoint == null or bell == null:
		return
	assert_eq(checkpoint.text, "チェックポイント（F で保存）")
	_rebind_interact(KEY_G)
	assert_eq(checkpoint.text, "チェックポイント（G で保存）", "no new island needed")
	assert_eq(bell.text, "鐘（G で鳴らす）")
	for board: KeyLabel3D in _key_signs():
		assert_false(board.text.contains("{key:"), "every board is resolved: %s" % board.text)


func test_signs_redraw_when_switching_to_a_pad() -> void:
	var checkpoint := _sign_starting("チェックポイント")
	assert_ne(checkpoint, null)
	if checkpoint == null:
		return
	InputMode.using_pad = true
	var pad_key := InputMode.key(&"interact")
	assert_ne(pad_key, "F")
	assert_eq(checkpoint.text, "チェックポイント（%s で保存）" % pad_key)
	InputMode.using_pad = false
	assert_eq(checkpoint.text, "チェックポイント（F で保存）")


func test_signs_on_a_stage_island_follow_the_bindings() -> void:
	var director := PartyDirector.new()
	director.profile = "zz_test_key_labels"
	tree.root.add_child(director)
	director.enter_stage(StageCatalog.HUB_ID)
	await wait_physics_frames(3)
	var signs: Array[KeyLabel3D] = []
	for node: Node in director.world.find_children("*", "Label3D", true, false):
		var board := node as KeyLabel3D
		if board != null and board.template.contains(InputMode.token(&"interact")):
			signs.append(board)
	assert_gt(signs.size(), 0, "the hub has entrance signs with the interact key")
	_rebind_interact(KEY_G)
	for board: KeyLabel3D in signs:
		var expected := board.template.replace(InputMode.token(&"interact"), "G")
		assert_eq(board.text, expected, "the board follows the rebind")
	director.queue_free()
	await tree.process_frame
	ProgressStore.new().delete("zz_test_key_labels")


func test_toasts_render_and_redraw_with_the_local_bindings() -> void:
	var toasts := ToastStack.new()
	tree.root.add_child(toasts)
	toasts.push("台座で %s" % InputMode.token(&"interact"))
	assert_eq(toasts.messages(), PackedStringArray(["台座で F"]))
	_rebind_interact(KEY_G)
	assert_eq(toasts.messages(), PackedStringArray(["台座で G"]), "a shown toast redraws")
	toasts.free()
