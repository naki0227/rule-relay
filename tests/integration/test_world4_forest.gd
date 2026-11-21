extends "res://tests/integration/world_playing.gd"
## 4-6 森の奥（難しい★）を、ひとりで最初から最後まで自動で遊ぶ（2 通り）。協力の道は test_world34_coop.gd、
## 関所と詰みは test_world4_probes.gd。操作はプレイヤーと同じで、瞬間移動しない。

const ID := DeepForest.ID
const KIT_PERCH := AABB(Vector3(-6.0, 1.5, -12.0), Vector3(1.0, 2.0, 1.0))


func _take_the_weight() -> int:
	assert_true(await _wait_door("cage_door", false), "the cage is open")
	var slot := await _pick(DeepForest.HEAVY_AT, HEAVY)
	await _walk_to(Vector3(-3.5, 1.0, 2.5), 0.3)
	return slot


func _forest_cross_and_goal() -> void:
	assert_true(await _wait_door("forest_bridge", true), "the bridge rose")
	await _walk_to(Vector3(8.6, 1.0, 6.0), 0.3)
	await _walk_to(Vector3(19.5, 1.0, 6.0), 0.35, 400)
	await _walk_into_goal([Vector3(19.5, 1.0, 1.5), Vector3(22.5, 1.0, 1.5)])
	assert_true(await _cleared(), "the creature is on its dais and everyone is at the goal")


## 道 1: 子どもに D を投げ渡して岩へ上げ、檻の前から「投げる」を投げ渡す → 木の実で鐘（8 秒）→ おもりを取る →
## 願いの動物に重い・ジャンプ・A → 台の板を 1 匹で押す → ジャンプなしで橋を渡る。
func test_deep_forest_the_kits_nut_and_the_heavy_wish() -> void:
	await _enter(ID)
	await _walk_to(Vector3(-3.5, 1.0, 0.6), 0.3)
	await _give_creature("kit", [_slot_of(RIGHT)], true)
	assert_true(await _wait_creature_in("kit", KIT_PERCH), "the kit hopped onto its rock")
	await _walk_to(Vector3(-3.6, 1.0, 2.5), 0.3)
	await _give_creature("kit", [_slot_of(THROW)], true)
	assert_true(await _wait_until_rung("cage_bell"), "the nut rang the cage bell")
	var heavy := await _take_the_weight()
	await _walk_to(Vector3(3.5, 1.0, 2.5), 0.4)
	await _give_creature("forest_wish", [heavy, _slot_of(JUMP), _slot_of(LEFT)])
	assert_true(await _wait_wish("forest_wish"), "the heavy creature stepped onto the dais plate")
	assert_true(w.ledger.player_can(FORWARD, _me().player_id), "W is left to walk")
	await _forest_cross_and_goal()


## 道 2: 発射台に S を単発で投げ渡して押し、「投げる」を投げ渡す → 檻が開いたまま → おもりを石に渡して
## D の単発で石の板へ → 願いの動物にジャンプと A で台へ、取り戻してジャンプを持って渡る。
func test_deep_forest_the_launcher_and_the_heavy_stone() -> void:
	await _enter(ID)
	var launcher := _block("launcher")
	await _walk_to(Vector3(-2.5, 1.0, 0.6), 0.3)
	_throw_lend(launcher, _slot_of(BACK), TriggerMode.Kind.SINGLE_SHOT)
	await _fire(BACK)
	assert_eq(launcher.cell(), Vector3i(-3, 2, -15), "pushed the launcher into line")
	await _walk_to(Vector3(-2.5, 1.0, 0.6), 0.3)
	_throw_lend(launcher, _slot_of(THROW), TriggerMode.Kind.NONE)
	assert_true(await _wait_until_rung("cage_bell"), "the launcher rang the cage bell")
	var heavy := await _take_the_weight()
	var stone := _block("weight_stone")
	await _walk_to(Vector3(0.5, 1.0, 7.5), 0.3)
	_lend(stone, heavy, TriggerMode.Kind.NONE)
	_lend(stone, _slot_of(RIGHT), TriggerMode.Kind.SINGLE_SHOT)
	await _fire(RIGHT)
	assert_eq(stone.cell(), Vector3i(2, 1, 6), "the heavy stone sits on the stone plate")
	await _walk_to(Vector3(3.5, 1.0, 2.5), 0.4)
	await _give_creature("forest_wish", [_slot_of(JUMP), _slot_of(LEFT)])
	assert_true(await _wait_wish("forest_wish"), "the creature hopped onto its dais")
	await _recall_creature("forest_wish")
	assert_true(w.ledger.player_can(JUMP, _me().player_id), "my jump is back")
	await _forest_cross_and_goal()
