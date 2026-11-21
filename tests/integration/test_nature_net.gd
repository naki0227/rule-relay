extends TestCase
## 2人のオンライン協力で、風と水が両方の画面で同じに働く（docs/adr/0015）。
## - 風・水はどの画面も同じ定義から作る。自分のアバターは自分の画面で風・水を受け、位置をホストへ送る。
## - 脈打つ風の拍子（時計）は、ホストが WorldFrame で配る。
## - 浮くブロックの流れはホストが動かし、参加者は受け取った位置へ動く。
## - 泳げずに沈んだ参加者は、島から落ちたのと同じく、ホストの判定で死亡→観戦になる。
##
## 試しの置き方: 導入ステージ（出現地点の列は z = 4.5）の上に、出現地点を西へ吹き抜ける風
## （x -5〜5, z 3〜6）と、島の外（x 200〜206、底なし）に東へ流れる川を、両方の画面で置く。

const NetParty := preload("res://tests/integration/net_party.gd")
const A := RuleLedger.PLAYER_ID
const B := 2
const WEST := Vector3i(-1, 0, 0)
const EAST := Vector3i(1, 0, 0)
## 川（水のセルの上面 y = 0）で浮いている人の足は y ≈ -0.65。沈み始めた人と分けるための下限。
const SURFACE_FLOOR := -1.0

var party: NetParty
var host: PartyDirector
var client: PartyDirector


func before_each() -> void:
	party = NetParty.new(self, 2, "zz_test_nature_net")
	host = party.directors[0]
	client = party.directors[1]
	await party.open(StageCatalog.HUB_ID, 36000)
	await party.join(1)
	await party.enter(StageCatalog.INTRO_ID)


func after_each() -> void:
	await party.close()


## 同じ置き方を両方の画面に（ステージの定義に書いたのと同じ）。
func _build_nature(wind_period: float = 0.0) -> void:
	for i in 2:
		var layout := NatureLayout.new()
		var wind := layout.add_wind(Vector3i(-5, 0, 3), Vector3i(5, 2, 6), WEST)
		if wind_period > 0.0:
			wind.period = wind_period
			wind.on_time = wind_period * 0.5
		layout.add_current(Vector3i(200, -2, 0), Vector3i(206, -1, 6), EAST)
		NatureBuilder.build(party.world(i), layout)


func test_wind_blows_the_client_and_the_host_sees_it() -> void:
	# ホストは重い（流されない）、参加者はふつう
	host.world.ledger.give_player_item(RuleAction.Kind.HEAVY, false, 8, A)
	await party.until(func() -> bool: return party.converged(), "ledger synced")
	_build_nature()
	var host_start := host.world.player.global_position
	var client_start := client.world.player.global_position
	await wait_physics_frames(40)
	var blown := client_start.x - client.world.player.global_position.x
	assert_gt(blown, 1.2, "the client is blown west on its own screen")
	await party.settle(1)
	var seen := host.world.avatars[B].global_position
	assert_almost(seen.x, client.world.player.global_position.x, 0.15, "the host sees it")
	assert_almost(host.world.player.global_position.x, host_start.x, 0.05, "heavy host stands")


func test_the_gust_clock_follows_the_host() -> void:
	_build_nature(2.0)
	host.world.nature.clock = 10.0
	client.world.nature.clock = 0.0
	await party.until(
		func() -> bool: return absf(client.world.nature.clock - host.world.nature.clock) < 0.2,
		"the client's clock catches up"
	)
	var host_wind := host.world.find_child("Wind", false, false) as WindVisual
	var client_wind := client.world.find_child("Wind", false, false) as WindVisual
	await wait_physics_frames(2)
	assert_eq(client_wind.is_blowing(), host_wind.is_blowing(), "both screens gust together")


func test_a_floating_block_drifts_on_both_screens() -> void:
	_build_nature()
	var cell := Vector3i(201, -1, 1)
	var on_host := host.world.add_block(cell)
	var on_client := client.world.add_block(cell)
	on_client.remote = true
	assert_eq(on_host.entity_id, on_client.entity_id, "same id on both screens")
	host.world.ledger.place_on_entity(
		RuleAction.Kind.FLOAT, false, on_host.entity_id, TriggerMode.Kind.NONE
	)
	await wait_physics_frames(200)
	assert_true(on_host.afloat, "floats on the host")
	assert_gt(float(on_host.cell().x), 201.0, "carried east by the current")
	assert_almost(on_client.global_position.x, on_host.global_position.x, 0.3, "client follows")


func test_a_swimming_client_is_carried_and_a_sinking_one_dies() -> void:
	_build_nature()
	host.world.ledger.give_player_item(RuleAction.Kind.SWIM, false, 8, B)
	await party.until(
		func() -> bool: return BodyTraits.swim_level(client.world.ledger, B) == 1, "swim arrives"
	)
	var me := client.world.player
	me.global_position = Vector3(200.5, -0.3, 3.5)
	me.velocity = Vector3.ZERO
	await wait_physics_frames(45)
	assert_true(me.afloat, "swimming")
	assert_gt(me.global_position.x, 201.5, "the current carries the client")
	# 流れに運ばれ続けて止まらないので、party.settle（止まった位置がホストに届くまで待つ）は使えない。
	# 動き続ける相手との差は 0.1 未満にならず、待つ間に川の東の端（x = 207）から落ちて死んでしまう。
	# ホストの画面で、流れに運ばれて水面に浮いている姿が見えるまで待ってから確かめる。
	await party.until(
		func() -> bool:
			var seen := host.world.avatar_of(B).global_position
			var in_water := host.world.nature.water_at(seen) != null
			return in_water and seen.x > 201.5 and seen.y > SURFACE_FLOOR,
		"the host sees the client swimming in the current"
	)
	assert_true(me.afloat, "still swimming when the host looks")
	assert_eq(host.lifecycle.state_of(B), PartyLifecycle.State.ACTIVE, "afloat is alive")
	# 泳ぐを取り上げると沈み、落ちたのと同じく観戦になる
	var v := host.world.ledger.hotbar_vessel(8, B)
	host.world.ledger.move_to_inventory(v.id)
	await party.until(func() -> bool: return client.is_spectating(), "sank and spectates", 600)
	assert_eq(host.lifecycle.state_of(B), PartyLifecycle.State.DEAD_SPECTATING)
