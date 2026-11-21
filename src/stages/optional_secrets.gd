class_name OptionalSecrets
extends RefCounted
## 広場の秘密の入口（寄り道のワールドの庭・小島）を見つけたら、そのとき部屋にいる全員の進行に保存して
## ポータルを開ける（docs/campaign-plan.md「寄り道のワールドの開き方」）。PartyDirector が広場にいる間、毎フレーム呼ぶ。
## 誰か（参加者も）が入れば見つけたことになる。
##
## 発見はステージの報酬と同じく、1 人ずつ自分の PC の進行に入る（2026-11-21 の v0.2.0 レビュー）。ホストは自分の進行に
## 入れ、つながっている参加者へは PartyDirector._secret で送り、参加者は自分の進行に入れて保存する。
## 同じ発見は何度届いても 1 回分（PlayerProgress.record_secret が覚えている）。ホストは、届けた人を
## PartyDirector.secrets_told に覚えて毎フレーム送り直さない。後から来た人・その場にいなかった人には届かないが、
## その人が広場で同じ場所に入れば、その人にも届く（その人を含めた、まだ届けていない全員に届く）。
## 協力中の参加者の広場の見た目は、次に広場へ戻ったときにホストの進行で開いた姿になる
## （ポータルに入るのは、ホストが判断するので今すぐ入れる）。


## 権威（1 人用・ホスト）だけが呼ぶ。
static func check(director: PartyDirector) -> void:
	var world := director.world
	if world == null or world.def.overworld == null:
		return
	for secret in world.def.overworld.secrets:
		var w := CampaignPlan.world(secret.key)
		if w == null or not w.optional or _untold(director, secret.key).is_empty():
			continue
		for player_id in world.ledger.players():
			var avatar := world.avatar_of(player_id)
			if avatar != null and secret.area.has_point(avatar.global_position):
				deliver(director, secret.key)
				break


## いまつながっている人のうち、まだこの発見を届けていない人。
static func _untold(director: PartyDirector, world_id: String) -> PackedInt32Array:
	var told: Dictionary = director.secrets_told.get(world_id, {})
	var result := PackedInt32Array()
	for player_id in director.connected_players():
		if not told.has(player_id):
			result.append(player_id)
	return result


## 発見を、いまつながっている全員（まだ届けていない人）へ届ける。権威だけが呼ぶ。
static func deliver(director: PartyDirector, world_id: String) -> void:
	var told: Dictionary = director.secrets_told.get(world_id, {})
	for player_id in _untold(director, world_id):
		if player_id == director.local_id():
			record(director, world_id)
		else:
			director._secret.rpc_id(director.net.session.peer_of_player(player_id), world_id)
		told[player_id] = true
	director.secrets_told[world_id] = told


## 寄り道のワールドの入口を見つけたことを自分の進行に保存し、広場のポータルの見た目を開け直す。
static func record(director: PartyDirector, world_id: String) -> void:
	if not director.progress.record_secret(world_id):
		return
	director.store.save(director.profile, director.progress)
	var world := director.world
	if world != null and world.def.overworld != null:
		OverworldDressing.refresh_portals(world, director.overworld_state())
