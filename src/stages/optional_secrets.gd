class_name OptionalSecrets
extends RefCounted
## 広場の秘密の入口（寄り道のワールドの庭・小島）を見つけたら、ホストの進行に保存してポータルを開ける
## （docs/campaign-plan.md「寄り道のワールドの開き方」）。PartyDirector が広場にいる間、毎フレーム呼ぶ。
## 誰か（参加者も）が入れば見つけたことになる。協力中の参加者の広場は、次に広場へ戻ったときに
## ホストの進行で開いた姿になる（ポータルに入るのは、ホストが判断するので今すぐ入れる）。


## 権威（1 人用・ホスト）だけが呼ぶ。
static func check(director: PartyDirector) -> void:
	var world := director.world
	if world == null or world.def.overworld == null:
		return
	for secret in world.def.overworld.secrets:
		var w := CampaignPlan.world(secret.key)
		if w == null or not w.optional or director.progress.found_secrets().has(secret.key):
			continue
		for player_id in world.ledger.players():
			var avatar := world.avatar_of(player_id)
			if avatar != null and secret.area.has_point(avatar.global_position):
				record(director, secret.key)
				break


## 寄り道のワールドの入口を見つけたことを進行に保存し、広場のポータルの見た目を開け直す。
static func record(director: PartyDirector, world_id: String) -> void:
	if not director.progress.record_secret(world_id):
		return
	director.store.save(director.profile, director.progress)
	var world := director.world
	if world != null and world.def.overworld != null:
		OverworldDressing.refresh_portals(world, director.overworld_state())
