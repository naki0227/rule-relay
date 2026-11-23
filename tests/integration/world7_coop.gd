extends "res://tests/integration/world7_playthrough.gd"
## ワールド 7 の協力の道を、2 人のオンライン協力（同じプロセスの中で ENet でつなぐ。net_party.gd）で通す
## 共通部品（ファイル名が test_ で始まらないので、これ自体は実行されない）。
## _as(i) で「いま操作する人」を切り替えると、island_playthrough.gd の歩く・跳ぶ・渡すをその人の画面で使える
## （w と _me() がその人の画面と自分のアバターになる）。能力の受け渡しは画面の操作（仲間へ渡す）で、ホストを通る。
## 仲間へ渡した能力が届いたか・拾った物が届いたかは、その人の画面の台帳で待つ。

const NetParty := preload("res://tests/integration/net_party.gd")

var party: NetParty


## 単独の進行役は使わない（2 人の部屋を作る）。
func before_each() -> void:
	pass


func after_each() -> void:
	if party != null:
		await party.close()
	ProgressStore.new().delete(PROFILE)


## 2 人の部屋を作り、ホストが stage_id に入って全員がそろうまで待つ。
func _start_pair(stage_id: String, base_port: int) -> void:
	party = NetParty.new(self, 2, "zz_test_world7_coop")
	await party.open(StageCatalog.HUB_ID, base_port)
	await party.join_all()
	await party.enter(stage_id)
	director = party.host()
	_as(0)


## i 番目の人を操作する（w・_me() がその人の画面・自分のアバターになる）。
func _as(i: int) -> void:
	w = party.world(i)


## 操作中の人の位置が、ホストの画面にも届くまで待つ（届くかどうかはホストの画面の位置で決まる）。
func _settle_me() -> void:
	for i in party.count():
		if party.world(i) == w:
			await party.settle(i)


## 操作中の人から j 番目の人へ、action を 1 つ渡す（投げるの届き方なら throwing）。届くまで待つ。
func _hand_to(j: int, action: RuleAction.Kind, throwing: bool = false) -> void:
	await _settle_me()
	await party.settle(j)
	var receiver := party.world(j)
	var before := receiver.ledger.ability_count(action, party.pid(j))
	w.select_slot(_give_slot(action))
	w.set_lend_mode(TriggerMode.Kind.NONE)
	if throwing and not w.throw_mode:
		w.toggle_reach()
	w.lend_to(w.avatars[party.pid(j)], false)
	if w.throw_mode:
		w.toggle_reach()
	assert_true(
		await party.until(
			func() -> bool: return receiver.ledger.ability_count(action, party.pid(j)) > before,
			"%s reaches side %d" % [RuleAction.label(action), j],
			240
		),
		"handed %s" % RuleAction.label(action)
	)
	await party.until(party.converged, "after handing")


## 仲間へ渡すときに選ぶホットバーの枠。自分の器の枠があればそこ（器が貸出中なら、借りている同じ能力が渡る）。
## 無ければ空いた枠（借りているだけの能力が渡る。WorldQueries.giveable_token）。
func _give_slot(action: RuleAction.Kind) -> int:
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(slot, _me().player_id)
		if v != null and w.ledger.token(v.token_id).action == action:
			return slot
	return _free_slot()


## 操作中の人が持っている action を全部、j 番目の人へ渡す。
func _hand_all_to(j: int, action: RuleAction.Kind) -> void:
	for i in 4:
		if w.ledger.ability_count(action, _me().player_id) == 0:
			return
		await _hand_to(j, action)
	assert_eq(w.ledger.ability_count(action, _me().player_id), 0, "handed every %s" % action)


## 落ちている器を拾い、ホットバーの空きへ置く（参加者は依頼なので、自分の画面に届くまで待つ）。
func _pick_remote(at: Vector3, action: RuleAction.Kind) -> void:
	await _walk_to(at, 0.6)
	await _settle_me()
	var me := _me().player_id
	var before := w.ledger.ability_count(action, me)
	w.interact(null)
	# 拾った器は、ホットバーに空きがあればそこへ入る（2026-11-23。重い・浮く・泳ぐはかばんへ）
	await party.until(
		func() -> bool:
			return _inventory_vessel(action) != null or w.ledger.ability_count(action, me) > before,
		"picked %s" % action,
		240
	)
	var v := _inventory_vessel(action)
	if v != null:
		w.ledger_actions.move_to_hotbar(v.id, _free_slot())
	await party.until(
		func() -> bool: return w.ledger.ability_count(action, me) > 0, "%s on the hotbar" % action
	)
	await party.until(party.converged, "after picking")


func _inventory_vessel(action: RuleAction.Kind) -> RuleVessel:
	for v in w.ledger.inventory_vessels(_me().player_id):
		var t := w.ledger.token(v.token_id)
		if t != null and t.action == action and not t.is_prohibition:
			return v
	return null


## ホストの画面で、全員がゴールに集まってクリアするまで待つ。
func _pair_cleared() -> bool:
	var host := party.host()
	return await party.until(func() -> bool: return host.last_clear_text != "", "cleared", 300)


## 操作中の人が、ゴールの窪みの中の (dx, dz) へ歩いて入る（2 人が重ならないようにずらす）。
func _walk_into_goal_at(dx: float) -> void:
	var goal := _goal()
	var center := goal.get_center()
	await _walk_to(Vector3(center.x + dx, goal.position.y + 0.1, center.z))
	await wait_physics_frames(10)
	assert_true(goal.has_point(_me().global_position), "standing in the goal")


## 操作中の人が鐘に触って鳴らす（参加者の F はホストへの依頼。鳴ったかはホストの画面で見る）。
func _ring_remote(key: String) -> void:
	var bell := w.bells_by_key[key]
	await _walk_to(
		bell.global_position + (_me().global_position - bell.global_position).normalized() * 1.4,
		0.5
	)
	_face(bell.global_position)
	await _settle_me()
	var host_world := party.host().world
	for i in 120:
		if host_world.activated.has(key):
			break
		if i % 20 == 0:
			w.interact(bell)
		await tree.physics_frame
	assert_true(host_world.activated.has(key), "rang %s" % key)


## 操作中の人が、ブロック（key）に付いているものを F で全部回収する（ホストの台帳に届くまで待つ）。
func _recall_all_from_remote(key: String) -> void:
	var host_world := party.host().world
	var id := int(host_world.entity_ids[key])
	await _settle_me()
	for i in 300:
		if host_world.ledger.tokens_on(id).is_empty():
			break
		if i % 15 == 0 and w.is_within_reach(_block(key)):
			w.interact(_block(key))
		await tree.physics_frame
	assert_true(host_world.ledger.tokens_on(id).is_empty(), "recalled from %s" % key)
	await party.until(party.converged, "after recalling")


## かばんの action をホットバーへ移す（参加者は依頼なので、届くまで待つ）。
func _bag_to_hotbar_remote(action: RuleAction.Kind) -> void:
	var me := _me().player_id
	var v := _inventory_vessel(action)
	if v == null and w.ledger.ability_count(action, me) > 0:
		return  # 拾ったときにホットバーへ入っていた（2026-11-23）
	assert_ne(v, null, "%s in the bag" % action)
	if v != null:
		w.ledger_actions.move_to_hotbar(v.id, _free_slot())
	await party.until(
		func() -> bool: return w.ledger.ability_count(action, me) > 0, "%s on the hotbar" % action
	)
	await party.until(party.converged, "after moving")
