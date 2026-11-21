extends TestCase
## 部屋の出方と報酬・寄り道の入口の発見（2026-11-21 の v0.2.0 レビュー。docs/reports/2026-11-21-v0.2.0-review.md）。
## - メニューの「ゲームをやめる」で参加者が抜けたら、ホストは「退出」（LEFT）として扱い、その回の報酬を渡さない
## - 意図しない通信切断は「通信が切れた人」（DISCONNECTED）のまま、部屋がある間に戻れば報酬が届く
## - 広場の秘密の入口の発見は、その場にいた全員の、それぞれの PC の進行に入る
## 部屋の組み立ては net_party.gd（2人）。

const NetParty := preload("res://tests/integration/net_party.gd")
const B := 2

var party: NetParty
var host: PartyDirector
var client: PartyDirector


func before_each() -> void:
	party = NetParty.new(self, 2, "zz_test_leave")
	host = party.directors[0]
	client = party.directors[1]
	await party.open(StageCatalog.HUB_ID, 37000)
	await party.join_all()


func after_each() -> void:
	await party.close()


func _until(condition: Callable, what: String = "") -> bool:
	return await party.until(condition, what, 600)


## 導入の島で、ホストだけがゴールの窪みに入ってクリアする（抜けた・切れた人はゴールに来なくてよい）。
func _host_clears_intro_alone() -> StageRunRewards:
	var in_goal := Vector3(0.5, float(StageCatalog.INTRO_GOAL_MAX.y + 1) + 0.1, -7.5)
	host.world.player.global_position = in_goal
	host.world.player.velocity = Vector3.ZERO
	await _until(func() -> bool: return host.last_clear_text != "", "the host clears alone")
	var runs: Array = host.export_state()["runs"]
	assert_eq(runs.size(), 1, "one run was settled")
	return StageRunRewards.from_dict(runs[0] as Dictionary)


func _host_lost_b() -> bool:
	return party.nets[0].session.peer_of_player(B) == -1


## メニューの「ゲームをやめる」（PauseMenu.choose("quit") → PartyExit.quit）で参加者が抜ける。
## ホストは退出を受け付けて返事をし、参加者はそれを待ってから通信を閉じる。ホストの記録は LEFT のままで、
## 通信が閉じても「通信が切れた人」に変わらない。クリアしても、その人の報酬は作られず届かない。
func test_quitting_from_the_menu_is_a_leave_and_gets_no_reward_for_the_run() -> void:
	await party.enter(StageCatalog.INTRO_ID)
	var acks: Array[int] = [0]
	client.left_room.connect(func() -> void: acks[0] += 1)
	var finished: Array[bool] = [false]
	var menu := PauseMenu.new()
	menu.quit_request = func() -> void:
		await PartyExit.quit(client, func() -> void: finished[0] = true)
	party.sides[1].add_child(menu)
	var started := Time.get_ticks_msec()
	menu.choose("quit")
	assert_true(await _until(func() -> bool: return finished[0], "the menu quit finishes"))
	assert_eq(acks[0], 1, "the host acknowledged the leave before the client closed")
	assert_lt(Time.get_ticks_msec() - started, int(PartyExit.LEAVE_TIMEOUT * 1000.0), "no timeout")
	assert_false(party.nets[1].is_online(), "the client closed its connection")
	assert_eq(host.lifecycle.state_of(B), PartyLifecycle.State.LEFT, "recorded as a leave")
	await _until(_host_lost_b, "the host sees the connection closed")
	await wait_physics_frames(10)
	assert_eq(
		host.lifecycle.state_of(B), PartyLifecycle.State.LEFT, "still a leave, not a disconnect"
	)
	var rewards := await _host_clears_intro_alone()
	assert_eq(rewards.status_of(str(B)), StageRunRewards.Status.LEFT_BEFORE_CLEAR)
	assert_false(rewards.is_eligible(str(B)), "no reward for the player who left")
	assert_eq(rewards.events_to_send(PackedStringArray([str(B)])), [], "nothing to deliver later")
	assert_true(rewards.is_eligible("1"), "the host still gets the reward")
	assert_false(client.progress.has_cleared(StageCatalog.INTRO_ID), "the leaver got nothing")
	var saved := ProgressStore.new().load_progress(client.profile).progress
	assert_false(saved.has_cleared(StageCatalog.INTRO_ID), "nothing was saved for the leaver")


## 意図しない通信切断（退出を送らずに通信が閉じる）は守られる: ホストは「通信が切れた人」として報酬を作り、
## 部屋がある間に戻ってきたら届けられるよう、配達待ちのまま持つ。
func test_an_unexpected_disconnect_keeps_the_reward_while_the_room_exists() -> void:
	await party.enter(StageCatalog.INTRO_ID)
	party.nets[1].close()
	await _until(_host_lost_b, "the host sees the connection lost")
	await wait_physics_frames(5)
	assert_eq(host.lifecycle.state_of(B), PartyLifecycle.State.DISCONNECTED, "a disconnect")
	var rewards := await _host_clears_intro_alone()
	assert_eq(rewards.status_of(str(B)), StageRunRewards.Status.DISCONNECTED)
	assert_true(rewards.is_eligible(str(B)), "the disconnected player keeps the reward")
	assert_eq(rewards.pending_keys(), PackedStringArray([str(B)]), "waiting for B to come back")
	assert_eq(rewards.events_to_send(PackedStringArray([str(B)])).size(), 1, "sent on reconnect")


## ホストがメニューからやめても、参加者の退出としては送らない（ホスト移譲で部屋が続き、前のホストは
## 「通信が切れた人」になる。PartyExit の説明）。1人用も同じで、何も送らずにすぐ終わる。
func test_the_host_quitting_does_not_send_a_leave() -> void:
	assert_false(host.leave_room(), "the host has nobody to leave to")
	var finished: Array[bool] = [false]
	await PartyExit.quit(host, func() -> void: finished[0] = true)
	assert_true(finished[0], "finished without waiting for an acknowledgement")
	await _until(func() -> bool: return not party.nets[1].is_online(), "the client loses the host")
	assert_false(client.leave_room(), "nothing to send once the connection is gone")


## 広場の秘密の入口に参加者が入ると、ホストと参加者の両方の進行に入り、それぞれの PC に保存される。
## 同じ発見は何度届いても 1 回分。
func test_a_secret_found_in_the_hub_is_saved_for_every_player_present() -> void:
	var secret: OverworldLayout.SecretSpec = null
	for s in host.world.def.overworld.secrets:
		var w := CampaignPlan.world(s.key)
		if w != null and w.optional:
			secret = s
			break
	assert_true(secret != null, "the hub has an optional-world secret")
	assert_false(host.progress.found_secrets().has(secret.key))
	assert_false(client.progress.found_secrets().has(secret.key))
	var inside := secret.area.get_center()
	inside.y = secret.area.position.y + 0.4
	client.world.player.global_position = inside
	client.world.player.velocity = Vector3.ZERO
	await _until(
		func() -> bool: return client.progress.found_secrets().has(secret.key),
		"the client gets the discovery"
	)
	assert_true(host.progress.found_secrets().has(secret.key), "the host found it too")
	for director: PartyDirector in [host, client]:
		var saved := ProgressStore.new().load_progress(director.profile).progress
		assert_true(saved.found_secrets().has(secret.key), "saved in %s" % director.profile)
	OptionalSecrets.deliver(host, secret.key)  # 届け直しても何も起きない
	client._secret(secret.key)
	await wait_physics_frames(10)
	assert_eq(client.progress.found_secrets().count(secret.key), 1, "recorded once")
	assert_eq(host.progress.found_secrets().count(secret.key), 1, "recorded once")
