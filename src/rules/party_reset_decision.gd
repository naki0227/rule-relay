class_name PartyResetDecision
extends RefCounted
## 全員チェックポイントリセットが決まったことを呼び出し側へ伝える結果（PartyLifecycle が作る）。
## 受け取った側が、checkpoint_id の時点のスナップショットで世界と台帳を丸ごと戻し、
## headcount が previous_headcount と違えば人数別補助を headcount 人用に組み直す（引き継ぎ仕様 2-7・4.2）。
## PartyLifecycle 自身は世界も台帳も戻さない。参加者の状態だけを先に切り替えておく。

enum Reason {
	## 投票の母数の過半数が賛成した（1→1、2→2、3→2、4→3）
	MAJORITY,
	## 死亡観戦者がいるときに、生存者全員が賛成した（仕様 4.2。仮の扱いは ADR 0007）
	SURVIVORS_AGREED,
	## 操作できる人が誰もいなくなった（全員死亡・ソロの死亡）。投票を待たずに自動で戻す
	NO_ONE_ALIVE,
}

var reason: Reason = Reason.MAJORITY
## 戻す先。PartyLifecycle.STAGE_START ならステージに入った時点
var checkpoint_id: String = ""
## 何回目のリセットか（1 から）。同じ決定の再送を二重に適用しないために使う
var generation: int = 0
## リセット後に操作するプレイヤー（途中待機から合流した人を含む。通信切断中の人は含まない）
var active_player_ids: PackedInt32Array = PackedInt32Array()
## 途中待機観戦から、このリセットで正式参加になったプレイヤー
var joined_player_ids: PackedInt32Array = PackedInt32Array()
## 人数別補助を組む人数（= active_player_ids の数）
var headcount: int = 0
## リセット前に補助を組んでいた人数
var previous_headcount: int = 0


## 人数別補助を組み直す必要があるか。
func headcount_changed() -> bool:
	return headcount != previous_headcount


func to_dict() -> Dictionary:
	return {
		"reason": reason,
		"checkpoint_id": checkpoint_id,
		"generation": generation,
		"active_player_ids": active_player_ids.duplicate(),
		"joined_player_ids": joined_player_ids.duplicate(),
		"headcount": headcount,
		"previous_headcount": previous_headcount,
	}


static func from_dict(data: Dictionary) -> PartyResetDecision:
	var d := PartyResetDecision.new()
	d.reason = int(data["reason"]) as Reason
	d.checkpoint_id = str(data["checkpoint_id"])
	d.generation = int(data["generation"])
	d.active_player_ids = PackedInt32Array(data["active_player_ids"])
	d.joined_player_ids = PackedInt32Array(data["joined_player_ids"])
	d.headcount = int(data["headcount"])
	d.previous_headcount = int(data["previous_headcount"])
	return d
