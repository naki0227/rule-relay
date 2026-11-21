class_name InventoryQuery
extends RefCounted
## 持ち物（ホットバー＋通常インベントリ）の検索・絞り込み・状態表示（企画書 7 の UI 必須項目）。
## 通常インベントリは無制限なので、名前・種類・状態のどれでも引けるようにする。UI から分離した純粋な判定。

enum Category { ALL, ABILITY, PROHIBITION, EQUIPMENT, LENT }

enum State {
	## ホットバーにあり、自分に効いている能力
	ACTIVE,
	## 通常インベントリにあり、自分には効かない能力
	STORED,
	## 他者へ付与中（能力・禁止とも本人には効かない）
	LENT,
	## 手元にあり、自分に効いている禁止（ホットバーでも通常インベントリでも）
	PROHIBITION_APPLIED,
	## 装備欄にあり、自分に効いている装備
	EQUIPPED,
}


## 検索結果の1行。
class Entry:
	extends RefCounted
	var vessel_id: int
	var token: RuleToken
	var location: RuleVessel.Location
	var slot: int
	var state: State
	var label: String
	var state_text: String
	var is_equipment: bool
	var part: RuleVessel.Part


## ホットバー（スロット順）→ 装備欄（頭・体・手・足）→ 通常インベントリ（入手順）の順に、条件に合う持ち物を返す。
## text は空白区切りの全語を含むものだけを残す（AND）。大文字小文字・全角半角・カタカナとひらがなは区別しない。
static func search(
	ledger: RuleLedger, text: String, category: Category, player_id: int = RuleLedger.PLAYER_ID
) -> Array[Entry]:
	var words := normalize(text).split(" ", false)
	var result: Array[Entry] = []
	for v in _all_vessels(ledger, player_id):
		var entry := describe(ledger, v)
		if not _in_category(entry, category):
			continue
		var haystack := search_text(entry)
		var matched := true
		for word in words:
			if not haystack.contains(word):
				matched = false
				break
		if matched:
			result.append(entry)
	return result


## 1つの器の表示内容と状態。
static func describe(ledger: RuleLedger, v: RuleVessel) -> Entry:
	var t := ledger.token(v.token_id)
	var entry := Entry.new()
	entry.vessel_id = v.id
	entry.token = t
	entry.location = v.location
	entry.slot = v.slot
	entry.label = ("%s禁止" if t.is_prohibition else "%s") % RuleAction.label(t.action)
	entry.is_equipment = v.is_equipment()
	entry.part = v.part
	if v.is_equipment() and v.item_name != "":
		entry.label = v.item_name
	if not t.is_in_vessel():
		entry.state = State.LENT
		var target := _away_text(t)
		var mode := "" if t.mode == TriggerMode.Kind.NONE else "・" + TriggerMode.label(t.mode)
		entry.state_text = "貸出中（%s%s）" % [target, mode]
		if v.is_equipment():
			# 装備は入れ物が残り、中の能力だけが出ている（docs/adr/0018）
			entry.state_text = "空・中の能力を貸出中（%s%s）" % [target, mode]
		if v.location == RuleVessel.Location.EQUIPPED:
			entry.state_text += "・装備しているが効かない"
	elif t.is_prohibition:
		entry.state = State.PROHIBITION_APPLIED
		entry.state_text = "禁止適用中"
	elif v.location == RuleVessel.Location.EQUIPPED:
		entry.state = State.EQUIPPED
		entry.state_text = "装備中（%s）" % RuleVessel.part_label(v.part)
	elif v.is_equipment():
		entry.state = State.STORED
		entry.state_text = "無効（装備していない）"
	elif v.location == RuleVessel.Location.HOTBAR:
		entry.state = State.ACTIVE
		entry.state_text = "有効"
	else:
		entry.state = State.STORED
		entry.state_text = "無効（通常インベントリでは効かない）"
	return entry


## 検索対象の文字列（正規化済み）。
static func search_text(entry: Entry) -> String:
	var parts := PackedStringArray([entry.label, entry.state_text])
	parts.append("禁止" if entry.token.is_prohibition else "能力")
	parts.append(location_text(entry))
	parts.append_array(action_words(entry.token.action))
	if entry.is_equipment:
		parts.append_array(["装備", "そうび", RuleVessel.part_label(entry.part), "equipment"])
	return normalize(" ".join(parts))


## 行動ごとの検索語（表示名のほかに、キー名・読み・方角・英語でも引ける）。
## 型付きの定数 Dictionary に配列リテラルを入れると Godot 4.6.3 で読み出し時にクラッシュしたため関数にした。
static func action_words(action: RuleAction.Kind) -> PackedStringArray:
	match action:
		RuleAction.Kind.FORWARD:
			return PackedStringArray(["w", "前", "前進", "まえ", "北", "forward"])
		RuleAction.Kind.LEFT:
			return PackedStringArray(["a", "左", "ひだり", "西", "left"])
		RuleAction.Kind.BACK:
			return PackedStringArray(["s", "後", "後退", "うしろ", "南", "back"])
		RuleAction.Kind.RIGHT:
			return PackedStringArray(["d", "右", "みぎ", "東", "right"])
		RuleAction.Kind.JUMP:
			return PackedStringArray(["じゃんぷ", "跳", "space", "スペース", "jump"])
		RuleAction.Kind.DASH:
			return PackedStringArray(["だっしゅ", "突進", "shift", "シフト", "dash"])
		RuleAction.Kind.THROW:
			return PackedStringArray(["なげる", "投", "遠く", "c", "throw"])
		RuleAction.Kind.HIGH_JUMP:
			return PackedStringArray(["たかとび", "高跳", "ぶーつ", "靴", "じゃんぷ", "boots"])
		RuleAction.Kind.CLIMB:
			return PackedStringArray(["のぼる", "登", "壁", "ぐろーぶ", "手袋", "climb"])
		RuleAction.Kind.HEAVY:
			return PackedStringArray(["おもい", "重", "おもり", "風", "沈む", "heavy"])
		RuleAction.Kind.FLOAT:
			return PackedStringArray(["うく", "浮", "ふうせん", "ゆっくり", "float"])
		RuleAction.Kind.SWIM:
			return PackedStringArray(["およぐ", "泳", "水", "あしひれ", "swim"])
	return PackedStringArray()


static func location_text(entry: Entry) -> String:
	if entry.location == RuleVessel.Location.HOTBAR:
		return "ホットバー%d" % (entry.slot + 1)
	if entry.location == RuleVessel.Location.EQUIPPED:
		return "装備欄（%s）" % RuleVessel.part_label(entry.part)
	return "通常インベントリ"


## 小文字化、全角英数字・記号を半角に、カタカナをひらがなに、空白を1つにそろえる。
static func normalize(text: String) -> String:
	var out := ""
	for i in text.length():
		var code := text.unicode_at(i)
		if code >= 0xFF01 and code <= 0xFF5E:
			code -= 0xFEE0  # 全角英数字・記号 → 半角
		elif code == 0x3000:
			code = 0x20  # 全角スペース
		elif code >= 0x30A1 and code <= 0x30F6:
			code -= 0x60  # カタカナ → ひらがな
		out += String.chr(code)
	return " ".join(out.to_lower().split(" ", false))


static func category_label(category: Category) -> String:
	match category:
		Category.ABILITY:
			return "能力"
		Category.PROHIBITION:
			return "禁止"
		Category.EQUIPMENT:
			return "装備"
		Category.LENT:
			return "貸出中"
	return "すべて"


static func _in_category(entry: Entry, category: Category) -> bool:
	match category:
		Category.ABILITY:
			return not entry.token.is_prohibition
		Category.PROHIBITION:
			return entry.token.is_prohibition
		Category.EQUIPMENT:
			return entry.is_equipment
		Category.LENT:
			return entry.state == State.LENT
	return true


static func _all_vessels(ledger: RuleLedger, player_id: int) -> Array[RuleVessel]:
	var result: Array[RuleVessel] = []
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := ledger.hotbar_vessel(slot, player_id)
		if v != null:
			result.append(v)
	for part: RuleVessel.Part in [
		RuleVessel.Part.HEAD, RuleVessel.Part.BODY, RuleVessel.Part.HANDS, RuleVessel.Part.FEET
	]:
		var equipped := ledger.equipped_vessel(part, player_id)
		if equipped != null:
			result.append(equipped)
	result.append_array(ledger.inventory_vessels(player_id))
	return result


## 器を離れた能力がどこにあるか（貸出中の表示用）。
static func _away_text(t: RuleToken) -> String:
	if t.carrier_id != -1:
		return "仲間が持っている"
	if t.dropped:
		return "落ちている"
	return "範囲%d個" % t.holder_ids.size() if t.is_range else "単体"
