# ADR 0002: 品質ゲート（format / lint / static / test / build）と CI

- 状態: 採用（2026-11-18）

## 決定

| 段階 | 道具 | 内容 |
|---|---|---|
| format | gdtoolkit `gdformat`（4.5.0 固定） | `--check` で差分があれば失敗。`tools/check.sh --fix` で整形 |
| lint | gdtoolkit `gdlint` | 命名・定義順・行長100など。設定は `.gdlintrc` |
| import | Godot `--headless --import` | クラス名キャッシュを作り、インポートエラーを検出 |
| static | `tools/check_scripts.gd` | 全 `.gd` を読み込み、構文エラーと「エラーに格上げした警告」を検出 |
| test | `tests/run_tests.gd`＋`TestCase` | `tests/unit`・`tests/integration` の `test_*.gd` を実行。`--fixed-fps 60` で物理を決定的に進める |
| smoke | Godot `--headless --quit-after 180` | メインシーンが180フレーム走ってもエラーを出さない |
| build | Godot `--export-release "Windows Desktop"` | PCK を埋め込んだ単一 exe を出力 |

GitHub Actions（`.github/workflows/ci.yml`）は同じ `tools/check.sh --build` を実行し、Windows の exe を成果物にする。
続く `windows-smoke` ジョブで、Windows ランナー上で exe をヘッドレス起動する（Windows Server 上の確認で、Windows 11 実機の確認は別途手動）。

### 静的検査として格上げした警告（`project.godot`）

- `untyped_declaration` = エラー（型なしの宣言を禁止）
- `unsafe_property_access` / `unsafe_method_access` = エラー
- `unsafe_call_argument` = 警告

Godot はスクリプトエラーでも終了コード0で終わる場合があるので、`check.sh` は出力の `ERROR:` / `SCRIPT ERROR:` / `Parse Error` も失敗とする。各段に `timeout`（既定600秒）を付け、スクリプトエラーでの無限待ちを防ぐ。

## 依存関係

| 依存 | 導入理由 | 代替案 | 保守リスク |
|---|---|---|---|
| gdtoolkit 4.5.0（Python、開発時のみ） | GDScript 用で実用的な formatter / linter がほかにない | Godot 4.x エディタ内蔵のフォーマッタ（CLI 未提供）、手動レビュー | 個人主導の OSS。Godot の新構文に追随が遅れる可能性 → バージョン固定し、解析できない構文が出たら更新か除外を判断 |
| テストランナー（自前、約150行） | ルールの単体テストと物理の結合テストを最小の仕組みで回す | GUT、gdUnit4（多機能だがアドオン一式をリポジトリに抱え、Godot の更新に依存） | 機能は最小限（モック・パラメタ化なし）。必要になったら gdUnit4 への移行を再検討 |
| GitHub Actions の公式アクション（checkout, setup-python, cache, upload/download-artifact） | 標準的な CI 部品 | — | メジャー更新時に追随が必要 |

Godot のゲーム本体には、外部アドオンを入れていない。
