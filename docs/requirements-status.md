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
| 5.3 | 範囲単発は一斉に1回。禁止は個別判定。一部失敗の返還は未決 | 実装（仮: 1つでも成功で返還） | `block_rules.gd` `single_shot_succeeded` | `test_island_mechanics` |
| 5.3 | 単体と範囲で強さを変えない。倍率は不採用 | 実装（倍率の UI・値なし） | — | — |
| 5.4 | 音波そのものを信号に。音源ブロック、移動する音源 | 実装（2026-11-19 本人の判断: 当面は距離だけ。遮る物体・音を識別するブロックは後で追加） | `game_world.gd` `add_sound_source` | `test_signal` |

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
| 要検証: 複数回収候補の選択 | 一部（仮: 決まった順番で1つずつ） | `game_world.gd` `_recall_one` |

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

## まだ満たしていないもの・人の確認が要るもの

- 他者による15分プレイテスト（P0-3 の判定）。人がいないとできない
- Windows 11 実機での起動と操作感の確認（CI の Windows 起動確認は通っている）
- 生き物の行動を使った高台への解法（生き物には乗れない。島に組み込むかは要相談）
- キーの割り当て変更・明暗や点滅の調整（8 の検討項目）
- 未決事項（`docs/TODO.md` の要確認）への本人の判断
