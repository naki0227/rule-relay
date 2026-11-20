# 企画書の要件と実装の対応表

出典: Vault `02-Projects/rule-items-world-game-proposal.md`（2026-11-17、proposal-draft）。
確認日: 2026-11-19（ブランチ `claude/p1-5-acceptance` の時点）。状態は「実装＋テストあり／一部／未実装（理由）」で書く。
「仮」は企画書で未決・要検証の項目に対して、ここで置いた仮の判断（詳しくは `docs/TODO.md` の要確認）。

## 4. 世界の物理と操作方向【確定】

| # | 要件 | 状態 | 実装 | テスト |
|---|---|---|---|---|
| 4-1 | プレイヤーの WASD はカメラ相対。W を失っても視点を回して進めるのは許容 | 実装＋テスト | `player_avatar.gd` `_allowed_direction` | `test_player_movement` |
| 4-2 | ブロックの WASD は世界座標に固定（W＝北） | 実装＋テスト | `rule_action.gd` `world_direction` | `test_island_mechanics`（W で北へ） |
| 4-3 | 隣のブロックと結合しない。同じ範囲から同時に独立して試みる | 実装＋テスト | `rule_block.gd`、`game_world.gd` `_fire_single_shot` | `test_acceptance` 2 |
| 4-4 | 禁止はブロック単位。外力で動くことは妨げない | 実装＋テスト | `block_rules.gd` `attempt` | `test_acceptance` 2、`test_island_mechanics` `test_prohibited_block_is_still_pushed_up_from_below` |
| 4-5 | W と S を周期実行する自律ブロックは交互、禁止された行動はその回をスキップ | 実装＋テスト | `repeat_cursor.gd` | `test_trigger_modes`、`test_throw_pickup_shuttle`（谷の往復足場） |
| 4-6 | 段差補助 0.4（仮値）。ワープしない／隙間を飛ばない／禁止を無視しない | 実装＋テスト | `player_avatar.gd` `_try_step_up` | `test_player_movement` |

## 5. 能力を付与する【確定】

| # | 要件 | 状態 | 実装 | テスト |
|---|---|---|---|---|
| 5.1 | ブロック: 単体・範囲。生き物: 単体のみ。プレイヤー: 対象外 | 実装＋テスト | `rule_ledger.gd` `_validate_targets`、`game_world.gd` `lend_to` | `test_rule_ledger`、`test_creature` |
| 5.1 | C で触る／投げる、左クリック＝単体、右クリック＝範囲 | 実装＋テスト | `player_input.gd`、`game_world.gd` `toggle_reach` | `test_throw_pickup_shuttle` |
| 5.1 | 投げるも譲渡可能。貸すと遠距離付与できないが、触るとFの回収は残す | 実装＋テスト | `RuleAction.THROW`、`game_world.gd` `reach`／`_within_touch` | `test_throw_and_pickup`、`test_throw_pickup_shuttle` |
| 5.2 | 単発: 対応キーで1回だけ試み、成功で自動返還。付与直後に勝手に実行しない | 実装＋テスト | `input_router.gd`、`rule_ledger.gd` `complete_single_shot` | `test_acceptance` 4 |
| 5.2 | 繰り返し: 周期的に自動で試みる。手動回収 | 実装＋テスト | `game_world.gd` `_tick_repeats` | `test_acceptance` 4 |
| 5.2 | 信号: 音波が届いている間だけ発動、途絶えると休止、再受信で再開。手動回収 | 実装＋テスト | `game_world.gd` `_tick_signals`／`is_receiving_signal` | `test_signal`、`test_acceptance` 4 |
| 5.2 | 生き物には3方式を設定しない | 実装＋テスト | `rule_ledger.gd` `lend`（方式 NONE） | `test_creature` |
| 5.3 | 水平の円・縦1層。範囲内の全ブロック。生き物・プレイヤーには作用しない | 実装＋テスト | `block_rules.gd` `select_in_range` | `test_acceptance` 3、`test_range_selection` |
| 5.3 | 半径5（仮）。1回の範囲付与もトークンは1つ | 実装＋テスト | `BlockRules.DEFAULT_RANGE_RADIUS` | `test_range_selection` |
| 5.3 | 範囲内のどこからでも F で一括回収。回収用の結晶はない | 実装＋テスト | `rule_ledger.gd` `range_tokens_at` | `test_range_selection`、`test_acceptance`（範囲の端から F） |
| 5.3 | 範囲単発は一斉に1回。禁止は個別判定。一部失敗の返還は未決 | 実装（2026-11-19 本人の判断: 起動したら成否によらず、発動したのと同じ扱いで戻る） | `rule_ledger.gd` `complete_single_shot` | `test_trigger_modes`、`test_acceptance` 4b |
| 5.3 | 単体と範囲で強さを変えない。倍率は不採用 | 実装（倍率の UI・値なし） | — | — |
| 5.4 | 音波そのものを信号に。音源ブロック、移動する音源 | 実装（2026-11-19 本人の判断: 音源は鐘で F で鳴らす。判定は距離だけ。遮る物体・音を識別するブロック・吹くアイテムは後で追加） | `bell.gd`、`game_world.gd` `add_bell` | `test_signal`、`test_throw_uses` |
| 5.1 補足 | 投げるの使い道（2026-11-19 本人の判断: 発射台は投げるが来ないと撃たない、物を持つ生き物は投げる） | 実装＋テスト | `game_world.gd` `add_launcher`／`throw_ball`、`creature.gd` `_maybe_throw` | `test_throw_uses` |

## 6. 生き物の自律行動【確定】

| 要件 | 状態 | 実装 | テスト |
|---|---|---|---|
| 与えられた能力を使うかを願いに従って選ぶ。直接命令しない | 実装＋テスト | `creature_mind.gd`、`creature.gd` | `test_creature_mind`、`test_creature` |
| 禁止は願いより優先 | 実装＋テスト | `creature.gd` `can`（禁止を差し引く） | `test_creature_mind`、`test_creature` |
| 4段階: 願いへ向かう／別ルートを探す／待つ／環境変化で再挑戦 | 実装＋テスト | `CreatureMind.Stage`、`creature.gd` `notify_environment_changed` | `test_creature_mind`、`test_creature` |
| 探索半径 5〜10（仮） | 実装（8） | `CreatureMind.SEARCH_RADIUS` | `test_creature_mind` |
| 最初は「高いところへ行きたい生き物」1種。理由が見える有限状態機械 | 実装（頭の上に ↑／？／…） | `prototype_island.gd` `_build_creature` | `test_creature` |
| 生き物の W/A/S/D（2026-11-19 本人の判断: 生き物が向いている向きが基準） | 実装＋テスト | `CreatureMind.choose_move` | `test_creature_mind` |
| 回収は近づいて F | 実装＋テスト | `game_world.gd` `interact` | `test_creature` |

## 7. アイテム、装備、インベントリ【確定】

| 要件 | 状態 | 実装 | テスト |
|---|---|---|---|
| 器と能力を区別。付与しても器は残り、位置は変わらない。複製しない | 実装＋テスト | `rule_ledger.gd`、`rule_vessel.gd` | `test_acceptance` 1、`test_rule_ledger` |
| 装備中: 本人に有効、装備由来の能力は付与不可 | 実装＋テスト | `rule_ledger.gd` `_applies_to_player`／`EQUIPPED_CANNOT_LEND` | `test_equipment` |
| 未装備・器に能力あり: 付与できる／貸出中: 回収まで再付与不可 | 実装＋テスト | `rule_ledger.gd` `lend` | `test_equipment` |
| 装備部位は各部位1個。ジャンプブーツ（約2ブロック）、クライミンググローブ | 実装＋テスト | `rule_ledger.gd` `equip`、`player_avatar.gd` `jump_height`／`_should_climb` | `test_equipment`、`test_equipment_in_world` |
| ブロックに渡した登る（2026-11-19 本人の判断: 隣でいちばん高い上面まで登ってつかまる） | 実装＋テスト | `rule_block.gd` `_integrate_climb`、`game_world.gd` `_tick_climbers` | `test_block_climb` |
| 貸出中の装備（企画書では実装前の確認事項） | 実装（2026-11-19 本人の判断: 装備はできるが、回収まで能力は効かない） | `rule_ledger.gd` `equip` | `test_equipment` |
| ホットバー9枠: 能力が有効（付与中は無効）。禁止は有効 | 実装＋テスト | `rule_ledger.gd` `player_has_ability`／`player_prohibited` | `test_acceptance` 5 |
| 通常インベントリ（無制限）: 能力は無効、禁止は有効 | 実装＋テスト | 同上 | `test_acceptance` 5、`test_inventory_panel`（大量の器） |
| 他者へ付与中: 能力・禁止とも本人に無効 | 実装＋テスト | `is_lent()` の除外 | `test_rule_ledger` |
| F で拾ったアイテムは通常インベントリへ | 実装＋テスト | `rule_ledger.gd` `pickup`、`game_world.gd` `nearest_world_item` | `test_throw_and_pickup`、`test_throw_pickup_shuttle` |
| E で開いてホットバーへ移すと適用・付与できる | 実装＋テスト | `inventory_panel.gd` | `test_inventory_panel` |
| UI: 検索、能力／禁止／装備の絞り込み、貸出中・装備中・禁止適用中の状態表示 | 実装＋テスト | `inventory_query.gd`、`inventory_panel.gd` | `test_inventory_query`、`test_equipment` |
| 倍率アイテム・自由倍率・倍率クラフトは導入しない | 実装（導入していない） | — | — |

## 8. 操作と UI【確定中心】

| 要件 | 状態 | 備考 |
|---|---|---|
| W/A/S/D・Space・1〜9・C・左右クリック・ホイール＋ドラッグの円形 UI・E・F・Esc | 実装＋テスト | `project.godot` の入力マップ、`player_input.gd` |
| 赤系アウトラインで付与先、範囲は濃い赤の角マーカー | 実装 | `rule_block.gd`、生き物は足もとの赤い輪 |
| 色だけで区別しない（線・角・禁止記号・文字・アイコン） | 実装 | 禁止は赤い輪＋斜線、方式は文字で併記 |
| 信号受信中／休止中、能力貸出中、回収対象、単発の待機中を表示 | 実装 | ブロックの上に「♪ 受信中／休止中」、方式の文字、F 回収の案内 |
| 明暗・線幅・点滅緩和・キー変更を検討 | 未実装（検討項目） | キーの割り当て変更・文字サイズ設定は `docs/TODO.md` |
| 要検証: 範囲プレビュー、キャンセル、ホイールの代替キー、最後の投擲 | 実装（仮） | 範囲プレビュー・Esc で取り消し・Q・投げるを渡す1回は届く |
| 要検証: 複数回収候補の選択 | 実装（2026-11-19 本人の判断: F で全部回収） | `game_world.gd` `interact` |

## 9. セーブと巻き戻し【確定】

| 要件 | 状態 | テスト |
|---|---|---|
| チェックポイントで F で保存更新 | 実装＋テスト | `test_checkpoint_softlock` |
| 死亡時・Esc の復帰で世界を丸ごと巻き戻す | 実装＋テスト（死亡＝島から落ちる） | `test_acceptance` 6、`test_island_mechanics` |
| 保存するもの: プレイヤー位置、器と能力の所有、ホットバー／装備／インベントリ、ブロックの位置・速度・禁則、生き物、仕掛け・音源 | 実装＋テスト（落ちている器・信号の周期も含む） | `test_acceptance` 6、`test_signal` |
| 能力を二重生成しない | 実装＋テスト | `test_checkpoint_snapshot` |
| 要検証: 詰み状態での保存 → 直前の安全なスナップショット・保存条件 | 実装（仮） | `test_checkpoint_softlock` |
| 能力が何も無くてもメニューから復帰できる | 実装＋テスト | `test_checkpoint_softlock` |

## 10. 初期ワールド（仮案）

| 要素 | 状態 |
|---|---|
| ひとつながりの小さな島（草原・上下する足場・小さな谷・高台） | 実装 |
| 初期能力 W/A/S/D・ジャンプ・投げる をホットバーに | 実装 |
| 禁止（ジャンプ禁止中心、個別禁止が見える構成） | 実装（跳ねる足場・3つ並びの中央） |
| 単体ブロック、範囲内の複数ブロック、往復・上下する足場 | 実装 |
| 追加候補: ジャンプブーツ、願いを持つ生き物1種 | 実装（＋クライミンググローブ、音源） |
| 高台に到達したら順番を問わず成功。少なくとも2通りの独立した解法 | 実装＋テスト。高台まで到達をテストした解法は4通り（跳ねる足場・3つ並び・青緑を運んで階段・グローブで登る）。ジャンプブーツは岩棚（高さ2）までをテスト。**他者のプレイテストは未実施** |

## 11. 受け入れテスト

1〜7 は `tests/integration/test_acceptance.gd` に番号どおりに書いた（7 は 7a・7b の2通り）。

## マルチプレイ（2026-11-20 引き継ぎ仕様）

出典: `docs/handoff/2026-11-20-multiplayer-handoff.md`（Vault Draft PR #44 の 14〜44 節と突き合わせ済み。食い違いなし）。
確認日: 2026-11-20、main 5a050fa にブランチ `claude/p3-1-party-ledger` を重ねた時点。上の 4〜11 は1人用プロトタイプの表で、ここはその後の新仕様。
番号は引き継ぎ仕様 9 の受け入れテスト候補。**ルール層（台帳）だけ**で確かめた項目は「台帳のみ」と書き、ゲーム画面・物理・ネットワークではまだ動かない。

| # | 要件 | 状態 | 実装 | テスト |
|---|---|---|---|---|
| 1 | 1人用の既存挙動をすべて保つ | 実装＋テスト | `player_id` を省略すると `PLAYER_ID` | 既存の unit・integration 全件 |
| 2 | プレイヤー間で能力を直接渡す（承認なし）。受け取った人はさらに人・ブロックへ渡せる | 台帳のみ | `RuleLedger.give_to_player`・`lend_token` | `test_party_ledger` 2 |
| 3 | 同じ能力を集めると数だけ強まる（ジャンプ×4、W×4、投げる×4）。空の器は数えない | 台帳のみ（数まで）。高さ・速度・射程の倍率は未実装 | `RuleLedger.ability_count` | `test_party_ledger` 3 |
| 4 | 器は元の人に残り、能力はその人に効かない。トークンは世界に1つ | 台帳のみ | `RuleVessel.owner_id`、`RuleToken.carrier_id` | `test_party_ledger` 4 |
| 5 | F で回収した人が受け取る（元の持ち主へ戻さない） | 台帳のみ | `RuleLedger.recall(token, by_player)` | `test_party_ledger` 5 |
| 6 | 単発成功は直前の付与者へ返る。4個束ねても ID は別々 | 台帳のみ | `RuleToken.lender_id`、`complete_single_shot` | `test_party_ledger` 6 |
| 7 | 退出者がブロックへ付けた能力は残り、F で回収できる | 台帳のみ | `RuleLedger.set_player_present` | `test_party_ledger` 7 |
| 8 | 付与者が退出していたら単発成功で現場に落ち、拾える（複製しない） | 台帳のみ。落ちる場所の選び方・見た目は未実装 | `RuleToken.dropped`、`pickup_token` | `test_party_ledger` 8 |
| 9 | 循環譲渡でも出自を書き換えない | 台帳のみ | `vessel_id` を不変にした | `test_party_ledger` 9 |
| P2 | オンライン: ホスト権威で依頼を検証・適用し、台帳を全員へ配る。2人が通信越しに渡す・F で回収する | 台帳の同期のみ（ENet、同じ PC 内の2端で確認）。アバター・ブロックの同期、画面からの操作は未実装 | `src/net/`（`NetSession`・`PartyCommand`・`PartyRoster`）、ADR 0006 | `test_net_session`、`test_party_command`、`test_party_roster` |
| 16 の一部 | 同じトークンを二重に持たない（再送・peer ID の振り直し・なりすまし） | 台帳の同期のみ | 依頼の seq で再送を一度だけ適用、session_key でプレイヤー ID を固定、送り主は通信から決める | 同上 |
| P2 続き | 仲間のアバター・世界の同期・通信越しの操作（付与・F・単発・持ち物の整理）・仲間へ渡す | 実装＋テスト（同じ PC 内の ENet） | `NetWorld`・`WorldFrame`・`WorldParty`・`GameWorld.replica` | `test_net_world` |
| 3（倍率） | ジャンプ×n は到達高度 n 倍、W×n は速さ n 倍、投げる×n は射程 n 倍、ブロックの単発 n 個はまとめて n 倍 | 実装＋テスト（上限は未決のため仮になし） | `Tuning.stack_factor`、`PlayerAvatar`、`GameWorld._fire_single_shots` | `test_net_world`（ジャンプ×2） |
| 10 | 人数別補助は全員リセットのときだけ作り直す | 実装＋テスト | `StageLoadout.rebuild_helpers`、`PartyDirector._apply_reset` | `test_stage_rules`、`test_net_director`（途中参加） |
| 11 | 死亡しても貸与・手持ちはそのまま、世界は戻らない | 実装＋テスト | `PartyLifecycle.die`、`PartyDirector._check_deaths` | `test_party_lifecycle`、`test_net_director` |
| 12 | 1人到達で共通チェックポイント、台座の F で全員復活（ロードなし・巻き戻しなし） | 実装＋テスト | `PartyDirector._check_checkpoints`／`_on_checkpoint_interacted` | `test_net_director`、`test_party_director` |
| 13 | 全員リセットは過半数（1/1・2/2・2/3・3/4）、世界まるごと戻る | 実装＋テスト | `PartyLifecycle.vote_reset`、V キー | `test_party_lifecycle`、`test_party_director` |
| 14 | 死亡観戦がいるとき生存者全員の同意でも全状態リセット | 実装＋テスト（優先順位は仮: どちらでも成立） | `PartyLifecycle` | `test_party_lifecycle` |
| 15 | 途中入室は観戦、次の全員リセットで合流 | 実装＋テスト | `PartyDirector._on_player_joined` | `test_net_director` |
| 16 | ホスト移譲: 停止→選出中→新ホストで再開、二重所有なし、失敗は失敗と出す | 実装＋テスト（ENet・同じ PC 内の3人） | `HostMigration`、`PartyDirector.export_state`／`adopt_state` | `test_host_migration` |
| 17〜21 | 報酬資格の真理値表、切断者は部屋があるうちに戻れば受け取る、初回と周回、複数の記録 | 実装＋テスト | `src/progress/`、`PartyDirector._on_clear`／`deliver_rewards` | `test_stage_run_rewards`、`test_player_progress`、`test_net_director` |
| 22 | 再送・競合で状態・報酬が一意 | 一部（依頼の再送・報酬の再送・投票の重複はテスト済み。同時 F 回収の競合はホストが順に処理する作りで、専用テストなし） | `NetSession`、`StageRunRewards`、`PartyLifecycle` | `test_net_session`、`test_stage_run_rewards`、`test_party_lifecycle` |
| 23 | 導入ステージをソロでも2〜4人でも攻略できる | 一部（ソロのクリアは結合テスト。2〜4人の別解は ×n の式が仮のため未確認） | `StageCatalog.intro_jump_lend` | `test_party_director`、`test_stage_rules` |
| ハブ | ハブを歩いて入口を見つけ、F でステージへ。クリア後はハブへ戻る | 実装＋テスト（見た目は仮） | `StageCatalog.hub`、`StageWorld`、`PartyDirector` | `test_party_director` |
| 入口 | タイトル（ひとりで／部屋を作る／相棒ボットと／部屋に入る） | 実装（起動確認のみ） | `TitleMenu`、`GameRoot` | `tools/check.sh` の起動確認 |
| 相棒ボット | （仕様外・試遊用）参加者として入り、ついてくる・能力を渡す・回収する | 実装＋テスト | `CompanionBot` | `test_companion_bot` |
| Steam 版 | ロビー・招待・P2P | 差し替え口のみ（**未検証**） | `SteamTransport` | `test_steam_transport`（使えないときの動作だけ） |

台帳で仮に決めた挙動（禁止をプレイヤーへ渡せない、付与者が退出していて単発が失敗したらブロックに残す、受け取った能力は持っていれば効く）は `docs/adr/0005-party-token-ledger.md` の「未決のため仮にした挙動」。

## まだ満たしていないもの・人の確認が要るもの

- 他者による15分プレイテスト（P0-3 の判定）。人がいないとできない
- Windows 11 実機での起動と操作感の確認（CI の Windows 起動確認は通っている）
- キーの割り当て変更・明暗や点滅の調整（8 の検討項目）
- 未決事項（`docs/TODO.md` の要確認）への本人の判断
- マルチプレイを別々の PC・インターネット越し・Windows 11 実機で試すこと（手順は `docs/how-to-test.md`）
- Steam 版（GodotSteam と App ID が要る）
