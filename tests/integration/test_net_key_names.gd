extends TestCase
## 協力プレイで、ホストが作った知らせのキー名が、受け取った人の割り当てで出ること。
## ホストは参加者の操作の結果（例: 鐘には渡せません（F で鳴らす））を通信で返す。キー名をホストの側で
## 文字にすると、参加者がキーを割り当て直していてもホストのキー名が出てしまう。そこで知らせは目印
## `{key:操作}` のまま運び、表示する側（ToastStack）でその人の割り当てと入力の種類に置きかえる。
## 同じプロセスの中では InputMode（割り当て）は全員で共有なので、「届いた文がまだ目印のままか」と
## 「表示するときに、その時点の割り当てで描くか」を分けて確かめる。

const NetParty := preload("res://tests/integration/net_party.gd")

var party: NetParty


func before_each() -> void:
	party = NetParty.new(self, 2, "zz_test_net_keys")
	await party.open(StageCatalog.HUB_ID, 36000)
	await party.join_all()
	await party.enter(StageCatalog.THREE_BELLS_ID)


func after_each() -> void:
	KeyBindings.new().apply()
	InputMode.using_pad = false
	await party.close()


func test_host_notice_carries_a_key_token_and_renders_with_local_bindings() -> void:
	var client := party.world(1)
	var bell := client.bells_by_key["east_bell"] as Node3D
	var received: Array[String] = []
	client.message_posted.connect(func(text: String) -> void: received.append(text))
	await party.place(1, bell.global_position + Vector3(-1.2, 0.6, 0.0))
	await party.settle(1)
	client.select_slot(NetParty.JUMP_SLOT)
	client.lend_to(bell, false)
	await party.until(
		func() -> bool: return received.any(func(t: String) -> bool: return t.contains("鐘")),
		"the host answers that bells cannot take abilities"
	)
	var notice := ""
	for text: String in received:
		if text.contains("鐘"):
			notice = text
	assert_true(
		notice.contains(InputMode.token(&"interact")), "sent as a token, not a key: %s" % notice
	)
	assert_false(notice.contains("（F "), "the host's key name is not baked in")
	# 参加者の画面: 自分の割り当てで描く
	var toasts := ToastStack.new()
	tree.root.add_child(toasts)
	var bindings := KeyBindings.new()
	bindings.assign(&"interact", KeyBindings.Slot.KEYBOARD, "key:%d" % KEY_G)
	bindings.apply()
	toasts.push(notice)
	assert_eq(toasts.messages(), PackedStringArray(["鐘には渡せません（G で鳴らす）"]))
	InputMode.using_pad = true
	var pad := InputMode.key(&"interact")
	assert_eq(
		toasts.messages(),
		PackedStringArray(["鐘には渡せません（%s で鳴らす）" % pad]),
		"switching to a pad redraws the shown notice"
	)
	toasts.free()
