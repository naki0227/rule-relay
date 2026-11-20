# 2026-11-20 作業報告: 複数プレイヤーの能力台帳（マルチ P1 の第1段）

## 依頼

本人共有の引き継ぎ仕様（`docs/handoff/2026-11-20-multiplayer-handoff.md`）に沿って、最新 main・開いている PR・CI・Vault Draft PR #44 を照合し、
「既存の RuleLedger を壊さず、複数プレイヤーの能力貸与・スタック・F回収・単発返還を支えるドメイン設計と受け入れテスト」から小さく始める。

## 照合した結果

- main は 5a050fa（引き継ぎ仕様の確認時 HEAD と同じ）。開いている PR は #21〜#24（効果音・見た目。台帳には触れていない）
- Vault Draft PR #44 の 14〜44 節と引き継ぎ仕様に食い違いは無かった。31 節（死亡は個人リスポーン）は 32・35 節で訂正済みで、引き継ぎ仕様もそれに従っている

## したこと

- `RuleToken` に `carrier_id`・`lender_id`・`dropped`／`drop_position`、`RuleVessel` に `owner_id` を足した
- `RuleLedger` にプレイヤーの参加・退出、`give_to_player`、`lend_token`、`ability_count`、`pickup_token` を足し、問い合わせ・回収・単発返還に `player_id` を通した（省略すると従来の1人用）
- 不変条件の検査を `LedgerValidator` へ、読み取りの問い合わせを `PartyQuery` へ分けた
- UI の「貸出中」表示を、器を離れた状態全体（付与中・仲間が持っている・落ちている）に広げた
- `tests/unit/test_party_ledger.gd`（受け入れテスト候補 2〜9 と、拒否・復元の 24 件）
- 設計判断は `docs/adr/0005-party-token-ledger.md`

## 検証（実測）

`tools/check.sh --build` をローカル（Linux、Godot 4.6.3 headless）で実行し、すべて通った:
format・lint・sound budget（7件）・import・static・test（204 件成功、0 件失敗）・smoke（180 フレーム）・Windows 向け export。
Windows 11 実機・ネットワークでの確認はしていない。

## していないこと

- 倍率の物理（ジャンプ×4 の高さなど）、2人目のプレイヤーの操作・表示、ドロップの見た目と安全な位置の選び方
- 通信・ハブ・死亡観戦・投票・報酬（引き継ぎ仕様 10〜23）
- 未決の項目は仮の挙動にとどめ、`docs/TODO.md` の「マルチプレイの要確認」に並べた
