class_name WorldParty
extends RefCounted
## GameWorld に仲間のアバターを出し入れし、ホストが参加者の代わりに操作するための補助（通信専用）。
## GameWorld が長くなりすぎないよう切り出した。


## 仲間のアバター（操り人形）を置く。
static func add_avatar(w: GameWorld, player_id: int, at: Vector3) -> PlayerAvatar:
	var avatar := PlayerAvatar.new()
	avatar.name = "Avatar%d" % player_id
	avatar.puppet = true
	avatar.player_id = player_id
	avatar.ledger = w.ledger
	avatar.position = at
	w.add_child(avatar)
	w.avatars[player_id] = avatar
	return avatar


static func remove_avatar(w: GameWorld, player_id: int) -> void:
	if w.avatars.has(player_id):
		w.avatars[player_id].queue_free()
		w.avatars.erase(player_id)


## ホストが参加者の代わりに操作する: その人のアバター・選んでいる枠・方式・届き方に一時的に切り替えて
## action を呼び、元に戻す。メッセージは sink（その人へ返す）に送る。
static func act_as(
	w: GameWorld, player_id: int, choice: Dictionary, sink: Callable, action: Callable
) -> void:
	var avatar := w.avatars.get(player_id) as PlayerAvatar
	if avatar == null:
		return
	var saved := [w.player, w.selected_slot, w.lend_mode, w.throw_mode, w.post_sink]
	w.player = avatar
	w.selected_slot = clampi(int(choice.get("slot", 0)), 0, RuleLedger.HOTBAR_SIZE - 1)
	w.lend_mode = int(choice.get("mode", TriggerMode.Kind.SINGLE_SHOT)) as TriggerMode.Kind
	w.throw_mode = bool(choice.get("throw", false)) and w.can_throw()
	w.post_sink = sink
	action.call()
	w.player = saved[0]
	w.selected_slot = saved[1]
	w.lend_mode = saved[2]
	w.throw_mode = saved[3]
	w.post_sink = saved[4]


## 参加者が依頼に添える「いまの選択」。
static func current_choice(w: GameWorld) -> Dictionary:
	return {"slot": w.selected_slot, "mode": w.lend_mode, "throw": w.throw_mode}
