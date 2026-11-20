extends RefCounted
## オンライン協力の部屋（ホスト1人＋参加者、合わせて最大4人）を同じプロセスの中に作る結合テストの部品
## （ファイル名が test_ で始まらないので、これ自体は実行されない）。
## 各側は専用の SceneMultiplayer（tree.set_multiplayer）と、own_world_3d の SubViewport（物理の世界）を持ち、
## ENet（127.0.0.1）でつなぐ。i 番目の側のプレイヤー ID は i + 1（ホスト 1、参加者は入った順に 2・3・4）。
## 使い方: party = NetParty.new(self, 4, "zz_test_x") → await party.open() → await party.join_all()
## → await party.enter(StageCatalog.INTRO_ID) … 最後に await party.close()。

const JUMP := RuleAction.Kind.JUMP
## 開けた島・導入のどちらも、ジャンプはホットバーの 5 番目（0 始まりで 4）。
const JUMP_SLOT := 4

var test: TestCase
var tree: SceneTree
var sides: Array[Node] = []
var directors: Array[PartyDirector] = []
var nets: Array[NetWorld] = []
var port: int = 0

var _profiles: PackedStringArray = PackedStringArray()


func _init(test_case: TestCase, count: int, profile_prefix: String) -> void:
	assert(count >= 1 and count <= StageDef.MAX_PLAYERS, "1〜4人")
	test = test_case
	tree = test_case.tree
	for i in count:
		var profile := "%s_%d" % [profile_prefix, i]
		_profiles.append(profile)
		ProgressStore.new().delete(profile)
		_make_side(i, profile)


func count() -> int:
	return directors.size()


func host() -> PartyDirector:
	return directors[0]


func world(i: int) -> StageWorld:
	return directors[i].world


func pid(i: int) -> int:
	return i + 1


func _make_side(i: int, profile: String) -> void:
	var side := Node.new()
	side.name = "Side%d" % i
	tree.root.add_child(side)
	tree.set_multiplayer(SceneMultiplayer.new(), side.get_path())
	# 物理の世界を分けるため、進行役（とその下のステージ）は専用の SubViewport に入れる
	var view := SubViewport.new()
	view.name = "View"
	view.own_world_3d = true
	view.size = Vector2i(16, 16)
	side.add_child(view)
	var director := PartyDirector.new()
	director.profile = profile
	view.add_child(director)
	var net := NetWorld.new()
	side.add_child(net)
	sides.append(side)
	directors.append(director)
	nets.append(net)


## ホストが stage_id に入ってから部屋を作る。
func open(stage_id: String = StageCatalog.HUB_ID, base_port: int = 41000) -> void:
	host().enter_stage(stage_id)
	nets[0].world = host().world
	port = base_port + randi() % 3000
	var server := ENetMultiplayerPeer.new()
	test.assert_eq(server.create_server(port, StageDef.MAX_PLAYERS), OK)
	nets[0].start_host(server, "key-1")
	host().attach_net(nets[0])
	await test.wait_physics_frames(3)


## i 番目の側が参加者として入る（仮のハブを作ってから NetWorld をつなぐ）。
func join(i: int) -> void:
	directors[i].prepare_client()
	nets[i].world = directors[i].world
	directors[i].attach_net(nets[i])
	var peer := ENetMultiplayerPeer.new()
	test.assert_eq(peer.create_client("127.0.0.1", port), OK)
	nets[i].start_client(peer, "key-%d" % pid(i))
	await until(
		func() -> bool: return world(i) != null and world(i).player.player_id == pid(i),
		"side %d gets player id %d" % [i, pid(i)]
	)
	await until(
		func() -> bool: return directors[i].stage_id == host().stage_id, "side %d stage" % i
	)


## 参加者を順に全員入れ、全員の画面に全員がそろうまで待つ。
func join_all() -> void:
	for i in range(1, count()):
		await join(i)
	await until(func() -> bool: return _everyone_sees_everyone(), "everyone sees everyone")
	await test.wait_physics_frames(10)


func _everyone_sees_everyone() -> bool:
	for i in count():
		if world(i).ledger.players().size() != count() or world(i).avatars.size() != count() - 1:
			return false
	return converged()


## ホストがステージに入り、全員が同じステージで正式に参加し、出現地点に着くまで待つ。
func enter(stage_id: String) -> void:
	host().enter_stage(stage_id)
	await until(func() -> bool: return _all_in(stage_id), "everyone enters %s" % stage_id)
	await test.wait_physics_frames(10)


func _all_in(stage_id: String) -> bool:
	if host().lifecycle.formal_participants().size() != count():
		return false
	for i in count():
		var w := world(i)
		if directors[i].stage_id != stage_id or w.player.global_position.y < -1.0:
			return false
		if w.player.global_position.distance_to(w.spawn_for(pid(i))) > 1.0:
			return false
	return converged()


## 通信を閉じ、全部の側を片付け、保存した進行を消す。
func close() -> void:
	for net in nets:
		net.close()
	for side in sides:
		tree.set_multiplayer(null, side.get_path())
		side.queue_free()
	await tree.process_frame
	for profile in _profiles:
		ProgressStore.new().delete(profile)
	# テストとこの部品は互いを参照しているので、ここで切る（切らないと終了時に解放されず残る）
	test = null


## 条件が真になるまで物理フレームを進める（既定 15 秒）。来なければ失敗にして false。
func until(condition: Callable, what: String = "", frames: int = 900) -> bool:
	for f in frames:
		if condition.call():
			return true
		await tree.physics_frame
	test.fail("timed out: %s" % what)
	return false


## 参加者の自分のアバターを置き、ホストの画面のその人のアバターも着くまで待つ（競合テストの準備用）。
func place(i: int, at: Vector3) -> void:
	var me := world(i).player
	me.global_position = at
	me.velocity = Vector3.ZERO
	if i == 0:
		await test.wait_physics_frames(3)
		return
	await until(
		func() -> bool: return host().world.avatars[pid(i)].global_position.distance_to(at) < 0.3,
		"host sees side %d at %s" % [i, at]
	)


## i 番目の自分の位置が、ホストの画面のその人のアバターにも届くまで待つ。
func settle(i: int) -> void:
	if i == 0:
		return
	await until(
		func() -> bool:
			var here := world(i).player.global_position
			return host().world.avatar_of(pid(i)).global_position.distance_to(here) < 0.1,
		"host sees side %d where it stands" % i
	)


# --- 一致の確認 ---------------------------------------------------------------


## 全員の台帳が同じ世代・同じ中身か（ホストの正本と参加者の写しが一致）。
func converged() -> bool:
	var generation := nets[0].session.generation
	var digest := ledger_digest(0)
	for i in range(1, count()):
		if nets[i].session.generation != generation or ledger_digest(i) != digest:
			return false
	return true


func ledger_digest(i: int) -> String:
	return var_to_str(world(i).ledger.snapshot())


## 全員の台帳で不変条件が守られ（複製・消失なし）、写しがホストとそろうことを確かめる。
func assert_consistent(label: String) -> void:
	await until(converged, "%s: replicas converge" % label)
	for i in count():
		test.assert_eq(world(i).ledger.validate(), PackedStringArray(), "%s: side %d" % [label, i])


## 台帳のトークンの数（増えも減りもしないことを確かめる）。
func token_count(i: int) -> int:
	return world(i).ledger.all_tokens().size()


# --- 歩く・跳ぶ・渡す -------------------------------------------------------------


## i 番目のアバターを target へ歩かせる（移動の入力と向きだけ。瞬間移動しない）。
## 水平の距離が tolerance 以内で高さも近ければ着いた。段差で止まったら、跳べれば跳ぶ。
func walk(i: int, target: Vector3, tolerance: float = 0.35, frames: int = 900) -> bool:
	var w := world(i)
	var me := w.player
	var stuck := 0
	for f in frames:
		var flat := Vector3(target.x - me.global_position.x, 0.0, target.z - me.global_position.z)
		var near := flat.length() <= tolerance and absf(me.global_position.y - target.y) < 0.7
		if near and me.is_on_floor():
			me.move_intent = Vector2.ZERO
			await test.wait_physics_frames(3)
			return true
		me.view_yaw = atan2(-flat.x, -flat.z)
		me.move_intent = Vector2(0.0, 1.0)
		var moving := Vector2(me.velocity.x, me.velocity.z).length() > 0.5
		stuck = 0 if moving else stuck + 1
		if stuck > 8 and me.is_on_floor():
			w.press_action(JUMP)
			stuck = 0
		await tree.physics_frame
	me.move_intent = Vector2.ZERO
	test.fail("side %d could not walk to %s (at %s)" % [i, target, me.global_position])
	return false


## i 番目が持っているジャンプ（自分の器の分・借りている分）を、全部 j 番目へ渡す。
## 1回の操作で1つずつ渡るので、受け手の画面に届いてから次を渡す。
func give_all_jumps(i: int, j: int) -> void:
	var w := world(i)
	# 届くかはホストの画面の位置で決まるので、2人の位置がホストに届くまで待つ
	await settle(i)
	await settle(j)
	w.select_slot(JUMP_SLOT)
	while w.ledger.ability_count(JUMP, pid(i)) > 0:
		var before := world(j).ledger.ability_count(JUMP, pid(j))
		w.lend_to(w.avatars[pid(j)], false)
		var arrived := await until(
			func() -> bool: return world(j).ledger.ability_count(JUMP, pid(j)) > before,
			"side %d gives a jump to side %d" % [i, j],
			180
		)
		if not arrived:
			return
		await until(converged, "after giving")
