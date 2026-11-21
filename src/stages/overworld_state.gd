class_name OverworldState
extends RefCounted
## 広場（オーバーワールド）の様子を決める入力（純粋なデータ）。協力中はホストの進行で決め、参加者へ配る
## （docs/adr/0013）。広場の地形・ポータル・住む生き物・建物・開始時の能力は、これだけから決まる。

## クリアしたステージ（ホストの進行。PlayerProgress.cleared_stages）
var cleared: PackedStringArray = PackedStringArray()
## 見つけた寄り道のワールドの入口（ホストの進行。PlayerProgress.found_secrets）
var found: PackedStringArray = PackedStringArray()
## 試遊の版: ポータルを全部開ける（PartyDirector.all_stages_open）
var all_stages_open: bool = true
## 試遊の版・デバッグ: 地方を全部つなぐ（橋・階段を全部出し、岩をどける）
var all_regions_open: bool = true
## デバッグ: 広場で使える能力を全部持たせる（ふだんはクリアで開いた分だけ）
var all_abilities: bool = false


static func of(
	p_cleared: PackedStringArray,
	stages_open: bool,
	regions_open: bool,
	abilities: bool,
	p_found: PackedStringArray = PackedStringArray()
) -> OverworldState:
	var state := OverworldState.new()
	state.cleared = p_cleared.duplicate()
	state.found = p_found.duplicate()
	state.all_stages_open = stages_open
	state.all_regions_open = regions_open
	state.all_abilities = abilities
	return state


## 製品版の初めての状態（何もクリアしていない・何も開けない）。
static func first_visit() -> OverworldState:
	var state := OverworldState.new()
	state.all_stages_open = false
	state.all_regions_open = false
	return state


## 全部開けた状態（デバッグ・スクリーンショット用）。clear_all なら作ってあるステージを全部クリア済みにする。
static func everything(clear_all: bool) -> OverworldState:
	var state := OverworldState.new()
	state.all_abilities = true
	if clear_all:
		for def in StageCatalog.all_stages():
			state.cleared.append(def.stage_id)
	return state


func is_region_open(world_id: String) -> bool:
	var w := CampaignPlan.world(world_id)
	return all_regions_open or CampaignPlan.is_region_open(w, cleared, found)


func is_stage_open(stage_id: String) -> bool:
	return all_stages_open or CampaignPlan.is_stage_open(stage_id, cleared, found)


func has_cleared(stage_id: String) -> bool:
	return cleared.has(stage_id)


## 広場のホットバーに足す能力（W/A/S/D・ジャンプのほかに、クリアで開いた分）。
func unlocked_actions() -> Array[RuleAction.Kind]:
	if all_abilities:
		var every: Array[RuleAction.Kind] = []
		for key: String in CampaignPlan.GRANT_ACTIONS:
			every.append(CampaignPlan.GRANT_ACTIONS[key])
		return every
	return CampaignPlan.unlocked_actions(cleared)


func to_dict() -> Dictionary:
	return {
		"cleared": cleared.duplicate(),
		"found": found.duplicate(),
		"all_stages_open": all_stages_open,
		"all_regions_open": all_regions_open,
		"all_abilities": all_abilities,
	}


## 通信から来た値なので、形が違えば既定の状態にする。
static func from_dict(data: Dictionary) -> OverworldState:
	var state := OverworldState.new()
	if data.get("cleared") is PackedStringArray:
		state.cleared = (data["cleared"] as PackedStringArray).duplicate()
	if data.get("found") is PackedStringArray:
		state.found = (data["found"] as PackedStringArray).duplicate()
	state.all_stages_open = bool(data.get("all_stages_open", true))
	state.all_regions_open = bool(data.get("all_regions_open", true))
	state.all_abilities = bool(data.get("all_abilities", false))
	return state
