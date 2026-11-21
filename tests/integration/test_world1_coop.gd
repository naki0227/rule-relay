extends "res://tests/integration/coop_stage_route.gd"
## はじまりの草原（W1）の新しいステージの協力の道（2 人のオンライン協力。部品は coop_stage_route.gd）。
## ひとりの道は test_world1_stages.gd、関所と詰みの試遊は test_world1_probes.gd。

const BACK := RuleAction.Kind.BACK
const FORWARD := RuleAction.Kind.FORWARD
const RIGHT := RuleAction.Kind.RIGHT


## 押し石の小道: ホストが段の縁を削って溝を埋め、参加者が生き物に移動を渡す（手分け）。
func test_push_path_two_players_split_the_pushing_and_the_kit() -> void:
	await _start("w1_push_path", 52000)
	await _walk(0, Vector3(1.5, 0.0, 0.5), 0.3)
	await _push(0, _w(0).terrain_target(Vector3i(-1, 1, -1)), BACK)
	var kit := _creature(1, "kit")
	await _walk(1, kit.global_position + Vector3(1.4, 0.0, 0.0), 0.4)
	await _lend(1, kit, RIGHT, TriggerMode.Kind.NONE)
	var ledge := AABB(Vector3(-7.0, 1.9, -6.0), Vector3(15.0, 1.0, 6.0))
	assert_true(await _wait_creature_in("kit", ledge, 900), "the kit hopped up the carved stairs")
	await _walk_route(0, [Vector3(-0.5, 1.0, 0.5), Vector3(-0.5, 2.0, -2.5)])
	await _walk(0, Vector3(0.5, 2.0, -4.6), 0.3)
	await _push(0, _w(0).terrain_target(Vector3i(0, 1, -6)), FORWARD)
	assert_true(await _wait_creature_in("kit", OpenIslandsW1.PATH_NEST), "the kit reached its nest")
	await _walk_route(1, [Vector3(-0.5, 1.0, 0.5), Vector3(-0.5, 2.0, -2.5)])
	await _walk_route(0, [Vector3(1.5, 2.0, -2.5), Vector3(3.0, 1.0, -4.5)])
	await _walk_route(1, [Vector3(1.5, 2.0, -2.0), Vector3(5.0, 1.0, -4.5)])
	await _assert_cleared_by_everyone("w1_push_path")


## 持ち上げ台の段々: ジャンプは 2 つしかない（人数によらない）。参加者が浜から石 1 を押し落とし、
## ホストが動物のジャンプを借りて頂のジャンプを取り、石 2 を落として参加者へ渡す。ホストが動物を送り出した
## あと、残りの 1 つを段の縁から下の仲間へ順に渡して（受け渡し）、2 人とも石の段で頂へ上がる。
func test_lift_steps_two_players_relay_the_last_jump() -> void:
	await _start("w1_lift_steps", 52100)
	await _walk(1, Vector3(-2.5, 0.0, 0.4), 0.25)
	for k in 3:
		await _push(1, _block(1, "stone_low"), BACK)
	await _settle_block(0, "stone_low")
	assert_eq(_block(0, "stone_low").cell(), Vector3i(-4, 0, 0), "the guest pushed the low stone")
	var critter := _creature(0, "critter")
	await _walk(0, critter.global_position + Vector3(1.4, 0.0, 0.0), 0.4)
	await _interact_and_hold(0, critter, JUMP)
	await _walk_route(0, [Vector3(-3.5, 1.0, 0.5), Vector3(-3.5, 2.0, -1.5)])
	await _walk(0, Vector3(4.5, 2.0, -5.5))
	await _ride_lift(0, "terrace_lift", Vector3(4.5, 4.0, -8.6))
	await _walk(0, Vector3(4.5, 4.0, -11.5), 0.6)
	await _interact_and_hold(0, null, JUMP)
	await _walk(0, Vector3(-2.5, 4.0, -10.5))
	for k in 3:
		await _push(0, _block(0, "stone_high"), BACK)
	await _settle_block(0, "stone_high")
	assert_eq(_block(0, "stone_high").cell(), Vector3i(-4, 2, -7), "the high stone is in place")
	# 段の縁から、下の参加者へ 1 つ渡す。ホストは残りの 1 つを動物へ
	await _walk_route(0, [Vector3(-2.5, 2.0, -5.5), Vector3(-2.5, 2.0, -1.4)])
	await _walk(1, Vector3(-2.5, 0.0, 0.4), 0.3)
	await _give(0, 1, JUMP)
	await _walk(0, Vector3(-2.1, 0.0, 4.5), 0.4)
	await _lend(0, _creature(0, "critter"), JUMP, TriggerMode.Kind.NONE)
	await _lend(0, _creature(0, "critter"), RIGHT, TriggerMode.Kind.NONE)
	assert_true(await _wait_creature_in("critter", OpenIslandsW1.STEPS_NEST), "the critter is home")
	# 参加者が段へ上がって縁から渡す → ホストが段へ → 頂へ上がって縁から渡す → 参加者が頂へ
	await _walk_route(1, [Vector3(-3.5, 1.0, 0.5), Vector3(-3.5, 2.0, -1.5)])
	await _walk(0, Vector3(-2.5, 0.0, 0.4), 0.3)
	await _give(1, 0, JUMP)
	await _walk_route(0, [Vector3(-3.5, 1.0, 0.5), Vector3(-3.5, 2.0, -1.5)])
	await _walk_route(0, [Vector3(-3.5, 2.0, -5.5), Vector3(-3.5, 3.0, -6.5)])
	await _walk_route(0, [Vector3(-3.5, 4.0, -8.5), Vector3(-2.5, 4.0, -8.6)])
	await _walk(1, Vector3(-2.5, 2.0, -6.6), 0.3)
	await _give(0, 1, JUMP)
	await _walk_route(1, [Vector3(-3.5, 3.0, -6.5), Vector3(-3.5, 4.0, -8.5)])
	await _walk_route(0, [Vector3(0.5, 4.0, -11.5), Vector3(2.0, 3.0, -14.5)])
	await _walk_route(1, [Vector3(0.5, 4.0, -12.0), Vector3(3.9, 3.0, -14.5)])
	await _assert_cleared_by_everyone("w1_lift_steps")


## 参加者の画面でも、生き物の願い（行き先の光の柱・一文・頭の上の印）がホストと同じに見える。
func test_push_path_guest_sees_the_kits_wish() -> void:
	await _start("w1_push_path", 52200)
	var guest_kit := _creature(1, "kit")
	assert_eq(guest_kit.wish_text(), Creature.WISH_NEST, "the guest has the wish text")
	assert_eq(guest_kit.wish_box, OpenIslandsW1.PATH_NEST, "and the nest")
	assert_false(_w(1).find_children("WishMarker*", "WishMarker", false, false).is_empty())
	assert_eq(guest_kit.bubble_key(), CreatureWishView.KEY_NEED_MOVE, "asks for a move")
	await _walk(1, guest_kit.global_position + Vector3(1.4, 0.0, 0.0), 0.4)
	await _lend(1, guest_kit, RIGHT, TriggerMode.Kind.NONE)
	var host_kit := _creature(0, "kit")
	for i in 600:
		if host_kit.bubble_key() == CreatureWishView.KEY_STUCK:
			break
		await tree.physics_frame
	await wait_physics_frames(20)
	assert_eq(host_kit.bubble_key(), CreatureWishView.KEY_STUCK, "stuck at the step on the host")
	assert_eq(guest_kit.bubble_key(), CreatureWishView.KEY_STUCK, "the guest sees the same")
