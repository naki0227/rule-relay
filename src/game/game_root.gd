class_name GameRoot
extends Node
## メインシーンの入口。タイトル（ひとりで／部屋を作る／部屋に入る）から、
## 進行役（PartyDirector）・通信（NetWorld）・HUD・入力を組み立てる。
## ステージが変わるたびに HUD と入力を新しい島へつなぎ直す。
## コマンドラインでタイトルを飛ばせる（試すとき用。`--` の後ろに書く）:
##   --solo / --host[=ポート] / --join=IPアドレス[:ポート] / --profile=名前
##   --allow-prohibition-give（部屋のオプション: 禁止をプレイヤーへ直接渡せる）
##   --campaign（広場を製品版の開き方に）/ --open-all（広場の地方・ポータル・能力を全部開ける）
## Steam 版（機能タグ "steam" か `--steam`、かつ GodotSteam があるときだけ）は SteamGate が Steam 版の通信を作り、
## タイトルに Steam の項目が増える。それ以外（提出版・CI）は Steam に一切触れない（docs/adr/0012）。
## テストは PrototypeIsland や PartyDirector だけを木に追加し、HUD と入力なしで操作する。

const SESSION_KEY_DIR := "user://session"

var director: PartyDirector
var net: NetWorld
var sounds: SoundBank
## BGM（場面ごとの曲。タイトル・ハブ・島で切り替える）。
var music: MusicPlayer
var migration: HostMigration
## 部屋のオプション（部屋を作るときに使う）: 禁止をプレイヤーへ直接渡せる。
var room_allow_prohibition: bool = false
## Steam 版の通信（src/steam/steam_transport.gd）。提出版・CI ではいつも null。
var steam: Node = null

var _title: TitleMenu
var _hud: Hud
var _input: PlayerInput
var _banner: PartyBanner
## 操作の案内の「慣れた」記録（記録の名前ごと。島が変わっても引き継ぐ）。
var _hints: HintMemory = HintMemory.new()


func _ready() -> void:
	# 設定（文字の大きさ・視点の速さ・キー割り当て）は、タイトルより先に反映する
	GameSettings.load_and_apply(get_tree())
	sounds = SoundBank.new()
	sounds.name = "Sounds"
	add_child(sounds)
	music = MusicPlayer.new()
	music.name = "Music"
	add_child(music)
	_open_steam()
	var args := _arguments()
	if args.has("solo") or args.has("host") or args.has("join"):
		_start_from_arguments(args)
		return
	_title = TitleMenu.new()
	_title.name = "Title"
	add_child(_title)
	_title.settings_menu.play_sound = func(event: StringName) -> void: sounds.play_ui(event)
	_title.solo_chosen.connect(start_solo)
	_title.host_chosen.connect(start_host)
	_title.prohibition_option_toggled.connect(func(on: bool) -> void: room_allow_prohibition = on)
	_title.join_chosen.connect(start_join)
	music.play_scene(MusicPlayer.TITLE)
	if steam != null:
		steam.call(&"add_title_entries", _title)


func start_solo(profile: String) -> void:
	_make_director(profile)
	director.enter_stage(StageCatalog.HUB_ID)


## 部屋を作る。
func start_host(profile: String, port: int) -> void:
	var server := ENetMultiplayerPeer.new()
	var error := server.create_server(port, PartyRoster.MAX_PLAYERS)
	if error != OK:
		_show_error("部屋を作れませんでした（ポート %d が使われているかも）" % port)
		return
	_host_with(profile, server, port, null)
	director.world.message_posted.emit("部屋を作りました（ポート %d）。友だちは IP アドレスとポートで入れます" % port)


func start_join(profile: String, address: String, port: int) -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, port) != OK:
		_show_error("%s:%d に接続できませんでした" % [address, port])
		return
	_join_with(profile, peer, port, null)
	director.world.message_posted.emit("%s:%d の部屋に入っています…" % [address, port])


## 部屋を開く（ENet でも Steam でも同じ）。link は Steam 版の通信（ホスト移譲で使う。ENet なら null）。
func _host_with(profile: String, server: MultiplayerPeer, port: int, link: Node) -> void:
	_make_director(profile)
	director.allow_prohibition_to_player = room_allow_prohibition
	director.enter_stage(StageCatalog.HUB_ID)
	net = _make_net(self)
	net.world = director.world
	net.start_host(server, session_key(profile))
	director.attach_net(net)
	_make_migration(port, profile, link)


func _join_with(profile: String, peer: MultiplayerPeer, port: int, link: Node) -> void:
	_make_director(profile)
	director.prepare_client()
	net = _make_net(self)
	net.world = director.world
	net.start_client(peer, session_key(profile))
	director.attach_net(net)
	_make_migration(port, profile, link)
	migration.watch()


## Steam 版のときだけ、Steam 版の通信を用意する（使えなければ何もしない）。
func _open_steam() -> void:
	steam = SteamGate.open(self)
	if steam == null:
		return
	steam.connect(&"peer_ready", _on_steam_peer)
	steam.connect(&"failed", _show_error)


## Steam のロビーを作った・招待から入ったとき。
func _on_steam_peer(peer: MultiplayerPeer, as_host: bool) -> void:
	if director != null:
		push_warning("もう遊んでいるので、Steam の招待は使いません")
		return
	var profile := _title.profile_name() if _title != null else "player"
	if as_host:
		_host_with(profile, peer, 0, steam)
		director.world.message_posted.emit("Steam の部屋を作りました。フレンドを招待できます")
	else:
		_join_with(profile, peer, 0, steam)
		director.world.message_posted.emit("Steam の部屋に入っています…")


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
	_apply_overworld_options(_arguments())
	_hints = HintMemory.for_profile(profile)
	add_child(director)
	director.world_changed.connect(_on_world_changed)
	_banner = PartyBanner.new()
	_banner.director = director


## 広場の開き方のオプション（docs/how-to-test.md）。既定は試遊の版（ポータルと地方は全部開く）。
##   --campaign: 製品版と同じ開き方（クリアで次のポータル・地方が開く）
##   --open-all: 全部開ける（ポータル・地方に加えて、広場で使える能力も全部）
func _apply_overworld_options(args: Dictionary) -> void:
	if args.has("campaign"):
		director.all_stages_open = false
		director.all_regions_open = false
	if args.has("open-all"):
		director.all_stages_open = true
		director.all_regions_open = true
		director.all_abilities_unlocked = true


## ホスト移譲の係（ホストは状態を配り、参加者はホストが落ちたら引き継ぐ）。
func _make_migration(port: int, profile: String, link: Node) -> void:
	migration = HostMigration.new()
	migration.director = director
	migration.net = net
	migration.port = port
	migration.link = link
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
	StageTransition.play_on(self)  # 新しい島を生成りの幕から丸く開いて見せる（見た目だけ）
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
	_hud.hints = _hints
	add_child(_hud)
	_hud.pause_menu.quit_request = quit_game
	if _banner.get_parent() != null:
		_banner.get_parent().remove_child(_banner)
	_hud.add_child(_banner)
	# ステージの目的（隅の短い一覧。入ったときだけ大きく出す）と、メニューの「広場へもどる」
	var objectives := ObjectivePanel.new()
	objectives.name = "Objectives"
	objectives.director = director
	objectives.hud = _hud
	_hud.add_child(objectives)
	if director.in_stage():
		_hud.pause_menu.leave_request = director.request_leave_stage
		_hud.pause_menu.refresh()
	# 参加者もホストから届いた島の作り直しでここを通るので、いまいる島の曲になる
	music.play_scene(MusicPlayer.scene_for_stage(director.stage_id))
	music.duck_source = _hud.is_menu_open
	_input = PlayerInput.new()
	_input.name = "PlayerInput"
	_input.world = world
	_input.hud = _hud
	_input.party = self
	add_child(_input)


## いまの島の HUD と入力（島が変わるたびに作り直す。テスト用）。
func current_hud() -> Hud:
	return _hud


func current_input() -> PlayerInput:
	return _input


## PlayerInput から: V（全員リセットの投票）。
func handle_party_action(action: StringName) -> void:
	if director == null or director.world == null:
		return
	if action == &"vote_reset":
		director.request_vote()


## メニューの「ゲームをやめる」。協力中の参加者は、部屋を出たことをホストへ伝え、受け付け（最長 2 秒）を
## 待ってから通信を閉じて終わる（自分で出たのを通信切断として扱わせない。PartyExit）。
func quit_game() -> void:
	await PartyExit.quit(director, get_tree().quit)


## 通信を閉じる（テスト・タイトルへ戻るとき）。
func shutdown() -> void:
	if net != null:
		net.close()


func _start_from_arguments(args: Dictionary) -> void:
	var profile := String(args.get("profile", "player"))
	room_allow_prohibition = args.has("allow-prohibition-give")
	if args.has("join"):
		var target := String(args["join"]).split(":")
		var port := int(target[1]) if target.size() > 1 else TitleMenu.DEFAULT_PORT
		start_join(profile, target[0], port)
	elif args.has("host"):
		var port_text := String(args["host"])
		var port := int(port_text) if port_text.is_valid_int() else TitleMenu.DEFAULT_PORT
		start_host(profile, port)
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
