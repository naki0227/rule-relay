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
	return blockers


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
	return "?"
