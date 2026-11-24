class_name TestCase
extends RefCounted
## テストの基底クラス。`test_` で始まるメソッドを run_tests.gd が順に呼ぶ。
## 外部アドオンに依存しない最小実装（理由は docs/adr/0002-testing-and-ci.md）。

## 並列で流すときの組の数の上限と、組ごとのテスト用ポートの範囲（free_port）。
## 8 組 × 2000 = 12000〜27999 で、Linux の一時ポート（32768〜）に入らない。
const MAX_SHARDS := 8
const PORT_FLOOR := 12000
const PORT_BLOCK := 2000
## ENet の既定（ENET_PEER_PACKET_THROTTLE_INTERVAL / ACCELERATION）と同じ。steady_enet で減り幅だけ 0 にする。
const ENET_THROTTLE_INTERVAL_MS := 5000
const ENET_THROTTLE_ACCELERATION := 2

## 結合テスト用。シーンを木に追加したり物理フレームを待ったりするときに使う。
var tree: SceneTree

var _failures: PackedStringArray = PackedStringArray()


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func get_failures() -> PackedStringArray:
	return _failures


func clear_failures() -> void:
	_failures = PackedStringArray()


func fail(message: String) -> void:
	_failures.append(message)


func assert_true(condition: bool, message: String = "") -> void:
	if not condition:
		fail("expected true. %s" % message)


func assert_false(condition: bool, message: String = "") -> void:
	if condition:
		fail("expected false. %s" % message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if not _same(actual, expected):
		fail("expected <%s> but was <%s>. %s" % [str(expected), str(actual), message])


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	if _same(actual, unexpected):
		fail("did not expect <%s>. %s" % [str(unexpected), message])


func assert_almost(actual: float, expected: float, tolerance: float, message: String = "") -> void:
	if absf(actual - expected) > tolerance:
		fail("expected %f±%f but was %f. %s" % [expected, tolerance, actual, message])


func assert_gt(actual: float, threshold: float, message: String = "") -> void:
	if not actual > threshold:
		fail("expected > %f but was %f. %s" % [threshold, actual, message])


func assert_lt(actual: float, threshold: float, message: String = "") -> void:
	if not actual < threshold:
		fail("expected < %f but was %f. %s" % [threshold, actual, message])


## 物理フレームを n 回進める（結合テスト用）。
func wait_physics_frames(count: int) -> void:
	for i in count:
		await tree.physics_frame


## その人が持っている器（かばん＋ホットバー）。拾った器は、ホットバーに空きがあればそこへ入るので
## （2026-11-23 本人の判断。docs/adr/0021）、拾った物を探すときはかばんだけでなくホットバーも見る。
static func carried(ledger: RuleLedger, player_id: int) -> Array[RuleVessel]:
	var result := ledger.inventory_vessels(player_id)
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := ledger.hotbar_vessel(slot, player_id)
		if v != null:
			result.append(v)
	return result


## 投げたメダル（docs/adr/0017）が当たるか手元へ戻るまで待つ（結合テスト用）。待ち切ったら true。
func wait_throws(world: GameWorld, frames: int = 300) -> bool:
	for i in frames:
		if MedalThrow.flying(world).is_empty():
			return true
		await tree.physics_frame
	return MedalThrow.flying(world).is_empty()


## テストの部屋（ENet のサーバー）に使う空いた UDP ポート（結合テスト用）。並列で流すとき
## （run_tests.gd の --shard=i/n）は組ごとに別の範囲から選ぶので、別のプロセスの部屋とぶつからない。
## 範囲は Linux の一時ポート（32768〜）より下にして、クライアント側のソケットともぶつからないようにする。
## 選んだポートを一度 bind して、空いていることも確かめる。
static func free_port() -> int:
	var shard := shard_spec()
	var low := PORT_FLOOR + shard.x * PORT_BLOCK
	var candidate := low
	for i in 50:
		candidate = low + randi() % PORT_BLOCK
		var probe := PacketPeerUDP.new()
		var bound := probe.bind(candidate) == OK
		probe.close()
		if bound:
			return candidate
	return candidate


## ENet の送信の間引き（packet throttle）を止める（結合テスト用。ホストと参加者の両方の peer で呼ぶ）。
## ENet は往復の実時間が揺れると、相手ごとに unreliable の送信を間引く（間引きの値が 0 まで下がると全部落とす）。
## テストは --fixed-fps でコマ数を数えて待つので、CPU が混んで（並列で流すと）実時間だけ揺れると、
## ホストの画面の同期（unreliable で、大きいので分割して送る）が何百コマも届かずに時間切れになった
## （実測: ホスト側の間引きの値が 32 から 0〜22 に下がっていた）。減り幅を 0 にして、どのコマも送る。
## 今つながっている相手にだけ効くので、相手がつながってから呼ぶ。
static func steady_enet(peer: MultiplayerPeer) -> void:
	var enet := peer as ENetMultiplayerPeer
	if enet == null or enet.host == null:
		return
	for remote in enet.host.get_peers():
		remote.throttle_configure(ENET_THROTTLE_INTERVAL_MS, ENET_THROTTLE_ACCELERATION, 0)


## branch（set_multiplayer した枝）に相手がつながるたびに steady_enet をかける（結合テスト用）。
## HostMigration はホストが落ちたあと、新しいホストの部屋と、つなぎ直しの peer を自分で作るので、
## テストからはその peer に手が届かない。枝の MultiplayerAPI の peer_connected で、そのときの peer に
## かけ直せば、移譲のあとの接続にも、最初の接続にも同じように効く（ゲームのコードは変えない）。
## 本番の接続では間引きを止めない: ENet の混雑への備えであり、実際のネットワークで止めてよいかは
## 測っていない（テストの時間切れは、--fixed-fps でコマ数だけ数えるテスト特有の揺れが原因）。
static func keep_enet_steady(branch: Node) -> void:
	# 枝（Node）だけを覚える。MultiplayerAPI を覚えると、自分の信号から自分を参照して解放されなくなる
	branch.multiplayer.peer_connected.connect(
		func(_id: int) -> void:
			if is_instance_valid(branch) and branch.is_inside_tree():
				steady_enet(branch.multiplayer.multiplayer_peer)
	)


## peer の、いまつながっている相手のすべてで間引きが止まっているか（keep_enet_steady の確かめ用）。
static func enet_is_steady(peer: MultiplayerPeer) -> bool:
	var enet := peer as ENetMultiplayerPeer
	if enet == null or enet.host == null or enet.host.get_peers().is_empty():
		return false
	for remote in enet.host.get_peers():
		var deceleration := remote.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_DECELERATION)
		if deceleration != 0.0:
			return false
	return true


## コマンドラインの --shard=i/n（i は 1 始まり）を Vector2i(i - 1, n) で返す。無い・不正なら (0, 1)。
static func shard_spec() -> Vector2i:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--shard="):
			continue
		var parts := arg.trim_prefix("--shard=").split("/")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			break
		var index := parts[0].to_int()
		var count := parts[1].to_int()
		if count < 1 or count > MAX_SHARDS or index < 1 or index > count:
			break
		return Vector2i(index - 1, count)
	return Vector2i(0, 1)


func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		# int と float の比較だけは値で比べる
		var numeric := [TYPE_INT, TYPE_FLOAT]
		if typeof(a) in numeric and typeof(b) in numeric:
			return float(a) == float(b)
		return false
	return a == b
