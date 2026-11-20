extends "res://tests/integration/island_playthrough.gd"
## ゴールの窪み（OpenIslands.goal_hollow。docs/adr/0011 決定 9・10）を、プレイヤーの操作だけで壊しにいく試遊。
## 結果は docs/reports/2026-11-20-goal-probes.md。
## - test_gate_*: 意図した挙動が守られていることを確かめる
## - test_finding_*: 試遊した時点の、意外な挙動を記録する（直すかどうかは本人が決める）
## 照準はゲームと同じく、カメラ（CameraRig）を回して GameWorld.aimed_block() の光線で決める。
## カメラは頭の上 1.5 を中心に回るので、光線はいつもその点を通る。狙う点（仲間の体の高さ）へ
## 向けた yaw・pitch を、CameraRig の範囲（-70°〜30°）に収めて与える（マウスで向けるのと同じ）。
## 動かすのは move_intent・view_yaw・press_action と、渡す・F・投票の操作だけ。
## 例外（測定の準備）: 窪みの各点からの見通しを測るときは、観察者を窪みの床の各点に置く。
## 仲間（下で待つ人）は通信の操り人形と同じ WorldParty.add_avatar で置く。2人の協力のテストでは、
## test_net_director と同じく、始めに2人を頂上・岩棚の縁に置く。ゴールへ歩いて入れることは
## test_goal_sightlines・test_open_islands で確かめ済み。

const HOST_PROFILE := "zz_test_goal_host"
const CLIENT_PROFILE := "zz_test_goal_client"
const A := RuleLedger.PLAYER_ID
const B := 2
## 仲間の体の、狙う高さ（足もとから。カプセルの高さは 1.6）。
const BODY: Array[float] = [0.1, 0.4, 0.7, 1.0, 1.3, 1.5, 1.58]
const HEAD := 1.5

## [ステージ, 登り口の下に立つ仲間の足もと, 立ったまま狙えるか, 跳んで狙えるか]
## 下の仲間の位置は test_goal_sightlines と同じ。
const CASES: Array = [
	[StageCatalog.INTRO_ID, Vector3(0.5, 0.0, -3.5), true, true],
	[StageCatalog.HILL_ID, Vector3(0.5, 2.0, -1.5), false, true],
	[StageCatalog.HILL_ID, Vector3(0.5, 0.0, 5.5), false, true],
	[StageCatalog.QUARRY_ID, Vector3(1.5, 3.0, -7.5), false, false],
	[StageCatalog.QUARRY_ID, Vector3(0.5, 0.0, 0.5), false, true],
	[StageCatalog.THREE_BELLS_ID, Vector3(0.5, 3.0, -16.5), false, false],
	[StageCatalog.THREE_BELLS_ID, Vector3(-0.5, 0.0, -13.5), false, false],
	[StageCatalog.FLOATING_ID, Vector3(-3.5, 0.0, -4.5), false, true],
	[StageCatalog.WINDY_ID, Vector3(-1.5, 4.0, -18.5), false, true],
	[StageCatalog.WINDY_ID, Vector3(4.5, 2.0, -22.5), false, false],
	[StageCatalog.FORT_ID, Vector3(6.5, 2.0, -14.5), false, true],
	[StageCatalog.FORT_ID, Vector3(0.5, 0.0, -4.5), false, false],
]

var host_side: Node
var client_side: Node
var host: PartyDirector
var client: PartyDirector
var host_net: NetWorld
var client_net: NetWorld
var _port: int


func after_each() -> void:
	if host_net != null:
		host_net.close()
		client_net.close()
		for side: Node in [host_side, client_side]:
			tree.set_multiplayer(null, side.get_path())
			side.queue_free()
		host_net = null
		await tree.process_frame
		for p: String in [HOST_PROFILE, CLIENT_PROFILE]:
			ProgressStore.new().delete(p)
	await super()


# --- 1. カメラは縁を越えて下の仲間を狙えるか ---------------------------------------


## 窪みの床に立ったままでは、カメラをどう向けても（下向きいっぱいの -70° を含む）下の仲間に照準が
## 合わない（開けた島 6 つ）。導入だけは縁が 1 マスなので合う（test_finding_intro_*）。
func test_gate_camera_from_the_hollow_floor_misses_the_climbers_below() -> void:
	for case: Array in CASES:
		var seen := await _standing_aims(String(case[0]), case[1] as Vector3)
		print("    %s %s: 窪みの床から狙えた点 %d / %d" % [case[0], case[1], seen.x, seen.y])
		if bool(case[2]):
			assert_gt(seen.x, 0, "%s: the camera sees over the 1-cell rim" % case[0])
		else:
			assert_eq(seen.x, 0, "%s: the rim hides %s from the camera" % [case[0], case[1]])


## 窪みの中で跳ぶと、頂点の近くで縁の上からカメラが下の仲間に合う（足もとはゴールの箱の中のまま）。
## 三つの鐘・採石場の段など、下の人が崖のすぐ下にいる所は跳んでも合わない。
func test_finding_jumping_in_the_hollow_aims_over_the_rim() -> void:
	for case: Array in CASES:
		var seen := await _jumping_aims(String(case[0]), case[1] as Vector3)
		print("    %s %s: 跳んで狙えた点 %d / %d" % [case[0], case[1], seen.x, seen.y])
		if bool(case[3]):
			assert_gt(seen.x, 0, "%s: a jump lifts the camera over the rim" % case[0])
		else:
			assert_eq(seen.x, 0, "%s: even a jump does not see %s" % [case[0], case[1]])


## 丘の上の旗: 歩いて窪みに入り、窪みの中で跳んで、段丘（高さ 2）の仲間へジャンプを投げ渡せる。
func test_finding_hill_top_jump_and_give_from_inside_the_goal() -> void:
	await _enter_with_teammate(StageCatalog.HILL_ID)
	var mate := WorldParty.add_avatar(w, B, Vector3(0.5, 2.0, -1.5))
	await _walk_to(Vector3(0.5, 1.0, 1.5))
	await _walk_to(Vector3(-0.5, 2.0, -1.5))
	await _lift_up("lift", Vector3(-0.5, 2.0, -1.5), Vector3(0.5, 4.0, -4.5))
	await _walk_into_goal()
	w.toggle_reach()
	w.select_slot(_slot_of(JUMP))
	w.press_action(JUMP)
	var given := false
	for i in 70:
		_aim_point(w, _me(), mate.global_position + Vector3(0.0, HEAD, 0.0))
		await tree.physics_frame
		if _goal().has_point(_me().global_position) and w.aimed_block() == mate:
			given = w.lend_to(w.aimed_block(), false) == RuleLedger.LendResult.OK
			break
	assert_true(given, "gave the jump while airborne inside the goal box")
	assert_true(_goal().has_point(_me().global_position), "the giver never left the goal box")
	assert_eq(w.ledger.ability_count(JUMP, B), 2, "the teammate below now has jump x2")


## 導入: 窪みの南の列に立てば、立ったまま下の仲間の頭に照準が合い、触る距離（4.0）で渡せる。
func test_finding_intro_gives_down_from_the_hollow_floor() -> void:
	await _enter_with_teammate(StageCatalog.INTRO_ID)
	var mate := WorldParty.add_avatar(w, B, Vector3(0.5, 0.0, -3.5))
	await _lift_up("lift", Vector3(0.5, 0.0, -3.5), Vector3(0.5, 2.0, -5.5))
	await _walk_into_goal()
	await _walk_to(Vector3(0.5, 1.0, -6.4), 0.1)
	assert_true(_goal().has_point(_me().global_position), "standing on the hollow floor")
	assert_lt(_me().global_position.y, 1.2, "down in the hollow")
	assert_true(await _aims(w, _me(), mate, BODY), "the camera sees the head over the rim")
	var chest := _me().global_position + Vector3(0.0, 1.0, 0.0)
	print("    導入: 胸から仲間の足もとまで %.2f（触る届き 4.0）" % chest.distance_to(mate.global_position))
	w.select_slot(_slot_of(JUMP))
	assert_eq(w.lend_to(w.aimed_block(), false), RuleLedger.LendResult.OK, "gave by touch")
	assert_eq(w.ledger.ability_count(JUMP, B), 2, "the teammate below now has jump x2")


# --- 4. 縁に立ってもゴールに数えられるか -------------------------------------------


## 縁の角に乗ったまま（足もとの高さは縁）、体の中心が窪みの上へ 0.2 ほど出ると、ゴールの箱に入る。
## そこからは下の仲間に照準が合い、投げて渡せる（縁に立っているのと同じ見通し）。
func test_finding_standing_on_the_rim_lip_counts_as_in_the_goal() -> void:
	await _enter_with_teammate(StageCatalog.HILL_ID)
	var mate := WorldParty.add_avatar(w, B, Vector3(0.5, 2.0, -1.5))
	await _walk_to(Vector3(0.5, 1.0, 1.5))
	await _walk_to(Vector3(-0.5, 2.0, -1.5))
	await _lift_up("lift", Vector3(-0.5, 2.0, -1.5), Vector3(0.5, 4.0, -4.5))
	await _walk_to(Vector3(0.5, 4.0, -4.3), 0.15)
	var lip := false
	for step in 60:
		_face(Vector3(0.5, 4.0, -9.0))
		_me().move_intent = Vector2(0.0, 0.3)  # ほんの少しずつ前へ（キーを短く押す）
		await tree.physics_frame
		_me().move_intent = Vector2.ZERO
		await wait_physics_frames(20)
		if _goal().has_point(_me().global_position) and _me().global_position.y > 3.8:
			lip = true
			break
	assert_true(lip, "balanced on the rim lip inside the goal box")
	await wait_physics_frames(120)
	var at := _me().global_position
	print("    縁の角: 足もと %s（窪みの床は y = 3、縁は y = 4）" % at)
	assert_true(_me().is_on_floor() and at.y > 3.8, "still standing on the rim after 2 s")
	assert_true(_goal().has_point(at), "and still counted as in the goal")
	assert_true(await _aims(w, _me(), mate, BODY), "the terrace below is in sight")
	w.toggle_reach()
	w.select_slot(_slot_of(JUMP))
	assert_eq(w.lend_to(w.aimed_block(), false), RuleLedger.LendResult.OK, "threw the jump down")


# --- 2. 窪みの罠（ひとり） ---------------------------------------------------------


## 浮島めぐり: ジャンプを遠くへ貸してから窪みに入ると、ひとりでは出られない。
func test_gate_hollow_without_jump_cannot_be_left_alone() -> void:
	await _trap_in_floating_goal()
	for exit: Vector3 in [
		Vector3(0.5, 2.0, -17.6),
		Vector3(0.5, 2.0, -14.4),
		Vector3(3.5, 2.0, -16.0),
		Vector3(-2.5, 2.0, -16.0),
	]:
		assert_false(await _try_walk_to(exit, 0.35, 150), "cannot climb out toward %s" % exit)
		assert_true(_goal().has_point(_me().global_position), "still in the hollow")


## ひとりなら V（全員リセットの投票）が1票で決まり、島のはじめへ戻ってジャンプも戻る。
func test_gate_hollow_trap_solo_vote_resets() -> void:
	await _trap_in_floating_goal()
	director.request_vote()
	await wait_physics_frames(5)
	assert_eq(director.lifecycle.reset_count(), 1, "one vote is enough alone")
	assert_false(_goal().has_point(_me().global_position), "back at the start")
	assert_true(w.ledger.player_can(JUMP, _me().player_id), "the jump came back")


## ひとりなら、メニューの「島のはじめから」で本当に最初から作り直す。
func test_gate_hollow_trap_solo_menu_restart() -> void:
	await _trap_in_floating_goal()
	w.restart_island()
	await wait_physics_frames(10)
	w = director.world
	assert_false(_goal().has_point(_me().global_position), "back at the start")
	assert_true(w.ledger.player_can(JUMP, _me().player_id), "a fresh island with the jump")


func _trap_in_floating_goal() -> void:
	await _enter(StageCatalog.FLOATING_ID)
	await _lift_up("tower_lift", Vector3(1.5, 0.0, -1.5), Vector3(0.5, 2.0, -5.5))
	await _jump_across(Vector3(0.5, 2.0, -5.7), Vector3(0.5, 2.0, -11.0))
	# 「投げる」で、ジャンプを真ん中の島の遠くの地面へ繰り返しで貸す（F で回収できない距離）
	var far := w.terrain_target(Vector3i(0, -1, 3))
	w.toggle_reach()
	_lend(far, _slot_of(JUMP), TriggerMode.Kind.REPEAT)
	w.toggle_reach()
	assert_false(w.ledger.player_can(JUMP, _me().player_id), "lent the jump away")
	# 北の鐘（窪みのすぐ南）をよけて、東の縁から入る
	await _walk_into_goal([Vector3(2.5, 2.0, -12.5), Vector3(2.5, 2.0, -14.4)])
	assert_lt(_me().global_position.y, 1.3, "down in the hollow")
	assert_eq(director.last_clear_text, "", "the bells are not rung, so no clear")


# --- 測る部品（1 人の島に、仲間の操り人形を置く） ------------------------------------


## 仲間（B）を正式参加者にしてからステージに入る（生きている仲間がゴールの外にいるので、ひとりで
## ゴールに入ってもクリアしない。下の仲間は操り人形で、動かない）。
func _enter_with_teammate(stage_id: String) -> void:
	director.enter_stage(StageCatalog.HUB_ID)
	if not director.world.ledger.has_entity(B):
		director.world.ledger.register_player(B)
	await _enter(stage_id)


## 窪みの床の各点（0.5 おき、壁から 0.3 内側）に立ち、下の仲間の体のどこかに照準が合うか。
## 返り値は (合った点の数, 点の数)。
func _standing_aims(stage_id: String, base: Vector3) -> Vector2i:
	await _enter_with_teammate(stage_id)
	var mate := WorldParty.add_avatar(w, B, base)
	var seen := 0
	var points := _floor_points(_goal(), 0.5)
	for from in points:
		await _stand_at(from)
		if await _aims(w, _me(), mate, BODY):
			seen += 1
	return Vector2i(seen, points.size())


## 窪みの床の 5 点（真ん中と四隅）から真上に跳び、跳んでいる間（ゴールの箱の中）に、毎コマ
## 仲間の頭へカメラを向けて照準が合うか。
func _jumping_aims(stage_id: String, base: Vector3) -> Vector2i:
	await _enter_with_teammate(stage_id)
	var mate := WorldParty.add_avatar(w, B, base)
	var seen := 0
	var points := _floor_points(_goal(), 10.0)
	for from in points:
		await _stand_at(from)
		w.press_action(JUMP)
		var hit := false
		for i in 70:
			_aim_point(w, _me(), mate.global_position + Vector3(0.0, HEAD, 0.0))
			await tree.physics_frame
			hit = hit or (_goal().has_point(_me().global_position) and w.aimed_block() == mate)
		seen += 1 if hit else 0
	return Vector2i(seen, points.size())


## 測定の準備: 観察者を窪みの床の点に置き、落ち着くまで待つ。
func _stand_at(from: Vector3) -> void:
	_me().global_position = from + Vector3(0.0, 0.05, 0.0)
	_me().velocity = Vector3.ZERO
	await wait_physics_frames(4)


## ゴールの箱の床の点（壁から 0.3 内側。step が箱より大きければ真ん中と四隅）。
func _floor_points(goal: AABB, step: float) -> Array[Vector3]:
	var y := goal.position.y + 0.1
	var lo := Vector3(goal.position.x + 0.3, y, goal.position.z + 0.3)
	var hi := Vector3(goal.end.x - 0.3, y, goal.end.z - 0.3)
	if step > goal.size.x:
		var c := goal.get_center()
		return [
			Vector3(c.x, y, c.z),
			lo,
			Vector3(hi.x, y, lo.z),
			Vector3(lo.x, y, hi.z),
			hi,
		]
	var out: Array[Vector3] = []
	var x := lo.x
	while x <= hi.x + 0.001:
		var z := lo.z
		while z <= hi.z + 0.001:
			out.append(Vector3(x, y, z))
			z += step
		x += step
	return out


## カメラを viewer の頭の上 1.5（CameraRig の回転の中心）から point へ向ける（範囲は CameraRig のまま）。
func _aim_point(world: GameWorld, viewer: PlayerAvatar, point: Vector3) -> void:
	var dir := (point - (viewer.global_position + Vector3(0.0, 1.5, 0.0))).normalized()
	world.camera_rig.yaw = atan2(-dir.x, -dir.z)
	world.camera_rig.pitch = clampf(asin(dir.y), CameraRig.MIN_PITCH, CameraRig.MAX_PITCH)


## target の高さ offsets のどこかへ向けたとき、照準（aimed_block）が target に合うか。
## 合えば、そのまま照準を合わせた状態で true を返す。
func _aims(world: GameWorld, viewer: PlayerAvatar, target: Node3D, offsets: Array[float]) -> bool:
	for h in offsets:
		_aim_point(world, viewer, target.global_position + Vector3(0.0, h, 0.0))
		await wait_physics_frames(2)
		if world.aimed_block() == target:
			return true
	return false


# --- 2. 窪みの罠（2人）・3. 鐘の妨害・4. 死亡と途中参加 ------------------------------


## B がジャンプを A に渡してから窪みに入ると、ひとりでは出られない。縁の A が B に照準を合わせて
## ジャンプを渡せば、B は自分で跳んで出られる。
func test_gate_rim_teammate_gives_a_jump_back_into_the_hollow() -> void:
	await _trap_client_in_hill_goal()
	var b_on_host := host.world.avatars[B] as PlayerAvatar
	host.world.select_slot(_slot_for(host.world, A, JUMP))
	assert_true(await _aims(host.world, host.world.player, b_on_host, BODY), "A sees B below")
	assert_eq(host.world.lend_to(host.world.aimed_block(), false), RuleLedger.LendResult.OK)
	await _until(func() -> bool: return client.world.ledger.player_can(JUMP, B))
	assert_true(await _drive(client.world, Vector3(0.5, 4.0, -4.0), 300), "B climbed out")


## 2人なら V は 2 票要る。閉じ込められた B だけの票では戻らず、A も賛成すると戻ってジャンプも戻る
## （逆に言えば、A が賛成しなければ B は戻れない）。
func test_gate_trapped_player_needs_the_partner_vote() -> void:
	await _trap_client_in_hill_goal()
	client.request_vote()
	await _until(func() -> bool: return host.lifecycle.yes_vote_count() == 1)
	await wait_physics_frames(30)
	assert_eq(host.lifecycle.required_votes(), 2, "both must agree")
	assert_eq(host.lifecycle.reset_count(), 0, "B's vote alone does not reset")
	host.request_vote()
	await _until(func() -> bool: return host.lifecycle.reset_count() == 1)
	await _until(func() -> bool: return client.world.ledger.player_can(JUMP, B))
	await _until(func() -> bool: return not _goal_of(host).has_point(client.world.player.position))


## 三つの鐘: A が発射台に「投げる」を渡して東の鐘を鳴らしたあと、B が発射台を F で回収する。
## - 鳴らした鐘は数えられたまま（activated は消えない）。「投げる」は B の手元へ移り、A には戻らない
## - B ひとりの投票では戻らない（2 票要る）
## - ただし B の賛成票は取り消されずに残る。A が落ちて死亡観戦になった瞬間、「死亡観戦がいるとき
##   生存者全員の賛成」が成り立ち、B がもう一度押さなくても全員リセットが決まって鐘も戻る
func test_finding_bell_griefing_recall_vote_and_the_dead_partner() -> void:
	await _open_net()
	await _go(StageCatalog.THREE_BELLS_ID)
	var launcher := host.world.blocks[int(host.world.entity_ids["launcher"])]
	assert_true(await _drive(host.world, Vector3(9.5, 0.0, 1.5), 600), "A at the launcher")
	host.world.select_slot(_slot_for(host.world, A, THROW))
	assert_true(await _aims(host.world, host.world.player, launcher, [0.0, 0.3, -0.3]))
	assert_eq(host.world.lend_to(host.world.aimed_block(), false), RuleLedger.LendResult.OK)
	await _until(func() -> bool: return host.world.activated.has("east_bell"), "bell")
	var launcher_c := client.world.blocks[launcher.entity_id]
	assert_true(await _drive(client.world, Vector3(9.5, 0.0, -0.5), 600), "B at the launcher")
	assert_true(await _aims(client.world, client.world.player, launcher_c, [0.0, 0.3, -0.3]))
	client.world.interact(client.world.aimed_block())
	var id := launcher.entity_id
	await _until(func() -> bool: return host.world.ledger.tokens_on(id).is_empty(), "recall")
	assert_eq(host.world.ledger.ability_count(THROW, A), 0, "A's throw is gone")
	assert_eq(host.world.ledger.ability_count(THROW, B), 2, "B holds both throws")
	await wait_physics_frames(120)
	assert_true(host.world.activated.has("east_bell"), "the rung bell still counts")
	client.request_vote()
	await _until(func() -> bool: return host.lifecycle.yes_vote_count() == 1, "vote")
	await wait_physics_frames(600)
	assert_eq(host.lifecycle.reset_count(), 0, "10 s later a lone vote has not rolled it back")
	assert_true(host.lifecycle.is_vote_open(), "the lone yes vote is still open")
	assert_true(host.world.activated.has("east_bell"))
	# A が東の岸から谷へ歩いて落ちる。B は何もしない
	await _drive(host.world, Vector3(16.0, 0.0, 1.5), 120)
	await _until(func() -> bool: return host.lifecycle.reset_count() == 1, "auto reset")
	assert_false(host.world.activated.has("east_bell"), "the stale vote rolled the bell back")
	assert_eq(host.world.ledger.ability_count(THROW, A), 1, "and A's throw is back")


## 生きている1人がゴールの外にいる限りクリアしない（妨害する人はゴールに入らないだけで止められる）。
## その人が落ちて死亡観戦になると、ゴールにいる人だけでクリアし、死亡観戦の人も報酬を受け取る。
func test_finding_one_player_outside_blocks_the_clear_until_they_die() -> void:
	await _open_net()
	await _go(StageCatalog.INTRO_ID)
	host.world.player.global_position = Vector3(0.5, 2.1, -5.5)
	client.world.player.global_position = Vector3(-0.5, 2.1, -5.5)
	await wait_physics_frames(20)
	var goal := _goal_of(host)
	assert_true(await _drive(host.world, Vector3(0.5, 1.1, -7.0), 300), "A walked into the goal")
	assert_true(goal.has_point(host.world.player.global_position))
	await wait_physics_frames(600)
	assert_eq(host.last_clear_text, "", "10 s with B outside: no clear")
	# B が岩棚から南へ歩き、島の端から落ちる
	await _drive(client.world, Vector3(-0.5, 0.0, 12.0), 420)
	await _until(func() -> bool: return client.is_spectating())
	await _until(func() -> bool: return host.last_clear_text != "")
	await _until(func() -> bool: return client.progress.has_cleared(StageCatalog.INTRO_ID))


## 途中で入って待機観戦している人は、クリアの邪魔をしない（正式参加者ではない）。
func test_gate_waiting_spectator_does_not_block_the_clear() -> void:
	await _open_net(false)
	host.enter_stage(StageCatalog.INTRO_ID)
	await wait_physics_frames(5)
	await _join()
	assert_eq(host.lifecycle.state_of(B), PartyLifecycle.State.WAITING_SPECTATOR)
	host.world.player.global_position = Vector3(0.5, 2.1, -5.5)
	await wait_physics_frames(20)
	assert_true(await _drive(host.world, Vector3(0.5, 1.1, -7.0), 300), "A walked into the goal")
	await _until(func() -> bool: return host.last_clear_text != "")
	assert_false(client.progress.has_cleared(StageCatalog.INTRO_ID), "the waiting one gets nothing")


## 丘の上の旗で、2人を頂上の南の縁に置き（準備）、B が A にジャンプを渡して窪みに入る。
## B はひとりでは出られないことを確かめる。
func _trap_client_in_hill_goal() -> void:
	await _open_net()
	await _go(StageCatalog.HILL_ID)
	host.world.player.global_position = Vector3(0.5, 4.1, -4.5)
	client.world.player.global_position = Vector3(-0.5, 4.1, -4.5)
	await wait_physics_frames(20)
	var a_on_client := client.world.avatars[A] as PlayerAvatar
	client.world.select_slot(_slot_for(client.world, B, JUMP))
	assert_true(await _aims(client.world, client.world.player, a_on_client, BODY), "B aims at A")
	client.world.lend_to(client.world.aimed_block(), false)
	await _until(func() -> bool: return host.world.ledger.ability_count(JUMP, A) == 2)
	await _until(func() -> bool: return not client.world.ledger.player_can(JUMP, B))
	var goal := _goal_of(host)
	var center := goal.get_center()
	assert_true(await _drive(client.world, Vector3(center.x, goal.position.y + 0.1, center.z), 300))
	assert_false(await _drive(client.world, Vector3(0.5, 4.0, -4.0), 240), "B cannot climb out")
	assert_true(goal.has_point(client.world.player.global_position), "B is still in the hollow")


# --- 2人の協力の部品（test_net_director と同じ形） ------------------------------------


## ホストを立て、join なら参加者もつなぐ。
func _open_net(join: bool = true) -> void:
	for p: String in [HOST_PROFILE, CLIENT_PROFILE]:
		ProgressStore.new().delete(p)
	host_side = _side("HostSide")
	client_side = _side("ClientSide")
	host = _director(host_side, HOST_PROFILE)
	client = _director(client_side, CLIENT_PROFILE)
	host_net = NetWorld.new()
	host_side.add_child(host_net)
	client_net = NetWorld.new()
	client_side.add_child(client_net)
	host.enter_stage(StageCatalog.HUB_ID)
	host_net.world = host.world
	var server := ENetMultiplayerPeer.new()
	_port = 36000 + randi() % 3000
	assert_eq(server.create_server(_port, 4), OK)
	host_net.start_host(server, "host-key")
	host.attach_net(host_net)
	await wait_physics_frames(3)
	if join:
		await _join()


func _side(side_name: String) -> Node:
	var side := Node.new()
	side.name = side_name
	tree.root.add_child(side)
	tree.set_multiplayer(SceneMultiplayer.new(), side.get_path())
	return side


func _director(side: Node, profile: String) -> PartyDirector:
	var viewport := SubViewport.new()
	viewport.name = "View"
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	side.add_child(viewport)
	var d := PartyDirector.new()
	d.profile = profile
	viewport.add_child(d)
	return d


func _join() -> void:
	client.prepare_client()
	client_net.world = client.world
	client.attach_net(client_net)
	var peer := ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", _port), OK)
	client_net.start_client(peer, "bob-key")
	await _until(func() -> bool: return client.world != null and client.world.player.player_id == B)
	await wait_physics_frames(10)


func _go(stage_id: String) -> void:
	host.enter_stage(stage_id)
	await _until(func() -> bool: return client.stage_id == stage_id)
	await _until(func() -> bool: return client.world.ledger.ability_count(JUMP, B) == 1)
	await wait_physics_frames(10)


func _until(condition: Callable, what: String = "") -> void:
	for i in 600:
		if condition.call():
			return
		await tree.physics_frame
	fail("timed out %s" % what)


func _goal_of(d: PartyDirector) -> AABB:
	return d.world.def.clear_condition.goal_area()


func _slot_for(world: GameWorld, player_id: int, action: RuleAction.Kind) -> int:
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := world.ledger.hotbar_vessel(slot, player_id)
		if v != null and world.ledger.token(v.token_id).action == action:
			return slot
	return -1


## その世界の自分のアバターを target へ歩かせる（段差で止まったら跳ぶ）。着けば true。
func _drive(world: GameWorld, target: Vector3, frames: int) -> bool:
	var me := world.player
	var stuck := 0
	for i in frames:
		var flat := Vector3(target.x - me.global_position.x, 0.0, target.z - me.global_position.z)
		if flat.length() <= 0.35 and absf(me.global_position.y - target.y) < 0.7:
			me.move_intent = Vector2.ZERO
			return true
		me.view_yaw = atan2(-flat.x, -flat.z)
		me.move_intent = Vector2(0.0, 1.0)
		var moving := Vector2(me.velocity.x, me.velocity.z).length() > 0.5
		stuck = 0 if moving else stuck + 1
		if stuck > 8 and me.is_on_floor():
			world.press_action(JUMP)
			stuck = 0
		await tree.physics_frame
	me.move_intent = Vector2.ZERO
	return false
