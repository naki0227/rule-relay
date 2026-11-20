class_name SteamGate
extends RefCounted
## Steam 版の入口の門番（docs/adr/0012）。提出版（コンテスト版）に入る Steam 関係のコードはこれだけ。
## ここでは Steam の関数を一度も呼ばない。次の3つがそろったときだけ、Steam 版の通信を load する:
##   1. Steam 版として起動した: エクスポートの機能タグ "steam"（Steam 版のプリセットだけが付ける）か、
##      開発中に `--` の後ろへ `--steam` を書いた
##   2. GodotSteam（GDExtension）が読み込まれていて、Steam のシングルトンがある
##   3. Steam 版の通信のスクリプトが pck に入っている（提出版のプリセットは exclude_filter で外す）
## どれかが欠けたら null を返し、ゲームは今までどおり（ソロと ENet の直接接続）に動く。
## 提出版の書き出しに Steam の名前が残っていないかを tools/check_no_steam.py が文字列で調べるので、
## このファイルには GodotSteam のファイル名・クラス名・Steam 版のフォルダ名をそのまま書かない
## （フォルダとファイルの名前は機能タグから組み立てる）。

## エクスポートの機能タグ（Steam 版のプリセットの custom_features）。Steam 版のフォルダ名も兼ねる。
const FEATURE: String = "steam"
## 開発用: Steam のシングルトンの名前。
const SINGLETON: StringName = &"Steam"


## Steam 版として起動したか（機能タグ、または開発用の `--steam`）。
static func wanted(has_feature_tag: bool, user_args: PackedStringArray) -> bool:
	return has_feature_tag or user_args.has("--" + FEATURE)


## 3つの条件から、Steam 版の通信を使うかを決める（純粋な判断。テストで全組み合わせを確かめる）。
static func decide(is_wanted: bool, has_singleton: bool, has_script: bool) -> bool:
	return is_wanted and has_singleton and has_script


## Steam 版の通信のスクリプトの場所（機能タグの名前のフォルダ）。
static func transport_path() -> String:
	return "res://src/%s/%s_transport.gd" % [FEATURE, FEATURE]


## 開発用: `--steam-appid=番号`（ローカルの実験だけ。App ID 480 は Valve の見本 Spacewar）。
## 指定が無ければ 0（Steam クライアントから起動したときは Steam が App ID を知っている）。
static func app_id_from(user_args: PackedStringArray) -> int:
	var prefix := "--%s-appid=" % FEATURE
	for arg: String in user_args:
		if arg.begins_with(prefix) and arg.trim_prefix(prefix).is_valid_int():
			return int(arg.trim_prefix(prefix))
	return 0


## この起動で Steam 版の通信を使えるか。
static func is_enabled() -> bool:
	return decide(
		wanted(OS.has_feature(FEATURE), OS.get_cmdline_user_args()),
		Engine.has_singleton(SINGLETON),
		ResourceLoader.exists(transport_path())
	)


## Steam 版の通信を作って parent の子に入れ、Steam を初期化する。使えなければ null（何も作らない）。
static func open(parent: Node) -> Node:
	if not is_enabled():
		return null
	var script := load(transport_path()) as GDScript
	if script == null or not script.can_instantiate():
		return null
	var transport := script.new() as Node
	if transport == null:
		return null
	transport.name = "SteamTransport"
	parent.add_child(transport)
	if not bool(transport.call(&"start", app_id_from(OS.get_cmdline_user_args()))):
		transport.queue_free()
		return null
	return transport
