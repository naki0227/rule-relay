# rule-relay

能力（操作）を世界へ「貸す」3D箱庭探索パズルの試作リポジトリ。タイトル・世界観・物語は未定（作業用リポジトリ名）。

- 企画書・設計判断の正本: Private Vault `naki0227/personal-knowledge` の `02-Projects/rule-items-world-game-proposal.md` / `rule-items-world-game-concept.md`
- 提出期限: 2027-03-15 23:59（Windows 11 実行ファイル）

## 開発環境

- Godot **4.6.3-stable**（標準版。.NET 版は使わない）と型付き GDScript。選定理由は [docs/adr/0001-engine-selection.md](docs/adr/0001-engine-selection.md)
- Python 3.10+ と `pip install -r requirements-dev.txt`（gdformat / gdlint）
- 3D素材: Blender 4.5 LTS。原本の `.blend` は `art/source/`、生成スクリプトは `art/scripts/`、ゲームが読むのは `assets/models/` の `.glb`（[art/README.md](art/README.md)）

```bash
tools/install_godot.sh "$HOME/godot"     # Linux: 公式リリースを SHA-512 検証して配置
GODOT="$HOME/godot/godot" tools/check.sh # format / lint / import / static / test / smoke
GODOT="$HOME/godot/godot" tools/check.sh --build   # + Windows exe を build/windows/ へ
```

品質ゲートの内訳と依存の理由は [docs/adr/0002-testing-and-ci.md](docs/adr/0002-testing-and-ci.md)。CI（GitHub Actions）は同じスクリプトを実行し、Windows の exe を成果物として残す。

## ディレクトリ

| パス | 役割 |
|---|---|
| `src/rules/` | ゲームルール（能力トークン・禁止・発動方式・範囲など）。ノードや入力に依存しない純粋なクラス |
| `src/game/` | Godot のノード（プレイヤー、ブロック、カメラ、ワールド）。ルールを呼び出して物理へ反映する |
| `src/ui/` | HUD・入力の変換 |
| `scenes/` | シーン |
| `tests/unit/` | ルールの単体テスト / `tests/integration/` 物理を進める結合テスト |
| `tools/` | 品質ゲートと Godot の導入スクリプト |
| `src/audio/` | 効果音を鳴らす SoundBank / `tools/sfx/` 効果音の合成・測定・基準のテスト（[docs/sound-design.md](docs/sound-design.md)） |
| `art/` | 3Dモデルの原本と生成スクリプト（Godot からは除外） / `assets/models/` ゲーム用 `.glb` |
| `docs/adr/` | 設計判断 / `docs/reports/` 作業報告 / `docs/TODO.md` |
