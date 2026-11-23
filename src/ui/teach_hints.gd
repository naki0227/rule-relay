class_name TeachHints
extends RefCounted
## 照準の下に出す操作の案内を、「いまいちばん要る 1 つ」だけ選ぶ（docs/w1-teaching.md）。
## 2026-11-22 本人「ゲームが分かりにくい」。長い説明は嫌い・画面のごちゃごちゃも嫌い、に合わせて:
## - 出すのは必要になった瞬間だけ、キーの絵と数文字（例: [F] 取り戻す）。同時に 2 つ以上は出さない
## - その操作を HintMemory.LEARN_AFTER 回したら出なくなる（記録は遊ぶ人ごと。協力中も各自の画面と記録）
## - ステージに入った直後の目的の札（ObjectivePanel が大きく出ている 3 秒）とは重ねない
## - どこで何を教えるかは、ステージの「教える場所」（StageDef.HintSpot）でも決められる
## 選ぶ順（上ほど急ぐ）: その場の動作（入口・拾う）→ 貸した単発を使う → 取り戻す → 鐘 → 投げる（遠くを狙った）→
## 動物に移動をあげる → かばんの能力をホットバーへ → ステージの教える場所 → 渡す（選ぶ）→ 装備 → 保存 → 足もとの禁止 → 段差でジャンプ →
## 歩く・見回す → やり直し・メニュー。
## 返り値は [キーの表記, 動作, 表記をそのまま出すか] か、空の配列（何も出さない）。

## 段差の案内を出す、足もとから段差までの水平の距離（m。近い順に調べる）。
const STEP_AHEAD: Array[float] = [0.7, 1.4]

static var _stage_names: Dictionary[String, String] = {}


static func pick(hud: Hud, target: Node3D, in_reach: bool, on_checkpoint: bool) -> Array:
	var w := hud.world
	if w == null or w.player == null or _objectives_big(hud) or _cleared(hud):
		return []
	_learn_from_state(hud)
	# 上から順に見て、最初に当てはまった 1 つだけを返す（毎フレーム呼ぶので、残りは調べない）
	var steps: Array[Callable] = [
		func() -> Array: return _place(hud),
		func() -> Array: return _fire(hud),
		func() -> Array: return _take_back(hud, target, in_reach),
		func() -> Array: return _bell(target, in_reach),
		func() -> Array: return _throw(hud, target, in_reach),
		func() -> Array: return _creature(hud, target, in_reach),
		func() -> Array: return _bag(hud, target, in_reach),
		func() -> Array: return _spot(hud),
		func() -> Array: return _lend(hud, target, in_reach),
		func() -> Array: return _equip(hud),
		func() -> Array: return _save(hud, on_checkpoint),
		func() -> Array: return _floor_ban(hud),
		func() -> Array: return _jump(hud),
		func() -> Array: return _first_steps(hud),
		func() -> Array: return _retry(hud),
	]
	for step in steps:
		var found: Array = step.call()
		if not found.is_empty():
			return found
	return []


## 入ったばかりの目的の札が大きく出ている間は、案内を出さない（同じ画面に 2 つの説明を重ねない）。
static func _objectives_big(hud: Hud) -> bool:
	var panel := hud.get_node_or_null(^"Objectives") as ObjectivePanel
	return panel != null and panel.is_big()


## クリアした後（広場へ戻るのを待つ 4 秒）は案内を出さない。ゴールの窪みの壁を向いているだけで
## 「Space ジャンプ」が出ていた（2026-11-22 のはじめての 10 分の通し）。
static func _cleared(hud: Hud) -> bool:
	var panel := hud.get_node_or_null(^"Objectives") as ObjectivePanel
	return panel != null and panel.director != null and panel.director.last_clear_text != ""


## 状態から分かる「できた」を記録する（装備を身につけた、など。押したキーでは数えにくいもの）。
static func _learn_from_state(hud: Hud) -> void:
	var w := hud.world
	if hud.hints.should_show("equip"):
		for part: RuleVessel.Part in [RuleVessel.Part.FEET, RuleVessel.Part.HANDS]:
			if w.ledger.equipped_vessel(part, w.acting_id()) != null:
				for i in HintMemory.LEARN_AFTER:
					hud.hints.used("equip")
				return


## 足もとの物・ハブの入口（慣れても出す。そこで何ができるかの案内）。
static func _place(hud: Hud) -> Array:
	var w := hud.world
	if w.nearest_world_item() != null:
		return ["F", "拾う"]
	var stage_world := w as StageWorld
	if stage_world == null:
		return []
	var entrance := stage_world.entrance_at(w.player.global_position)
	if entrance != "":
		return ["F", "「%s」へ" % _stage_name(entrance)]
	return []


## 単発で貸した能力があるとき: 自分のキーで、貸した先が1回だけ動く（どこを向いていても出す）。
## 同じブロックにジャンプと W/A/S/D の単発があれば「跳んでから進む」（ブロックが段を上がる）。
static func _fire(hud: Hud) -> Array:
	var w := hud.world
	var me := w.acting_id()
	if hud.hints.should_show("jump_then_move"):
		var combo := _jump_then_move(w, me)
		if not combo.is_empty():
			return combo
	if not hud.hints.should_show("fire"):
		return []
	for action_name: StringName in PlayerInput.ACTION_KEYS:
		var kind: RuleAction.Kind = PlayerInput.ACTION_KEYS[action_name]
		if not w.ledger.pending_single_shots(kind, me).is_empty():
			return [InputMode.key(action_name), "貸した%sを使う" % RuleAction.label(kind), true]
	return []


static func _jump_then_move(w: GameWorld, me: int) -> Array:
	var jumps := w.ledger.pending_single_shots(RuleAction.Kind.JUMP, me)
	if jumps.is_empty():
		return []
	for action_name: StringName in [&"move_forward", &"move_left", &"move_back", &"move_right"]:
		var kind: RuleAction.Kind = PlayerInput.ACTION_KEYS[action_name]
		for t in w.ledger.pending_single_shots(kind, me):
			for j in jumps:
				if not _shares_holder(t, j):
					continue
				var keys := "%s→%s" % [InputMode.key(&"jump"), InputMode.key(action_name)]
				return [keys, "跳んでから進む", true]
	return []


static func _shares_holder(a: RuleToken, b: RuleToken) -> bool:
	for id in a.holder_ids:
		if b.holder_ids.has(id):
			return true
	return false


## 能力（禁止）が付いている物を、手の届くところで狙っているとき。自分が貸した物なら「取り戻す」。
static func _take_back(hud: Hud, target: Node3D, in_reach: bool) -> Array:
	if target == null or not in_reach or target is Bell or target is PlayerAvatar:
		return []
	var w := hud.world
	var tokens := w.ledger.tokens_on(int(target.get("entity_id")))
	if tokens.is_empty():
		return []
	if tokens.any(func(t: RuleToken) -> bool: return t.is_prohibition):
		return ["F", "禁止を取る"] if hud.hints.should_show("ban") else []
	if not hud.hints.should_show("recall"):
		return []
	var me := w.acting_id()
	var mine := tokens.any(func(t: RuleToken) -> bool: return t.lender_id == me)
	return ["F", "取り戻す" if mine else "取る"]


static func _bell(target: Node3D, in_reach: bool) -> Array:
	return ["F", "鳴らす"] if target is Bell and in_reach else []


## 使える能力が本当にかばんにあって、ホットバーに空きがあるとき（何かを狙って渡す案内とは重ねない）。
## 拾った・F で取った能力は空きがあればホットバーへ入るので（2026-11-23）、ふだんは出ない。
static func _bag(hud: Hud, target: Node3D, in_reach: bool) -> Array:
	if target != null and in_reach and not target is TerrainCell:
		return []  # 足もとの地面を見ているだけなら出す
	if not hud.needs_bag_prompt():
		return []
	return [InputMode.key(&"inventory"), "かばんの能力をホットバーへ", true]


## ステージの「教える場所」（StageDef.HintSpot）。近くにいて、まだ慣れていない案内のうち、いちばん近いもの。
static func _spot(hud: Hud) -> Array:
	var stage_world := hud.world as StageWorld
	if stage_world == null or stage_world.def == null:
		return []
	var at := hud.world.player.global_position
	var best: StageDef.HintSpot = null
	var best_distance := INF
	for spot in stage_world.def.hint_spots:
		if not hud.hints.should_show(spot.key) or absf(at.y - spot.position.y) > 1.6:
			continue
		if spot.while_holding != "" and not _holds_tokens(stage_world, spot.while_holding):
			continue
		var d := Vector2(at.x - spot.position.x, at.z - spot.position.z).length()
		if d <= spot.radius and d < best_distance:
			best = spot
			best_distance = d
	if best == null:
		return []
	return [best.keyboard, best.text]


static func _holds_tokens(w: StageWorld, key: String) -> bool:
	if not w.entity_ids.has(key):
		return false
	return not w.ledger.tokens_on(int(w.entity_ids[key])).is_empty()


## 移動の無い生き物を、手の届くところで狙っているとき。
static func _creature(hud: Hud, target: Node3D, in_reach: bool) -> Array:
	var creature := target as Creature
	if creature == null or not in_reach or creature.can_walk():
		return []
	return ["左クリック", "移動をあげる"] if hud.hints.should_show("creature_move") else []


## 手の届く相手を狙っているとき。選んでいる能力の名前を出す（何を渡すのかが分かるように）。
## 地形のセルには、初めのうちは出さない（地面に渡すことはステージの教える場所で教える）。
## 手元に禁止があれば「禁止をえらぶ」（手放し方）、窪みのブロックに W/A/S/D を渡しそうなら「ジャンプをえらぶ」。
static func _lend(hud: Hud, target: Node3D, in_reach: bool) -> Array:
	if target == null or not in_reach or target is TerrainCell or target is Bell:
		return []
	var w := hud.world
	var creature := target as Creature
	var token := _selected_token(w)
	var ban_slot := _free_slot_of(w, func(t: RuleToken) -> bool: return t.is_prohibition)
	if (
		hud.hints.should_show("ban")
		and ban_slot >= 0
		and ban_slot != w.selected_slot
		and creature == null
	):
		return [_slot_key(ban_slot), "禁止をえらぶ", true]
	if not hud.hints.should_show("lend"):
		return []
	if token == null:
		return [InputMode.label("1〜9"), "能力をえらぶ", true]
	var jump_slot := _free_slot_of(
		w, func(t: RuleToken) -> bool: return t.action == RuleAction.Kind.JUMP
	)
	var is_move := RuleAction.is_horizontal(token.action) and not token.is_prohibition
	if (
		hud.hints.should_show("select")
		and is_move
		and jump_slot >= 0
		and target is RuleBlock
		and _in_pit(w, target as RuleBlock)
	):
		return [_slot_key(jump_slot), "ジャンプをえらぶ", true]
	if not token.holder_ids.is_empty():
		return []
	return ["左クリック", "%sを渡す" % Hud.token_label(token)]


## ホットバーの n 番を選ぶキーの表記（パッドは LB / RB）。
static func _slot_key(slot: int) -> String:
	if InputMode.using_pad:
		return InputMode.label("1〜9")
	return InputMode.key(StringName("slot_%d" % (slot + 1)))


## 窪みのブロック（まわり 4 方向のうち 3 つ以上が同じ高さの地形）。乗って持ち上げる台。
static func _in_pit(w: GameWorld, block: RuleBlock) -> bool:
	if w.terrain == null:
		return false
	var cell := block.cell()
	var walls := 0
	for side: Vector3i in [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)
	]:
		if w.terrain.has_cell(cell + side):
			walls += 1
	return walls >= 3


## 手の届かない相手を狙っているとき（「投げる」を持っていれば、届き方を変えれば届く）。
static func _throw(hud: Hud, target: Node3D, in_reach: bool) -> Array:
	if target == null or in_reach or not hud.hints.should_show("throw"):
		return []
	if hud.world.throw_mode:
		return ["C", "遠すぎる"]
	if hud.world.can_throw():
		return ["C", "投げるで届く"]
	return []


## 装備を持っているのに身につけていない（ホットバー・かばんの装備は効かない。docs/adr/0018）。
static func _equip(hud: Hud) -> Array:
	if not hud.hints.should_show("equip"):
		return []
	var w := hud.world
	var me := w.acting_id()
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(slot, me)
		if v != null and v.is_equipment():
			return ["E", "そうびする"]
	for v in w.ledger.inventory_vessels(me):
		if v.is_equipment():
			return ["E", "そうびする"]
	return []


static func _save(hud: Hud, on_checkpoint: bool) -> Array:
	return ["F", "ここで保存"] if on_checkpoint and hud.hints.should_show("save") else []


## 禁止の付いたブロックの上に立っている（その禁止は上に立つ人にも効く。docs/adr/0003 決定 7）。
static func _floor_ban(hud: Hud) -> Array:
	if not hud.hints.should_show("ban"):
		return []
	var w := hud.world
	for block in FloorBans.blocks_under(w.player):
		if w.ledger.tokens_on(block.entity_id).any(
			func(t: RuleToken) -> bool: return t.is_prohibition
		):
			return ["F", "下を見て禁止を取る"]
	return []


## 自分で跳べる段差（高さ 1）の前に立って、その方を向いているとき。
static func _jump(hud: Hud) -> Array:
	var w := hud.world
	if not hud.hints.should_show("jump") or w.terrain == null or not w.player.is_on_floor():
		return []
	if not w.player.can(RuleAction.Kind.JUMP):
		return []
	var yaw := w.camera_rig.yaw if w.camera_rig != null else w.player.view_yaw
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var feet := floori(w.player.global_position.y + 0.05)
	for reach: float in STEP_AHEAD:
		var ahead := w.player.global_position + forward * reach
		var cell := Vector3i(floori(ahead.x), feet, floori(ahead.z))
		if w.terrain.has_cell(cell + Vector3i.UP):
			return []  # 2 段以上の壁（自分では跳べない）
		if w.terrain.has_cell(cell):
			return [InputMode.key(&"jump"), "ジャンプ", true]
	return []


## 歩く・見回す（初めて遊ぶ人の最初の数秒だけ。歩くのが先、慣れたら見回す）。
static func _first_steps(hud: Hud) -> Array:
	if hud.hints.should_show("move"):
		return [Hud.move_keys(), "歩く", true]
	if hud.hints.should_show("look"):
		return [Hud.look_keys(), "見回す", true]
	return []


## ステージで目安の時間を過ぎたら、やり直しとメニューの場所をそっと出す（使ったら出なくなる）。
static func _retry(hud: Hud) -> Array:
	var stage_world := hud.world as StageWorld
	if stage_world == null or stage_world.def == null or stage_world.def.is_hub():
		return []
	if hud.stage_seconds < stage_world.def.target_minutes * 60.0:
		return []
	if hud.hints.should_show("vote"):
		return ["V", "長押しでやり直し"]
	if hud.hints.should_show("menu"):
		return ["Esc", "メニュー"]
	return []


static func _selected_token(w: GameWorld) -> RuleToken:
	var v := w.selected_vessel()
	return null if v == null else w.ledger.token(v.token_id)


## ホットバーで、貸していない器のうち matches に合う能力・禁止の枠（無ければ -1）。
static func _free_slot_of(w: GameWorld, matches: Callable) -> int:
	var me := w.acting_id()
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(slot, me)
		if v == null or v.is_equipment():
			continue
		var t := w.ledger.token(v.token_id)
		if t != null and t.holder_ids.is_empty() and t.carrier_id == -1 and bool(matches.call(t)):
			if t.is_prohibition or not w.ledger.player_prohibited(t.action, me):
				return slot
	return -1


static func _stage_name(stage_id: String) -> String:
	if not _stage_names.has(stage_id):
		var stage := StageCatalog.by_id(stage_id)
		_stage_names[stage_id] = stage.display_name if stage != null else stage_id
	return _stage_names[stage_id]
