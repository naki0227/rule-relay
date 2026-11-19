class_name BlockRules
extends RefCounted
## ブロックが行動を試みたときの判定と、範囲付与の対象選択。物理の状態は呼び出し側が渡す。

enum Attempt {
	SUCCESS,
	## 禁止を持っている。能力より優先して行動を始めない。
	PROHIBITED,
	## 能力を持っていない。
	NO_ABILITY,
	## 物理的に行動できない（空中・頭上や進路が塞がれているなど）。
	NOT_READY,
}

## 範囲付与の半径（ブロック単位）。企画書の候補は5または10で、P0は5を試す（仮値）。
const DEFAULT_RANGE_RADIUS: float = 5.0


## 行動を試みた結果。禁止 → 能力 → 物理の順に判定する（禁止優先）。
## 「キーを押しただけ」では成功にしない: physically_ready が偽なら NOT_READY。
static func attempt(
	ledger: RuleLedger, entity_id: int, action: RuleAction.Kind, physically_ready: bool
) -> Attempt:
	if ledger.entity_prohibited(entity_id, action):
		return Attempt.PROHIBITED
	if not ledger.entity_has_ability(entity_id, action):
		return Attempt.NO_ABILITY
	if not physically_ready:
		return Attempt.NOT_READY
	return Attempt.SUCCESS


## 単発で、対象のうち1つでも行動に成功したか（表示と音の出し分けに使う）。
## 返還は成否によらず起動したら戻る（RuleLedger.complete_single_shot）。
static func single_shot_succeeded(results: Array[Attempt]) -> bool:
	return results.has(Attempt.SUCCESS)


## 範囲付与の対象を選ぶ。水平面の円（中心から各ブロック中心までの水平距離 <= radius）で、
## 縦は layer と同じ1層だけ。candidates は {entity_id: Vector3i（グリッド座標）}。
## 円に一部だけ掛かったブロックの扱いは「中心が円内なら対象」とする（仮）。
static func select_in_range(
	center: Vector3, radius: float, layer: int, candidates: Dictionary
) -> PackedInt32Array:
	var selected := PackedInt32Array()
	for entity_id: int in candidates:
		var cell := candidates[entity_id] as Vector3i
		if cell.y != layer:
			continue
		var flat := Vector2(float(cell.x) + 0.5 - center.x, float(cell.z) + 0.5 - center.z)
		if flat.length() <= radius + 0.0001:
			selected.append(entity_id)
	selected.sort()
	return selected
