class_name ClearCondition
extends RefCounted
## ステージ固有のクリア条件（2026-11-20 引き継ぎ仕様 2-3・5.1、受け入れ 17）。純粋な判定で、物理に依存しない。
## 結果の状態だけを見て、開発者の想定手順は強制しない（引き継ぎ仕様 2-5「ルールは厳格に。解法は自由に。」）。
##
## 判定の材料（snapshot の辞書。実行時の層が毎フレーム作って渡す）:
## - "positions": Dictionary  正式参加者の player_id → 足もとの位置（Vector3）
## - "active": PackedInt32Array  正式参加者のうち、いま操作中（生きている）人
## - "entities": Dictionary  ステージ内の key（StageDef の BlockSpec.key など）→ 位置（Vector3）
## - "activated": PackedStringArray  作動した仕掛けの key（鳴らした鐘など）
## 途中入室で待機観戦している人は正式参加者ではないので、どちらにも入れない（引き継ぎ仕様 4.3）。
##
## 誰が「必要な人」か:
## - REACH_HEIGHT / ALL_AT_GOAL は active の人だけを見る。死亡観戦中の人の体は数えない
## - ALL_AT_GOAL は active の全員が goal に入れば成立。死亡観戦中の人の到達は要らない
##   （仮の判断。引き継ぎ仕様 5.1「条件成立後は死亡観戦中の人もクリア・報酬」から、生きている人だけで
##   達成できる形にした。通信切断中の人を active に入れるかは実行時の層が決める）
## - active が空（全員死亡）なら、どの人の条件も成立しない

enum Kind { NONE, REACH_HEIGHT, ALL_AT_GOAL, CARRY_OBJECT, ACTIVATE, ALL_OF }

## 足もとの高さの誤差（物理で 2.999 のように少し沈むため）。仮値。
const HEIGHT_TOLERANCE: float = 0.05

var kind: Kind = Kind.NONE
## REACH_HEIGHT は水平（x・z）の範囲だけ、ALL_AT_GOAL / CARRY_OBJECT は箱の中を見る。
var area: AABB = AABB()
## REACH_HEIGHT の高さ（足もとがこの高さ以上）。
var height: float = 0.0
## CARRY_OBJECT の対象物、ACTIVATE の仕掛けの key。
var target_key: String = ""
## ALL_OF: これが全部成り立てばクリア（手分けして別々の鐘を鳴らす、など）。
var parts: Array[ClearCondition] = []


static func none() -> ClearCondition:
	return ClearCondition.new()


## 正式参加者の誰か（操作中）が、範囲の上で高さ height 以上に立つ。
static func reach_height(p_area: AABB, p_height: float) -> ClearCondition:
	var c := ClearCondition.new()
	c.kind = Kind.REACH_HEIGHT
	c.area = p_area
	c.height = p_height
	return c


## 操作中の正式参加者が全員、ゴールの箱の中にいる。
static func all_at_goal(goal: AABB) -> ClearCondition:
	var c := ClearCondition.new()
	c.kind = Kind.ALL_AT_GOAL
	c.area = goal
	return c


## 物体（key）が箱の中にある。
static func carry_object(key: String, goal: AABB) -> ClearCondition:
	var c := ClearCondition.new()
	c.kind = Kind.CARRY_OBJECT
	c.target_key = key
	c.area = goal
	return c


## 全部が成り立つ（順番は問わない。例: 3つの鐘を全部鳴らす）。
static func all_of(conditions: Array[ClearCondition]) -> ClearCondition:
	var c := ClearCondition.new()
	c.kind = Kind.ALL_OF
	c.parts = conditions
	return c


## 仕掛け（key）が作動した（鐘を鳴らした など）。
static func activate(key: String) -> ClearCondition:
	var c := ClearCondition.new()
	c.kind = Kind.ACTIVATE
	c.target_key = key
	return c


func is_met(snapshot: Dictionary) -> bool:
	match kind:
		Kind.REACH_HEIGHT:
			return _anyone_high(snapshot)
		Kind.ALL_AT_GOAL:
			return _everyone_in_goal(snapshot)
		Kind.CARRY_OBJECT:
			var entities := snapshot.get("entities", {}) as Dictionary
			return entities.has(target_key) and area.has_point(entities[target_key] as Vector3)
		Kind.ACTIVATE:
			return (snapshot.get("activated", PackedStringArray()) as PackedStringArray).has(
				target_key
			)
		Kind.ALL_OF:
			return (
				not parts.is_empty()
				and parts.all(func(c: ClearCondition) -> bool: return c.is_met(snapshot))
			)
	return false


## ゴールの箱（ALL_AT_GOAL。ALL_OF の中も探す）。無ければ大きさ 0 の AABB。
## 「島の条件＋生きている全員がゴールに集まる」（docs/adr/0011 決定 9）の目印・検査に使う。
func goal_area() -> AABB:
	if kind == Kind.ALL_AT_GOAL:
		return area
	if kind == Kind.ALL_OF:
		for c in parts:
			var found := c.goal_area()
			if found.has_volume():
				return found
	return AABB()


## ゴールにまだ来ていない人（試遊 G5、2026-11-20 本人の判断）。HUD に出す情報だけで、誰も止めない・外さない。
## 生きている人（active）のうち、ゴールの箱に入っていない人を ID 昇順で返す。
## 出すのは「島の条件（ゴール以外の部分）がそろった」か「生きている誰かがゴールにいる」ときだけ。
## それ以外・ゴールの無い条件・全員そろっているときは空。
func goal_stragglers(snapshot: Dictionary) -> PackedInt32Array:
	var goal := goal_area()
	var missing := PackedInt32Array()
	if not goal.has_volume():
		return missing
	var positions := snapshot.get("positions", {}) as Dictionary
	var someone_in := false
	for id in _active(snapshot):
		if positions.has(id) and goal.has_point(positions[id] as Vector3):
			someone_in = true
		else:
			missing.append(id)
	if not someone_in and not _stage_parts_met(snapshot):
		return PackedInt32Array()
	missing.sort()
	return missing


func describe() -> String:
	if kind == Kind.ALL_OF:
		var texts := PackedStringArray()
		for c in parts:
			texts.append(c.describe())
		return "全部: " + "／".join(texts)
	match kind:
		Kind.REACH_HEIGHT:
			return "高さ %.0f の場所へ誰かが上がる" % height
		Kind.ALL_AT_GOAL:
			return "動ける全員がゴールに入る"
		Kind.CARRY_OBJECT:
			return "%s をゴールへ運ぶ" % target_key
		Kind.ACTIVATE:
			return "%s を作動させる" % target_key
	return "クリア条件なし"


func _anyone_high(snapshot: Dictionary) -> bool:
	var positions := snapshot.get("positions", {}) as Dictionary
	for id in _active(snapshot):
		if not positions.has(id):
			continue
		var at := positions[id] as Vector3
		var inside := (
			at.x >= area.position.x
			and at.x <= area.end.x
			and at.z >= area.position.z
			and at.z <= area.end.z
		)
		if inside and at.y >= height - HEIGHT_TOLERANCE:
			return true
	return false


func _everyone_in_goal(snapshot: Dictionary) -> bool:
	var positions := snapshot.get("positions", {}) as Dictionary
	var active := _active(snapshot)
	if active.is_empty():
		return false
	for id in active:
		if not positions.has(id) or not area.has_point(positions[id] as Vector3):
			return false
	return true


func _active(snapshot: Dictionary) -> PackedInt32Array:
	return snapshot.get("active", PackedInt32Array()) as PackedInt32Array


## ALL_OF の、ゴールに集まる以外の部分（鐘・運ぶ物など）が全部成り立っているか。
## そういう部分が無い条件（ゴールだけ）は false（ステージに入っただけで一覧を出さないため）。
func _stage_parts_met(snapshot: Dictionary) -> bool:
	if kind != Kind.ALL_OF:
		return false
	var found := false
	for c in parts:
		if c.kind == Kind.ALL_AT_GOAL:
			continue
		if not c.is_met(snapshot):
			return false
		found = true
	return found
