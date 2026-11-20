# AI 利用の記録

コンテストの応募規約・AI 利用ガイドラインで、使用した AI ツールと工程の記載を求められる（企画書 12）。提出前に正式なガイドラインを再確認し、この記録から企画書 PDF へ転記する。

| 日付 | ツール | 工程 | 内容 | 人の確認 |
|---|---|---|---|---|
| 2026-11-17 | ChatGPT | 企画 | 企画相談（Vault の企画書ノートに記録） | 本人が仕様を選択 |
| 2026-11-18 | Claude Code（Anthropic） | 実装 | 技術選定の比較、CI、ゲームルール・試作の島のコード、テスト | PR でレビュー予定 |
| 2026-11-18 | Claude Code（Anthropic） | 3Dモデル | Blender の Python スクリプト（`art/scripts/build_assets.py`）を書き、試作用のモデル13点を生成。画像生成AI・3D生成AI は未使用 | PR でレビュー予定 |
| 2026-11-18 | Claude Code（Anthropic） | アイコン | Blender の Python スクリプト（`art/scripts/build_icons.py`）で器のアイコン10枚を描画。画像生成AIは未使用 | PR でレビュー予定 |
| 2026-11-18 | Claude Code（Anthropic） | 効果音 | Python のスクリプト（`tools/sfx/build_sfx.py`）でモーダル合成と雑音の加工により効果音24種を合成。音声生成AI・外部の音素材は未使用 | 本人の試聴待ち |
| 2026-11-20 | Audio Studio MCP（Stable Audio 3 medium、Stability AI、ローカル生成） | BGM・効果音 | BGM 3場面×2、効果音 27種×2 の候補を生成（`art/audio/stable-audio/`、一覧は `docs/sound-candidates-2026-11-20.md`）。同日、うち6個をゲームに採用（次の行） | 本人の試聴待ち |
| 2026-11-20 | Stable Audio 3 medium（Stability AI。Audio Studio MCP 経由でローカル生成。ライセンス: Stability AI Community License） | 効果音 | 上の候補のうち、測定の基準を全部満たす効果音 6 種をゲームの効果音として採用: E01→ui_hover、E32→receive_stone、E38→block_jump、E42→block_step、E45→player_jump、E51→save（`assets/audio/sfx/`、取り込みは `tools/sfx/build_sfx.py` の `ADOPTED`、経緯と数値は `docs/sound-design.md`）。加工は人の書いたスクリプトでのフィルター・切り出し・音量調整だけ。BGM は採用していない | AI（Claude Code）が測定値で選んだ。本人の試聴待ち |
| 2026-11-20 | Claude Code（Anthropic） | 効果音 | 上の候補の測定と選定、取り込みのスクリプト（`tools/sfx/stable_audio_candidates.py`・`build_sfx.py`）と記録の作成 | PR でレビュー予定 |
| 2026-11-20 | Audio Studio MCP（Stable Audio 3 medium、Stability AI、ローカル生成。Stability AI Community License） | BGM | 上の候補のうち BGM の B1（ハブ）・B3（島）・B5（タイトル）を、加工せずにゲームへ取り込んだ（`assets/audio/music/`、鳴らすのは `src/audio/music_player.gd`）。AI は音を聴けないので仮の選曲 | 本人の試聴待ち |
| 2026-11-20 | Audio Studio MCP 1.2.0（Stable Audio 3 medium、Stability AI、`stabilityai/stable-audio-3-optimized` MLX 版 rev `30cb264`、ローカル生成） | 効果音 | 1回目で基準を外れた21イベントを作り直し、3つずつ計63個の候補を生成（`art/audio/stable-audio/sfx2/`、一覧は `docs/sound-candidates-2026-11-20-round2.md`）。ゲームの音は置き換えていない | 本人の試聴待ち |
| 2026-11-20 | Stable Audio 3 medium（Stability AI。Hugging Face `stabilityai/stable-audio-3-optimized` の MLX 版 `dit_medium_f16`、リビジョン `30cb2644da54bfa63275d1bc7f1fa67fc718680f`。Audio Studio MCP 1.2.0 経由で本人の Mac でローカル生成。ライセンス: Stability AI Community License） | 効果音 | 上の2回目の候補のうち、測定の基準を全部満たす効果音 15 種をゲームの効果音として採用: R09→ui_close、R12→ui_drop、R16→prohibit、R19→receive_wood、R22→receive_creature、R26→block_land、R29→ui_cancel、R36→ui_pick、R38→radial_open、R40→lend、R43→lend_range、R47→recall、R50→receive_grass、R53→player_land、R63→goal（`assets/audio/sfx/`、取り込みは `tools/sfx/build_sfx.py` の `ADOPTED`、経緯と数値は `docs/sound-design.md`）。加工は人の書いたスクリプトでのフィルター・切り出し・音量調整だけ | AI（Claude Code）が測定値で選んだ。本人の試聴待ち |

- モデル名・バージョンは、提出時に本人が各サービスの表示で確認して記入する。
- 生成 AI（音声）の版（2026-11-20 に本人から受け取った情報。企画書の開示表 `docs/submission/proposal-draft.md` 3.6 に転記）: Hugging Face の `stabilityai/stable-audio-3-optimized` の MLX 版、リビジョン `30cb264`。Audio Studio MCP 1.2.0 を通して、本人の Mac の中で生成した
- 生成 AI（音声）: ツールとモデルは Stable Audio 3 medium（Stability AI）。このMacでローカルに生成し、外部のサービスには送っていない。ライセンスは Stability AI Community License（年間収入 100 万ドル未満は商用利用可）。使った工程は効果音の候補の生成（採用は1回目の 6 種と2回目の 15 種）。使った期間は 2026-11-20
- AI によるコーディング支援: Claude Code（Anthropic）。使った工程は実装・テスト・CI・3Dモデルとアイコンの生成スクリプト・効果音の合成と取り込みのスクリプト・記録の作成。使った期間は 2026-11-18〜（作業が続く間）
- 応募のガイドライン（https://gc2026.jp.square-enix.com/guideline/）は AI ツール名・モデルとバージョン・使った工程・期間の記載を求める。2026-11-20 に AI 利用ガイドライン（策定中の版）と応募規約（確定版）を読み、生成 AI の使用は「容認」で、条件は使用ツールの利用規約の遵守・第三者の権利（特定の個人の声や作家の作風を含む）を侵害しないこと・使用状況の申告だと確かめた（本人も「大丈夫そう、何を使ったかだけ記録しておく」と判断）。ガイドラインの確定版はエントリー開始（2026-12-15）以降に出るので、提出前にもう一度確かめる
- 3D生成AI（Tripo など）を使った場合は、生成物のファイル名・利用規約上の権利・加工の有無をここに追記する。
