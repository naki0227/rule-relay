extends TestCase
## Steam 版の分け方（docs/adr/0012）。GodotSteam が無い環境（提出版・CI）では、Steam 版の通信は作られず、
## タイトルもホスト移譲も今までどおりに動く。Steam があるときの動作（ロビー・P2P）は未検証。

const TRANSPORT_PATH := "res://src/steam/steam_transport.gd"


func test_gate_is_closed_in_ci() -> void:
	# CI は機能タグ "steam" も `--steam` も GodotSteam も無い
	assert_false(SteamGate.is_enabled())
	var parent := Node.new()
	tree.root.add_child(parent)
	assert_eq(SteamGate.open(parent), null)
	assert_eq(parent.get_child_count(), 0, "使えないときは何も作らない")
	parent.queue_free()


func test_gate_needs_all_three_conditions() -> void:
	for wanted: bool in [false, true]:
		for singleton: bool in [false, true]:
			for script: bool in [false, true]:
				var expected := wanted and singleton and script
				assert_eq(
					SteamGate.decide(wanted, singleton, script),
					expected,
					"wanted=%s singleton=%s script=%s" % [wanted, singleton, script]
				)


func test_gate_wanted_by_feature_tag_or_dev_argument() -> void:
	assert_false(SteamGate.wanted(false, PackedStringArray()))
	assert_false(SteamGate.wanted(false, PackedStringArray(["--solo", "--host=24991"])))
	assert_true(SteamGate.wanted(true, PackedStringArray()))
	assert_true(SteamGate.wanted(false, PackedStringArray(["--steam"])))
	# `--steam-appid=480` だけでは Steam 版にならない（App ID の指定は `--steam` と一緒に使う）
	assert_false(SteamGate.wanted(false, PackedStringArray(["--steam-appid=480"])))


func test_gate_app_id_is_zero_unless_given() -> void:
	assert_eq(SteamGate.app_id_from(PackedStringArray()), 0)
	assert_eq(SteamGate.app_id_from(PackedStringArray(["--steam"])), 0)
	assert_eq(SteamGate.app_id_from(PackedStringArray(["--steam", "--steam-appid=480"])), 480)
	assert_eq(SteamGate.app_id_from(PackedStringArray(["--steam-appid=abc"])), 0)


func test_gate_path_points_at_the_steam_folder() -> void:
	assert_eq(SteamGate.transport_path(), TRANSPORT_PATH)
	assert_true(ResourceLoader.exists(TRANSPORT_PATH), "開発用の木には入っている（提出版の pck からは外す）")


func test_transport_does_nothing_without_godotsteam() -> void:
	var script := load(TRANSPORT_PATH) as GDScript
	assert_true(script != null and script.can_instantiate())
	var transport := script.new() as Node
	tree.root.add_child(transport)
	assert_false(bool(transport.call(&"start", 0)))
	assert_false(bool(transport.call(&"is_started")))
	assert_eq(transport.call(&"make_host_peer"), null, "初期化前に peer を作ると Godot ごと落ちるので作らない")
	assert_eq(transport.call(&"make_client_peer", 1234), null)
	assert_eq(int(transport.call(&"lobby_owner")), 0)
	transport.call(&"host_lobby")
	transport.call(&"invite")
	assert_eq(int(transport.get(&"lobby_id")), 0)
	transport.queue_free()


func test_invite_launch_argument() -> void:
	var script := load(TRANSPORT_PATH) as GDScript
	var parse := Callable(script, &"lobby_from_args")
	assert_eq(int(parse.call(PackedStringArray())), 0)
	assert_eq(int(parse.call(PackedStringArray(["+connect_lobby", "109775241"]))), 109775241)
	assert_eq(int(parse.call(PackedStringArray(["+connect_lobby"]))), 0)
	assert_eq(int(parse.call(PackedStringArray(["+connect_lobby", "x"]))), 0)


func test_title_menu_is_unchanged_without_steam() -> void:
	var title := TitleMenu.new()
	tree.root.add_child(title)
	assert_eq(
		_button_texts(title.menu_box()), ["ひとりで遊ぶ", "友だちと遊ぶ", "部屋を作る（友だちを待つ）", "部屋に入る", "せってい"]
	)
	assert_false(_any_text_contains(title, "Steam"))
	title.queue_free()


func test_title_menu_shows_added_entries_above_status() -> void:
	var title := TitleMenu.new()
	tree.root.add_child(title)
	title.add_entry("Steam で部屋を作る（フレンドを招待）", func() -> void: pass)
	title.add_note("招待から入れます")
	var texts := _button_texts(title.menu_box())
	assert_eq(texts.size(), 6)
	assert_eq(texts[4], "Steam で部屋を作る（フレンドを招待）")
	assert_eq(texts[5], "せってい", "せっていは部屋の項目の下")
	title.show_error("テスト")
	var labels := title.menu_box().find_children("*", "Label", true, false)
	assert_eq((labels[labels.size() - 1] as Label).text, "テスト", "エラー表示はいちばん下のまま")
	title.queue_free()


func test_steam_election_follows_the_new_lobby_owner() -> void:
	var steam_ids := {1: 7001, 2: 7002, 3: 7003}
	# 前のホスト（1）が持ち主のまま・まだ分からない → 待つ
	assert_eq(HostMigration.elect_by_owner(steam_ids, 7001, 1), -1)
	assert_eq(HostMigration.elect_by_owner(steam_ids, 0, 1), -1)
	# Steam が 3 を持ち主にした → ID が小さい 2 ではなく 3 がホスト
	assert_eq(HostMigration.elect_by_owner(steam_ids, 7003, 1), 3)
	# 知らない SteamID → 待つ
	assert_eq(HostMigration.elect_by_owner(steam_ids, 9999, 1), -1)
	# ENet の選出は今までどおり（ID がいちばん小さい人）
	assert_eq(HostMigration.elect({1: "a", 2: "b", 3: "c"}, 1), 2)


func test_migration_without_link_keeps_enet_package() -> void:
	var migration := HostMigration.new()
	assert_eq(migration.link, null, "既定は ENet（Steam 版の通信なし）")
	migration.free()


func _button_texts(root: Node) -> Array[String]:
	var texts: Array[String] = []
	for node: Node in root.find_children("*", "Button", true, false):
		if not node is CheckBox:
			texts.append((node as Button).text)
	return texts


func _any_text_contains(root: Node, word: String) -> bool:
	for node: Node in root.find_children("*", "", true, false):
		if node is Label and (node as Label).text.contains(word):
			return true
		if node is Button and (node as Button).text.contains(word):
			return true
	return false
