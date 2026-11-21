extends "res://tests/integration/optional_playthrough.gd"
## 寄り道のワールドの入口（広場の秘密の場所）を能力で見つけると、進行に保存されてポータルが開く
## （docs/campaign-plan.md「寄り道のワールドの開き方」）。製品版の開き方（--campaign）で確かめる。
## 歩く・鐘を鳴らす・ポータルで F は、プレイヤーと同じ操作だけ。


func _clear(stage_id: String) -> void:
	var rewards := StageRunRewards.new(stage_id, stage_id + "#optional-overworld-test")
	var statuses: Dictionary[String, int] = {"1": StageRunRewards.Status.ACTIVE}
	rewards.settle(statuses, RunMetrics.new(), 1_790_000_000)
	var result := director.progress.apply_reward_event(rewards.event_for("1"), director.table)
	assert_eq(result.outcome, PlayerProgress.Outcome.APPLIED, "cleared %s" % stage_id)


func _campaign() -> void:
	director.all_stages_open = false
	director.all_regions_open = false


func _portal_node(stage_id: String) -> OverworldPortal:
	return w.get_node("OverworldDressing/Portal_%s" % stage_id) as OverworldPortal


## 鐘の扉を鐘で開けて庭に入ると、寄り道 O1 の入口を見つけたことが保存され、1 つ目のポータルが開く。
func test_the_bell_yard_secret_opens_the_workshop_and_is_saved() -> void:
	_campaign()
	_clear(CampaignPlan.required_stage(CampaignPlan.world("o1")))
	await _enter(StageCatalog.HUB_ID)
	assert_false(w.def.overworld.portal("o1_1").open, "sealed before the secret is found")
	assert_false(_portal_node("o1_1").is_open())
	await _walk_to(Overworld.BELL_AT + Vector3(-1.2, 0.0, 0.8), 0.4)
	w.interact(w.bells_by_key["ow_bell"])
	await wait_physics_frames(240)
	await _walk_to(Vector3(13.5, 0.0, -12.5), 0.3)
	assert_true(await _walk_to(Vector3(18.5, 0.0, -12.5), 0.5, 600), "walked into the yard")
	assert_true(director.progress.found_secrets().has("o1"), "the secret entrance is recorded")
	var saved := ProgressStore.new().load_progress(PROFILE).progress
	assert_true(saved.found_secrets().has("o1"), "and saved to the profile")
	assert_true(_portal_node("o1_1").is_open(), "the first workshop portal opened right away")
	assert_false(_portal_node("o1_2").is_open(), "the second waits for the first clear")
	await _walk_to(Vector3(19.5, 0.0, -12.5), 0.3)
	w.interact(null)
	await wait_physics_frames(5)
	assert_eq(director.stage_id, "o1_1", "entered the first optional stage")


## 入口を見つけても、opened_by のステージをクリアするまでは開かない（見つけた記録は残る）。
func test_the_secret_alone_does_not_open_before_the_required_clear() -> void:
	_campaign()
	await _enter(StageCatalog.HUB_ID)
	await _walk_to(Overworld.BELL_AT + Vector3(-1.2, 0.0, 0.8), 0.4)
	w.interact(w.bells_by_key["ow_bell"])
	await wait_physics_frames(240)
	await _walk_to(Vector3(13.5, 0.0, -12.5), 0.3)
	await _walk_to(Vector3(18.5, 0.0, -12.5), 0.5, 600)
	assert_true(director.progress.found_secrets().has("o1"), "found")
	assert_false(_portal_node("o1_1").is_open(), "still sealed until the required clear")
	_clear(CampaignPlan.required_stage(CampaignPlan.world("o1")))
	await _enter(StageCatalog.HUB_ID)
	assert_true(_portal_node("o1_1").is_open(), "opens after the clear (the find was kept)")


## 試遊の版（全部開ける）は、入口を見つけなくても寄り道のポータルが開いている。
func test_the_trial_build_opens_every_optional_portal() -> void:
	await _enter(StageCatalog.HUB_ID)
	for id in OptionalWorldPlan.IDS:
		for s in CampaignPlan.world(id).slots:
			assert_true(
				_portal_node(s.stage_id).is_open(), "%s is open in the trial build" % s.stage_id
			)
