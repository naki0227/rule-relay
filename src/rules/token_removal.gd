class_name TokenRemoval
extends RefCounted
## 台帳からトークンを消す（人数別補助の作り直しとステージ終了用。2026-11-20 引き継ぎ仕様 2-7・2-8）。
##
## RuleLedger の公開メソッドは gdlint の上限（45）に達しているので、削除の口を足さず、
## 公開済みの snapshot() → 取り除く → restore() で消す。トークンと一緒に、その器（出自）も消すので、
## 器の中・ホットバー・付与中・仲間が持っている・落ちている・範囲で共有、のどこにあっても一度で消える。
## restore() は台帳の RuleToken / RuleVessel を作り直すので、呼んだ後は参照を持ち直す
## （全員リセットは直前に台帳ごと restore するので、補助の作り直しで新たに古くなる参照は無い）。
## 消したトークンの ID は再利用しない（採番の続きは snapshot のまま）。


## token_ids のトークンと、その器を消す。台帳に無い ID は無視する。消した数を返す。
static func remove_tokens(ledger: RuleLedger, token_ids: PackedInt32Array) -> int:
	if token_ids.is_empty():
		return 0
	var data := ledger.snapshot()
	var doomed := {}
	for id in token_ids:
		doomed[id] = true
	var kept_tokens: Array[Dictionary] = []
	var removed := 0
	for d: Dictionary in data["tokens"] as Array:
		if doomed.has(int(d["id"])):
			removed += 1
		else:
			kept_tokens.append(d)
	if removed == 0:
		return 0
	var kept_vessels: Array[Dictionary] = []
	for d: Dictionary in data["vessels"] as Array:
		if not doomed.has(int(d["token_id"])):
			kept_vessels.append(d)
	data["tokens"] = kept_tokens
	data["vessels"] = kept_vessels
	ledger.restore(data)
	return removed


## ステージ中のトークン・器と、ステージの対象（ブロック・生き物）をすべて消す。
## プレイヤーの登録と参加中の印は残す（ハブへそのまま戻る）。
static func clear_stage(ledger: RuleLedger) -> void:
	var data := ledger.snapshot()
	var players := {}
	var entities := data["entities"] as Dictionary
	for id: int in entities:
		if int(entities[id]) == EntityKind.Kind.PLAYER:
			players[id] = EntityKind.Kind.PLAYER
	data["entities"] = players
	data["tokens"] = []
	data["vessels"] = []
	ledger.restore(data)
