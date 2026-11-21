extends "res://tests/integration/world_playing.gd"
## ワールド 3 の新しいステージの関所と詰みを、プレイヤーと同じ操作で壊しにいく（敵対的な試遊）。
## - test_gate_*: 意図した関所が守られていること（ふつうの跳び・縁ちょうど・ダッシュ・風で越えられない）
## - test_accepted_*: 本人が「残してよい」と決めた技（重ね跳びなど）や、意図した別解の挙動を固定する
## - test_finding_*: 意図と違うが今は直していない挙動（docs/campaign-plan.md の「直していない発見」）
## 氷はワールド 3 に無い（5-4 から）。瞬間移動・状態の書き換えはしない。

const NORTH := Vector3(0.0, 0.0, -1.0)
const EAST := Vector3(1.0, 0.0, 0.0)

# --- 3-1 ダッシュの浜 -------------------------------------------------------------


## 浜 → 西の小島の幅 5 は、縁ちょうどを含めて、ふつうの走り跳びでは越えられない。
func test_gate_dash_beach_gap_of_five_is_not_a_running_jump() -> void:
	await _enter(World3Stages.DASH_BEACH_ID)
	var offset := await _first_crossing([Vector3(-2.5, 0.0, 1.5)], NORTH, 1.0, 5.0)
	assert_true(
		is_nan(offset), "no plain running jump crosses the gap of 5 (crossed at %s)" % offset
	)


## 地上のダッシュ（3 マス）だけでは幅 5 を越えない（跳んでから空中でダッシュする）。
func test_gate_dash_beach_ground_dash_is_too_short() -> void:
	await _enter(World3Stages.DASH_BEACH_ID)
	await _pick(Vector3(1.5, 0.0, 2.5), DASH)
	assert_false(
		await _ground_dash(Vector3(-3.5, 0.0, -0.75), NORTH), "the ground dash falls short"
	)


## 受け入れた技（足もとのセルに単発のジャンプを貸して乗り、上昇中に自分でも跳ぶ）は、ダッシュなしで幅 5 を越える。
## 本人の決定（2026-11-20、上手い人の技は残す）どおり残す。ワールド 3 の空の関所は、この技では越えない
## 幅（3-5・3-6 の幅 9〜10）か、ジャンプを持ち込まない島で作った。
func test_accepted_dash_beach_stacked_jump_crosses_without_a_dash() -> void:
	await _enter(World3Stages.DASH_BEACH_ID)
	var crossed := await _stacked_leap(Vector3(-3.5, 0.0, -0.5), Vector3i(-4, -1, -1), NORTH, 6.2)
	assert_true(crossed, "ACCEPTED: riding a promoted cell + own jump crosses the gap of 5")


## 詰み: ジャンプを遠くのセルへ繰り返しで投げ渡すと空中ダッシュができない。崖から落ちれば、
## 保存の時点（ジャンプが手元にある）へ戻る。
func test_gate_dash_beach_throwing_the_jump_away_recovers_by_falling() -> void:
	await _enter(World3Stages.DASH_BEACH_ID)
	await _walk_to(Vector3(2.5, 0.0, -0.5), 0.3)
	_throw_lend(w.terrain_target(Vector3i(6, -1, -8)), _slot_of(JUMP), TriggerMode.Kind.REPEAT)
	assert_false(w.ledger.player_can(JUMP, _me().player_id), "the jump is far away")
	assert_false(await _try_walk_to(Vector3(2.5, 0.0, -3.0), 0.3, 120), "walked off the beach")
	await _wait_respawn()
	assert_true(w.ledger.player_can(JUMP, _me().player_id), "the jump is back after the fall")


# --- 3-2 往復足場の入り江 ---------------------------------------------------------


## ジャンプの無い入り江では、足場の無いところの幅 2 は歩いても越えられない（落ちて戻る）。
func test_gate_shuttle_cove_no_crossing_without_a_shuttle() -> void:
	await _enter(World3Stages.SHUTTLE_COVE_ID)
	assert_false(await _try_walk_to(Vector3(2.5, 1.0, -2.5), 0.4, 150), "fell into the channel")
	await _wait_respawn()
	assert_gt(_me().global_position.z, 1.5, "back on the beach")


## 足場の台座（1 段下）に降りてしまっても、詰まない（空へ歩き出せば、島から落ちたのと同じく戻る）。
func test_gate_shuttle_cove_the_rail_is_not_a_trap() -> void:
	await _enter(World3Stages.SHUTTLE_COVE_ID)
	await _walk_to(Vector3(-3.5, 1.0, 2.6), 0.3)
	assert_true(await _wait_shuttle_at("north_shuttle", Vector3i(-4, 0, 0)), "the shuttle is away")
	await _try_walk_to(Vector3(-3.5, 0.0, 1.5), 0.3, 60)
	await wait_physics_frames(20)
	print("    standing at %s after stepping off the beach" % _me().global_position)
	assert_lt(_me().global_position.z, 2.0, "left the beach")
	assert_true(await _walk_off(Vector3(-1.5, 0.0, 1.5)), "walked off the rail and came back")


# --- 3-4 風の通り道 ---------------------------------------------------------------


## 風が止んでいる間の走り跳びでは、風の道の幅 5 を越えられない。
func test_gate_wind_path_no_crossing_in_the_calm() -> void:
	await _enter(World3Stages.WIND_PATH_ID)
	var gust := Vector3(-1.5, 0.5, -2.5)
	await _walk_to(Vector3(-1.5, 0.0, 2.5), 0.25)
	assert_true(await _wait_wind(gust, true), "a gust")
	assert_true(await _wait_wind(gust, false), "the calm begins")
	assert_false(
		await _running_jump([Vector3(-1.5, 0.0, 2.5)], NORTH, 0.0, 5.0, 0.0), "too far in the calm"
	)


## 風の道の外（追い風の無いところ）では、縁ちょうどを含めて幅 5 を越えられない。
func test_gate_wind_path_no_crossing_outside_the_wind() -> void:
	await _enter(World3Stages.WIND_PATH_ID)
	var offset := await _first_crossing([Vector3(4.5, 0.0, 3.5)], NORTH, 0.0, 5.0)
	assert_true(is_nan(offset), "no crossing without the tailwind (crossed at %s)" % offset)


## 横風が吹いている間に、まっすぐ北へ歩くだけで橋を渡ろうとすると、西へ押し出されて落ちる。
func test_gate_wind_path_the_crosswind_pushes_walkers_off() -> void:
	await _enter(World3Stages.WIND_PATH_ID)
	var cross := Vector3(-9.0, 0.5, -3.0)
	await _walk_to(Vector3(-9.0, 0.0, 0.6), 0.2)
	assert_true(await _wait_wind(cross, false), "calm")
	assert_true(await _wait_wind(cross, true), "the crosswind starts")
	_me().view_yaw = 0.0
	_me().move_intent = Vector2(0.0, 1.0)
	var fell := false
	for f in 120:
		await tree.physics_frame
		if _me().global_position.y < -1.0:
			fell = true
			break
	_me().move_intent = Vector2.ZERO
	assert_true(fell, "blown off the bridge")
	await _wait_respawn()


# --- 3-5 谷越えリレー -------------------------------------------------------------


## 幅 9 は、受け入れた重ね跳び（ダッシュの無い島）でも届かない。橋が要る。
func test_gate_gap_relay_gap_of_nine_is_not_a_stacked_jump() -> void:
	await _enter(World3Stages.GAP_RELAY_ID)
	var crossed := await _stacked_leap(Vector3(2.5, 0.0, 0.5), Vector3i(2, -1, 0), NORTH, 9.3)
	assert_false(crossed, "the stacked jump falls short of the gap of 9")


## 先に「投げる」をひつじへ投げ渡すと、ふもとから北へ木の実を投げて外す（鐘は鳴らない）。
## 「投げる」も手元から無くなるが、谷へ落ちれば保存の時点（木の実も「投げる」もある）へ戻る。
func test_finding_gap_relay_throw_first_wastes_the_nut_until_a_fall() -> void:
	await _enter(World3Stages.GAP_RELAY_ID)
	await _walk_to(Vector3(0.0, 0.0, 0.5), 0.3)
	await _give_creature("lamb", [_slot_of(THROW)], true)
	await wait_physics_frames(90)
	assert_eq(_creature("lamb").held_item, "", "the nut is gone")
	assert_false(w.activated.has("bridge_bell"), "the nut missed the bell")
	assert_false(await _try_walk_to(Vector3(0.0, 0.0, -3.0), 0.3, 120), "walked into the gap")
	await _wait_respawn()
	assert_ne(_creature("lamb").held_item, "", "the nut is back")
	assert_ne(_slot_of(THROW), -1, "THROW is back")


# --- 3-6 雲の回廊 -----------------------------------------------------------------


## 信号の往復足場は、港の鐘が鳴っていなければ動かない。
func test_gate_cloud_corridor_signal_shuttles_wait_for_the_bell() -> void:
	await _enter(CloudCorridor.ID)
	await wait_physics_frames(300)
	assert_eq(_block("harbor_south").cell(), Vector3i(-3, 0, 3), "still at the harbor")
	assert_eq(_block("harbor_north").cell(), Vector3i(-3, 0, 0), "still at the cloud")


## 地上のダッシュ（3 マス）では、往復足場の幅 4 は越えられない（跳べないので空中ダッシュも無い）。
func test_gate_cloud_corridor_ground_dash_cannot_cross_four() -> void:
	await _enter(CloudCorridor.ID)
	await _pick(Vector3(3.5, 1.0, 6.5), DASH)
	assert_false(await _ground_dash(Vector3(0.5, 1.0, 4.25), NORTH), "the gap of 4 is too wide")


## 柱の上の鐘は、鐘の雲の地面からは触って鳴らせない。
func test_gate_cloud_corridor_sky_bell_out_of_reach_from_the_cloud() -> void:
	await _enter(CloudCorridor.ID)
	await _pick(Vector3(3.5, 1.0, 6.5), DASH)
	await _ground_dash_across(Vector3(6.6, 1.0, 6.5), Vector3(9.5, 1.0, 6.5))
	await _walk_to(Vector3(9.4, 1.0, -2.5), 0.2)
	await _ground_dash_across(Vector3(9.3, 1.0, -2.5), Vector3(5.5, 1.0, -2.5))
	await _ground_dash_across(Vector3(-0.5, 1.0, -5.7), Vector3(-0.5, 1.0, -9.5))
	await _walk_to(Vector3(0.5, 1.0, -10.7), 0.3)
	assert_false(await _try_ring_from("sky_bell", Vector3(0.5, 1.0, -13.7)), "out of reach")


## 意図した 3 つ目の道: グローブを自分で着けて段々の岩を登り、柱の鐘を鳴らして 6 秒のうちに橋を走る
## （動物には、あとでグローブと D を渡す）。
func test_accepted_cloud_corridor_climb_and_ring_it_yourself() -> void:
	await _enter(CloudCorridor.ID)
	await _pick(Vector3(3.5, 1.0, 6.5), DASH)
	await _ground_dash_across(Vector3(6.6, 1.0, 6.5), Vector3(9.5, 1.0, 6.5))
	await _walk_to(Vector3(9.4, 1.0, -2.5), 0.2)
	await _ground_dash_across(Vector3(9.3, 1.0, -2.5), Vector3(5.5, 1.0, -2.5))
	await _pick_and_wear(Vector3(-4.5, 1.0, -3.5), RuleVessel.Part.HANDS)
	await _ground_dash_across(Vector3(-0.5, 1.0, -5.7), Vector3(-0.5, 1.0, -9.5))
	await _walk_to(Vector3(-5.5, 1.0, -12.5), 0.3)
	for x in range(-5, 0):
		await _walk_to(Vector3(x + 0.5, 2.0 + x + 5, -13.5), 0.4)
	var bell := w.bells_by_key["sky_bell"]
	_face(bell.global_position)
	w.interact(bell)
	await wait_physics_frames(2)
	assert_true(w.activated.has("sky_bell"), "rang the bell from the top of the rock")
	assert_true(await _wait_door("sky_bridge", true), "the bridge rose")
	await _walk_to(Vector3(2.0, 1.0, -13.6), 0.3)
	assert_true(await _try_walk_to(Vector3(2.0, 1.0, -25.5), 0.35, 400), "ran over in time")
