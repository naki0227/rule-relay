extends TestCase
## 2〜4人のオンライン協力の通しプレイ（docs/requirements-status.md 23）。ホストと参加者を同じプロセスの
## 中で別々の物理世界に作り、ENet でつなぐ（部屋の組み立ては net_party.gd）。
## 出現地点から先は、全員が移動の入力と向き（move_intent / view_yaw）とジャンプのキーだけで進む
## （瞬間移動しない）。能力は画面の操作（仲間へ渡す）でホストを通して受け渡す。
##
## 協力の道（ジャンプを集めて跳ぶ。導入・丘の上の旗の両方で「×2 で届く」高さ 2 の壁を越える）:
## 1. 全員が壁の下に並ぶ。1人目（ホスト）が自分のジャンプを2人目へ渡す
## 2. 2人目がジャンプ×2 で壁の上へ。上から、持っているジャンプを全部、次の人へ渡し、ゴールの窪みへ降りる
## 3. 次の人も同じように上がって渡す。最後に上がった人は、全部をホストへ渡す
## 4. ホストが全員分のジャンプで上がり、窪みへ。生きている全員がゴールに集まってクリア

const NetParty := preload("res://tests/integration/net_party.gd")

var party: NetParty


func after_each() -> void:
	if party != null:
		await party.close()


func _start(players: int, stage_id: String) -> void:
	party = NetParty.new(self, players, "zz_test_four_players")
	await party.open(StageCatalog.HUB_ID, 47000)
	await party.join_all()
	await party.enter(stage_id)


## 上の「協力の道」を流す。queue: 壁の下で順番を待つ位置（人ごと）。climb: 壁の下の跳ぶ位置。
## top: 壁の上の、下の仲間へ渡す位置。goals: ゴールの窪みの中の位置（人ごと）。
func _pool_jumps_and_climb(
	queue: Array[Vector3], climb: Vector3, top: Vector3, goals: Array[Vector3]
) -> void:
	var n := party.count()
	for i in n:
		assert_true(await party.walk(i, queue[i]), "side %d lines up under the wall" % i)
	await party.give_all_jumps(0, 1)
	var order: Array[int] = []
	for i in range(1, n):
		order.append(i)
	order.append(0)
	for k in order.size():
		var climber := order[k]
		await party.walk(climber, climb)
		var jumps := party.world(climber).ledger.ability_count(
			RuleAction.Kind.JUMP, party.pid(climber)
		)
		assert_gt(jumps, 1, "side %d climbs with pooled jumps" % climber)
		assert_true(await party.walk(climber, top), "side %d gets onto the wall" % climber)
		if k + 1 < order.size():
			var next := order[k + 1]
			await party.walk(next, climb)
			await party.give_all_jumps(climber, next)
		assert_true(
			await party.walk(climber, goals[climber]), "side %d walks into the goal" % climber
		)


## 全員がゴールの窪みに入っている間にクリアし、全員の進行に記録されることを確かめる。
func _assert_cleared_by_everyone(stage_id: String) -> void:
	var host := party.host()
	await party.until(func() -> bool: return host.last_clear_text != "", "%s clears" % stage_id)
	var goal := host.world.def.clear_condition.goal_area()
	for i in party.count():
		var at := host.world.avatar_of(party.pid(i)).global_position
		assert_true(goal.has_point(at), "player %d is in the goal (%s)" % [party.pid(i), at])
	for i in party.count():
		await party.until(
			func() -> bool: return party.directors[i].progress.has_cleared(stage_id),
			"side %d records the clear" % i
		)
	await party.assert_consistent("after the clear")


## 導入（跳ぶ力を貸す）。岩棚の上面 y = 2、ゴールの窪み y = 1（x -2〜3, z -9〜-7。数える箱は 0.3 内側）。
## 持ち上げ台（x 0〜1, z -5〜-4）は使わず、その西の岩棚の縁で受け渡す。
func _intro_route() -> void:
	var queue: Array[Vector3] = []
	var goals: Array[Vector3] = []
	for i in party.count():
		queue.append(Vector3(-4.3 + 1.1 * float(i), 0.0, -2.5))
		goals.append(Vector3(-1.4 + 1.2 * float(i), 1.0, -8.0))
	await _pool_jumps_and_climb(queue, Vector3(-2.5, 0.0, -4.3), Vector3(-2.5, 2.0, -5.5), goals)
	await _assert_cleared_by_everyone(StageCatalog.INTRO_ID)


func test_intro_cleared_by_four_players_pooling_jumps() -> void:
	await _start(4, StageCatalog.INTRO_ID)
	await _intro_route()


func test_intro_cleared_by_three_players_pooling_jumps() -> void:
	await _start(3, StageCatalog.INTRO_ID)
	await _intro_route()


func test_intro_cleared_by_two_players_pooling_jumps() -> void:
	await _start(2, StageCatalog.INTRO_ID)
	await _intro_route()


## 丘の上の旗。浜（y = 0）→ 段（y = 1）→ 段丘（y = 2）は自分のジャンプで上がり、段丘から頂上（y = 4）は
## ジャンプを集めて跳ぶ（OpenIslands.hill_top の道 4）。ゴールの窪み y = 3（x -1〜2, z -7〜-5）。
## 段丘の持ち上げ台（x 0〜1, z -3〜-2）は使わず、その西で受け渡す。2人の版は test_net_director の
## 「ゴールに2人集まるとクリア」（頂上の縁から歩く）と違い、浜から通しで上がる。
func test_hill_top_cleared_by_four_players_pooling_jumps() -> void:
	await _hill_top_route(4)


func test_hill_top_cleared_by_two_players_pooling_jumps() -> void:
	await _hill_top_route(2)


func _hill_top_route(players: int) -> void:
	await _start(players, StageCatalog.HILL_ID)
	var queue: Array[Vector3] = [
		Vector3(-3.5, 2.0, -0.6),
		Vector3(-2.5, 2.0, -0.6),
		Vector3(2.5, 2.0, -0.6),
		Vector3(3.5, 2.0, -0.6),
	]
	var goals: Array[Vector3] = [
		Vector3(-0.5, 3.0, -6.5),
		Vector3(1.4, 3.0, -6.5),
		Vector3(-0.5, 3.0, -5.5),
		Vector3(1.4, 3.0, -5.5),
	]
	await _pool_jumps_and_climb(queue, Vector3(-1.5, 2.0, -2.3), Vector3(-1.5, 4.0, -3.6), goals)
	await _assert_cleared_by_everyone(StageCatalog.HILL_ID)
