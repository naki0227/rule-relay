class_name CheckpointPolicy
extends RefCounted
## チェックポイントに保存してよいかの判定（企画書 9 の要検証項目「取り返しのつかない状態のまま
## 保存できてしまう問題」への対策の1つ）。保存を断る理由を列挙し、空なら保存してよい。
## もう1つの対策（直前の安全なスナップショットを残す）は CheckpointHistory が受け持つ。

enum Blocker {
	## 空中にいる（落下中の状態を保存すると、復帰した瞬間にまた落ちる）
	AIRBORNE,
	## W/A/S/D のどれも自分で使えない（復帰しても一歩も動けない）
	CANNOT_MOVE,
	## 島から落ちていく途中のブロックがある
	FALLING_BLOCK,
	## 能力トークンの所有が壊れている（複製・行方不明。本来起きない）
	INVALID_OWNERSHIP,
	## 自分のジャンプを遠くへ貸した・投げたまま（手元に無く、登るも無い）。保存すると、戻っても
	## 上へ行けないまま（2026-11-20 試遊 F8。本人の判断で「保存の判定を直す」）。
	## 禁止の札で跳べないだけ・仲間が持っている（返してもらえる）ときは対象にしない
	JUMP_AWAY,
}

const MOVE_ACTIONS: Array[RuleAction.Kind] = [
	RuleAction.Kind.FORWARD, RuleAction.Kind.LEFT, RuleAction.Kind.BACK, RuleAction.Kind.RIGHT
]


static func save_blockers(
	ledger: RuleLedger,
	player_on_floor: bool,
	falling_block_count: int,
	player_id: int = RuleLedger.PLAYER_ID
) -> Array[Blocker]:
	var blockers: Array[Blocker] = []
	if not player_on_floor:
		blockers.append(Blocker.AIRBORNE)
	if not player_can_move(ledger, player_id):
		blockers.append(Blocker.CANNOT_MOVE)
	if falling_block_count > 0:
		blockers.append(Blocker.FALLING_BLOCK)
	if not ledger.validate().is_empty():
		blockers.append(Blocker.INVALID_OWNERSHIP)
	if jump_is_away(ledger, player_id):
		blockers.append(Blocker.JUMP_AWAY)
	return blockers


## 自分の器のジャンプが、ブロック・地形のセルへ貸し出し中か、世界に落ちていて、
## 自分は跳べず、登る（グローブ）も使えない。
static func jump_is_away(ledger: RuleLedger, player_id: int = RuleLedger.PLAYER_ID) -> bool:
	if ledger.player_has_ability(RuleAction.Kind.JUMP, player_id):
		return false
	if ledger.player_can(RuleAction.Kind.CLIMB, player_id):
		return false
	for t in ledger.all_tokens():
		if t.is_prohibition or t.action != RuleAction.Kind.JUMP:
			continue
		if PartyQuery.origin_owner(ledger, t.id) == player_id and (t.is_lent() or t.dropped):
			return true
	return false


## 自分で歩ける方向が1つでもあるか。カメラを回せばどの方角へも進めるので、1方向あれば足りる。
static func player_can_move(ledger: RuleLedger, player_id: int = RuleLedger.PLAYER_ID) -> bool:
	for action in MOVE_ACTIONS:
		if ledger.player_can(action, player_id):
			return true
	return false


static func describe(blocker: Blocker) -> String:
	match blocker:
		Blocker.AIRBORNE:
			return "足が地面についていません"
		Blocker.CANNOT_MOVE:
			return "W/A/S/D のどれも使えない状態です（1つはホットバーに戻してください）"
		Blocker.FALLING_BLOCK:
			return "島から落ちているブロックがあります"
		Blocker.INVALID_OWNERSHIP:
			return "能力の所有状態が不正です"
		Blocker.JUMP_AWAY:
			return "ジャンプを遠くに貸したままです（手元に戻してから台座に触れてください）"
	return "?"
