# AI 利用の記録

コンテストの応募規約・AI 利用ガイドラインで、使用した AI ツールと工程の記載を求められる（企画書 12）。提出前に正式なガイドラインを再確認し、この記録から企画書 PDF へ転記する。

| 日付 | ツール | 工程 | 内容 | 人の確認 |
|---|---|---|---|---|
| 2026-11-17 | ChatGPT | 企画 | 企画相談（Vault の企画書ノートに記録） | 本人が仕様を選択 |
| 2026-11-18 | Claude Code（Anthropic） | 実装 | 技術選定の比較、CI、ゲームルール・試作の島のコード、テスト | PR でレビュー予定 |
| 2026-11-18 | Claude Code（Anthropic） | 3Dモデル | Blender の Python スクリプト（`art/scripts/build_assets.py`）を書き、試作用のモデル13点を生成。画像生成AI・3D生成AI は未使用 | PR でレビュー予定 |
| 2026-11-18 | Claude Code（Anthropic） | アイコン | Blender の Python スクリプト（`art/scripts/build_icons.py`）で器のアイコン10枚を描画。画像生成AIは未使用 | PR でレビュー予定 |
| 2026-11-18 | Claude Code（Anthropic） | 効果音 | Python のスクリプト（`tools/sfx/build_sfx.py`）でモーダル合成と雑音の加工により効果音24種を合成。音声生成AI・外部の音素材は未使用 | 本人の試聴待ち |
| 2026-11-20 | Audio Studio MCP（Stable Audio 3 medium、Stability AI、ローカル生成） | BGM・効果音 | BGM 3場面×2、効果音 27種×2 の候補を生成（`art/audio/stable-audio/`、一覧は `docs/sound-candidates-2026-11-20.md`）。ゲームの音は置き換えていない。応募規約で生成音声が使えるかは未確認 | 本人の試聴待ち |
| 2026-11-20 | Audio Studio MCP 1.2.0（Stable Audio 3 medium、Stability AI、`stabilityai/stable-audio-3-optimized` MLX 版 rev `30cb264`、ローカル生成） | 効果音 | 1回目で基準を外れた21イベントを作り直し、3つずつ計63個の候補を生成（`art/audio/stable-audio/sfx2/`、一覧は `docs/sound-candidates-2026-11-20-round2.md`）。ゲームの音は置き換えていない | 本人の試聴待ち |

- モデル名・バージョンは、提出時に本人が各サービスの表示で確認して記入する。
- 3D生成AI（Tripo など）を使った場合は、生成物のファイル名・利用規約上の権利・加工の有無をここに追記する。
