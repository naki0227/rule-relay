extends "res://tests/integration/world_playing.gd"
## 3-6 雲の回廊（難しい★）を、ひとりで最初から最後まで自動で遊ぶ（2 通り）。協力の道は test_world34_coop.gd、
## 関所と詰みは test_world3_probes.gd。操作はプレイヤーと同じで、瞬間移動しない。

const ID := CloudCorridor.ID


## 鐘の雲で、願いの動物にグローブと D を渡して高い岩へ登らせる。
func _climber(extra: Array[int] = []) -> void:
	await _walk_to(Vector3(-5.5, 1.0, -12.4), 0.4)
	var slots: Array[int] = [_slot_of(CLIMB), _slot_of(RIGHT)]
	slots.append_array(extra)
	await _give_creature("cloud_wish", slots)
	assert_true(await _wait_wish("cloud_wish"), "it climbed its tall rock")


func _corridor_goal() -> void:
	await _walk_to(Vector3(2.0, 1.0, -13.6), 0.3)
	await _walk_to(Vector3(2.0, 1.0, -25.5), 0.35, 400)
	await _walk_into_goal([Vector3(4.5, 1.0, -26.5), Vector3(4.5, 1.0, -28.5)])
	assert_true(await _cleared(), "the creature is on its rock and everyone is in the hollow")


## 道 1: 港の時の鐘で信号の往復足場を動かして乗り継ぎ → グローブ → 往復足場で鐘の雲 → 動物にグローブと D、
## 橋の手前から「投げる」を投げ渡す → 木の実で柱の鐘 → 6 秒の橋を走る。
func test_cloud_corridor_signal_shuttles_and_the_nut() -> void:
	await _enter(ID)
	assert_eq(_slot_of(JUMP), -1, "no jump on the clouds")
	await _ring("harbor_bell")
	await _ride(
		"harbor_south",
		Vector3(-2.5, 1.0, 4.4),
		Vector3i(-3, 0, 3),
		Vector3i(-3, 0, 2),
		Vector3(-2.5, 1.0, 1.5)
	)
	assert_true(await _wait_shuttle_at("harbor_north", Vector3i(-3, 0, 0)), "carried to the cloud")
	await _walk_to(Vector3(-2.5, 1.0, -1.5), 0.35, 120)
	await _pick(Vector3(-4.5, 1.0, -3.5), CLIMB)
	await _ride(
		"cloud_shuttle",
		Vector3(3.5, 1.0, -5.4),
		Vector3i(3, 0, -7),
		Vector3i(3, 0, -8),
		Vector3(3.5, 1.0, -9.5)
	)
	await _climber()
	await _walk_to(Vector3(2.0, 1.0, -13.6), 0.3)
	await _give_creature("cloud_wish", [_slot_of(THROW)], true)
	assert_true(await _wait_until_rung("sky_bell"), "the nut rang the bell on the pillar")
	assert_true(await _wait_door("sky_bridge", true), "the sky bridge rose")
	await _corridor_goal()


## 道 2: ダッシュで東の細い雲を回って中の雲へ（地上のダッシュ 2 回）→ グローブ → ダッシュで鐘の雲 →
## 発射台を S で 1 マス押して「投げる」→ 東の小島の鐘を撃ち続け、橋が架かったまま → 動物にグローブと D。
func test_cloud_corridor_dash_hops_and_the_launcher() -> void:
	await _enter(ID)
	await _pick(Vector3(3.5, 1.0, 6.5), DASH)
	assert_true(
		await _ground_dash_across(Vector3(6.6, 1.0, 6.5), Vector3(9.5, 1.0, 6.5)),
		"to the east cloud"
	)
	await _walk_to(Vector3(9.4, 1.0, -2.5), 0.2)
	assert_true(
		await _ground_dash_across(Vector3(9.3, 1.0, -2.5), Vector3(5.5, 1.0, -2.5)), "to the cloud"
	)
	await _pick(Vector3(-4.5, 1.0, -3.5), CLIMB)
	assert_true(
		await _ground_dash_across(Vector3(-0.5, 1.0, -5.7), Vector3(-0.5, 1.0, -9.5)),
		"to the bell cloud"
	)
	var launcher := _block("launcher")
	await _walk_to(Vector3(4.5, 1.0, -10.6), 0.3)
	_lend(launcher, _slot_of(BACK), TriggerMode.Kind.SINGLE_SHOT)
	await _fire(BACK)
	assert_eq(launcher.cell(), Vector3i(5, 1, -12), "pushed the launcher into line")
	await _walk_to(Vector3(4.5, 1.0, -10.6), 0.3)
	_lend(launcher, _slot_of(THROW), TriggerMode.Kind.NONE)
	assert_true(await _wait_until_rung("far_bell"), "the launcher rang the far bell")
	assert_true(await _wait_door("sky_bridge", true), "the sky bridge rose")
	await _climber()
	await _corridor_goal()
