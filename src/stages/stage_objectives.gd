class_name StageObjectives
extends RefCounted
## ステージの目的の一覧（画面の隅の短いチェックリスト。docs/adr/0020）。ステージのクリア条件（ClearCondition）
## から作る純粋なデータで、物理に依存しない。
##
## - 条件の木（ALL_OF の中も）を葉に分け、同じ種類・同じ文の葉を 1 行にまとめる（鐘 3 つ → 「鐘を鳴らす 0/3」）
## - 行の順: どうぶつ → 運ぶ物 → 鐘 → 時の鐘 → 高い所 → ゴール（ゴールはいつも最後。クリアの決め手なので）
## - 文は条件の objective_text があればそれ、無ければ種類と対象（生き物か・時の鐘か）から決める
## - 進み具合（行ごとの「できた数 / 要る数」）はホストが ClearCondition.is_met と同じ材料（snapshot）で数え、
##   party の配信で参加者へ届ける（PartyDirector）。参加者は自分で数えない（全員の画面が同じになる）
## 一覧は表示だけで、クリアの判定はこれまでどおり ClearCondition が決める（順番も強制しない）。

enum Icon { ANIMAL, CARRY, BELL, TIMED_BELL, HEIGHT, GOAL, OTHER }

const TEXT_ANIMAL := "どうぶつを巣へ"
const TEXT_CARRY := "ブロックを運ぶ"
const TEXT_BELL := "鐘を鳴らす"
const TEXT_TIMED_BELL := "時の鐘を鳴らす"
const TEXT_OTHER := "しかけを動かす"
const TEXT_HEIGHT := "高い所へのぼる"
const TEXT_GOAL := "全員でゴールへ"
## ひとりのとき（要る人が 1 人以下）のゴールの文。
const TEXT_GOAL_SOLO := "ゴールへ"


## 一覧の 1 行。
class Item:
	var icon: Icon = Icon.OTHER
	var text: String = ""
	## この行にまとめた条件（葉）
	var conditions: Array[ClearCondition] = []
	## できた数 / 要る数（ゴールは「ゴールにいる生きている人 / 生きている人」）
	var done: int = 0
	var total: int = 0

	func is_met() -> bool:
		return total > 0 and done >= total

	## 画面に出す文（数は 2 つ以上要るときだけ。ひとりのゴールは「ゴールへ」）。
	func label() -> String:
		var head := text
		if icon == Icon.GOAL and total <= 1 and text == TEXT_GOAL:
			head = TEXT_GOAL_SOLO
		if total > 1:
			return "%s %d/%d" % [head, mini(done, total), total]
		return head

	## テスト・ログ用の文（印つき）。
	func describe() -> String:
		return "%s %s" % ["[x]" if is_met() else "[ ]", label()]


## 定義から一覧を作る（数はまだ 0。measure で数える）。クリア条件が無ければ空。
static func build(def: StageDef) -> Array[Item]:
	var items: Array[Item] = []
	if def == null or def.is_hub():
		return items
	var leaves: Array[ClearCondition] = []
	_collect(def.clear_condition, leaves)
	var by_key: Dictionary[String, Item] = {}
	for leaf in leaves:
		var icon := _icon_of(def, leaf)
		var text := leaf.objective_text if leaf.objective_text != "" else _default_text(icon)
		var key := "%d|%s" % [icon, text]
		if not by_key.has(key):
			var item := Item.new()
			item.icon = icon
			item.text = text
			by_key[key] = item
			items.append(item)
		by_key[key].conditions.append(leaf)
	for item in items:
		item.total = item.conditions.size()
	items.sort_custom(func(a: Item, b: Item) -> bool: return int(a.icon) < int(b.icon))
	return items


## 一覧の進み具合を数える（権威だけが呼ぶ。snapshot は ClearCondition.is_met と同じ形）。
## 返り値は [できた数, 要る数] を行の順に並べたもの（配信する形）。items にもそのまま入れる。
static func measure(items: Array[Item], snapshot: Dictionary) -> PackedInt32Array:
	var counts := PackedInt32Array()
	for item in items:
		if item.icon == Icon.GOAL:
			_count_goal(item, snapshot)
		else:
			item.done = 0
			for c in item.conditions:
				if c.is_met(snapshot):
					item.done += 1
			item.total = item.conditions.size()
		counts.append(item.done)
		counts.append(item.total)
	return counts


## 配信で届いた数を一覧に入れる（参加者）。形が合わなければ何もしない。
static func apply(items: Array[Item], counts: PackedInt32Array) -> void:
	if counts.size() != items.size() * 2:
		return
	for i in items.size():
		items[i].done = counts[i * 2]
		items[i].total = counts[i * 2 + 1]


## 一覧の文（テスト・一時停止の画面用）。
static func describe_all(items: Array[Item]) -> PackedStringArray:
	var lines := PackedStringArray()
	for item in items:
		lines.append(item.describe())
	return lines


static func _collect(c: ClearCondition, out: Array[ClearCondition]) -> void:
	if c == null:
		return
	if c.kind == ClearCondition.Kind.ALL_OF:
		for part in c.parts:
			_collect(part, out)
	elif c.kind != ClearCondition.Kind.NONE:
		out.append(c)


static func _icon_of(def: StageDef, c: ClearCondition) -> Icon:
	match c.kind:
		ClearCondition.Kind.ALL_AT_GOAL:
			return Icon.GOAL
		ClearCondition.Kind.REACH_HEIGHT:
			return Icon.HEIGHT
		ClearCondition.Kind.CARRY_OBJECT:
			for creature in def.creatures:
				if creature.key == c.target_key:
					return Icon.ANIMAL
			return Icon.CARRY
		ClearCondition.Kind.ACTIVATE:
			for timed in def.mechanisms.timed_bells:
				if timed.key == c.target_key:
					return Icon.TIMED_BELL
			for bell in def.bells:
				if bell.key == c.target_key:
					return Icon.BELL
	return Icon.OTHER


static func _default_text(icon: Icon) -> String:
	match icon:
		Icon.ANIMAL:
			return TEXT_ANIMAL
		Icon.CARRY:
			return TEXT_CARRY
		Icon.BELL:
			return TEXT_BELL
		Icon.TIMED_BELL:
			return TEXT_TIMED_BELL
		Icon.HEIGHT:
			return TEXT_HEIGHT
		Icon.GOAL:
			return TEXT_GOAL
	return TEXT_OTHER


## ゴールの行: 生きている人のうち、ゴールの箱にいる人の数 / 生きている人の数。
static func _count_goal(item: Item, snapshot: Dictionary) -> void:
	var positions := snapshot.get("positions", {}) as Dictionary
	var active := snapshot.get("active", PackedInt32Array()) as PackedInt32Array
	var inside := 0
	for id in active:
		if not positions.has(id):
			continue
		for c in item.conditions:
			if c.area.has_point(positions[id] as Vector3):
				inside += 1
				break
	item.done = inside
	item.total = active.size()
