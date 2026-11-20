class_name GameRoot
extends Node
## メインシーンの入口。タイトル（ひとりで／部屋を作る／相棒ボットと／部屋に入る）から、
## 進行役（PartyDirector）・通信（NetWorld）・HUD・入力を組み立てる。
## ステージが変わるたびに HUD と入力を新しい島へつなぎ直す。
## コマンドラインでタイトルを飛ばせる（試すとき用。`--` の後ろに書く）:
##   --solo / --host[=ポート] / --join=IPアドレス[:ポート] / --bot（--host と一緒に）/ --profile=名前
## テストは PrototypeIsland や PartyDirector だけを木に追加し、HUD と入力なしで操作する。

const SESSION_KEY_DIR := "user://session"

var director: PartyDirector
var net: NetWorld
var sounds: SoundBank
var bot: CompanionBot
var migration: HostMigration

var _title: TitleMenu
var _hud: Hud
var _input: PlayerInput
var _banner: PartyBanner
var _bot_root: Node


func _ready() -> void:
	sounds = SoundBank.new()
	sounds.name = "Sounds"
	add_child(sounds)
	var args := _arguments()
	if args.has("solo") or args.has("host") or args.has("join"):
		_start_from_arguments(args)
		return
	_title = TitleMenu.new()
	_title.name = "Title"
	add_child(_title)
	_title.solo_chosen.connect(start_solo)
	_title.host_chosen.connect(start_host)
	_title.join_chosen.connect(start_join)


func start_solo(profile: String) -> void:
	_make_director(profile)
	director.enter_stage(StageCatalog.HUB_ID)


## 部屋を作る。with_bot なら相棒ボットを同じ PC の中で参加させる。
func start_host(profile: String, port: int, with_bot: bool = false) -> void:
	var server := ENetMultiplayerPeer.new()
	var error := server.create_server(port, PartyRoster.MAX_PLAYERS)
	if error != OK:
		_show_error("部屋を作れませんでした（ポート %d が使われているかも）" % port)
		return
	_make_director(profile)
	director.enter_stage(StageCatalog.HUB_ID)
	net = _make_net(self)
	net.world = director.world
	net.start_host(server, session_key(profile))
	director.attach_net(net)
	_make_migration(port, profile)
	director.world.message_posted.emit("部屋を作りました（ポート %d）。友だちは IP アドレスとポートで入れます" % port)
	if with_bot:
		_spawn_bot(port)


func start_join(profile: String, address: String, port: int) -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, port) != OK:
		_show_error("%s:%d に接続できませんでした" % [address, port])
		return
	_make_director(profile)
	director.prepare_client()
	net = _make_net(self)
	net.world = director.world
	net.start_client(peer, session_key(profile))
	director.attach_net(net)
	_make_migration(port, profile)
	migration.watch()
	director.world.message_posted.emit("%s:%d の部屋に入っています…" % [address, port])


## 再接続しても同じプレイヤーに戻れるよう、記録の名前ごとに推測できない鍵を保存しておく。
static func session_key(profile: String) -> String:
	var path := "%s/%s.key" % [SESSION_KEY_DIR, profile]
	if FileAccess.file_exists(path):
		var saved := FileAccess.get_file_as_string(path).strip_edges()
		if saved.length() >= 32:
			return saved
	var key := Crypto.new().generate_random_bytes(16).hex_encode()
	DirAccess.make_dir_recursive_absolute(SESSION_KEY_DIR)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(key)
	return key


func _make_director(profile: String) -> void:
	if _title != null:
		_title.queue_free()
		_title = null
	director = PartyDirector.new()
	director.profile = profile
	add_child(director)
	director.world_changed.connect(_on_world_changed)
	_banner = PartyBanner.new()
	_banner.director = director


## ホスト移譲の係（ホストは状態を配り、参加者はホストが落ちたら引き継ぐ）。
func _make_migration(port: int, profile: String) -> void:
	migration = HostMigration.new()
	migration.director = director
	migration.net = net
	migration.port = port
	migration.session_key = session_key(profile)
	add_child(migration)


func _make_net(parent: Node) -> NetWorld:
	var made := NetWorld.new()
	parent.add_child(made)
	return made


## 島が変わったら、HUD と入力を新しい島へつなぎ直す。
func _on_world_changed(world: StageWorld) -> void:
	for old: Node in [_hud, _input]:
		if old != null:
			old.queue_free()
	world.sound_requested.connect(
		func(event: StringName, at: Vector3, positional: bool) -> void:
			if positional:
				sounds.play_at(event, at)
			else:
				sounds.play_ui(event)
	)
	_hud = Hud.new()
	_hud.name = "Hud"
	_hud.world = world
	_hud.sounds = sounds
	add_child(_hud)
	if _banner.get_parent() != null:
		_banner.get_parent().remove_child(_banner)
	_hud.add_child(_banner)
	_input = PlayerInput.new()
	_input.name = "PlayerInput"
	_input.world = world
	_input.hud = _hud
	_input.party = self
	add_child(_input)


## PlayerInput から: V（投票）と、相棒ボットへの頼みごと（G/H/R）。
func handle_party_action(action: StringName) -> void:
	if director == null or director.world == null:
		return
	var text := ""
	match action:
		&"vote_reset":
			director.request_vote()
		&"bot_follow":
			text = bot.toggle_follow() if bot != null else ""
		&"bot_give":
			text = bot.ask_give() if bot != null else ""
		&"bot_recall":
			text = bot.ask_recall() if bot != null else ""
	if text != "":
		director.world.message_posted.emit(text)


## 相棒ボット: ホストと同じパスになるよう「GameRoot/Director」「GameRoot/Net」を持つ別の木を作り、
## 自分専用の通信（SceneMultiplayer）と物理の世界（SubViewport）で参加者として入る。
func _spawn_bot(port: int) -> void:
	_bot_root = Node.new()
	_bot_root.name = "CompanionBotRoot"
	get_tree().root.add_child.call_deferred(_bot_root)
	await get_tree().process_frame
	get_tree().set_multiplayer(SceneMultiplayer.new(), _bot_root.get_path())
	var mirror := Node.new()
	mirror.name = "GameRoot"
	_bot_root.add_child(mirror)
	var view := SubViewport.new()
	view.name = "View"
	view.own_world_3d = true
	view.size = Vector2i(2, 2)
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	view.audio_listener_enable_3d = false
	mirror.add_child(view)
	var bot_director := PartyDirector.new()
	bot_director.profile = "companion_bot"
	bot_director.world_parent = view
	mirror.add_child(bot_director)
	bot_director.prepare_client()
	var bot_net := _make_net(mirror)
	bot_net.world = bot_director.world
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", port)
	bot_net.start_client(
		peer, "companion-bot-%s" % Crypto.new().generate_random_bytes(8).hex_encode()
	)
	bot_director.attach_net(bot_net)
	var bot_migration := HostMigration.new()
	bot_migration.director = bot_director
	bot_migration.net = bot_net
	mirror.add_child(bot_migration)
	bot = CompanionBot.new()
	bot.name = "Brain"
	bot.director = bot_director
	mirror.add_child(bot)
	director.world.message_posted.emit("相棒ボットが来ます（G: 待って/ついてきて　H: 能力をちょうだい　R: 回収して）")


## 通信を閉じ、相棒ボットを片付ける（テスト・タイトルへ戻るとき）。
func shutdown() -> void:
	if net != null:
		net.close()
	if _bot_root != null:
		var bot_net := _bot_root.get_node_or_null("GameRoot/Net") as NetWorld
		if bot_net != null:
			bot_net.close()
		get_tree().set_multiplayer(null, _bot_root.get_path())
		_bot_root.queue_free()
		_bot_root = null
	bot = null


func _start_from_arguments(args: Dictionary) -> void:
	var profile := String(args.get("profile", "player"))
	if args.has("join"):
		var target := String(args["join"]).split(":")
		var port := int(target[1]) if target.size() > 1 else TitleMenu.DEFAULT_PORT
		start_join(profile, target[0], port)
	elif args.has("host"):
		var port_text := String(args["host"])
		var port := int(port_text) if port_text.is_valid_int() else TitleMenu.DEFAULT_PORT
		start_host(profile, port, args.has("bot"))
	else:
		start_solo(profile)


## `--` の後ろの引数 {名前: 値}（値が無ければ ""）。
static func _arguments() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		result[pair[0]] = pair[1] if pair.size() > 1 else ""
	return result


func _show_error(text: String) -> void:
	if _title != null:
		_title.show_error(text)
	else:
		push_warning(text)
